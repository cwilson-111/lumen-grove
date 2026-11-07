--!strict
--[[
	The authoritative plot: who owns which plot, what is planted, and what a
	harvest pays.

	The client sends intents only -- "plant species X on tile 4", "tap tile
	4", "unlock the next tile", "help tend tile 4 of that plot". It never
	sends a price, a payout, a timestamp or a balance. Every number here is
	read from Config or from os.time() on this machine, so the only thing a
	modified client can do is ask for something it is not allowed to have,
	and be told no.

	Prompts are never enabled or disabled here. Each carries a `Role`
	("owner" or "visitor") and an `Active` attribute; every client turns on
	only the prompts that are active *and* meant for it, because the same
	plot needs different prompts for its owner and for everyone else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Growth = require(ReplicatedStorage.Shared.Growth)
local PlantModels = require(script.Parent.PlantModels)
local Profiles = require(script.Parent.Profiles)

local PlotService = {}

local plotsFolder: Folder? = nil
local assigned: { [Player]: number } = {}
local plotModels: { [number]: Model } = {}
local random = Random.new()

local LOCKED_TRANSPARENCY = 0.85
local NEXT_TRANSPARENCY = 0.55

export type Outcome = {
	ok: boolean,
	message: string,
	-- Set on a harvest that paid out a mutation, so the caller can decide
	-- whether to tell the server.
	mutation: string?,
	-- The species name involved, for the caller's announcements.
	species: string?,
	-- Seconds of head start a tend added, for telling a helped owner.
	amount: number?,
}

local function newPrompt(name: string, role: string, index: number, parent: Instance): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Role", role)
	prompt:SetAttribute("Active", false)
	prompt:SetAttribute("TileIndex", index)
	prompt.Parent = parent
	return prompt
end

-- -- world ------------------------------------------------------------- --

local function plotSize(): number
	return Config.GRID * Config.TILE_STUDS + 6
end

local function buildPlot(slot: number): Model
	local frame = Config.plotCFrame(slot)

	local model = Instance.new("Model")
	model.Name = "Plot" .. slot

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(plotSize(), 1, plotSize())
	base.CFrame = frame
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model
	model.PrimaryPart = base

	-- A soft lamp over every plot, so the grove's night still reads as a
	-- place to garden rather than a dark field.
	local lampMount = Instance.new("Attachment")
	lampMount.Name = "Lamp"
	lampMount.Position = Vector3.new(0, 14, 0)
	lampMount.Parent = base
	local lamp = Instance.new("PointLight")
	lamp.Range = 40
	lamp.Brightness = 1.6
	lamp.Color = Color3.fromRGB(176, 214, 255)
	lamp.Shadows = false
	lamp.Parent = lampMount

	-- Whose grove this is, on the edge facing the hub.
	local signMount = Instance.new("Attachment")
	signMount.Name = "Sign"
	signMount.Position = Vector3.new(0, 12, -plotSize() / 2)
	signMount.Parent = base
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	-- Sized in studs, not pixels: it shrinks with distance like the world
	-- does, instead of covering the view of a player standing on the plot.
	sign.Size = UDim2.new(14, 0, 2, 0)
	sign.MaxDistance = 160
	sign.LightInfluence = 0
	sign.Adornee = signMount
	sign.Parent = signMount
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(236, 240, 248)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = sign

	for index = 1, Config.TILE_COUNT do
		local cell = Config.TILE_LAYOUT[index]
		local tile = Instance.new("Part")
		tile.Name = "Tile" .. index
		tile.Anchored = true
		tile.Size = Vector3.new(Config.TILE_STUDS - 1, 0.4, Config.TILE_STUDS - 1)
		tile.CFrame = frame * CFrame.new(cell.X * Config.TILE_STUDS, 0.7, cell.Y * Config.TILE_STUDS)
		tile.TopSurface = Enum.SurfaceType.Smooth
		tile.Parent = model

		-- One owner prompt and one visitor prompt per tile is the whole
		-- input surface. No free-form clicking, so the client cannot address
		-- a tile that does not exist.
		newPrompt("Prompt", "owner", index, tile)
		local help = newPrompt("HelpPrompt", "visitor", index, tile)
		help.ActionText = "Help tend"
	end

	model.Parent = plotsFolder
	return model
end

--[[
	Repaint a plot in a skin. Touches colour, material and the optional rim and
	nothing else: no part a prompt, a plant or the economy depends on is
	created or destroyed here, except the rim, which nothing reads.
]]
local function paint(plot: Model, skin: Config.Skin)
	local base = plot:FindFirstChild("Base") :: Part?
	if not base then
		return
	end
	base.Color = skin.baseColour
	base.Material = skin.baseMaterial
	for index = 1, Config.TILE_COUNT do
		local tile = plot:FindFirstChild("Tile" .. index) :: Part?
		if tile then
			tile.Color = skin.tileColour
			tile.Material = skin.tileMaterial
		end
	end

	local oldTrim = plot:FindFirstChild("Trim")
	if oldTrim then
		oldTrim:Destroy()
	end
	local trimColour = skin.trimColour
	if not trimColour then
		return
	end
	local trim = Instance.new("Model")
	trim.Name = "Trim"
	local size = base.Size
	local lift = size.Y / 2 + 0.25
	local edges = {
		{ Vector3.new(0, lift, size.Z / 2), Vector3.new(size.X + 1, 0.5, 1) },
		{ Vector3.new(0, lift, -size.Z / 2), Vector3.new(size.X + 1, 0.5, 1) },
		{ Vector3.new(size.X / 2, lift, 0), Vector3.new(1, 0.5, size.Z + 1) },
		{ Vector3.new(-size.X / 2, lift, 0), Vector3.new(1, 0.5, size.Z + 1) },
	}
	for _, edge in edges do
		local strip = Instance.new("Part")
		strip.Anchored = true
		strip.CanCollide = false
		strip.CastShadow = false
		strip.Material = Enum.Material.Neon
		strip.Color = trimColour
		strip.Size = edge[2]
		strip.CFrame = base.CFrame * CFrame.new(edge[1])
		strip.Parent = trim
	end
	trim.Parent = plot
end

local function plantPart(plot: Model, index: number): Model?
	local tile = plot:FindFirstChild("Tile" .. index)
	return tile and tile:FindFirstChild("Plant") :: Model?
end

local function setSign(plot: Model, text: string)
	local base = plot:FindFirstChild("Base")
	local label = base and base:FindFirstChild("Label", true) :: TextLabel?
	if label then
		label.Text = text
	end
end

--[[
	How a tile with nothing planted on it looks, given how many tiles its
	owner has. Called for every empty tile on each render and, with the
	starting count, when a plot is built or released -- so a plot nobody owns
	shows a fresh grove, not the last owner's.
]]
local function drawEmptyTile(tile: Part, index: number, tileCount: number)
	local prompt = tile:FindFirstChild("Prompt") :: ProximityPrompt?
	local help = tile:FindFirstChild("HelpPrompt") :: ProximityPrompt?
	if help then
		help:SetAttribute("Active", false)
	end
	if index <= tileCount then
		tile.Transparency = 0
		if prompt then
			prompt:SetAttribute("Active", true)
			prompt.ActionText = "Plant"
			prompt.ObjectText = "Tile " .. index
		end
	elseif index == tileCount + 1 then
		-- Only the next tile in order is for sale, so the client never has
		-- to say which one it is buying.
		tile.Transparency = NEXT_TRANSPARENCY
		if prompt then
			prompt:SetAttribute("Active", true)
			prompt.ActionText = "Unlock"
			prompt.ObjectText = ("%d lumen"):format(Config.tileUnlockCost(index))
		end
	else
		tile.Transparency = LOCKED_TRANSPARENCY
		if prompt then
			prompt:SetAttribute("Active", false)
		end
	end
end

local function resetPlot(plot: Model)
	for index = 1, Config.TILE_COUNT do
		local existing = plantPart(plot, index)
		if existing then
			existing:Destroy()
		end
		local tile = plot:FindFirstChild("Tile" .. index) :: Part?
		if tile then
			drawEmptyTile(tile, index, Config.STARTING_TILES)
		end
	end
	setSign(plot, "")
	local dew = plot:FindFirstChild("Dewdrop")
	if dew then
		dew:Destroy()
	end
	paint(plot, Config.SKINS[1])
end

local function mutationColour(mutation: Config.Mutation, index: number): Color3
	-- A colour that cycles, for the rarest: the slow render tick steps it
	-- around the wheel. Each tile is offset, so several Prismatics side by
	-- side read as a rainbow rather than one pale colour in lockstep.
	return mutation.colour or Color3.fromHSV((os.clock() / 4 + index * 0.17) % 1, 0.8, 1)
end

--[[
	Redraw one tile from the profile. Called after every change and on a
	slow cosmetic tick; it is pure presentation, so a dropped frame costs
	nothing but a stale colour.
]]
local function renderTile(player: Player, index: number)
	local slot = assigned[player]
	local plot = slot and plotModels[slot]
	local profile = Profiles.get(player)
	if not plot or not profile then
		return
	end

	local tilePart = plot:FindFirstChild("Tile" .. index) :: Part?
	if not tilePart then
		return
	end
	local prompt = tilePart:FindFirstChild("Prompt") :: ProximityPrompt?
	local help = tilePart:FindFirstChild("HelpPrompt") :: ProximityPrompt?
	local saved = profile.tiles[tostring(index)]
	local existing = plantPart(plot, index)
	local species = saved and Config.speciesById(saved.species)

	if not saved or not species then
		if existing then
			existing:Destroy()
		end
		drawEmptyTile(tilePart, index, profile.tileCount)
		return
	end

	local now = os.time()
	local progress = Growth.progress(saved, now)
	local ripe = progress >= 1
	-- The roll exists from the moment of planting, but nothing shows it
	-- until the plant is ripe.
	local mutation = ripe and Config.mutationById(saved.mutation) or nil

	-- Rebuilt rather than reshaped if the tile now holds a different
	-- species (harvested and replanted between two renders).
	local plant = existing
	if plant and plant:GetAttribute("Species") ~= species.id then
		plant:Destroy()
		plant = nil
	end
	if not plant then
		local built = PlantModels.build(species)
		built.Parent = tilePart
		plant = built
	end
	assert(plant)

	local colour = mutation and mutationColour(mutation, index) or species.colour
	local ground = tilePart.Position + Vector3.new(0, tilePart.Size.Y / 2, 0)
	PlantModels.pose(plant, species.id, progress, ripe, colour, ground)

	local cap = PlantModels.mainCap(plant)
	-- Brighter as it ripens, so a ripe plot is visible from across the
	-- grove: the harvest is the thing worth walking back for.
	local glow = cap and cap:FindFirstChild("Glow") :: PointLight?
	if glow then
		glow.Color = colour
		glow.Range = ripe and 14 or 4 + progress * 6
		glow.Brightness = ripe and 2.2 or 0.4 + progress * 0.6
	end

	local sparkles = cap and cap:FindFirstChild("Sparkles") :: Sparkles?
	if mutation and cap then
		if not sparkles then
			local made = Instance.new("Sparkles")
			made.Name = "Sparkles"
			made.Parent = cap
			sparkles = made
		end
		assert(sparkles)
		sparkles.SparkleColor = colour
	elseif sparkles then
		sparkles:Destroy()
	end

	tilePart.Transparency = 0
	local bonus = Growth.neighbourBonus(profile.tiles, index)
	local name = mutation and ("%s %s"):format(mutation.name, species.name) or species.name
	if bonus > 0 then
		name = ("%s · +%d%%"):format(name, math.floor(bonus * 100 + 0.5))
	end
	local tendable = not ripe and Growth.tendAmount(saved, now) > 0 and Growth.tendCooldown(saved, now) <= 0
	if prompt then
		prompt:SetAttribute("Active", true)
		prompt.ObjectText = name
		local remaining = Format.duration(Growth.secondsRemaining(saved, now))
		if ripe then
			prompt.ActionText = "Harvest"
		elseif Growth.tendAmount(saved, now) <= 0 then
			-- Fully tended: nothing more to gain, so do not invite a press
			-- that can only be refused.
			prompt.ActionText = ("Growing · %s"):format(remaining)
		elseif not tendable then
			prompt.ActionText = ("Tend in %s · %s"):format(Format.duration(Growth.tendCooldown(saved, now)), remaining)
		else
			prompt.ActionText = ("Tend · %s"):format(remaining)
		end
	end
	if help then
		-- Visitors are only ever offered a press that will work.
		help:SetAttribute("Active", tendable)
		help.ObjectText = ("%s's %s"):format(player.DisplayName, species.name)
	end
end

function PlotService.renderAll(player: Player)
	for index = 1, Config.TILE_COUNT do
		renderTile(player, index)
	end
end

-- -- intents ----------------------------------------------------------- --

-- Validate the index rather than trusting it: an unchecked index is how a
-- client writes an arbitrary key into someone's save. A tile the player has
-- not unlocked does not exist as far as planting is concerned.
local function ownedTile(profile: any, tileIndex: any): boolean
	return typeof(tileIndex) == "number"
		and tileIndex % 1 == 0
		and tileIndex >= 1
		and tileIndex <= profile.tileCount
end

local function rollMutation(): string?
	for _, mutation in Config.MUTATIONS do
		if random:NextNumber() < mutation.chance then
			return mutation.id
		end
	end
	return nil
end

function PlotService.plant(player: Player, tileIndex: any, speciesId: any): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if not ownedTile(profile, tileIndex) then
		return { ok = false, message = "No such tile." }
	end
	if typeof(speciesId) ~= "string" then
		return { ok = false, message = "No such spore." }
	end

	local species = Config.speciesById(speciesId)
	if not species then
		return { ok = false, message = "No such spore." }
	end
	if profile.harvested < species.unlockHarvests then
		return {
			ok = false,
			message = ("%s unlocks at %d harvests."):format(species.name, species.unlockHarvests),
		}
	end

	local slotKey = tostring(tileIndex)
	if profile.tiles[slotKey] then
		return { ok = false, message = "Something is already growing there." }
	end
	if profile.lumen < species.cost then
		return { ok = false, message = ("%s costs %d lumen."):format(species.name, species.cost) }
	end

	profile.lumen -= species.cost
	-- os.time() on the server, never a value from the client; the mutation
	-- is rolled here too, and kept from the client until ripe.
	profile.tiles[slotKey] = { species = species.id, plantedAt = os.time(), mutation = rollMutation() }
	renderTile(player, tileIndex)
	return { ok = true, message = ("Planted %s."):format(species.name) }
end

function PlotService.harvest(player: Player, tileIndex: any): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if not ownedTile(profile, tileIndex) then
		return { ok = false, message = "No such tile." }
	end

	local slotKey = tostring(tileIndex)
	local saved = profile.tiles[slotKey]
	if not saved then
		return { ok = false, message = "Nothing growing there." }
	end

	local now = os.time()
	-- Read the neighbours before the tile is cleared; the bonus is the board
	-- as it stands at this moment.
	local bonus = Growth.neighbourBonus(profile.tiles, tileIndex)
	local payout = Growth.payout(saved, now, bonus)
	if payout <= 0 then
		return {
			ok = false,
			message = ("Not ready for %s."):format(Format.duration(Growth.secondsRemaining(saved, now))),
		}
	end

	-- Clear the tile BEFORE crediting, so a yield between the two cannot be
	-- raced into a double payout.
	profile.tiles[slotKey] = nil
	profile.lumen += payout
	profile.harvested += 1
	local species = Config.speciesById(saved.species)
	if species then
		profile.bestValue = math.max(profile.bestValue, species.value)
	end
	renderTile(player, tileIndex)

	local extra = bonus > 0 and ("  (+%d%% from neighbours)"):format(math.floor(bonus * 100 + 0.5)) or ""
	local mutation = Config.mutationById(saved.mutation)
	if mutation and species then
		return {
			ok = true,
			message = ("%s %s!  +%d lumen.%s"):format(mutation.name, species.name, payout, extra),
			mutation = mutation.id,
			species = species.name,
		}
	end
	return { ok = true, message = ("+%d lumen.%s"):format(payout, extra) }
end

-- The tend itself, shared by an owner tending and a visitor helping. The
-- caller has already validated the tile against `owner`'s profile.
local function tendTile(owner: Player, saved: any, tileIndex: number): Outcome
	local now = os.time()
	local cooldown = Growth.tendCooldown(saved, now)
	if cooldown > 0 then
		return { ok = false, message = ("Let it rest %s."):format(Format.duration(cooldown)) }
	end
	local amount = Growth.tendAmount(saved, now)
	if amount <= 0 then
		return { ok = false, message = "It's had all the tending it can use." }
	end

	-- Both written from this machine's clock and Growth's own answer; nothing
	-- here comes from the client but the index, already validated.
	saved.boost = (saved.boost or 0) + amount
	saved.lastTended = now
	renderTile(owner, tileIndex)
	return { ok = true, message = ("Tended — %s sooner."):format(Format.duration(amount)), amount = amount }
end

function PlotService.tend(player: Player, tileIndex: any): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if not ownedTile(profile, tileIndex) then
		return { ok = false, message = "No such tile." }
	end
	local saved = profile.tiles[tostring(tileIndex)]
	if not saved then
		return { ok = false, message = "Nothing growing there." }
	end
	return tendTile(player, saved, tileIndex)
end

-- [helper][ownerUserId] = whether they are Roblox friends. IsFriendsWith is
-- a web call; a friendship does not change mid-session often enough to ask
-- again on every tend.
local friendCache: { [Player]: { [number]: boolean } } = {}

local function areFriends(helper: Player, owner: Player): boolean
	local known = friendCache[helper]
	if not known then
		known = {}
		friendCache[helper] = known
	end
	assert(known)
	local cached = known[owner.UserId]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return helper:IsFriendsWith(owner.UserId)
	end)
	-- A failed lookup counts as "not friends" and is not cached, so it is
	-- asked again next time rather than costing the pair their bonus forever.
	if ok then
		known[owner.UserId] = result
		return result
	end
	return false
end

--[[
	A visitor tends a growing plant on someone else's plot. The owner's plant
	gets an ordinary tend -- same cap, same cooldown -- and the helper earns a
	small share of the plant's value. A visitor can never plant on, harvest
	from or otherwise change another player's plot.

	Returns (outcome for the helper, owner to notify or nil).
]]
function PlotService.help(helper: Player, ownerUserId: any, tileIndex: any): (Outcome, Player?)
	local helperProfile = Profiles.get(helper)
	if not helperProfile then
		return { ok = false, message = "Your grove is still loading." }, nil
	end
	if typeof(ownerUserId) ~= "number" then
		return { ok = false, message = "No one to help there." }, nil
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local ownerProfile = owner and Profiles.get(owner)
	if not owner or owner == helper or not ownerProfile then
		return { ok = false, message = "No one to help there." }, nil
	end
	if not ownedTile(ownerProfile, tileIndex) then
		return { ok = false, message = "No such tile." }, nil
	end

	-- The helper has to actually be at the plant: a remote fired from across
	-- the map is not helping.
	local plot = PlotService.plotOf(owner)
	local tilePart = plot and plot:FindFirstChild("Tile" .. tileIndex) :: Part?
	local character = helper.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not tilePart or not root or (root.Position - tilePart.Position).Magnitude > Config.HELP_REACH then
		return { ok = false, message = "Get closer to help." }, nil
	end

	local saved = ownerProfile.tiles[tostring(tileIndex)]
	local species = saved and Config.speciesById(saved.species)
	if not saved or not species then
		return { ok = false, message = "Nothing growing there." }, nil
	end
	if Growth.isRipe(saved, os.time()) then
		return { ok = false, message = ("It's ripe — that's %s's to harvest."):format(owner.DisplayName) }, nil
	end

	local tended = tendTile(owner, saved, tileIndex)
	if not tended.ok then
		return tended, nil
	end
	local friends = areFriends(helper, owner)
	local reward = Config.helpReward(species, friends)
	helperProfile.lumen += reward
	return {
		ok = true,
		message = ("Helped %s's %s — +%d lumen%s."):format(
			owner.DisplayName,
			species.name,
			reward,
			friends and " (friends ×2)" or ""
		),
		species = species.name,
		amount = tended.amount,
	},
		owner
end

--[[
	Show or remove the day's dewdrop on a player's plot. Its prompt is for
	the owner only; everyone else just sees the drop.
]]
function PlotService.setDew(player: Player, ready: boolean)
	local plot = PlotService.plotOf(player)
	if not plot then
		return
	end
	local existing = plot:FindFirstChild("Dewdrop")
	if not ready then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local base = plot:FindFirstChild("Base") :: Part?
	if not base then
		return
	end
	local drop = Instance.new("Part")
	drop.Name = "Dewdrop"
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(2.6, 2.6, 2.6)
	drop.Anchored = true
	drop.CanCollide = false
	drop.CastShadow = false
	drop.Material = Enum.Material.Neon
	drop.Color = Color3.fromRGB(150, 230, 255)
	-- Over the hub-facing border, beside the owner's sign: the first thing a
	-- player walking home from the hub reaches.
	drop.CFrame = base.CFrame * CFrame.new(0, 3.5, -(base.Size.Z / 2) + 1.5)
	local light = Instance.new("PointLight")
	light.Color = drop.Color
	light.Range = 12
	light.Brightness = 2
	light.Parent = drop
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = drop.Color
	sparkles.Parent = drop
	local prompt = newPrompt("DewPrompt", "owner", 0, drop)
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Morning dew"
	prompt:SetAttribute("Active", true)
	drop.Parent = plot
end

--[[
	The only intent for an occupied tile. The server, not the client, decides
	whether that means harvest or tend: the client's view of ripeness is the
	last state push, up to a second stale, and a client that picked "tend" on
	a plant that had just ripened would be told no for no reason the player
	could see.
]]
function PlotService.tap(player: Player, tileIndex: any): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if not ownedTile(profile, tileIndex) then
		return { ok = false, message = "No such tile." }
	end
	local saved = profile.tiles[tostring(tileIndex)]
	if saved and Growth.isRipe(saved, os.time()) then
		return PlotService.harvest(player, tileIndex)
	end
	return PlotService.tend(player, tileIndex)
end

--[[
	Buy the next tile. Takes no argument: only the next tile in order is ever
	for sale, so there is nothing for the client to choose and nothing to
	validate but the balance.
]]
function PlotService.expand(player: Player): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	local next = profile.tileCount + 1
	if next > Config.TILE_COUNT then
		return { ok = false, message = "Your grove is as big as it grows." }
	end
	local cost = Config.tileUnlockCost(next)
	if profile.lumen < cost then
		return { ok = false, message = ("The next tile costs %d lumen."):format(cost) }
	end

	profile.lumen -= cost
	profile.tileCount = next
	renderTile(player, next)
	if next < Config.TILE_COUNT then
		renderTile(player, next + 1)
	end
	return { ok = true, message = ("Tile %d unlocked."):format(next) }
end

-- -- lifecycle --------------------------------------------------------- --

function PlotService.assign(player: Player): Model
	local slot = 1
	while true do
		local taken = false
		for _, used in assigned do
			if used == slot then
				taken = true
				break
			end
		end
		if not taken then
			break
		end
		slot += 1
	end

	assigned[player] = slot
	local plot = plotModels[slot]
	if not plot then
		plot = buildPlot(slot)
		resetPlot(plot)
		plotModels[slot] = plot
	end
	assert(plot)
	plot:SetAttribute("OwnerUserId", player.UserId)
	setSign(plot, ("%s's grove"):format(player.DisplayName))
	return plot
end

--[[
	Paint a player's plot. Which skin they may show is Skins' decision; this
	only draws it.
]]
function PlotService.paintSkin(player: Player, skin: Config.Skin)
	local plot = PlotService.plotOf(player)
	if plot then
		paint(plot, skin)
	end
end

function PlotService.release(player: Player)
	local slot = assigned[player]
	assigned[player] = nil
	friendCache[player] = nil
	local plot = slot and plotModels[slot]
	if plot then
		plot:SetAttribute("OwnerUserId", 0)
		-- The next owner of this slot should not inherit anything of this
		-- one's: plants, unlocked tiles, skin or name.
		resetPlot(plot)
	end
end

function PlotService.plotOf(player: Player): Model?
	local slot = assigned[player]
	return slot and plotModels[slot] or nil
end

function PlotService.init()
	plotsFolder = Workspace:FindFirstChild("Plots") :: Folder?
	if not plotsFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Plots"
		folder.Parent = Workspace
		plotsFolder = folder
	end
end

return PlotService
