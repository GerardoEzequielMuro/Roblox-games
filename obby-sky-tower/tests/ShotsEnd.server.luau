-- Screenshot playtest (shots / shotslow projects): builds the towers the tour visits, keeps them
-- in Workspace for the whole run and ends the test once the runner has cycled through its sizes.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
Players.PlayerAdded:Wait()
local Towers = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Towers"))
Towers.IDLE_SECONDS = 1e9
task.spawn(function()
	for _, t in { 2, 5, 10 } do
		local ok, err = pcall(Towers.ensure, t)
		print(("[TEST] shots tower %d %s"):format(t, if ok then "built" else "FAILED " .. tostring(err)))
	end
end)
task.wait(workspace:GetAttribute("ShotSeconds") or 125)
game:GetService("StudioTestService"):EndTest(0)
