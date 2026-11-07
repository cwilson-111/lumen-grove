# Handoff

> Current state, not a log. Overwrite rather than append. Read by the next
> session — or the hourly resume job — to continue without re-deriving anything.

**Written:** 2026-11-07 (after daily dew, neighbour bonuses, helping, store media)
**Repo:** `cwilson-111/lumen-grove`, branch `main`
**Place:** published, placeId `119675424382289`, universeId `10774896318`,
visibility **PRIVATE**, server size **8**, display name still **"first"**
**Studio id (this machine, this run):** `5fff069f-e222-43e2-b2bf-7cacc8f9b603`
— re-read with `list_roblox_studios`; it changes when Studio restarts.

## Goal

An idle-grow Roblox game built to the signals Roblox's Home recommendations
rank on (`create.roblox.com/docs/discovery`): play through rate, first play
bounce rate, **play days per user** and **playtime per user** top tier;
co-play and the two Robux-spend signals one below.

## Done

Verified by driving the live place over Studio MCP unless marked otherwise.

- [x] Loop, tending, persistence, skins (3 passes), grove world, mutations,
      species unlocks, 5×5 expansion — see README.
- [x] **Neighbour bonuses.** Pure math checked against hand values (bonus
      0.40 → payout 728; ×3 golden → 2184; diagonals excluded). Live: a
      Glowcap with three Glowcap neighbours paid 70 (18 × 1.3 × 3, golden);
      harvest order changed later bonuses as expected; prompt preview read
      `Glowcap · +30%`.
- [x] **Daily dew.** Migrated save (v3 → v4) had dew ready; collected +100
      through the real prompt; second collect refused; dewdrop removed;
      label `Next dew in 22h 18m`. Dew math checked (100 / 520 / 780 / 1560).
- [x] **Helping.** Server path and prompt roles verified solo (owner sees 12
      owner prompts, 0 help prompts). **Two-player flow verified by the user
      by hand** in Studio's Clients and Servers test: help prompt only for the
      visitor, both toasts, hidden during cooldown and when ripe.
- [x] **Icon + thumbnails** (`assets/marketing/`): icon uploaded, **InReview**;
      detail-page thumbnail live on the CDN (`state: Completed`); Home page
      thumbnail **Approved, Active** (homepageThumbnailId
      `797547bc-4685-4f55-b850-ae09b8271fad`).

## Not yet done / needs the user

- **Publish the place** (File → Publish to Roblox). Every script change this
  session exists only in the open Studio session until then.
- **Rename the experience.** It is still called "first" on Roblox. Not done
  without asking: the name is the user's call.
- Skin purchase by a non-owner: still untested (creator owns their passes).
- Usage budget: `~/.omp/agent/usage-budget.json` is still the $60/5h
  placeholder.

**Next action:** ask the user. Candidates: rename + description, a second
Home thumbnail (personalization needs ≥ 2), plant models instead of spheres,
time-skips, making the place public.

## Deliberately not done

- **Neighbour bonus is read at harvest, never stored** — keeps growth pure
  and caps stacking at four sides.
- **No dew on day one** — only the promise of tomorrow's.
- **Dew count never resets** — no streak to lose.
- **Helping is the owner's ordinary tend** — same cap and cooldown.
- **No decay; co-op rewarded, never required; skins are game passes.**

## Files touched this session

- `src/shared/Config.luau` — `Aura`, species auras, `NEIGHBOURS`, dew and help
  tunables, `dayOf`, `dewAmount`, `helpReward`
- `src/shared/Growth.luau` — `neighbourBonus`; `payout(tile, now, bonus)`
- `src/server/Daily.luau` — new
- `src/server/Profiles.luau` — schema v4: `firstDay`, `lastDewDay`,
  `dewsCollected`, `bestValue`
- `src/server/PlotService.luau` — prompt `Role`/`Active`, `HelpPrompt`,
  `help`, `setDew`, bonus in harvest and prompts, `bestValue`
- `src/server/Main.server.luau` — `CollectDew`, `Help`, `Notice`; dew in state
- `src/client/Main.client.luau` — dew line, aura text, role-based prompt
  visibility, dew/help routing, notices
- `assets/marketing/` — icon and thumbnail

## Gotchas discovered

- **Multi-client test windows are invisible to MCP.** Two-player paths need
  the user.
- **`screen_capture` returns base64 JPEG** in
  `details.rawContent[0].data` (1920×888 here) — usable for marketing images.
- **Assets API rejects cookie auth**; legacy `publish.roblox.com` icon and
  thumbnail endpoints and the thumbnail-personalization API accept it.
- **Server code must never set `ProximityPrompt.Enabled`** — the client owns
  it (see PlotService header).
- Earlier: terrain surfaces at y = 2; forced-odds testing; `InputHoldBegin`
  presses real prompts; `execute_luau` module cache.
