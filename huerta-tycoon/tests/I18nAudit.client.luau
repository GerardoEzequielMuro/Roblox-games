-- i18n visual audit (tests/i18naudit.project.json): every time the runner resizes the window, switch to the next
-- language (through the real LanguagePanel -> SetLanguage path), open a panel, and list visible text that doesn't fit.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local UI = script.Parent:WaitForChild("Client"):WaitForChild("UI")
local LanguagePanel = require(UI:WaitForChild("LanguagePanel"))
local Panels = require(UI:WaitForChild("Panels"))
local I18n = require(UI:WaitForChild("I18n"))

local PLAN = {
	{ "de", "Shop" },
	{ "ru", "Upgrades" },
	{ "ja", nil },
	{ "pt", "Daily" },
	{ "ko", "Rebirth" },
	{ "th", "Store" },
	{ "fr", "Language" },
	{ "tr", "Codes" },
}

local function visible(g: GuiObject): boolean
	local node: Instance? = g
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return node ~= nil
end

local function report(tag: string)
	local bad, total = {}, 0
	for _, g in player.PlayerGui:GetDescendants() do
		if (g:IsA("TextLabel") or g:IsA("TextButton")) and g.Text ~= "" and visible(g) and g.AbsoluteSize.X > 2 then
			total += 1
			if not g.TextFits then
				table.insert(bad, g:GetFullName():gsub("^.-PlayerGui%.", "") .. " = " .. g.Text:sub(1, 40))
			end
		end
	end
	local vp = workspace.CurrentCamera.ViewportSize
	print(string.format("[TEST] i18n %s @%dx%d: %d visible texts, %d not fitting", tag, vp.X, vp.Y, total, #bad))
	for i = 1, math.min(10, #bad) do print("[TEST]   nofit " .. bad[i]) end
end

task.wait(8)
local step, token = 0, 0
local function advance()
	step += 1
	local p = PLAN[step]
	if not p then return end
	LanguagePanel.choose(p[1])
	task.wait(0.5)
	if p[2] then Panels.open(p[2]) else Panels.close() end
	task.wait(1.2)
	report(p[1] .. "/" .. (p[2] or "HUD") .. " lang=" .. I18n.lang)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	token += 1
	local my = token
	task.delay(0.8, function()
		if my == token then advance() end
	end)
end)
