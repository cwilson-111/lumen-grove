# Handoff

> Current state, not a log. Overwrite rather than append. Read by the next
> session — or the hourly resume job — to continue without re-deriving anything.

**Written:** 2026-11-06
**Repo:** `cwilson-111/lumen-grove`, branch `main`
**Place:** published, placeId `119675424382289`, universeId `10774896318`

## Goal

An idle-grow Roblox game built to the signals Roblox's Home recommendations
actually rank on (`create.roblox.com/docs/discovery`). The most important tier
is play through rate, first play bounce rate, **play days per user**
(D1 / D2–7 / D8–28) and **playtime per user** (capped 60 min/user/day).
Intentional co-play and the two Robux-spend signals are one tier below. Since
the August 2026 update, sustainable monetization weighs alongside retention.

"Done" for the next milestone: a session worth staying in for 10–20 minutes,
not a 90-second check-in — that is the playtime signal, and it is currently
unaddressed.

## Done

Every item verified by driving the live place over Studio MCP, not by reading code.

- [x] **Plant → grow → harvest loop works end to end.** 25 starting lumen,
      two Glowcaps at 10 → 5 lumen; a third refused with
      *"Glowcap costs 10 lumen."*; harvesting a ripe Glowcap paid exactly +18
      (its `Config` value) and incremented `harvested`.
- [x] **Every intent validates its input.** Rejected: unknown species,
      tile 99, tile 1.5, planting onto an occupied tile, harvesting an empty
      one, harvesting early (*"Not ready for 10s."* with a live countdown).
- [x] **Real persistence.** Studio API access is on (probe:
      `API ACCESS ON -- real saving works`). Planted a Glowcap at 15 lumen,
      stopped the playtest (BindToClose save), left the server **down for 40s**,
      restarted: `lumen=15 | t1 present=true ripe=true remaining=0`.
- [x] **Offline growth needs no catch-up code.** That same tile, 30s grow
      time, came back ripe after 40s with the server off. This is the core
      design claim — growth is a pure function of `(now - plantedAt)` — proven
      rather than argued.
- [x] UI: balance label, spore picker with selection state, per-species plant
      colour; screenshots confirmed.

## In progress

Nothing half-finished. The last action completed cleanly.

**Next action:** build the **active layer** that earns the playtime signal.
Something to *do* on the plot between harvests, server-authoritative like the
rest. Start in `src/server/PlotService.luau` and add a new intent alongside
`plant`/`harvest`, validated the same way. Candidate mechanics, in order of
how directly they earn playtime without gating anything:

1. **Tending** — a ripening plant occasionally needs attention; tending it
   speeds or boosts it. Rewards presence, never punishes absence.
2. **Plot layout** — adjacency bonuses between species, so arranging the
   grid is a puzzle worth time.

Constraint: nothing may *decay* while offline. That would punish leaving and
contradict the offline-growth contract.

## Blocked

- **Native Studio tools need an omp restart.** `~/.omp/agent/mcp.json`
  registers `roblox-studio`, but MCP servers resolve at session start, so a
  session older than that file cannot call them. Until then use
  `tools/studio.py` and `tools/deploy.py`. After a restart, delete both.

## Deliberately not done

- **Co-op is rewarded, never required.** Gating progress on other players
  trades a most-important signal (bounce) for a second-tier one (co-play).
  An earlier design had an "impossible alone" threat; it was dropped for
  exactly this reason.
- **Not a Steal-genre clone.** Roblox explicitly deprioritises games whose
  metadata and place files closely resemble existing ones.
- **No monetization yet** — next after the active layer. Planned: cosmetic
  plot skins, a second plot slot, time-skips that never gate content.

## Files touched

- `src/shared/Config.luau` — species table and tunables
- `src/shared/Growth.luau` — pure growth/payout math
- `src/server/Profiles.luau` — versioned DataStore saves via `UpdateAsync`;
  refuses to play rather than save a blank profile over a real one
- `src/server/PlotService.luau` — authoritative plot state and rendering
- `src/server/Main.server.luau` — remotes, join/leave, autosave, cosmetic tick
- `src/client/Main.client.luau` — balance readout, spore picker, prompt handler
- `tools/studio.py`, `tools/deploy.py` — stopgap MCP driver and deployer

## Gotchas discovered

The highest-value section. Each of these cost a failed attempt first.

- **`execute_luau` has its own module cache.** `require`ing a ModuleScript
  there returns a *different instance* from the running game, with empty
  state. Test stateful services through the remotes from the `Client`
  datamodel — the real path anyway.
- **Every bridge tool needs `studio_id`**; `execute_luau` also needs
  `datamodel_type` (`Edit` / `Client` / `Server`).
- **`list_roblox_studios` is empty for ~1s after the proxy spawns** while
  Studio reattaches. Poll it; `studio.py` does.
- **The bridge only attaches to a *published* place.** Unpublished means no
  universe; the Studio log shows `no universe context; no grant to mint`.
- **`deploy.py` needs Edit mode.** In a playtest it fails with
  `Edit datamodel is not available in Play mode`. Stop play first.
- **`GetDataStore()` succeeds with Studio API access off;** only the first
  call throws. `Profiles` treats that as permanent and falls back to memory
  instead of retrying it as an outage.
- **Gotham has no ✦.** Roblox draws a missing glyph as a tofu box and does
  not fall back to another font.
- **Game Settings is greyed out during a playtest.** Stop play to reach it.
