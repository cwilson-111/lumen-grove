--!strict
--[[
	Plot skins: who owns which, and which one their plot shows.

	Ownership is never stored in the profile. Skins are game passes, and
	Roblox keeps the record of who bought a pass: it survives a lost save,
	follows a refund, and covers a pass bought from the website while the
	player was not even in the game. This module re-reads it on every join
	and adds to it when a purchase completes in-session. The profile holds
	only `skin`, the equipped id -- a preference.

	A failed ownership check therefore costs, at worst, one session showing
	the default skin. It never unequips anything: `profile.skin` is left as
	the player set it, and the plot shows it again on the next join that can
	confirm the pass.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlotService = require(script.Parent.PlotService)
local Profiles = require(script.Parent.Profiles)

local Skins = {}

local OWNERSHIP_ATTEMPTS = 3

-- [player] = set of skin ids this player owns this session. Absent until
-- `load` has started for them.
local owned: { [Player]: { [string]: boolean } } = {}
local onChanged: (Player) -> () = function() end

export type Outcome = { ok: boolean, message: string }

local function ownsPass(player: Player, gamePassId: number): boolean
	for attempt = 1, OWNERSHIP_ATTEMPTS do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		if ok then
			return result
		end
		warn(("[Skins] ownership check %d for %s failed: %s"):format(attempt, player.Name, tostring(result)))
		if attempt < OWNERSHIP_ATTEMPTS then
			task.wait(attempt)
		end
	end
	return false
end

function Skins.owns(player: Player, skin: Config.Skin): boolean
	if not skin.gamePassId then
		return true
	end
	local set = owned[player]
	return set ~= nil and set[skin.id] == true
end

-- What the plot should show: the equipped skin if it is confirmed owned,
-- otherwise the default.
function Skins.shown(player: Player): Config.Skin
	local profile = Profiles.get(player)
	local skin = profile and Config.skinById(profile.skin)
	if skin and Skins.owns(player, skin) then
		return skin
	end
	return Config.SKINS[1]
end

-- Ids of every skin this player may equip, for the state push.
function Skins.ownedIds(player: Player): { string }
	local ids = {}
	for _, skin in Config.SKINS do
		if Skins.owns(player, skin) then
			table.insert(ids, skin.id)
		end
	end
	return ids
end

--[[
	Yields: one web call per paid skin. Call after the plot is assigned; the
	plot shows the default until this finishes.
]]
function Skins.load(player: Player)
	local set: { [string]: boolean } = {}
	-- Installed before the first yield, so a purchase that completes while
	-- the checks are still running lands in this same set.
	owned[player] = set
	for _, skin in Config.SKINS do
		local gamePassId = skin.gamePassId
		if gamePassId and ownsPass(player, gamePassId) then
			set[skin.id] = true
		end
	end
	if owned[player] ~= set then
		return -- left while we were checking
	end
	PlotService.paintSkin(player, Skins.shown(player))
	onChanged(player)
end

function Skins.equip(player: Player, skinId: any): Outcome
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	if typeof(skinId) ~= "string" then
		return { ok = false, message = "No such skin." }
	end
	local skin = Config.skinById(skinId)
	if not skin then
		return { ok = false, message = "No such skin." }
	end
	if not Skins.owns(player, skin) then
		return { ok = false, message = ("%s isn't unlocked."):format(skin.name) }
	end
	profile.skin = skin.id
	PlotService.paintSkin(player, skin)
	return { ok = true, message = ("%s equipped."):format(skin.name) }
end

function Skins.release(player: Player)
	owned[player] = nil
end

--[[
	`changed` is called whenever what a player owns or shows changes outside
	a remote call, so the caller can push fresh state to them.
]]
function Skins.init(changed: (Player) -> ())
	onChanged = changed

	-- Fires on the server, from Roblox, after a pass purchase prompt closes.
	-- `wasPurchased` is Roblox's word, not the client's.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			local skin = Config.skinByGamePass(gamePassId)
			local set = owned[player]
			if not skin or not set then
				return
			end
			set[skin.id] = true
			-- They just paid to see it: put it on.
			local profile = Profiles.get(player)
			if profile then
				profile.skin = skin.id
			end
			PlotService.paintSkin(player, Skins.shown(player))
			onChanged(player)
		end
	)
end

return Skins
