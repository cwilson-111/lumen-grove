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

### Plot skins: the first thing for sale

Since August 2026, *spend days per user* and *Robux spent per user* rank
alongside retention. The first purchase had to be one that cannot feel like a
paywall, so it is purely cosmetic: a skin repaints your plot (base, tiles, a
glowing rim) for everyone in the server, and no growth, payout or tending
number reads it.

| Skin | Price | Game pass |
|---|---|---|
| Slate | free, default | — |
| Crystal Hollow | R$ 49 | `2075151059` |
| Ember Hearth | R$ 99 | `2074455097` |
| Starfall | R$ 149 | `2074929162` |

- **Game passes, not developer products.** A skin is owned once and forever.
  Roblox keeps the record of pass ownership, so a lost save cannot lose a
  purchase, a refund is respected, and a pass cannot be bought twice. There is
  no `ProcessReceipt` to make idempotent because there is no receipt.
- **Ownership is never saved.** `src/server/Skins.luau` re-reads it with
  `UserOwnsGamePassAsync` on every join and adds to it when Roblox fires
  `PromptGamePassPurchaseFinished` in-session. The profile stores only the
  *equipped* id, a preference.
- **A failed check never unequips.** If Roblox cannot confirm a pass, the
  plot shows the default for that session; `profile.skin` is left alone and
  the skin returns on the next join that can confirm it.
- **Prices live on the passes**, not in Config. The client reads them with
  `GetProductInfo`, so the button can never disagree with the prompt.
- Pass icons are in `assets/passes/`.

## Layout

```
src/shared/Config.luau     tunables; species, costs, grow times, skins
src/shared/Growth.luau     the pure growth/payout math
src/server/Profiles.luau   DataStore persistence, versioned, retrying
src/server/PlotService.luau  authoritative plot state and world rendering
src/server/Skins.luau      skin ownership (game passes) and equipping
src/server/Main.server.luau  remotes, join/leave, autosave, cosmetic tick
src/client/Main.client.luau  balance, spore picker, skin picker, prompts
```

## Working on it

Studio's built-in MCP bridge drives everything; there is no manual copy-paste.
The MCP client (omp, or Claude Code) holds the connection and exposes the
Studio tools directly: `execute_luau`, `start_stop_play`, `screen_capture`,
`get_console_output`, and the rest.

Prerequisites: Studio open on a **published** place (an unpublished one has no
universe, and the bridge will not attach), with **Assistant → … → Manage MCP
Servers → Enable Studio as MCP server** on.

```sh
python3 tools/deploy.py > /tmp/deploy.luau   # Luau that writes src/ into the place
python3 tools/deploy.py --dry                # show what would be written
```

`deploy.py` does not talk to Studio. It prints one Luau chunk; send it with
`execute_luau` against the **Edit** datamodel. Stop the playtest first, or
the bridge reports `Edit datamodel is not available in Play mode`.

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
- **The creator owns every pass they create.** In Studio on the owner's
  account, `UserOwnsGamePassAsync` is true for all three skins, so the
  purchase path cannot be exercised there — only equipping. Test buying with
  an account that is not the owner.
- The `SpawnLocation` sat at the same height as Plot1's base, overlapping it,
  and its decal z-fought through the gaps between tiles. It now sits at
  `(0, 0.5, -40)`, clear of the plot row; keep anything else off that row.

## Not built yet

- A second active mechanic: plot layout, with adjacency bonuses between
  species, so arranging the grid is worth time.
- Monetization, continued: a second plot slot, then time-skips that never
  gate content. Tending stays the free version of a time-skip.
- Co-op: helping on a friend's plot, rewarded and never required.
- A custom thumbnail. **Required** for any Home impressions — a place with the
  default thumbnail is ineligible.
