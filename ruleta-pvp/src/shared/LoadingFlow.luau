--!strict
-- Loading screen logic. Pure (no Roblox APIs, no clocks): the client passes elapsed seconds
-- and which stages are done. Guarantees: never shows longer than MAX_SECONDS, never shorter
-- than MIN_SECONDS once shown (so it does not flash), and a stage that failed to load counts
-- as done instead of hanging the bar.
local LoadingFlow = {}

LoadingFlow.MIN_SECONDS = 1.2
LoadingFlow.MAX_SECONDS = 6
LoadingFlow.TIP_SECONDS = 2.2
LoadingFlow.TipCount = 4 -- loading.tip.1 .. loading.tip.4

-- Stages in loading order with their weight in the bar.
LoadingFlow.Stages = {
	{ id = "game", weight = 0.35 }, -- game:IsLoaded
	{ id = "world", weight = 0.25 }, -- the lobby and tables replicated
	{ id = "ui", weight = 0.15 }, -- the HUD is built
	{ id = "data", weight = 0.25 }, -- the profile arrived
}

-- Bar value 0..1. `done` = ids of finished (or failed) stages. The bar also creeps with
-- time so it never looks frozen, but never passes 0.92 until everything is done.
function LoadingFlow.progress(done: { [string]: boolean }, elapsed: number): number
	local real = 0
	local all = true
	for _, s in LoadingFlow.Stages do
		if done[s.id] then
			real += s.weight
		else
			all = false
		end
	end
	if all then
		return 1
	end
	local creep = math.min(0.92, elapsed / LoadingFlow.MAX_SECONDS * 0.9)
	return math.clamp(math.max(real * 0.92, creep), 0, 0.92)
end

function LoadingFlow.allDone(done: { [string]: boolean }): boolean
	for _, s in LoadingFlow.Stages do
		if not done[s.id] then
			return false
		end
	end
	return true
end

-- Should the screen go away now?
function LoadingFlow.shouldDismiss(done: { [string]: boolean }, elapsed: number): boolean
	if elapsed >= LoadingFlow.MAX_SECONDS then
		return true
	end
	return elapsed >= LoadingFlow.MIN_SECONDS and LoadingFlow.allDone(done)
end

-- Which tip to show at `elapsed`, starting from a random-ish `seed` (any integer).
function LoadingFlow.tipIndex(seed: number, elapsed: number): number
	local n = LoadingFlow.TipCount
	return (math.floor(seed) + math.floor(elapsed / LoadingFlow.TIP_SECONDS)) % n + 1
end

return LoadingFlow
