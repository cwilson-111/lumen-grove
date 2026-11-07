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
	-- Lifetime harvests needed before this species can be planted.
	unlockHarvests: number,
	-- What this plant does for the tiles beside it; see NEIGHBOUR BONUSES.
	aura: Aura,
}

export type Aura = {
	-- A species id, or nil for every species.
	target: string?,
	-- Added to the neighbour's payout multiplier: 0.3 is +30%.
	bonus: number,
}

export type Mutation = {
	id: string,
	name: string,
	-- Probability per planting, rolled independently in table order; the
	-- first hit wins, so rarer entries go first.
	chance: number,
	multiplier: number,
	-- nil means the colour cycles through the spectrum.
	colour: Color3?,
	-- Tell the whole server, not just the harvester.
	announce: boolean,
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

--[[
	The plot is a GRID x GRID square of tiles. A new grove has the centre
	STARTING_TILES of it; the rest are bought one at a time with lumen, in
	index order.

	Tile indices 1-9 are the centre 3x3, in the same row-major order the
	original 3x3 plot used, so a save written before the plot could grow
	puts every plant exactly where it was. 10-25 are the outer ring.
]]
Config.GRID = 5
Config.TILE_COUNT = Config.GRID * Config.GRID
Config.STARTING_TILES = 9
Config.TILE_STUDS = 8
Config.STARTING_LUMEN = 25

local layout: { Vector2 } = {}
for row = -1, 1 do
	for column = -1, 1 do
		table.insert(layout, Vector2.new(column, row))
	end
end
local half = (Config.GRID - 1) / 2
for row = -half, half do
	for column = -half, half do
		if math.max(math.abs(row), math.abs(column)) > 1 then
			table.insert(layout, Vector2.new(column, row))
		end
	end
end
-- Column and row of each tile index, counted from the plot's centre.
Config.TILE_LAYOUT = layout

-- Tile indices directly up, down, left and right of each tile -- never
-- diagonal -- on the full 5x5 grid, locked tiles included (they hold no
-- plants, so they simply contribute nothing).
local neighbours: { { number } } = {}
for index, cell in layout do
	local found = {}
	for other, candidate in layout do
		if math.abs(candidate.X - cell.X) + math.abs(candidate.Y - cell.Y) == 1 then
			table.insert(found, other)
		end
	end
	neighbours[index] = found
end
Config.NEIGHBOURS = neighbours

-- The n-th tile (n > STARTING_TILES) costs this much to unlock. Rises
-- ~32% a tile: the 10th is a few Voidlily harvests, the 25th is a goal.
function Config.tileUnlockCost(n: number): number
	return math.floor(150 * 1.32 ^ (n - Config.STARTING_TILES - 1) / 10 + 0.5) * 10
end

--[[
	Plots stand in rings around the hub at the world origin, each facing it.
	Eight to a ring; a server bigger than that starts a second, wider ring,
	offset half a step so its plots sit in the first ring's gaps. At radius
	90 the inner corners of neighbouring 46-stud plots stay ~9 studs apart.
]]
Config.PLOTS_PER_RING = 8
Config.PLOT_RING_RADIUS = 90
Config.PLOT_RING_GAP = 75
-- Where the grove's terrain surface actually is (see tools/world.luau).
Config.GROUND_Y = 2

function Config.plotCFrame(slot: number): CFrame
	local ring = (slot - 1) // Config.PLOTS_PER_RING
	local step = (slot - 1) % Config.PLOTS_PER_RING
	local angle = (step + (ring % 2) * 0.5) / Config.PLOTS_PER_RING * 2 * math.pi
	local radius = Config.PLOT_RING_RADIUS + ring * Config.PLOT_RING_GAP
	local height = Config.GROUND_Y + 0.5 -- a 1-stud base resting on the ground
	local position = Vector3.new(math.sin(angle) * radius, height, math.cos(angle) * radius)
	return CFrame.lookAt(position, Vector3.new(0, height, 0))
end

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
		unlockHarvests = 0,
		aura = { target = nil, bonus = 0.1 },
	},
	{
		id = "emberbloom",
		name = "Emberbloom",
		cost = 45,
		growSeconds = 120,
		value = 95,
		colour = Color3.fromRGB(255, 148, 86),
		unlockHarvests = 0,
		aura = { target = "voidlily", bonus = 0.3 },
	},
	{
		id = "voidlily",
		name = "Voidlily",
		cost = 180,
		growSeconds = 600,
		value = 520,
		colour = Color3.fromRGB(168, 130, 255),
		unlockHarvests = 0,
		aura = { target = "moonpetal", bonus = 0.3 },
	},
	-- The long growers are what make tomorrow worth opening the game for:
	-- plant before leaving, harvest on return. Gated by harvests so the
	-- first session is about learning the loop, not reading a price list.
	{
		id = "moonpetal",
		name = "Moonpetal",
		cost = 900,
		growSeconds = 1800,
		value = 2600,
		colour = Color3.fromRGB(214, 226, 255),
		unlockHarvests = 30,
		aura = { target = "starcap", bonus = 0.3 },
	},
	{
		id = "starcap",
		name = "Starcap",
		cost = 4000,
		growSeconds = 7200,
		value = 12500,
		colour = Color3.fromRGB(255, 112, 196),
		unlockHarvests = 100,
		aura = { target = nil, bonus = 0.15 },
	},
} :: { Species }

--[[
	NEIGHBOUR BONUSES: the reason arranging the grid is worth time. Every
	plant's `aura` raises the payout of the plants directly beside it --
	Glowcap and Starcap a little for anything, each mid-tier species a lot
	for the next tier up. A Starcap ringed by four Moonpetals pays +120%.

	Read from the plot as it stands *at harvest*, never stored: nothing about
	a tile's growth changes, so growth stays a pure function of time, and
	with four sides there is nothing to stack beyond four neighbours.

	DAILY DEW: a gift on the plot once per UTC day, from a player's second
	day on -- day one only says when it will come, which is a reason to come
	back for day two. It scales with the most valuable species the player has
	ever harvested, so it stays worth collecting as they progress, and with
	how many dews they have *ever* collected. That count never resets: a
	missed day costs nothing, so there is no streak to lose.

	HELPING: a visitor may tend a growing plant on someone else's plot,
	through the same tend (same cap, same cooldown) the owner uses, so
	helping speeds a friend up without ever making a plant grow faster than
	attentive play could. The helper is paid a small share of the plant's
	value, doubled between Roblox friends. Never required: nothing anywhere
	needs a second player.
]]
Config.DEW_MINIMUM = 100
Config.DEW_GROWTH_PER_DAY = 0.1
Config.DEW_MAX_DAYS = 20
Config.HELP_REWARD_FRACTION = 0.03
Config.HELP_FRIEND_MULTIPLIER = 2
Config.HELP_REACH = 20

-- Days are UTC, counted from the epoch, so every server agrees on them.
function Config.dayOf(unixTime: number): number
	return unixTime // 86400
end

-- The dew for a player whose best harvest is `bestValue` and who has
-- collected `dewsCollected` dews before this one.
function Config.dewAmount(bestValue: number, dewsCollected: number): number
	local growth = 1 + Config.DEW_GROWTH_PER_DAY * math.min(dewsCollected, Config.DEW_MAX_DAYS)
	return math.floor(math.max(Config.DEW_MINIMUM, bestValue) * growth + 0.5)
end

function Config.helpReward(species: Species, friends: boolean): number
	local reward = math.max(1, math.floor(species.value * Config.HELP_REWARD_FRACTION + 0.5))
	return friends and reward * Config.HELP_FRIEND_MULTIPLIER or reward
end

--[[
	Mutations: a planting sometimes comes up rare, worth several times its
	species' value. Rolled by the server when the seed goes in and stored on
	the tile, but shown to nobody -- not the plot, not the state push --
	until the plant is ripe. The surprise lands at harvest time, and the
	client cannot peek because it is never told.

	Tending does not touch the roll, and a save without the field is simply
	unmutated.
]]
Config.MUTATIONS = {
	{
		id = "prismatic",
		name = "Prismatic",
		chance = 1 / 150,
		multiplier = 12,
		colour = nil,
		announce = true,
	},
	{
		id = "golden",
		name = "Golden",
		chance = 1 / 20,
		multiplier = 3,
		colour = Color3.fromRGB(255, 206, 84),
		announce = false,
	},
} :: { Mutation }

function Config.mutationById(id: string?): Mutation?
	if id == nil then
		return nil
	end
	for _, mutation in Config.MUTATIONS do
		if mutation.id == id then
			return mutation
		end
	end
	return nil
end

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
