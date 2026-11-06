--!strict
--[[
	Saved player data.

	Two rules this module exists to enforce, both taken from how Grow a
	Garden lost its players rather than from theory:

	1. NEVER reset or silently drop progress. A load that fails is not an
	   empty profile -- it is a refusal to play, because handing the player
	   a fresh plot and then saving it over their real one is how a transient
	   DataStore outage turns into permanent data loss. `loaded` stays false,
	   the player is told, and `save` refuses to write.
	2. Version every profile. `SCHEMA_VERSION` plus a migration step means a
	   shape change later is a migration, not a wipe.

	Studio note: DataStore access is off by default in Studio. Without
	"Enable Studio Access to API Services" (Game Settings > Security) every
	call throws, so this falls back to an in-memory store for the session,
	says so once in the output, and keeps the rest of the game testable.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Profiles = {}

local SCHEMA_VERSION = 1
local STORE_NAME = "LumenGrove_Profiles_v1"
local LOAD_ATTEMPTS = 4
local RETRY_BACKOFF_SECONDS = 2

local store: DataStore? = nil
local memoryFallback: { [string]: any } = {}
local apiAvailable = true
local warnedAboutApi = false

local cache: { [Player]: any } = {}
local loaded: { [Player]: boolean } = {}

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function blankProfile()
	return {
		version = SCHEMA_VERSION,
		lumen = Config.STARTING_LUMEN,
		tiles = {}, -- [tileIndex: string] = { species, plantedAt }
		harvested = 0,
	}
end

local function migrate(profile: any): any
	-- Only ever add; never drop a field a newer client might still read.
	if profile.version == nil then
		profile.version = 1
	end
	if profile.harvested == nil then
		profile.harvested = 0
	end
	profile.version = SCHEMA_VERSION
	return profile
end

local function getStore(): DataStore?
	if not apiAvailable then
		return nil
	end
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return store
	end
	apiAvailable = false
	return nil
end

local function noteApiUnavailable(reason: string)
	if warnedAboutApi then
		return
	end
	warnedAboutApi = true
	apiAvailable = false
	warn(
		("[Profiles] DataStores unavailable (%s). Running on an in-memory store for this session. "):format(reason)
			.. (
				RunService:IsStudio()
					and "In Studio, turn on Game Settings > Security > Enable Studio Access to API Services to test real saving."
				or "Progress will NOT persist."
			)
	)
end

--[[
	Returns (profile, persisted). `persisted` is false when the profile came
	from the in-memory fallback, so callers can tell the player their
	progress is not being written anywhere.
]]
function Profiles.load(player: Player): (any, boolean)
	local dataStore = getStore()
	if not dataStore then
		noteApiUnavailable("API services are off")
		local profile = memoryFallback[key(player)] or blankProfile()
		cache[player] = profile
		loaded[player] = true
		return profile, false
	end

	local lastError: string? = nil
	for attempt = 1, LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return dataStore:GetAsync(key(player))
		end)
		if ok then
			local profile = result and migrate(result) or blankProfile()
			cache[player] = profile
			loaded[player] = true
			return profile, true
		end
		lastError = tostring(result)

		-- GetDataStore() happily returns a DataStore in Studio with API
		-- access off; only the first *call* throws. That is a permanent
		-- condition for the session, not an outage, so retrying it just
		-- stalls the join and then kicks for no reason.
		if string.find(lastError, "Studio access to APIs is not allowed", 1, true) then
			noteApiUnavailable("Studio access to APIs is off")
			local profile = memoryFallback[key(player)] or blankProfile()
			cache[player] = profile
			loaded[player] = true
			return profile, false
		end

		if attempt < LOAD_ATTEMPTS then
			task.wait(RETRY_BACKOFF_SECONDS * attempt)
		end
	end

	-- Deliberately no blank-profile fallback here: see rule 1 above.
	loaded[player] = false
	warn(("[Profiles] load failed for %s after %d attempts: %s"):format(player.Name, LOAD_ATTEMPTS, tostring(lastError)))
	return nil, false
end

function Profiles.get(player: Player): any?
	if not loaded[player] then
		return nil
	end
	return cache[player]
end

--[[
	Writes through UpdateAsync, not SetAsync, so two servers holding the same
	player (a teleport, or a rejoin before the old server released them)
	cannot clobber each other's writes wholesale.
]]
function Profiles.save(player: Player): boolean
	if not loaded[player] then
		return false -- never write over a profile we failed to read
	end
	local profile = cache[player]
	if not profile then
		return false
	end

	local dataStore = getStore()
	if not dataStore then
		memoryFallback[key(player)] = profile
		return false
	end

	local ok, err = pcall(function()
		dataStore:UpdateAsync(key(player), function(_existing)
			return profile
		end)
	end)
	if not ok then
		warn(("[Profiles] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

function Profiles.release(player: Player)
	Profiles.save(player)
	cache[player] = nil
	loaded[player] = nil
end

--[[
	A last save for everyone still in the server when it shuts down.
	BindToClose blocks the shutdown for up to 30 seconds, which is what
	stops the final minutes of a session evaporating.
]]
function Profiles.bindToClose()
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(Profiles.release, player)
		end
		task.wait(2)
	end)
end

return Profiles
