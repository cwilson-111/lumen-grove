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

export type Tile = {
	species: string,
	plantedAt: number,
}

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
	local elapsed = now - tile.plantedAt
	if elapsed <= 0 then
		return 0
	end
	return math.min(elapsed / species.growSeconds, 1)
end

function Growth.isRipe(tile: Tile, now: number): boolean
	return Growth.progress(tile, now) >= 1
end

function Growth.secondsRemaining(tile: Tile, now: number): number
	local species = Config.speciesById(tile.species)
	if not species then
		return 0
	end
	return math.max(species.growSeconds - (now - tile.plantedAt), 0)
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
	return species.value
end

return Growth
