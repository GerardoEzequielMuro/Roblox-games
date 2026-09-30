--!strict
-- Pure math behind the model slots (server World/ModelSlots). No Roblox types, so it runs
-- under the plain `luau` CLI (tests/modelfit_check.luau).
local ModelFit = {}

-- Uniform scale that makes a model of `size` fit inside `target` (keeps proportions). Axes with
-- a degenerate size (<= 0) or a non-positive target are ignored; falls back to 1.
function ModelFit.fitScale(size: { number }, target: { number }): number
	local best = math.huge
	for i = 1, 3 do
		local s, t = size[i], target[i]
		if s ~= nil and t ~= nil and s > 1e-4 and t > 0 then
			best = math.min(best, t / s)
		end
	end
	if best == math.huge or best ~= best then
		return 1
	end
	return best
end

-- Library child names that belong to a slot: `slot` first (if present), then slot_1, slot_2...
-- in numeric order. Anything else is ignored (e.g. `tree_old`, `tree_x`, `tree2`).
function ModelFit.collectVariants(names: { string }, slot: string): { string }
	local has: { [string]: boolean } = {}
	local numbered: { { n: number, name: string } } = {}
	local prefix = slot .. "_"
	for _, name in names do
		has[name] = true
		if string.sub(name, 1, #prefix) == prefix then
			local rest = string.sub(name, #prefix + 1)
			if string.match(rest, "^%d+$") then
				table.insert(numbered, { n = tonumber(rest) :: number, name = name })
			end
		end
	end
	table.sort(numbered, function(a, b)
		return a.n < b.n
	end)
	local out: { string } = {}
	if has[slot] then
		table.insert(out, slot)
	end
	for _, v in numbered do
		table.insert(out, v.name)
	end
	return out
end

-- Deterministic 1..count pick from a world position (same spot -> same variant, neighbouring
-- props differ). Positions are rounded to 0.1 stud so float noise cannot flip the choice.
function ModelFit.pickVariant(count: number, x: number, y: number, z: number): number
	if count <= 1 then
		return 1
	end
	local function q(v: number): number
		return math.floor(v * 10 + 0.5)
	end
	local h = (q(x) * 73856093 + q(y) * 19349663 + q(z) * 83492791) % 2147483629
	h = (h * 1103515245 + 12345) % 2147483629 -- one LCG round so low bits mix
	return h % count + 1
end

-- Whether a model of `parts` parts is allowed (per-slot cap and what is left of the world budget).
function ModelFit.withinBudget(parts: number, cap: number, budgetLeft: number?): boolean
	if parts > cap then
		return false
	end
	if budgetLeft ~= nil and parts > budgetLeft then
		return false
	end
	return true
end

return ModelFit
