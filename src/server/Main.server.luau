--!strict
--[[
	Server entry point: wires remotes, loads profiles, drives the cosmetic
	refresh tick, and saves.

	The remote surface is deliberately six intents and three pushes:
	  Plant(tileIndex, speciesId)  -- an empty tile
	  Tap(tileIndex)               -- an occupied tile; the server decides
	                                  whether that harvests or tends it
	  Expand()                     -- buy the next tile; no argument, since
	                                  only the next one is ever for sale
	  Skin(skinId)                 -- equip a skin the player owns
	  CollectDew()                 -- the day's dew, if it has fallen
	  Help(ownerUserId, tileIndex) -- tend a plant on someone else's plot
	  State -> profile summary     -- server tells the client what is true
	  Announce -> text             -- server tells everyone about a rare find
	  Notice -> text               -- server tells one player something
	                                  happened to them (a friend helped)

	Buying a skin is not a remote: the client opens Roblox's own purchase
	prompt, and Roblox tells the server what was bought (see Skins).

	Nothing flows the other way as a number. The client cannot send a
	balance, a payout or a timestamp, because no handler accepts one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Growth = require(ReplicatedStorage.Shared.Growth)
local Daily = require(script.Parent.Daily)
local PlotService = require(script.Parent.PlotService)
local Profiles = require(script.Parent.Profiles)
local Skins = require(script.Parent.Skins)

local AUTOSAVE_SECONDS = 60
local RENDER_SECONDS = 1

-- -- remotes ------------------------------------------------------------ --

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local remotes = ensureFolder(ReplicatedStorage, "Remotes")

local function ensureRemote(className: string, name: string): any
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local plantRemote: RemoteFunction = ensureRemote("RemoteFunction", "Plant")
local tapRemote: RemoteFunction = ensureRemote("RemoteFunction", "Tap")
local stateRemote: RemoteEvent = ensureRemote("RemoteEvent", "State")
local skinRemote: RemoteFunction = ensureRemote("RemoteFunction", "Skin")
local expandRemote: RemoteFunction = ensureRemote("RemoteFunction", "Expand")
local announceRemote: RemoteEvent = ensureRemote("RemoteEvent", "Announce")
local dewRemote: RemoteFunction = ensureRemote("RemoteFunction", "CollectDew")
local helpRemote: RemoteFunction = ensureRemote("RemoteFunction", "Help")
local noticeRemote: RemoteEvent = ensureRemote("RemoteEvent", "Notice")

-- -- state push ---------------------------------------------------------- --

--[[
	What the client is allowed to know: its own balance and its own tiles.
	Built fresh rather than sending the profile table, so a field added to
	the save later is not leaked to the client by accident -- which is what
	keeps a tile's mutation hidden until the harvest reveals it.
]]
local function summarise(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return nil
	end
	local now = os.time()
	local tiles = {}
	for index = 1, Config.TILE_COUNT do
		local saved = profile.tiles[tostring(index)]
		if saved then
			tiles[tostring(index)] = {
				species = saved.species,
				remaining = Growth.secondsRemaining(saved, now),
				ripe = Growth.isRipe(saved, now),
			}
		end
	end
	local dew = Daily.status(profile, now)
	return {
		lumen = profile.lumen,
		harvested = profile.harvested,
		tileCount = profile.tileCount,
		tiles = tiles,
		skin = Skins.shown(player).id,
		ownedSkins = Skins.ownedIds(player),
		dew = {
			ready = dew.ready,
			nextIn = dew.nextIn,
			amount = dew.amount,
			-- Day one: no dew yet, only the promise of one tomorrow.
			firstDay = Config.dayOf(now) == profile.firstDay,
		},
	}
end

-- Everything a player sees of their own grove, redrawn.
local function refresh(player: Player)
	PlotService.renderAll(player)
	local profile = Profiles.get(player)
	if profile then
		PlotService.setDew(player, Daily.status(profile, os.time()).ready)
	end
end

local function pushState(player: Player)
	local summary = summarise(player)
	if summary then
		stateRemote:FireClient(player, summary)
	end
end

-- -- joining and leaving -------------------------------------------------- --

local function onPlayerAdded(player: Player)
	local profile, persisted = Profiles.load(player)
	if not profile then
		-- Refusing to play beats handing out a blank grove that would then
		-- be saved over the real one.
		player:Kick("Couldn't load your grove just now. Please rejoin in a moment — your progress is safe.")
		return
	end

	local plot = PlotService.assign(player)
	task.spawn(Skins.load, player)

	-- Offline growth needs no catch-up pass: progress is derived from the
	-- planting timestamp, so a plant left overnight is simply ripe on sight.
	refresh(player)
	pushState(player)

	if not persisted then
		warn(("[Main] %s is on the in-memory fallback; progress will not persist."):format(player.Name))
	end

	local spawnPart = plot.PrimaryPart
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if spawnPart and root then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 6, 0)
	end
end

local function onPlayerRemoving(player: Player)
	PlotService.release(player)
	Skins.release(player)
	Profiles.release(player)
end

-- -- intents --------------------------------------------------------------- --

plantRemote.OnServerInvoke = function(player: Player, tileIndex: any, speciesId: any)
	local outcome = PlotService.plant(player, tileIndex, speciesId)
	pushState(player)
	return outcome
end

tapRemote.OnServerInvoke = function(player: Player, tileIndex: any)
	local outcome = PlotService.tap(player, tileIndex)
	pushState(player)
	local mutation = Config.mutationById(outcome.mutation)
	if mutation and mutation.announce then
		announceRemote:FireAllClients(
			("%s harvested a %s %s!"):format(player.DisplayName, mutation.name, outcome.species or "plant")
		)
	end
	return outcome
end

expandRemote.OnServerInvoke = function(player: Player)
	local outcome = PlotService.expand(player)
	pushState(player)
	return outcome
end

skinRemote.OnServerInvoke = function(player: Player, skinId: any)
	local outcome = Skins.equip(player, skinId)
	pushState(player)
	return outcome
end

dewRemote.OnServerInvoke = function(player: Player)
	local outcome = Daily.collect(player)
	refresh(player)
	pushState(player)
	return outcome
end

helpRemote.OnServerInvoke = function(player: Player, ownerUserId: any, tileIndex: any)
	local outcome, owner = PlotService.help(player, ownerUserId, tileIndex)
	pushState(player)
	if owner then
		pushState(owner)
		noticeRemote:FireClient(
			owner,
			("%s tended your %s — %s sooner."):format(
				player.DisplayName,
				outcome.species or "plant",
				Format.duration(outcome.amount or 0)
			)
		)
	end
	return outcome
end

-- -- ticks ------------------------------------------------------------------ --

PlotService.init()
Profiles.bindToClose()
Skins.init(pushState)

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Cosmetic only: redraw sizes and countdowns. No economy state advances
-- here, so a slow or skipped tick cannot cost or credit anyone anything.
task.spawn(function()
	while true do
		task.wait(RENDER_SECONDS)
		for _, player in Players:GetPlayers() do
			refresh(player)
			pushState(player)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in Players:GetPlayers() do
			Profiles.save(player)
		end
	end
end)

print("[LumenGrove] server ready")
