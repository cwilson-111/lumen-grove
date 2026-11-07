--!strict
--[[
	The daily dew: once per UTC day, a gift waiting on the player's plot.

	No streak. `dewsCollected` is a lifetime count that only grows, so the
	dew gets better for everyone who keeps coming back and costs nothing to
	someone who missed a week. The first dew falls on the day after a grove
	is started; day one only tells the player it is coming.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Profiles = require(script.Parent.Profiles)

local Daily = {}

export type Status = {
	ready: boolean,
	-- Seconds until the next dew can fall; 0 when one is ready now.
	nextIn: number,
	-- The amount the ready (or next) dew pays.
	amount: number,
}

function Daily.status(profile: any, now: number): Status
	local today = Config.dayOf(now)
	local ready = today > profile.firstDay and today > profile.lastDewDay
	return {
		ready = ready,
		nextIn = ready and 0 or (today + 1) * 86400 - now,
		amount = Config.dewAmount(profile.bestValue, profile.dewsCollected),
	}
end

function Daily.collect(player: Player): { ok: boolean, message: string }
	local profile = Profiles.get(player)
	if not profile then
		return { ok = false, message = "Your grove is still loading." }
	end
	local now = os.time()
	local status = Daily.status(profile, now)
	if not status.ready then
		return { ok = false, message = "The dew has already been collected today." }
	end

	profile.lastDewDay = Config.dayOf(now)
	profile.dewsCollected += 1
	profile.lumen += status.amount
	-- Saved now rather than at the next autosave, so a crash cannot hand the
	-- same day's dew out twice.
	task.spawn(Profiles.save, player)
	return { ok = true, message = ("Morning dew: +%d lumen."):format(status.amount) }
end

return Daily
