--!strict
--[[
	How far along a planted tile is, as a pure function of time.

	This is the load-bearing decision of the whole economy. Progress is NEVER
	stored as an accumulated number and never advanced by a tick loop. A tile
	records only which species it is and the unix second it was planted; how
	grown it is, is always recomputed as (now - plantedAt) / growSeconds.

	Three things fall out of that, all of them the point:

	1. Offline growth costs nothing. There is no catch-up pass on join, no
	   "time since last seen" reconciliation, and no risk of double-crediting
	   a player who rejoins twice quickly.
	2. A tampered save cannot invent progress. The worst a forged plantedAt
	   can claim is "planted earlier", which the server rejects outright
	   because it only ever writes os.time() itself.
	3. Changing a species' growSeconds retunes every existing plant at once,
	   with no migration.

	The client runs this too, purely to draw countdowns. The server never
	reads a client's answer.
]]

local Config = require(script.Parent.Config)

local Growth = {}

--[[
	`boost` and `lastTended` are optional so every save written before
	tending existed loads unchanged: absent means zero boost and never
	tended. No schema version bump, no migration.
]]
export type Tile = {
	species: string,
	plantedAt: number,
	boost: number?,
	lastTended: number?,
	-- Rolled by the server at planting; nil means no mutation. Optional for
	-- the same reason as boost: older saves load unchanged.
	mutation: string?,
}

--[[
	Effective age in seconds: real time since planting plus any tending head
	start. Every other function here derives from this one number, so
	tending cannot drift out of agreement between progress, countdown and
	payout.
]]
local function age(tile: Tile, now: number): number
	return (now - tile.plantedAt) + (tile.boost or 0)
end

--[[
	0 at the moment of planting, 1 when ripe. Clamped at both ends: a clock
	that steps backwards must not produce a negative stage, and a plant left
	for a week is ripe, not 2000x ripe.
]]
function Growth.progress(tile: Tile, now: number): number
	local species = Config.speciesById(tile.species)
	if not species then
		return 0
	end
	local effective = age(tile, now)
	if effective <= 0 then
		return 0
	end
	return math.min(effective / species.growSeconds, 1)
end

function Growth.isRipe(tile: Tile, now: number): boolean
	return Growth.progress(tile, now) >= 1
end

function Growth.secondsRemaining(tile: Tile, now: number): number
	local species = Config.speciesById(tile.species)
	if not species then
		return 0
	end
	return math.max(species.growSeconds - age(tile, now), 0)
end

--[[
	Seconds of head start one tend would add right now, or 0 when it would
	add nothing. Returns the clipped amount rather than a yes/no so the
	server credits exactly what this says and the cap is enforced in one
	place: a tend that would overshoot the cap adds only the remainder.
]]
function Growth.tendAmount(tile: Tile, now: number): number
	local species = Config.speciesById(tile.species)
	if not species or Growth.isRipe(tile, now) then
		return 0
	end
	local cap = species.growSeconds * Config.TEND_MAX_FRACTION
	local headroom = cap - (tile.boost or 0)
	if headroom <= 0 then
		return 0
	end
	return math.min(species.growSeconds * Config.TEND_FRACTION, headroom)
end

--[[
	Seconds until this tile can be tended again; 0 means now. Scales with the
	species' grow time (see Config) so tends spread through the grow rather
	than all landing in its first seconds.

	Independent of the cap on purpose: "cooling down" and "nothing left to
	gain" are different answers, and the UI shows them differently.
]]
function Growth.tendCooldown(tile: Tile, now: number): number
	if not tile.lastTended then
		return 0
	end
	local species = Config.speciesById(tile.species)
	if not species then
		return 0
	end
	local period = math.max(
		species.growSeconds * Config.TEND_COOLDOWN_FRACTION,
		Config.TEND_COOLDOWN_MIN_SECONDS
	)
	return math.max(period - (now - tile.lastTended), 0)
end

--[[
	What harvesting this tile pays. Deliberately zero before ripeness rather
	than a pro-rata amount, so there is no incentive to spam-harvest early,
	and so the server's answer is a single comparison rather than a curve
	that has to agree with the client's.
]]
function Growth.payout(tile: Tile, now: number): number
	local species = Config.speciesById(tile.species)
	if not species or not Growth.isRipe(tile, now) then
		return 0
	end
	local mutation = Config.mutationById(tile.mutation)
	return species.value * (mutation and mutation.multiplier or 1)
end

return Growth
