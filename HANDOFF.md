# Handoff

> Current state, not a log. Overwrite rather than append. Read by the next
> session — or the hourly resume job — to continue without re-deriving anything.

**Written:** 2026-11-07 (after grove world, mutations, progression)
**Repo:** `cwilson-111/lumen-grove`, branch `main`
**Place:** published, placeId `119675424382289`, universeId `10774896318`,
visibility **PRIVATE**, server size **8** (set via Open Cloud this session)
**Studio id (this machine, this run):** `5fff069f-e222-43e2-b2bf-7cacc8f9b603`
— re-read with `list_roblox_studios`; it changes when Studio restarts.

## Goal

An idle-grow Roblox game built to the signals Roblox's Home recommendations
rank on (`create.roblox.com/docs/discovery`): play through rate, first play
bounce rate, **play days per user** and **playtime per user** top tier;
co-play and the two Robux-spend signals one below. The user asked for more
gameplay before more monetization.

## Done

Every item verified by driving the live place over Studio MCP.

- [x] Loop, validation, persistence, offline growth, tending, plot skins
      (3 game passes; equip and persisted choice verified; *purchase* by a
      non-owner still untested). See README.
- [x] **Grove world** (`tools/world.luau`, run into Edit): night lighting,
      terrain with hub, paths and hill ring, elder mushroom, ~90 glowshroom
      clusters, treeline, rocks, spore particles; 845 parts. Plots stand in a
      ring of 8 around the hub (`Config.plotCFrame`), each with a lamp and an
      owner sign. Screenshots confirmed readable at night on Slate.
- [x] **Plants glow** brighter as they ripen (PointLight per plant).
- [x] **Mutations.** With odds forced in a throwaway deploy: all five
      plantings rolled; the state push carried no `mutation` field and the
      prompts read plain `Glowcap` while growing; at ripeness they read
      `Golden Glowcap` / `Prismatic Glowcap` with sparkles; harvests paid
      exactly 54 (×3) and 216 (×12); each Prismatic fired the server-wide
      banner. Real odds (1/20, 1/150) redeployed and confirmed in the source.
- [x] **Species unlocks.** Moonpetal refused at 9 harvests (`Moonpetal unlocks
      at 30 harvests.`); with the threshold forced to 5 the picker row unlocked
      live on the next state push; real threshold redeployed (row reads
      `at 30 harvests`).
- [x] **Plot expansion.** Expand 150 → tile 10; planting on 11 refused until
      bought; tile 11 prompt read `Unlock / 200 lumen`, tile 12 disabled.
      Through *real prompt presses* on tile 11: unlock → plant → tend.
- [x] **Persistence of the new fields.** After stop/start: `tileCount=10`,
      tile 10's Glowcap present and ripe (grew while the server was down).
      v2 → v3 profile migration ran on the existing save.

## In progress / not yet verified

- **The world and SpawnLocation exist only in the open Studio session.** The
  user must **File → Publish to Roblox**. If lost, re-run a deploy and then
  `tools/world.luau` (both via `execute_luau`, Edit datamodel).
- **Foreign-plot guard untested** (needs two players): the client refuses a
  prompt on another player's plot with "That's someone else's grove."
- **Skin purchase by a non-owner untested** (creator owns their passes).

**Next action:** ask the user what to build next. Candidates, in the order
recommended last time: daily reward with no streak loss (play days),
adjacency bonuses (second active mechanic), help-a-friend co-op, custom
thumbnail (required for Home), then time-skips.

## Usage budget

`~/.omp/agent/usage-budget.json` is still the installer placeholder
($60 / 5h). Ask the user for their real plan limits.

## Deliberately not done

- **Mutation is rolled at planting, hidden until ripe** — not rolled at
  harvest — so a ripe rare plant is visible to the server and other
  players, and the summary can never leak it early.
- **Only the next tile is for sale**; `Expand()` takes no argument.
- **No decay, anywhere.** **Co-op rewarded, never required.**
- **Not a Steal-genre clone.**
- **Skins are game passes; ownership never saved in the profile.**

## Files touched this session

- `src/shared/Config.luau` — grid/layout, `tileUnlockCost`, ring and
  `plotCFrame`, `GROUND_Y`, species `unlockHarvests` + Moonpetal/Starcap,
  `MUTATIONS`
- `src/shared/Growth.luau` — `mutation` on the tile; payout multiplier
- `src/shared/Format.luau` — new: `duration`
- `src/server/PlotService.luau` — rewritten: ring placement, lamp, owner
  sign, locked/next tiles, glow, mutation visuals, `expand`, reset on release
- `src/server/Profiles.luau` — schema v3: `tileCount`
- `src/server/Main.server.luau` — `Expand` and `Announce` remotes,
  `tileCount` in state
- `src/client/Main.client.luau` — locked species, expand routing,
  foreign-plot guard, banner
- `tools/world.luau` — new: the grove builder

## Gotchas discovered

- **Smooth terrain surfaces at y = 2 for voxels solid to y = 0.** Plots sit
  at `Config.GROUND_Y`. Measure with a terrain-only raycast.
- **`screen_capture` with camera params works during play**, and captures
  the game view including UI; Roblox's purchase dialog does not appear in it.
- **Forced-odds testing:** string-replace in the emitted deploy Luau only;
  redeploy unmodified after. Never commit forced odds.
- **`ProximityPrompt:InputHoldBegin/End`** from the Client datamodel presses
  a real prompt.
- **Open Cloud via `open_cloud_invoke`**: `universe.place:write` works
  (server size); `game-pass:write` and uploads did not. Passes were created
  from a user-logged-in managed Chromium with a page `fetch`.
- **`execute_luau` keeps its own module cache**; require a clone of
  `ReplicatedStorage.Shared` for fresh pure modules (world.luau does).
- **Every bridge tool needs `studio_id`**; Edit is unavailable during play.
- **Gotham has no ✦**; use `R$`, not a Robux glyph.
