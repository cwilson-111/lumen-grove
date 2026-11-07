# Handoff

> Current state, not a log. Overwrite rather than append. Read by the next
> session — or the hourly resume job — to continue without re-deriving anything.

**Written:** 2026-11-07 (after plot skins)
**Repo:** `cwilson-111/lumen-grove`, branch `main`
**Place:** published, placeId `119675424382289`, universeId `10774896318`,
visibility **PRIVATE**
**Studio id (this machine, this run):** `5fff069f-e222-43e2-b2bf-7cacc8f9b603`
— re-read with `list_roblox_studios`; it changes when Studio restarts.

## Goal

An idle-grow Roblox game built to the signals Roblox's Home recommendations
actually rank on (`create.roblox.com/docs/discovery`): play through rate,
first play bounce rate, **play days per user** and **playtime per user** in
the top tier; intentional co-play and the two Robux-spend signals one below.
Since August 2026, sustainable monetization weighs alongside retention.

Retention has a loop (offline growth) and an active layer (tending).
Monetization now has its first, cosmetic-only purchase.

## Done

Every item verified by driving the live place over Studio MCP, not by reading code.

- [x] Plant → grow → harvest, input validation, real DataStore persistence,
      offline growth, tending with cap and cooldown. See README.
- [x] **Native Studio MCP tools work** in omp; `tools/studio.py` deleted.
- [x] **`tools/deploy.py` ported.** It now only prints the Luau chunk; the
      agent sends it with `execute_luau` (Edit datamodel). Verified: all 7
      scripts written, including the new `server.Skins`.
- [x] **Three skin game passes exist**, for sale: Crystal Hollow `2075151059`
      (R$49), Ember Hearth `2074455097` (R$99), Starfall `2074929162`
      (R$149). `GetProductInfo` from the client returns those names and
      prices, `IsForSale=true`.
- [x] **Equip path.** Through the real `Skin` remote: `ember`/`slate`/
      `starfall` equipped; `"nope"` and `5` refused with *"No such skin."*.
      Plot repainted (Starfall: Granite base, Pavement tiles, 4 neon rim
      strips). UI rows read `On` / `Equip`; screenshots confirmed.
- [x] **Equipped skin persists.** Equipped Starfall, stopped play, started
      again: plot came back Starfall. The pre-existing v1 profile migrated to
      v2 (`skin` field added) without loss.
- [x] Skin panel moved to the top-right; stacked under the spore picker it ran
      off the bottom of the viewport.
- [x] SpawnLocation moved to `(0, 0.5, -40)`. It overlapped Plot1's base at the
      same height and its decal z-fought through the tile gaps.

## In progress / not yet verified

- **The purchase path has not been exercised.** The creator owns every pass
  they create (`UserOwnsGamePassAsync` → true for all three), so on the
  owner's account every skin is already `Equip`. A non-owner must click a
  locked skin, buy it in Studio's test prompt, and see: toast
  *"<Skin> unlocked."*, the plot repaint, the row flip to `On`. Code path:
  client `PromptGamePassPurchase` → server
  `PromptGamePassPurchaseFinished` in `Skins.init`.
- **The SpawnLocation move is in the Edit datamodel only.** The place file is
  not in the repo; the user must **File → Publish to Roblox** (or save) for it
  to stick.

**Next action:** test a purchase from a non-owner account (Studio *Test →
Clients and Servers* gives `Player1`/`Player2`, who own nothing), then the
second monetization item: **a second plot slot** (a game pass; same pattern
as skins). Then time-skips, only if they never gate content.

## Usage budget

`~/.omp/agent/usage-budget.json` is still the installer placeholder
($60 / 5h). Ask the user for their real plan limits rather than guessing.

## Deliberately not done

- **Skins are game passes, not developer products.** Permanent, owned once;
  Roblox records ownership, so no idempotent `ProcessReceipt` is needed and a
  lost save cannot lose a purchase. Developer products (and
  `ProcessReceipt`) are for the later consumable time-skips.
- **Ownership is never saved in the profile.** Re-read on join; a failed
  check shows the default for that session and never unequips.
- **Co-op is rewarded, never required.**
- **Not a Steal-genre clone.**
- **No decay, anywhere.**
- **Plot layout / adjacency bonuses deferred** behind monetization.

## Files touched this session

- `src/shared/Config.luau` — `Skin` type, `SKINS`, `skinById`, `skinByGamePass`
- `src/server/Skins.luau` — new: ownership, `shown`, `equip`, purchase handler
- `src/server/PlotService.luau` — `paint`, `paintSkin`; release repaints default
- `src/server/Profiles.luau` — schema v2: `skin`
- `src/server/Main.server.luau` — `Skin` remote; `skin`/`ownedSkins` in state
- `src/client/Main.client.luau` — skin panel, prices, purchase prompt, toast
- `tools/deploy.py` — prints Luau instead of calling Studio; `studio.py` gone
- `assets/passes/*.png` — pass icons

## Gotchas discovered

- **Open Cloud via `open_cloud_invoke` could not create passes.**
  `game-pass:write` stayed "not granted" and `assets/passes/` stayed "not
  approved for uploads" even after the user saved and toggled the MCP
  permissions; `game-pass:read` worked. What worked: a headed managed
  Chromium logged in by the user on create.roblox.com, then a `fetch` from
  that page to `apis.roblox.com/game-passes/v1/universes/{id}/game-passes`
  (multipart: `name`, `description`, `price`, `isForSale`, `imageFile`),
  with the usual `x-csrf-token` retry on 403.
- **The creator owns their own passes.** Purchase cannot be tested on that
  account.
- **`execute_luau` keeps its own module cache, across calls.** Test stateful
  services through the remotes from the `Client` datamodel.
- **Every bridge tool needs `studio_id`**; `execute_luau` also needs
  `datamodel_type`. Edit is unavailable during play — stop first.
- **The bridge only attaches to a *published* place.**
- **Gotham has no ✦**; use `R$`, not a Robux glyph.
- **Game Settings is greyed out during a playtest.**
