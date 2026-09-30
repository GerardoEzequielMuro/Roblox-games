--!strict
-- "What should I do next?" (pure): the closest unmet power goal among the next form, the next
-- planet and the next ascension. Shown in the objective tracker once the story chain is done
-- (before that the story step is the goal). Progress is power / needed power.
local Config: any = if script then require(script.Parent.Config) :: any else (require :: any)("./Config")
local Formulas: any = if script then require(script.Parent.Formulas) :: any else (require :: any)("./Formulas")

local Goals = {}

export type Goal = { kind: string, id: string, need: number, have: number, frac: number }

-- power: best power; forms: highest unlocked form index; planets: unlocked planet indexes.
function Goals.next(power: number, forms: number, planets: { number }, rebirths: number): Goal
	local best: Goal? = nil
	local function consider(kind: string, id: string, need: number)
		local frac = math.clamp(power / math.max(1, need), 0, 1)
		if frac < 1 and (best == nil or frac > best.frac) then
			best = { kind = kind, id = id, need = need, have = power, frac = frac }
		end
	end
	for i = forms + 1, #Config.Forms do
		local f = Config.Forms[i]
		if f.special == nil and (f.reqRebirths or 0) <= rebirths then
			consider("form", f.id, f.reqPower)
			break
		end
	end
	for i, pl in Config.Planets do
		if not table.find(planets, i) then
			consider("planet", pl.id, pl.reqPower)
			break
		end
	end
	local need = Formulas.rebirthRequirement(rebirths)
	consider("rebirth", tostring(rebirths + 1), need)
	if best == nil then
		-- every power goal is already met: the ascension is the thing to do now
		return { kind = "rebirth", id = tostring(rebirths + 1), need = need, have = power, frac = 1 }
	end
	return best :: Goal
end

return Goals
