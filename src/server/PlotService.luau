--!strict
--[[
	The authoritative plot: who owns which plot, what is planted, and what a
	harvest pays.

	The client sends intents only -- "plant species X on tile 4", "harvest
	tile 4". It never sends a price, a payout, a timestamp or a balance. Every
	number here is read from Config or from os.time() on this machine, so the
	only thing a modified client can do is ask for something it is not allowed
	to have, and be told no.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Growth = require(ReplicatedStorage.Shared.Growth)
local Profiles = require(script.Parent.Profiles)

local PlotService = {}

local PLOT_SPACING = 80
local plotsFolder: Folder? = nil
local assigned: { [Player]: number } = {}
local plotModels: { [number]: Model } = {}

-- -- world ------------------------------------------------------------- --

local function tileOffset(index: number): Vector3
	local zeroBased = index - 1
	local row = math.floor(zeroBased / Config.TILES_PER_ROW)
	local column = zeroBased % Config.TILES_PER_ROW
	local span = (Config.TILES_PER_ROW - 1) * Config.TILE_STUDS / 2
	return Vector3.new(column * Config.TILE_STUDS - span, 0, row * Config.TILE_STUDS - span)
end

local function buildPlot(slot: number): Model
	local origin = Vector3.new((slot - 1) * PLOT_SPACING, 0.5, 0)

	local model = Instance.new("Model")
	model.Name = "Plot" .. slot

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(
		Config.TILES_PER_ROW * Config.TILE_STUDS + 6,
		1,
		Config.TILES_PER_ROW * Config.TILE_STUDS + 6
	)
	base.Position = origin
	base.Color = Color3.fromRGB(46, 52, 64)
	base.Material = Enum.Material.Slate
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model
	model.PrimaryPart = base

	for index = 1, Config.TILE_COUNT do
		local tile = Instance.new("Part")
		tile.Name = "Tile" .. index
		tile.Anchored = true
		tile.Size = Vector3.new(Config.TILE_STUDS - 1, 0.4, Config.TILE_STUDS - 1)
		tile.Position = origin + tileOffset(index) + Vector3.new(0, 0.7, 0)
		tile.Color = Color3.fromRGB(70, 78, 94)
		tile.Material = Enum.Material.Sand
		tile.TopSurface = Enum.SurfaceType.Smooth
		tile.Parent = model

		-- One prompt per tile is the whole input surface. No free-form
		-- clicking, so the client cannot address a tile that does not exist.
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "Plant"
		prompt.ObjectText = "Tile " .. index
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TileIndex", index)
		prompt.Parent = tile
	end

	model.Parent = plotsFolder
	return model
end

local function plantPart(plot: Model, index: number): Part?
	local tile = plot:FindFirstChild("Tile" .. index)
	return tile and tile:FindFirstChild("Plant") :: Part?
end

--[[
	Redraw one tile from the profile. Called after every mutation and on a
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
	local saved = profile.tiles[tostring(index)]
	local existing = plantPart(plot, index)

	if not saved then
		if existing then
			existing:Destroy()
		end
		if prompt then
			prompt.ActionText = "Plant"
		end
		return
	end

	local species = Config.speciesById(saved.species)
	if not species then
		return
	end

	local now = os.time()
	local progress = Growth.progress(saved, now)
	local ripe = progress >= 1

	local plant = existing
	if not plant then
		plant = Instance.new("Part")
		plant.Name = "Plant"
		plant.Anchored = true
		plant.Shape = Enum.PartType.Ball
		plant.Material = Enum.Material.Neon
		plant.CanCollide = false
		plant.Parent = tilePart
	end
	assert(plant)

	local size = 1 + progress * (Config.TILE_STUDS - 3)
	plant.Size = Vector3.new(size, size, size)
	plant.Position = tilePart.Position + Vector3.new(0, size / 2 + 0.3, 0)
	plant.Color = species.colour
	plant.Transparency = ripe and 0 or 0.45 - progress * 0.35

	if prompt then
		local remaining = Growth.secondsRemaining(saved, now)
		if ripe then
			prompt.ActionText = "Harvest"
		elseif Growth.tendAmount(saved, now) <= 0 then
			-- Fully tended: nothing more to gain, so do not invite a press
			-- that can only be refused.
			prompt.ActionText = ("Growing %ds"):format(remaining)
		elseif Growth.tendCooldown(saved, now) > 0 then
			prompt.ActionText = ("Tend in %ds · %ds"):format(Growth.tendCooldown(saved, now), remaining)
		else
			prompt.ActionText = ("Tend · %ds"):format(remaining)
		end
	end
end

function PlotService.renderAll(player: Player)
	for index = 1, Config.TILE_COUNT do
		renderTile(player, index)
	end
end

-- -- intents ----------------------------------------------------------- --

export type Outcome = { ok: boolean, message: string }

function PlotService.plant(player: Player, tileIndex: number, speciesId: string): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	-- Validate the index rather than trusting it: an unchecked index is how
	-- a client writes an arbitrary key into someone's save.
	if typeof(tileIndex) ~= "number" or tileIndex % 1 ~= 0 or tileIndex < 1 or tileIndex > Config.TILE_COUNT then
		return { ok = false, message = "No such tile." }
	end
	if typeof(speciesId) ~= "string" then
		return { ok = false, message = "No such spore." }
	end

	local species = Config.speciesById(speciesId)
	if not species then
		return { ok = false, message = "No such spore." }
	end

	local slotKey = tostring(tileIndex)
	if profile.tiles[slotKey] then
		return { ok = false, message = "Something is already growing there." }
	end
	if profile.lumen < species.cost then
		return { ok = false, message = ("%s costs %d lumen."):format(species.name, species.cost) }
	end

	profile.lumen -= species.cost
	-- os.time() on the server, never a value from the client.
	profile.tiles[slotKey] = { species = species.id, plantedAt = os.time() }
	renderTile(player, tileIndex)
	return { ok = true, message = ("Planted %s."):format(species.name) }
end

function PlotService.harvest(player: Player, tileIndex: number): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if typeof(tileIndex) ~= "number" or tileIndex % 1 ~= 0 or tileIndex < 1 or tileIndex > Config.TILE_COUNT then
		return { ok = false, message = "No such tile." }
	end

	local slotKey = tostring(tileIndex)
	local saved = profile.tiles[slotKey]
	if not saved then
		return { ok = false, message = "Nothing growing there." }
	end

	local now = os.time()
	local payout = Growth.payout(saved, now)
	if payout <= 0 then
		return { ok = false, message = ("Not ready for %ds."):format(Growth.secondsRemaining(saved, now)) }
	end

	-- Clear the tile BEFORE crediting, so a yield between the two cannot be
	-- raced into a double payout.
	profile.tiles[slotKey] = nil
	profile.lumen += payout
	profile.harvested += 1
	renderTile(player, tileIndex)
	return { ok = true, message = ("+%d lumen."):format(payout) }
end

function PlotService.tend(player: Player, tileIndex: number): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if typeof(tileIndex) ~= "number" or tileIndex % 1 ~= 0 or tileIndex < 1 or tileIndex > Config.TILE_COUNT then
		return { ok = false, message = "No such tile." }
	end

	local saved = profile.tiles[tostring(tileIndex)]
	if not saved then
		return { ok = false, message = "Nothing growing there." }
	end

	local now = os.time()
	local cooldown = Growth.tendCooldown(saved, now)
	if cooldown > 0 then
		return { ok = false, message = ("Let it rest %ds."):format(cooldown) }
	end
	local amount = Growth.tendAmount(saved, now)
	if amount <= 0 then
		return { ok = false, message = "It's had all the tending it can use." }
	end

	-- Both written from this machine's clock and Growth's own answer; nothing
	-- here comes from the client but the index, already validated above.
	saved.boost = (saved.boost or 0) + amount
	saved.lastTended = now
	renderTile(player, tileIndex)
	return { ok = true, message = ("Tended — %ds sooner."):format(math.floor(amount + 0.5)) }
end

--[[
	The only intent for an occupied tile. The server, not the client, decides
	whether that means harvest or tend: the client's view of ripeness is the
	last state push, up to a second stale, and a client that picked "tend" on
	a plant that had just ripened would be told no for no reason the player
	could see.
]]
function PlotService.tap(player: Player, tileIndex: number): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if typeof(tileIndex) ~= "number" or tileIndex % 1 ~= 0 or tileIndex < 1 or tileIndex > Config.TILE_COUNT then
		return { ok = false, message = "No such tile." }
	end
	local saved = profile.tiles[tostring(tileIndex)]
	if saved and Growth.isRipe(saved, os.time()) then
		return PlotService.harvest(player, tileIndex)
	end
	return PlotService.tend(player, tileIndex)
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
	local plot = plotModels[slot] or buildPlot(slot)
	plotModels[slot] = plot
	plot:SetAttribute("OwnerUserId", player.UserId)
	return plot
end

function PlotService.release(player: Player)
	local slot = assigned[player]
	assigned[player] = nil
	local plot = slot and plotModels[slot]
	if plot then
		plot:SetAttribute("OwnerUserId", 0)
		for index = 1, Config.TILE_COUNT do
			local existing = plantPart(plot, index)
			if existing then
				existing:Destroy()
			end
		end
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
