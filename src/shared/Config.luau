--!strict
--[[
	Every tunable in one place, shared by the server and the client.

	The client reads this only to *display* timers and prices. It is never
	trusted: the server recomputes every value from this same table, so a
	client that edits its own copy changes what it draws and nothing else.
]]

export type Species = {
	id: string,
	name: string,
	cost: number,
	growSeconds: number,
	value: number,
	colour: Color3,
}

local Config = {}

Config.TILE_COUNT = 9
Config.TILES_PER_ROW = 3
Config.TILE_STUDS = 8
Config.STARTING_LUMEN = 25

--[[
	Tending: the active layer. Being present lets you speed a plant up; being
	absent never slows one down.

	Each tend adds TEND_FRACTION of the species' grow time as a head start, up
	to TEND_MAX_FRACTION in total. The cap is what keeps idle play worthwhile:
	an attentive player halves the wait, but cannot make the clock irrelevant.
	There is no decay anywhere -- an untended plant grows at exactly its normal
	rate, so leaving the game is never punished.

	The cooldown scales with grow time rather than being a flat number. With a
	flat 8 seconds, a Voidlily (600s) took all four of its tends in the first
	24 seconds and then gave the player nothing to do for five minutes -- the
	active layer front-loaded its whole value, which defeats the point of it.
	Scaled, the tends land through the grow instead, so there is a reason to
	come back to the plot while it ripens. The floor stops a fast species from
	becoming a button to mash.
]]
Config.TEND_FRACTION = 0.15
Config.TEND_MAX_FRACTION = 0.5
Config.TEND_COOLDOWN_FRACTION = 0.1
Config.TEND_COOLDOWN_MIN_SECONDS = 4

-- Growth is derived from a planting timestamp, never accumulated into a
-- stored number (see Growth.luau). That is what makes offline growth free
-- and makes a tampered save unable to invent progress.
Config.SPECIES = {
	{
		id = "glowcap",
		name = "Glowcap",
		cost = 10,
		growSeconds = 30,
		value = 18,
		colour = Color3.fromRGB(126, 224, 168),
	},
	{
		id = "emberbloom",
		name = "Emberbloom",
		cost = 45,
		growSeconds = 120,
		value = 95,
		colour = Color3.fromRGB(255, 148, 86),
	},
	{
		id = "voidlily",
		name = "Voidlily",
		cost = 180,
		growSeconds = 600,
		value = 520,
		colour = Color3.fromRGB(168, 130, 255),
	},
} :: { Species }

function Config.speciesById(id: string): Species?
	for _, species in Config.SPECIES do
		if species.id == id then
			return species
		end
	end
	return nil
end

return Config
