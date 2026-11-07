# Lumen Grove

An idle-grow Roblox game. Plant spores on a plot, they grow in real time —
including while you are offline — harvest them for lumen, buy better spores.

Working prototype: the loop runs end to end in Studio.

## Why this shape

Roblox's Home recommendations judge a game on signals published at
[create.roblox.com/docs/discovery](https://create.roblox.com/docs/discovery).
The *most important* ones are play through rate, first play bounce rate
(negative, measured under 60s), **play days per user** across D1 / D2–7 /
D8–28, and **playtime per user**. Intentional co-play, qualified sessions and
the two Robux-spend signals sit one tier below.

An idle-grow loop is built to produce the top tier: something finished while
you were away is a reason to open the game tomorrow, which is literally what
*play days per user* counts. The genre also led platform growth at +185%
(Q4 2025 → Q1 2026).

Two things follow from the signal list and are design constraints here, not
preferences:

- **Co-op is rewarded, never required.** Gating progress behind other players
  trades a most-important signal (bounce) for a second-tier one (co-play).
- **Sessions are not 90 seconds.** Playtime per user is top tier, capped at 60
  minutes per user per day, so there has to be something worth staying for on
  top of the offline growth.

Since the [August 2026 update](https://devforum.roblox.com/t/boost-your-discovery-by-building-games-people-want-to-play/4779042),
live platform-wide from 20 August, Home also weighs sustainable monetization
alongside retention. That is a day-one design input, not a later bolt-on.

## The one rule in the code

**Growth is a pure function of time, never an accumulated number.**

A tile stores only `{species, plantedAt}`. How grown it is, is always
recomputed as `(now - plantedAt) / growSeconds` (`src/shared/Growth.luau`).
Three consequences, all deliberate:

1. Offline growth costs nothing — no catch-up pass, no "time since last seen"
   reconciliation, no double-crediting a fast rejoin.
2. A tampered save cannot invent progress. The server is the only thing that
   ever writes `plantedAt`, and it writes `os.time()`.
3. Retuning a species retunes every existing plant, with no migration.

Everything else is server-authoritative for the same reason: exploits and a
progression reset are what cost Grow a Garden its players, not its loop. The
client sends intents — `Plant(tileIndex, speciesId)` for an empty tile,
`Tap(tileIndex)` for an occupied one — and never a price, payout, timestamp or
balance; no handler accepts one. The **server** decides whether a tap harvests
or tends, because the client's view of ripeness is the last state push, up to
a second stale.

### Tending: the active layer

*Playtime per user* is a most-important signal, so there has to be something
to do between harvests. Tapping a growing plant tends it: a head start of 15%
of its grow time, capped at 50% in total, with a per-tile cooldown.

It keeps the invariant. A tile gains an optional `boost` (seconds) and
`lastTended`; effective age is `(now − plantedAt) + boost`, still a pure
function of time, still written only by the server. Old saves without those
fields load unchanged — no migration.

- **Presence is rewarded, absence is never punished.** Nothing decays; an
  untended plant grows at exactly its normal rate.
- **The cap keeps idle play worth it.** Attentive play halves the wait; it
  cannot zero it.
- **The cooldown scales with grow time** — 10% of it, floor 4s. A flat 8s let
  a Voidlily take all four tends in its first 24 seconds and then gave the
  player nothing to do for five minutes. Scaled, its tends land at 0, 60, 120
  and 180s, so there is a reason to come back while it ripens.

| Species | Grow | Attentive | Tends at |
|---|---|---|---|
| Glowcap | 30s | 15s | 0, 4, 8, 12 |
| Emberbloom | 120s | 60s | 0, 12, 24, 36 |
| Voidlily | 600s | 300s | 0, 60, 120, 180 |

`src/server/Profiles.luau` will refuse to play rather than hand out a blank
grove when a load fails, because a blank profile saved over a real one is how
a transient outage becomes permanent data loss.

## Layout

```
src/shared/Config.luau     tunables; species, costs, grow times
src/shared/Growth.luau     the pure growth/payout math
src/server/Profiles.luau   DataStore persistence, versioned, retrying
src/server/PlotService.luau  authoritative plot state and world rendering
src/server/Main.server.luau  remotes, join/leave, autosave, cosmetic tick
src/client/Main.client.luau  balance readout, spore picker, prompt handling
```

## Working on it

Studio's built-in MCP bridge drives everything; there is no manual copy-paste.

Prerequisites: Studio open on a **published** place (an unpublished one has no
universe, and the bridge will not attach), with **Assistant → … → Manage MCP
Servers → Enable Studio as MCP server** on.

```sh
python3 tools/deploy.py          # push src/ into the open place
python3 tools/deploy.py --dry    # show what would be written

python3 tools/studio.py state    # attached instance, Edit/Play mode
python3 tools/studio.py play on  # start a playtest
python3 tools/studio.py console  # read the output log
python3 tools/studio.py shot     # capture the viewport
python3 tools/studio.py luau 'return #workspace:GetChildren()'
python3 tools/studio.py luau --datamodel Client 'return 1 + 1'
```

`deploy.py` needs Edit mode — stop the playtest first, or it reports
`Edit datamodel is not available in Play mode`.

`tools/studio.py` exists because omp resolves MCP servers at session start; a
session started before `~/.omp/agent/mcp.json` was written cannot call the
Studio tools directly. Once a restarted session has them natively, this is
redundant and should be deleted.

### Testing notes, learned the hard way

- `execute_luau` keeps **its own module cache, across calls**. `require`ing a
  ModuleScript there returns a *different instance* than the running game
  holds, with empty state — and keeps returning the version from your *first*
  call even after a redeploy. Two fixes, for two cases:
  - **Stateful services:** test through the remotes from the `Client`
    datamodel, which is the real path anyway.
  - **Pure modules after a change:** require a clone, so they are new
    instances: `local fresh = ReplicatedStorage.Shared:Clone()`, parent it
    somewhere, `require(fresh.Growth)`, then `fresh:Destroy()`. Cloning the
    *folder* matters — `Growth` requires its sibling `Config`.
- Every bridge tool requires `studio_id`; `execute_luau` also requires
  `datamodel_type` of `Edit` / `Client` / `Server`.
- `list_roblox_studios` returns `{"studios":[]}` for about a second after the
  proxy starts, while Studio reattaches. Poll it.
- DataStores are off in Studio by default. The game degrades to an in-memory
  store and says so. For real save testing: **Game Settings → Security →
  Enable Studio Access to API Services**.

## Not built yet

- A second active mechanic: plot layout, with adjacency bonuses between
  species, so arranging the grid is worth time.
- Monetization: cosmetic plot skins, a second plot slot, time-skips that never
  gate content.
- Co-op: helping on a friend's plot, rewarded and never required.
- A custom thumbnail. **Required** for any Home impressions — a place with the
  default thumbnail is ineligible.
