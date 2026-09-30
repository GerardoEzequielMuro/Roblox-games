-- i18n screenshot tour (i18nshots.project.json only): every window resize by the runner switches
-- to the next language (through the real SetLanguage request) and opens a panel, so each
-- screenshot + UI-audit line shows one language.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local Net = require(Client:WaitForChild("Net"))
local Kit = require(Client:WaitForChild("UI"):WaitForChild("Kit"))
local Toast = require(Client:WaitForChild("UI"):WaitForChild("Toast"))
local Lang = require(Client:WaitForChild("Lang"))

local tour = {
	{ "de", "settings" }, { "de", "rewards" }, { "ru", "rewards" }, { "ru", "shop" },
	{ "ja", "settings" }, { "ja", "rewards" }, { "pt", "shop" }, { "ko", "rewards" },
	{ "th", "rewards" }, { "vi", "settings" }, { "fr", "rewards" }, { "tr", "settings" },
	{ "id", "rewards" }, { "es", "shop" },
}
local i = 0
local function nextShot()
	i += 1
	local step = tour[((i - 1) % #tour) + 1]
	Net.request("SetLanguage", { lang = step[1] })
	task.wait(0.3)
	Kit.open(step[2])
	Toast.show(Lang.t("msg.bought_trail", { name = { key = "trail.rainbow" } }), "success")
	print(("[TEST] lang shot %d: %s / %s (client lang %s)"):format(i, step[1], step[2], Lang.code))
end
task.wait(3)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	task.spawn(nextShot)
end)
