--!strict
--[[
	Display formatting shared by the server (prompt text) and the client
	(the spore picker), so both say the same thing.
]]

local Format = {}

-- 45 -> "45s", 125 -> "2m 5s", 1800 -> "30m", 7260 -> "2h 1m".
function Format.duration(seconds: number): string
	local total = math.max(math.ceil(seconds), 0)
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if hours > 0 then
		return minutes > 0 and ("%dh %dm"):format(hours, minutes) or ("%dh"):format(hours)
	elseif minutes > 0 then
		return secs > 0 and ("%dm %ds"):format(minutes, secs) or ("%dm"):format(minutes)
	end
	return ("%ds"):format(secs)
end

return Format
