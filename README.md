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

### Mutations: the reason to keep harvesting

A planting sometimes comes up rare. The server rolls it when the seed goes in
and stores it on the tile (`mutation`), but tells nobody — the plot, the
prompt and the state push all hide it — until the plant is ripe. The surprise
lands at harvest, and the client cannot peek because it is never sent.

| Mutation | Chance per planting | Pays | Shown as |
|---|---|---|---|
| Golden | 1 in 20 | ×3 | gold, sparkling |
| Prismatic | 1 in 150 | ×12 | cycling rainbow, sparkling; announced to the whole server |

Tending never touches the roll; a tile saved before mutations existed is
simply unmutated.

### Progression: something to come back for

- **Species unlock by lifetime harvests.** The first three are open from the
  start; the long growers are what make tomorrow worth opening the game for
  (plant before leaving, harvest on return):

  | Species | Unlocks at | Cost | Grow | Pays |
  |---|---|---|---|---|
  | Moonpetal | 30 harvests | 900 | 30m | 2,600 |
  | Starcap | 100 harvests | 4,000 | 2h | 12,500 |

- **The plot grows from 3×3 to 5×5**, one tile at a time, bought with lumen
  (`Expand()`, no argument: only the next tile is ever for sale). The 10th
  tile costs 150, each next one ~32% more, the 25th ~9,600. Tiles 1–9 are the
  centre, in the original order, so old saves keep every plant in place.

### Neighbour bonuses: arranging the grid

Every species boosts the plants directly beside it (up, down, left, right —
never diagonal). The bonus is read from the plot **at harvest**, never
stored, so growth stays a pure function of time and nothing can stack past
four sides. The prompt previews it (`Voidlily · +30%`) and the harvest message
names it.

| Species | Gives its neighbours |
|---|---|
| Glowcap | +10% to anything |
| Emberbloom | +30% to Voidlily |
| Voidlily | +30% to Moonpetal |
| Moonpetal | +30% to Starcap |
| Starcap | +15% to anything |

Mutations multiply on top: a Golden Voidlily with an Emberbloom and a
Glowcap beside it pays 520 × 1.4 × 3.

### Daily dew: a reason to come back tomorrow, with no streak

Once per UTC day a dewdrop waits on the player's plot; collecting it pays
`max(100, best species value ever harvested) × (1 + 0.1 × dews ever
collected, capped at 20)`. On a grove's first day there is no dew, only *"your
first dew falls in …"* — the hook for day two. The count of dews collected
never resets: missing a week costs nothing (*play days per user* without a
streak to lose). `src/server/Daily.luau`.

### Helping: co-play, rewarded and never required

Visitors see one prompt on someone else's plot — **Help tend**, only on a
plant that can be tended right now. It is the owner's ordinary tend (same
cap, same cooldown), so helping can never make a plant grow faster than
attentive play could. The helper earns 3% of the plant's value, doubled
between Roblox friends; the owner gets a notice. Visitors can never plant on,
harvest or unlock tiles on another plot, and the server checks they are
standing at the plant.

Prompts carry a `Role` (`owner`/`visitor`) and an `Active` attribute set by
the server; each client enables only the active prompts meant for it, so the
same plot shows different prompts to its owner and to everyone else.

### The grove

The world is a night forest: plots stand in a ring of eight around a hub
with an elder mushroom, joined to it by paths, under glowing fungi, a
treeline and drifting spores. Every plot has a lamp and its owner's name;
plants glow brighter as they ripen, so a ripe plot is visible across the
grove. Servers hold **8 players** (set through Open Cloud) — one ring; a
bigger server would start a second ring further out.

`tools/world.luau` builds all of it into the Edit datamodel (see *Working on
it*). It is seeded and idempotent, and reads plot positions from
`Config.plotCFrame`, the same function the server uses.

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
src/shared/Config.luau     tunables; species, mutations, grid, ring, skins
src/shared/Growth.luau     the pure growth/payout math
src/shared/Format.luau     durations for prompts and the picker
src/server/Profiles.luau   DataStore persistence, versioned, retrying
src/server/Daily.luau      the daily dew
src/server/PlotService.luau  authoritative plot state and world rendering
src/server/Skins.luau      skin ownership (game passes) and equipping
src/server/Main.server.luau  remotes, join/leave, autosave, cosmetic tick
src/client/Main.client.luau  balance, spore picker, skin picker, prompts
tools/deploy.py            builds the Luau that writes src/ into Studio
tools/world.luau           builds the grove (terrain, lighting, decor)
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

`tools/world.luau` is sent the same way, as-is, **after** a deploy (it reads
the deployed `Config`). Both write into the open place only: **File →
Publish to Roblox** to keep them.

### Icon and thumbnails

`assets/marketing/` holds the uploaded icon (512×512) and thumbnail
(1920×1080, 16:9). Both are real in-game captures: plants staged on a plot
during a playtest, UI hidden, `screen_capture` with a camera position (it
returns the JPEG as base64 in `rawContent`), then cropped and titled with
Pillow. Nothing staged is saved: it lives in the playtest only.

Uploaded from a logged-in Creator Dashboard browser session with `fetch`:

| What | Endpoint (cookie + `x-csrf-token` retry) |
|---|---|
| Icon | `POST publish.roblox.com/v1/games/{universeId}/icon`, form field `Files` |
| Detail-page thumbnail | `POST publish.roblox.com/v1/games/{universeId}/thumbnail/image`, `Files` |
| Home thumbnail | `POST apis.roblox.com/thumbnail-personalization-api/v1/universes/{id}/thumbnails/uploads` (`files`), poll `…/uploads/status`, then `…/personalization/create` with the `homepageThumbnailId` |

The Open Cloud Assets API (`assets/v1/assets`) rejects cookie auth, and the
MCP `open_cloud_invoke` tool cannot upload files from a directory Studio has
not approved.

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
- **Smooth terrain surfaces half a voxel above its fill.** Voxels solid up
  to y = 0 draw and collide at **y = 2**, which buried the plots' tiles until
  they were raised to `Config.GROUND_Y`. Measure with a terrain-only raycast
  rather than trusting the fill height; filling lower does not help, since
  `FillCylinder` rounds to whole voxels.
- **Testing rare rolls:** deploy with the odds forced in the emitted Luau
  only (e.g. replace `chance = 1 / 20` with `chance = 1`), play the real path,
  then redeploy unmodified. Never commit forced odds.
- `ProximityPrompt:InputHoldBegin()`/`InputHoldEnd()` from the `Client`
  datamodel presses a real prompt, which tests the client's routing too, not
  just the remote behind it. Stand within `MaxActivationDistance` first.
- **Studio's multi-client test windows do not attach to the MCP bridge**
  (Test → Clients and Servers). Only the Edit window is listed, so anything
  needing two players — helping — has to be played by hand in those windows.

## Not built yet

- Plants are plain glowing spheres; species-specific shapes (stem and cap,
  like the grove's decorative mushrooms) would read better on the plot and in
  thumbnails.
- Monetization, continued: time-skips that never gate content. Tending stays
  the free version of a time-skip. (A second plot slot is less obvious now
  that one plot grows to 5×5.)
- More Home thumbnails: personalization only starts with **two or more**
  active, and one is active today.
