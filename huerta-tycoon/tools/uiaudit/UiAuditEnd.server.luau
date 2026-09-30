-- Ends the playtest after the runner has cycled through window sizes.
local StudioTestService = game:GetService("StudioTestService")
local Players = game:GetService("Players")
Players.PlayerAdded:Wait()
local t = workspace:GetAttribute("AuditSeconds") or 75
task.wait(t)
print("[TEST] audit window closed")
StudioTestService:EndTest(0)
