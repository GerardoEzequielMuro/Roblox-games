--!strict
-- Referral launch data ("ref:<inviterUserId>"). Pure; unit-tested with luau.exe.
local Referral = {}

function Referral.launchData(userId: number): string
	return "ref:" .. tostring(math.floor(userId))
end

-- Inviter user id from a join's LaunchData, or nil.
function Referral.parse(launchData: any): number?
	if type(launchData) ~= "string" or #launchData > 40 then
		return nil
	end
	local digits = launchData:match("^ref:(%d+)$")
	local n = if digits then tonumber(digits) else nil
	if n and n > 0 then
		return n
	end
	return nil
end

return Referral
