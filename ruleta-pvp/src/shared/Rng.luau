--!strict
-- Small deterministic PRNG (xorshift32). Pure Luau so a seed replays the same match in the
-- standalone tests and on the server. The server seeds it from Random.new() entropy; the
-- client never sees the seed.
local Rng = {}

export type Rng = { next: () -> number, int: (lo: number, hi: number) -> number, state: () -> number }

function Rng.new(seed: number): Rng
	local s = bit32.bor(math.floor(seed) % 4294967296, 0)
	if s == 0 then
		s = 0x9E3779B9
	end
	local function step(): number
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		return s
	end
	-- warm up: nearby seeds should not give nearby first values
	for _ = 1, 8 do
		step()
	end
	local function next(): number
		return step() / 4294967296
	end
	return {
		next = next,
		int = function(lo: number, hi: number): number
			return lo + math.floor(next() * (hi - lo + 1))
		end,
		state = function(): number
			return s
		end,
	}
end

return Rng
