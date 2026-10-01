--!strict
-- The first-session guide: ONE obvious thing at every moment. A short line (2-4 words), a
-- bobbing arrow and a pulsing outline on the next thing to press. What to show comes from
-- Shared/Tutorial (pure, stateless: it is derived from what the client sees, so it can not
-- get stuck and resumes by itself after a rejoin). "Skip" turns it off for the session.
-- Reduced motion (the shake setting off) and the flash setting keep the arrow and the glow
-- still. A missing target degrades to the text line alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Hud = require(script.Parent.Hud)
local MatchHud = require(script.Parent.MatchHud)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Audio = require(script.Parent.Parent.Audio)
local Prefs = require(script.Parent.Parent.Prefs)
local Director = require(script.Parent.Parent.Arena.Director)

local Guide = {}
Guide.step = "none" :: string
Guide.pointing = nil :: string?
Guide.steps = 0 -- steps shown so far (playtest)
Guide.update = function() end :: () -> ()

local tracker = Tutorial.newTracker()
local T = Root.isTouch

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local layer = Theme.new("Frame", { Name = "Guide", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 60, Visible = false, Parent = Root.gui }) :: Frame

local glow = Theme.new("Frame", { Name = "Glow", BackgroundTransparency = 1, Visible = false, ZIndex = 60, Parent = layer }, { Theme.corner(18) }) :: Frame
local glowStroke = Theme.new("UIStroke", { Thickness = 4, Color = Theme.Yellow, Parent = glow }) :: UIStroke

local arrow = Theme.text({ Name = "Arrow", Text = "👇", Stroke = false, Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 62, Parent = layer })

local CHIP_H = if T then 46 else 40
local chip = Theme.panel({ Name = "Chip", Size = UDim2.fromOffset(260, CHIP_H), AnchorPoint = Vector2.new(0.5, 0.5), Corner = 18, StrokeColor = Theme.Yellow, StrokeThickness = 3, Visible = false, ZIndex = 61, Parent = layer })
local chipText = Theme.text({ Name = "Text", Text = "", Title = true, Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxTextSize = if T then 24 else 24, TextColor3 = Theme.Yellow, ZIndex = 62, Parent = chip })

local skip = Theme.new("TextButton", {
	Name = "Skip",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Theme.Ink,
	BackgroundTransparency = 0.25,
	Size = UDim2.fromOffset(if T then 124 else 104, if T then 44 else 30),
	AnchorPoint = Vector2.new(0, 0.5),
	Visible = false,
	ZIndex = 61,
	Parent = layer,
}, { Theme.corner(15) }) :: TextButton
Theme.text({ Name = "Label", Key = "tut.skip", Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), MaxTextSize = if T then 18 else 15, TextColor3 = Theme.Dim, Stroke = false, ZIndex = 62, Parent = skip })
skip.Activated:Connect(function()
	Theme.play("click", 0.3)
	Tutorial.skip(tracker)
	Guide.update()
end)

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------
local function shown(obj: GuiObject): boolean
	local cur: Instance? = obj
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return obj.AbsoluteSize.X > 4 and obj.AbsoluteSize.Y > 4
end

local function targetObject(name: string): GuiObject?
	if name == "play" then
		return Hud.buttons.Play
	elseif name == "action" then
		return MatchHud.actionButton
	elseif name == "targets" then
		return MatchHud.targetsFrame
	end
	return nil
end

-- Screen rect of what to outline, relative to the guide layer: the action / play button, or
-- the union of the rival buttons for "targets".
local function rectOf(name: string, obj: GuiObject): (Vector2, Vector2)
	local origin = layer.AbsolutePosition
	local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
	if name == "targets" then
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, c in obj:GetChildren() do
			if c:IsA("GuiButton") and c.Visible then
				minX = math.min(minX, c.AbsolutePosition.X)
				minY = math.min(minY, c.AbsolutePosition.Y)
				maxX = math.max(maxX, c.AbsolutePosition.X + c.AbsoluteSize.X)
				maxY = math.max(maxY, c.AbsolutePosition.Y + c.AbsoluteSize.Y)
			end
		end
		if minX < math.huge then
			pos, size = Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY)
		end
	end
	return pos - origin, size
end

local PLACEMENT = { play = "above", targets = "above", action = "left" } :: { [string]: string }

local function place(name: string, obj: GuiObject, now: number)
	local pos, size = rectOf(name, obj)
	local pad = 5
	glow.Position = UDim2.fromOffset(pos.X - pad, pos.Y - pad)
	glow.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
	-- the pulse (static when flashes are off)
	if Prefs.flashes() then
		glowStroke.Transparency = 0.1 + 0.4 * (0.5 + 0.5 * math.sin(now * 6))
	else
		glowStroke.Transparency = 0.15
	end
	local bob = if Prefs.shake() then math.sin(now * 6) * 7 else 0
	local layerSize = layer.AbsoluteSize
	local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
	local chipW = chip.AbsoluteSize.X
	local mode = PLACEMENT[name] or "above"
	local halfW = chipW / 2
	local function clampX(x: number): number
		return math.clamp(x, halfW + 6, layerSize.X - halfW - 6 - skip.AbsoluteSize.X)
	end
	local chipX, chipY
	if mode == "left" then
		arrow.Text = "👉"
		arrow.Position = UDim2.fromOffset(pos.X - 30 + bob, cy)
		chipX, chipY = pos.X - 56 - halfW, cy
	else
		local below = cy < 150
		arrow.Text = if below then "👆" else "👇"
		if below then
			arrow.Position = UDim2.fromOffset(cx, pos.Y + size.Y + 26 - bob)
			chipX, chipY = cx, pos.Y + size.Y + 26 + 28 + CHIP_H / 2
		else
			arrow.Position = UDim2.fromOffset(cx, pos.Y - 26 + bob)
			chipX, chipY = cx, pos.Y - 26 - 28 - CHIP_H / 2
		end
	end
	chipX = clampX(chipX)
	chip.Position = UDim2.fromOffset(chipX, chipY)
	-- Skip sits beside the line (never on the arrow)
	skip.AnchorPoint = Vector2.new(0, 0.5)
	skip.Position = UDim2.fromOffset(chipX + halfW + 8, chipY)
end

---------------------------------------------------------------------------
-- Context -> step -> view
---------------------------------------------------------------------------
local function context(): Tutorial.Context
	local c = Tutorial.newContext()
	local done = Net.get("tutorialDone")
	c.done = done ~= false -- unknown (profile not here yet) counts as done: never guess a guide
	c.skipped = tracker.skipped
	c.seated = Net.get("table") ~= nil
	c.inMatch = MatchHud.isVisible()
	c.spectating = MatchHud.spectating or Director.spectating
	c.myTurn = MatchHud.myTurn
	c.phase = MatchHud.phase
	local view = MatchHud.view
	c.targetPicked = MatchHud.selectedTarget ~= nil or (view ~= nil and view.target ~= nil)
	local me = if view then view.players[MatchHud.myId] else nil
	c.eliminated = me ~= nil and not me.alive
	c.resultShown = MatchHud.resultVisible()
	return c
end

local lastText = ""
local available: { [string]: boolean } = {}

function Guide.update()
	local c = context()
	local step = Tutorial.step(c)
	local minimal = Tutorial.minimalHud(c.done, c.skipped)
	Hud.setMinimal(minimal)
	if step ~= Guide.step then
		Guide.step = step
		if step ~= "none" then
			Guide.steps += 1
			Audio.play("card", 0.3, 1.5)
		end
	end
	if step == "none" then
		layer.Visible = false
		Guide.pointing = nil
		Tutorial.update(tracker, "none", false, os.clock())
		return
	end
	layer.Visible = true
	local key = Tutorial.keyFor[step]
	local text = if key then Lang.t(key) else ""
	if text ~= lastText then
		lastText = text
		chipText.Text = text
		Theme.pop(chip, 1.14)
	end
	local name = Tutorial.pointerFor[step]
	local obj = if name then targetObject(name) else nil
	available = {}
	if name and obj and shown(obj) then
		available[name] = true
	end
	local draw = Tutorial.update(tracker, step, name ~= nil and available[name] == true, os.clock())
	local point = if draw then Tutorial.pointer(step :: Tutorial.Step, available) else nil
	Guide.pointing = point
	chip.Visible = true
	skip.Visible = true
	glow.Visible = point ~= nil
	arrow.Visible = point ~= nil
	if not point then
		-- no target on screen: the line sits at a fixed place near the bottom centre
		local size = layer.AbsoluteSize
		-- lobby countdown: above the seated panel; in a match: middle of the screen, clear of
		-- the turn banner at the top and the cards at the bottom
		local x = size.X / 2 - skip.AbsoluteSize.X / 2
		local y = if step == "wait" then size.Y - 150 else size.Y * 0.5
		chip.Position = UDim2.fromOffset(x, y)
		skip.AnchorPoint = Vector2.new(0, 0.5)
		skip.Position = UDim2.fromOffset(x + chip.AbsoluteSize.X / 2 + 8, y)
	end
end

local acc = 0
function Guide.init()
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.12 then
			acc = 0
			Guide.update()
		end
		local point = Guide.pointing
		if point then
			local obj = targetObject(point)
			if obj and shown(obj) then
				place(point, obj, os.clock())
			end
		end
	end)
	Net.Changed:Connect(Guide.update)
	Guide.update()
end

return Guide
