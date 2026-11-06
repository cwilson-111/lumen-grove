#!/usr/bin/env python3
"""Drive Roblox Studio over its built-in MCP bridge from the shell.

A stopgap: omp resolves MCP servers at session start, so until the session is
restarted the `roblox-studio` tools aren't callable directly. This speaks the
same JSON-RPC to the same binary.

    python3 tools/studio.py state
    python3 tools/studio.py luau 'return workspace:GetChildren()'
    python3 tools/studio.py luau --file src/bootstrap.luau --datamodel Server
    python3 tools/studio.py console
    python3 tools/studio.py play on | off
    python3 tools/studio.py shot 1
    python3 tools/studio.py call search_game_tree '{"query": "Script"}'
    python3 tools/studio.py tools

Two things the schemas demand and this wraps up for you:

- every tool takes a required `studio_id`, obtained from list_roblox_studios
- `execute_luau` also takes a required `datamodel_type` of Edit/Client/Server

The session is interactive rather than a pre-baked batch, because the studio
id has to be discovered *before* the calls that use it, and Studio only stays
attached for the lifetime of one proxy process. list_roblox_studios also
returns an empty list for the first moment after the proxy starts, while
Studio reconnects over its websocket, so it is polled rather than trusted
once.
"""

import argparse
import json
import subprocess
import sys
import time

STUDIO_MCP = "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"
ATTACH_ATTEMPTS = 10
ATTACH_WAIT_SECONDS = 1.0


class StudioError(RuntimeError):
    pass


class Session:
    """One proxy process, many calls."""

    def __init__(self, timeout=180):
        self.timeout = timeout
        self._next_id = 1
        self.studio_id = None
        self.proc = subprocess.Popen(
            [STUDIO_MCP],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        self._request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "studio.py", "version": "2"},
            },
        )
        self._notify("notifications/initialized")

    # -- wire ------------------------------------------------------------- #

    def _send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def _notify(self, method, params=None):
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def _request(self, method, params):
        message_id = self._next_id
        self._next_id += 1
        self._send({"jsonrpc": "2.0", "id": message_id, "method": method, "params": params})
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                raise StudioError("the MCP proxy closed its output unexpectedly")
            line = line.strip()
            if not line:
                continue
            try:
                reply = json.loads(line)
            except json.JSONDecodeError:
                continue
            if reply.get("id") == message_id:
                return reply
        raise StudioError(f"{method} timed out after {self.timeout}s")

    # -- tools ------------------------------------------------------------ #

    def call(self, name, arguments=None, with_studio=True):
        arguments = dict(arguments or {})
        if with_studio:
            arguments.setdefault("studio_id", self.attach())
        reply = self._request("tools/call", {"name": name, "arguments": arguments})
        if "error" in reply:
            raise StudioError(json.dumps(reply["error"]))
        result = reply.get("result", {})
        text = "\n".join(
            block.get("text", "") for block in result.get("content", []) if block.get("type") == "text"
        )
        if result.get("isError"):
            raise StudioError(text or "the tool reported an error with no message")
        return text

    def attach(self):
        """The id of the connected Studio, waiting for it to appear."""
        if self.studio_id:
            return self.studio_id
        for attempt in range(ATTACH_ATTEMPTS):
            raw = self.call("list_roblox_studios", {}, with_studio=False)
            try:
                studios = json.loads(raw).get("studios", [])
            except json.JSONDecodeError:
                studios = []
            if studios:
                self.studio_id = studios[0]["id"]
                return self.studio_id
            if attempt + 1 < ATTACH_ATTEMPTS:
                time.sleep(ATTACH_WAIT_SECONDS)
        raise StudioError(
            "No Studio attached after "
            f"{ATTACH_ATTEMPTS}s. Open a published place in Studio and turn on "
            "Assistant > ... > Manage MCP Servers > Enable Studio as MCP server."
        )

    def luau(self, code, datamodel="Edit"):
        return self.call("execute_luau", {"code": code, "datamodel_type": datamodel})

    def close(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("state", help="Studio mode, DataModels and the attached instance")
    sub.add_parser("tools", help="List the bridge's tools")
    sub.add_parser("console", help="Studio output log")

    luau = sub.add_parser("luau", help="Run Luau in Studio")
    source = luau.add_mutually_exclusive_group(required=True)
    source.add_argument("code", nargs="?", help="Luau source")
    source.add_argument("--file", help="Read the source from this path")
    luau.add_argument("--datamodel", default="Edit", choices=["Edit", "Client", "Server"])

    play = sub.add_parser("play", help="Start or stop a playtest")
    play.add_argument("switch", choices=["on", "off"])

    shot = sub.add_parser("shot", help="Capture the viewport")
    shot.add_argument("capture_id", nargs="?", default="ScreenCapture_1")

    call = sub.add_parser("call", help="Call any tool by name")
    call.add_argument("name")
    call.add_argument("arguments", nargs="?", default="{}", help="JSON object")

    args = parser.parse_args(argv)

    try:
        with Session() as studio:
            if args.command == "tools":
                reply = studio._request("tools/list", {})
                for tool in reply.get("result", {}).get("tools", []):
                    first_line = (tool.get("description") or "").splitlines()[0]
                    print(f"{tool['name']:28} {first_line[:88]}")
                return 0

            if args.command == "state":
                print(f"studio_id: {studio.attach()}")
                print(studio.call("get_studio_state", {}))
            elif args.command == "console":
                print(studio.call("get_console_output", {}))
            elif args.command == "luau":
                code = open(args.file, encoding="utf-8").read() if args.file else args.code
                print(studio.luau(code, args.datamodel))
            elif args.command == "play":
                print(studio.call("start_stop_play", {"is_start": args.switch == "on"}))
            elif args.command == "shot":
                print(studio.call("screen_capture", {"capture_id": args.capture_id}))
            else:
                print(studio.call(args.name, json.loads(args.arguments)))
    except StudioError as exc:
        print(f"studio.py: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
