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

export type Skin = {
	id: string,
	name: string,
	-- nil for a skin every player owns. Otherwise the game pass that unlocks
	-- it; the price lives on the pass, not here, so it cannot drift.
	gamePassId: number?,
	baseColour: Color3,
	baseMaterial: Enum.Material,
	tileColour: Color3,
	tileMaterial: Enum.Material,
	-- nil for no rim. Otherwise a glowing border around the plot.
	trimColour: Color3?,
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

--[[
	Plot skins: the first thing for sale, chosen because it cannot feel like a
	paywall. A skin changes how a plot looks to everyone in the server and
	nothing else -- no growth, payout or tending number reads it. The rule for
	everything sold here: no purchase may make a non-paying player's game
	worse.

	Game passes rather than developer products, because a skin is owned once
	and forever. Roblox records pass ownership itself, so a lost save cannot
	lose a purchase, and a pass cannot be bought twice by accident.

	The first entry is the default every player owns.
]]
Config.SKINS = {
	{
		id = "slate",
		name = "Slate",
		gamePassId = nil,
		baseColour = Color3.fromRGB(46, 52, 64),
		baseMaterial = Enum.Material.Slate,
		tileColour = Color3.fromRGB(70, 78, 94),
		tileMaterial = Enum.Material.Sand,
		trimColour = nil,
	},
	{
		id = "crystal",
		name = "Crystal Hollow",
		gamePassId = 2075151059,
		baseColour = Color3.fromRGB(178, 214, 236),
		baseMaterial = Enum.Material.Glacier,
		tileColour = Color3.fromRGB(226, 240, 250),
		tileMaterial = Enum.Material.Marble,
		trimColour = Color3.fromRGB(120, 230, 255),
	},
	{
		id = "ember",
		name = "Ember Hearth",
		gamePassId = 2074455097,
		baseColour = Color3.fromRGB(40, 30, 28),
		baseMaterial = Enum.Material.Basalt,
		tileColour = Color3.fromRGB(110, 50, 30),
		tileMaterial = Enum.Material.CrackedLava,
		trimColour = Color3.fromRGB(255, 128, 48),
	},
	{
		id = "starfall",
		name = "Starfall",
		gamePassId = 2074929162,
		baseColour = Color3.fromRGB(26, 22, 48),
		baseMaterial = Enum.Material.Granite,
		tileColour = Color3.fromRGB(58, 48, 104),
		tileMaterial = Enum.Material.Pavement,
		trimColour = Color3.fromRGB(190, 150, 255),
	},
} :: { Skin }

Config.DEFAULT_SKIN = Config.SKINS[1].id

function Config.skinById(id: string): Skin?
	for _, skin in Config.SKINS do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

function Config.skinByGamePass(gamePassId: number): Skin?
	for _, skin in Config.SKINS do
		if skin.gamePassId == gamePassId then
			return skin
		end
	end
	return nil
end

return Config
