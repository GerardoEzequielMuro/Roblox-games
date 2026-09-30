--!strict
-- Auto-farm rules (pure: shared by the server, which is the only one that acts, and the client, which displays).
-- Three modes: harvest ripe crops, replant empty tiles with the chosen seed, sell the basket when it fills up.
-- Unlocked by the Farmhand upgrade (in-game cash); the Auto Harvest pass unlocks all three at full speed.
-- The server runs it on a timer, so it works while the player is AFK and no client can speed it up.
local AutoFarm = {}

export type Mode = "harvest" | "plant" | "sell"
export type Toggles = { harvest: boolean, plant: boolean, sell: boolean }
export type Rules = {
	upgradeId: string,
	passKey: string,
	levelFor: { harvest: number, plant: number, sell: number },
	interval: { number }, -- seconds between work rounds, by Farmhand level
	batch: { number }, -- tiles handled per round, by Farmhand level
	passInterval: number,
	passBatch: number,
	sellAtFill: number, -- sell when basket count >= cap * this
}

AutoFarm.Modes = { "harvest", "plant", "sell" } :: { string }

function AutoFarm.isMode(v: any): boolean
	return v == "harvest" or v == "plant" or v == "sell"
end

function AutoFarm.requiredLevel(rules: Rules, mode: string): number
	return (rules.levelFor :: any)[mode] or math.huge
end

-- What the player may switch on.
function AutoFarm.allowed(rules: Rules, level: number, hasPass: boolean): Toggles
	return {
		harvest = hasPass or level >= rules.levelFor.harvest,
		plant = hasPass or level >= rules.levelFor.plant,
		sell = hasPass or level >= rules.levelFor.sell,
	}
end

-- What actually runs: switched on AND unlocked.
function AutoFarm.effective(rules: Rules, wanted: Toggles, level: number, hasPass: boolean): Toggles
	local a = AutoFarm.allowed(rules, level, hasPass)
	return {
		harvest = a.harvest and wanted.harvest == true,
		plant = a.plant and wanted.plant == true,
		sell = a.sell and wanted.sell == true,
	}
end

function AutoFarm.any(t: Toggles): boolean
	return t.harvest or t.plant or t.sell
end

local function byLevel(list: { number }, level: number): number
	return list[math.clamp(level, 1, #list)]
end

-- Seconds between work rounds.
function AutoFarm.interval(rules: Rules, level: number, hasPass: boolean): number
	if hasPass then
		return rules.passInterval
	end
	return byLevel(rules.interval, level)
end

-- Tiles handled per round (per mode).
function AutoFarm.batch(rules: Rules, level: number, hasPass: boolean): number
	if hasPass then
		return rules.passBatch
	end
	return byLevel(rules.batch, level)
end

-- Is a work round due? lastAt = 0 means "never ran".
function AutoFarm.due(lastAt: number, now: number, interval: number): boolean
	return now - lastAt >= interval
end

function AutoFarm.shouldSell(count: number, cap: number, rules: Rules): boolean
	return count > 0 and count >= math.max(1, cap) * rules.sellAtFill
end

-- Saved toggles may be missing fields (older saves): fill them in. Harvest defaults to on so the first Farmhand
-- level (and the pass) work the moment they are bought.
function AutoFarm.sanitize(saved: any): Toggles & { seed: string }
	local t = if type(saved) == "table" then saved else {}
	return {
		harvest = if type(t.harvest) == "boolean" then t.harvest else true,
		plant = t.plant == true,
		sell = t.sell == true,
		seed = if type(t.seed) == "string" then t.seed else "",
	}
end

return AutoFarm
