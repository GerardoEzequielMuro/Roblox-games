--!strict
-- Invite / share-link launch data: "ref:<inviterUserId>" (pure Luau, unit-tested).
local Referral = {}

function Referral.make(userId: number): string
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
	local id = tonumber(digits)
	if not id or id <= 0 then
		return nil
	end
	return id
end

return Referral
