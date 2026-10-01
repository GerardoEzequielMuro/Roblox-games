--!strict
-- Strict argument validation for everything a client can send (pure: no Roblox services, unit-tested).
-- An exploiter can send ANY value for ANY field: wrong types, NaN, inf, negatives, huge numbers or huge strings.
local Validate = {}

Validate.MAX_ACTION_LEN = 32
Validate.MAX_ID_LEN = 48
Validate.MAX_CODE_LEN = 40

-- A real, finite number (rejects NaN, +-inf and any non-number type, strings included).
function Validate.finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A whole number in [min, max], or nil.
function Validate.integer(v: any, min: number, max: number): number?
	if not Validate.finite(v) or v ~= math.floor(v) or v < min or v > max then
		return nil
	end
	return v
end

-- A string of at most maxLen bytes (empty allowed), or nil.
function Validate.str(v: any, maxLen: number): string?
	if type(v) ~= "string" or #v > maxLen then
		return nil
	end
	return v
end

-- A key of a whitelist table ({ [id] = anything }), or nil. Never indexes with an over-long or non-string key.
function Validate.key(v: any, set: { [string]: any }, maxLen: number?): string?
	if type(v) ~= "string" or #v > (maxLen or Validate.MAX_ID_LEN) then
		return nil
	end
	if set[v] == nil then
		return nil
	end
	return v
end

-- Integer in range, otherwise the fallback (for optional amounts such as "buy N").
function Validate.integerOr(v: any, min: number, max: number, fallback: number): number
	local n = Validate.integer(v, min, max)
	return n or fallback
end

-- Clamps a client amount into [min, max]: NaN/inf/non-numbers become the fallback, fractions are floored.
function Validate.clampAmount(v: any, min: number, max: number, fallback: number): number
	if not Validate.finite(v) then
		return fallback
	end
	return math.clamp(math.floor(v), min, max)
end

-- Boolean, strictly.
function Validate.bool(v: any): boolean?
	if type(v) == "boolean" then
		return v
	end
	return nil
end

-- Normalises a redeem code: strips whitespace, upper-cases; nil when it is not a string or too long.
function Validate.code(v: any): string?
	if type(v) ~= "string" or #v > Validate.MAX_CODE_LEN then
		return nil
	end
	local s = string.upper((string.gsub(v, "%s", "")))
	if s == "" then
		return nil
	end
	return s
end

-- Is `payload` usable as a request payload (nil or a table)?
function Validate.payload(v: any): boolean
	return v == nil or type(v) == "table"
end

return Validate
