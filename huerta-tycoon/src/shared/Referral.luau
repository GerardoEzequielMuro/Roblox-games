--!strict
-- Referral LaunchData: "ref:<inviterUserId>". Pure (no Roblox services).
local Referral = {}

function Referral.encode(userId: number): string
	return "ref:" .. tostring(math.floor(userId))
end

-- Returns the inviter's UserId, or nil for anything that isn't exactly "ref:<digits>".
function Referral.parse(launchData: any): number?
	if type(launchData) ~= "string" or #launchData > 40 then
		return nil
	end
	local digits = string.match(launchData, "^ref:(%d+)$")
	if not digits then
		return nil
	end
	local n = tonumber(digits)
	if not n or n <= 0 then
		return nil
	end
	return n
end

return Referral
