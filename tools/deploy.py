#!/usr/bin/env python3
"""Push src/ into the open Roblox Studio place over the MCP bridge.

    python3 tools/deploy.py          # sync every script
    python3 tools/deploy.py --dry    # show what would be written

Mapping, by filename suffix:

    src/shared/X.luau          -> ModuleScript  ReplicatedStorage/Shared/X
    src/server/X.server.luau   -> Script        ServerScriptService/X
    src/server/X.luau          -> ModuleScript  ServerScriptService/X
    src/client/X.client.luau   -> LocalScript   StarterPlayerScripts/X

Server ModuleScripts sit directly in ServerScriptService next to the Script
that requires them, which is why Main.server.luau uses `script.Parent.X`.

Source is shipped as a quoted Luau long-string rather than interpolated, so
a script containing quotes, backslashes or newlines survives the trip. The
delimiter level is chosen per file to avoid colliding with any `]]` in the
source itself.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from studio import Session, StudioError  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"


def long_string(source: str) -> str:
    """`source` as a Luau long-bracket literal that cannot be broken by it."""
    level = 0
    while f"]{'=' * level}]" in source or f"[{'=' * level}[" in source:
        level += 1
    eq = "=" * level
    # A long string swallows one leading newline, so add one to keep line
    # numbers in Studio matching the file on disk.
    return f"[{eq}[\n{source}]{eq}]"


def targets():
    for path in sorted(SRC.rglob("*.luau")):
        area = path.relative_to(SRC).parts[0]
        stem = path.name[: -len(".luau")]
        if area == "shared":
            yield path, "ModuleScript", "shared", stem
        elif area == "server":
            if stem.endswith(".server"):
                yield path, "Script", "server", stem[: -len(".server")]
            else:
                yield path, "ModuleScript", "server", stem
        elif area == "client":
            if stem.endswith(".client"):
                yield path, "LocalScript", "client", stem[: -len(".client")]
            else:
                yield path, "ModuleScript", "client", stem


DEPLOY_LUAU = """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local function folder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = parent
	return made
end

local areas = {
	shared = folder(ReplicatedStorage, "Shared"),
	server = ServerScriptService,
	client = StarterPlayer:WaitForChild("StarterPlayerScripts"),
}

local written = {}
for _, item in ipairs(FILES) do
	local parent = areas[item.area]
	local existing = parent:FindFirstChild(item.name)
	-- Replace rather than edit in place: a leftover of the wrong ClassName
	-- (a ModuleScript where a Script now belongs) would silently never run.
	if existing and existing.ClassName ~= item.class then
		existing:Destroy()
		existing = nil
	end
	local target = existing
	if not target then
		target = Instance.new(item.class)
		target.Name = item.name
		target.Parent = parent
	end
	target.Source = item.source
	table.insert(written, string.format("%s %s.%s", item.class, item.area, item.name))
end
return table.concat(written, "\\n")
"""


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry", action="store_true", help="List targets, write nothing")
    args = parser.parse_args(argv)

    found = list(targets())
    if not found:
        print(f"deploy.py: no .luau files under {SRC}", file=sys.stderr)
        return 1

    entries = []
    for path, class_name, area, name in found:
        source = path.read_text(encoding="utf-8")
        print(f"{class_name:14} {area}.{name:16} <- {path.relative_to(ROOT)} ({len(source)}B)")
        entries.append(
            "{area = %s, name = %s, class = %s, source = %s}"
            % (
                long_string(area),
                long_string(name),
                long_string(class_name),
                long_string(source),
            )
        )

    if args.dry:
        return 0

    code = "local FILES = {\n" + ",\n".join(entries) + "\n}\n" + DEPLOY_LUAU
    try:
        with Session() as studio:
            print("---")
            print(studio.luau(code, "Edit"))
    except StudioError as exc:
        print(f"deploy.py: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
