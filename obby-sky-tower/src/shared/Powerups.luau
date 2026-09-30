--!strict
-- Shop-zone items: advantages bought with coins on the way up (one shop at the entrance of every
-- world). PURE Luau: catalogue + the purchase / expiry logic, run by server/Shops.luau on the saved
-- profile. Nothing here is random: every purchase gives exactly what the pedestal says.
--
-- kind
--   timed   : works for `seconds` from the purchase (buying again adds time, up to MAX_TIMED)
--   charge  : a counter (max `max`), one is spent each time it triggers
--   instant : happens at once
-- `pass` = a game pass (Config.Passes) that gives the same thing permanently.
-- `robux` = a developer product (Config.Products) that sells the same item for Robux.
local Powerups = {}

export type Item = {
	id: string,
	price: number, -- coins
	kind: string,
	seconds: number?,
	max: number?,
	pass: string?,
	robux: string?,
	icon: string,
	color: { number },
}

Powerups.MAX_TIMED = 30 * 60

Powerups.List = {
	{ id = "speed", price = 60, kind = "timed", seconds = 180, pass = "SpeedCoil", icon = "⚡", color = { 255, 205, 60 } }, -- WalkSpeed 24
	{ id = "gravity", price = 60, kind = "timed", seconds = 180, pass = "GravityCoil", icon = "🪶", color = { 140, 200, 255 } }, -- low gravity
	{ id = "doublejump", price = 90, kind = "timed", seconds = 300, pass = "DoubleJump", icon = "⏫", color = { 120, 235, 150 } }, -- one extra jump in the air
	{ id = "shield", price = 40, kind = "charge", max = 3, icon = "🛡", color = { 120, 170, 255 } }, -- survives one kill brick / laser hit
	{ id = "magnet", price = 50, kind = "timed", seconds = 300, icon = "🧲", color = { 255, 110, 120 } }, -- pulls in nearby coins
	{ id = "skip", price = 150, kind = "instant", robux = "SkipStage", icon = "⏭", color = { 90, 215, 110 } }, -- skips the next stage
	{ id = "pocket", price = 80, kind = "charge", max = 3, pass = "InfiniteRevives", icon = "📍", color = { 255, 150, 60 } }, -- portable checkpoint
} :: { Item }

local byId: { [string]: Item } = {}
for _, item in Powerups.List do
	byId[item.id] = item
end

function Powerups.get(id: string): Item?
	return byId[id]
end

-- The part of a profile the shop works on.
export type State = {
	coins: number,
	boosts: { [string]: number }, -- id -> os.time() when it ends
	charges: { [string]: number },
}

function Powerups.active(boosts: { [string]: number }, id: string, now: number): boolean
	return (boosts[id] or 0) > now
end

function Powerups.remaining(boosts: { [string]: number }, id: string, now: number): number
	return math.max(0, (boosts[id] or 0) - now)
end

-- Buys with coins. Returns ok and, when it fails, a locale key. Mutates `state` only on success.
-- "instant" items are paid here; the caller performs them (and refunds if it cannot).
function Powerups.buy(state: State, id: string, now: number): (boolean, string?)
	local item = byId[id]
	if not item then
		return false, "err.not_for_sale"
	end
	if state.coins < item.price then
		return false, "err.not_enough_coins"
	end
	if item.kind == "timed" then
		local left = Powerups.remaining(state.boosts, id, now)
		if left + (item.seconds or 0) > Powerups.MAX_TIMED then
			return false, "err.boost_full"
		end
		state.boosts[id] = now + left + (item.seconds or 0)
	elseif item.kind == "charge" then
		local have = state.charges[id] or 0
		if have >= (item.max or 1) then
			return false, "err.max_charges"
		end
		state.charges[id] = have + 1
	end
	state.coins -= item.price
	return true, nil
end

-- Spends one charge. False when there is none.
function Powerups.use(state: State, id: string): boolean
	local have = state.charges[id] or 0
	if have <= 0 then
		return false
	end
	state.charges[id] = have - 1
	return true
end

-- Drops expired boosts (keeps the saved profile small). Returns how many were removed.
function Powerups.sweep(boosts: { [string]: number }, now: number): number
	local n = 0
	for id, endsAt in boosts do
		if endsAt <= now then
			boosts[id] = nil
			n += 1
		end
	end
	return n
end

return Powerups
