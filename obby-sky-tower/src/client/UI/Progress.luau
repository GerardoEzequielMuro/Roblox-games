--!strict
-- Progress, the way tower games show it:
--   * "Progress": a thin vertical bar on the right edge for the 100 stages of the tower you are
--     on (ten segments in the colours of its worlds, bottom = stage 0, top = summit), with your
--     head and everybody else's next to it.
--   * "LevelBar": a wide slim bar at the bottom centre for the whole climb (stage N of 1,000, a
--     tick on every summit gift), and over it the tower's name and the next gift.
-- Hud.luau places both (they depend on the input mode and on the action buttons).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Segments = require(ReplicatedStorage.Shared.Segments)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local TowerStyle = require(ReplicatedStorage.Shared.TowerStyle)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Feel = require(script.Parent.Feel)

local Progress = {}

local TOTAL = Layout.TOTAL
Progress.SIDE_W = 64 -- design px: heads (left) + track (right)
Progress.TRACK_W = 16
Progress.LEVEL_W = 760
Progress.LEVEL_H = 50 -- tower line (18) + bar (28) + gap
local thumbs: { [number]: string } = {}

-- One colour per world (10 stages each), in tower order: the bar shows which world you are in
-- and what is coming.
Progress.WORLD_COLORS = {
	Color3.fromRGB(110, 205, 90), -- Grassy Hills
	Color3.fromRGB(255, 140, 205), -- Candy Land
	Color3.fromRGB(140, 210, 255), -- Frozen Peaks
	Color3.fromRGB(240, 190, 100), -- Desert Ruins
	Color3.fromRGB(255, 110, 40), -- Lava Caves
	Color3.fromRGB(60, 195, 200), -- Ocean Reef
	Color3.fromRGB(165, 225, 50), -- Toxic Factory
	Color3.fromRGB(190, 205, 255), -- Cloud Kingdom
	Color3.fromRGB(185, 85, 255), -- Neon Space
	Color3.fromRGB(255, 205, 60), -- Rainbow Summit
}

-- The side bar shows the 100 stages of the tower you are on: ten segments in the colours of its
-- ten worlds, in the order that tower plays them.
local function worldSequence(tower: number): ColorSequence
	local points = {}
	for _, stop in Segments.colorStops(#Progress.WORLD_COLORS) do
		local style = Layout.themeFor((tower - 1) * Layout.STAGES + (stop.index - 1) * 10 + 1)
		table.insert(points, ColorSequenceKeypoint.new(stop.t, Progress.WORLD_COLORS[style]))
	end
	return ColorSequence.new(points)
end

-- Tower being climbed at global stage `stage` (on a summit: the one just finished, until the
-- portal is taken) and the position inside it (0..100).
local function towerAndSlot(stage: number, onBase: boolean): (number, number)
	if stage <= 0 then
		return 1, 0
	end
	if stage % Layout.STAGES == 0 then
		local done = stage // Layout.STAGES
		if onBase and done < Layout.TOWERS then
			return done + 1, 0
		end
		return done, Layout.STAGES
	end
	return Layout.towerOf(stage), Layout.slotOf(stage)
end
Progress.towerAndSlot = towerAndSlot

local function reveal(p: number): NumberSequence
	local points = {}
	for _, stop in Segments.revealStops(p) do
		table.insert(points, NumberSequenceKeypoint.new(stop.t, stop.value))
	end
	return NumberSequence.new(points)
end

local function headshot(userId: number): string
	local cached = thumbs[userId]
	if cached then
		return cached
	end
	thumbs[userId] = "" -- in flight
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		thumbs[userId] = if ok then url else ""
	end)
	return ""
end

local function stageOf(p: Player): number
	local v = p:GetAttribute("Stage")
	if type(v) == "number" then
		return v
	end
	local ls = p:FindFirstChild("leaderstats")
	local st = ls and ls:FindFirstChild("Stage")
	if st and st:IsA("IntValue") then
		return st.Value
	end
	return 0
end

function Progress.init()
	-- side bar ---------------------------------------------------------------------------------
	local side = Kit.region("Progress", Vector2.new(1, 0.5), UDim2.new(1, -6, 0.5, 0), Vector2.new(Progress.SIDE_W, 500))
	local track = Kit.frame(side, UDim2.new(0, Progress.TRACK_W, 1, 0), UDim2.fromScale(1, 0), Color3.fromRGB(255, 255, 255), Vector2.new(1, 0))
	track.Name = "Track"
	Kit.corner(track, 8)
	Kit.stroke(track, Kit.C.ink, 2.5)
	-- the whole bar in pale world colours, and on top of it the part you've climbed at full
	-- strength (same gradient, revealed up to your progress). Rotation -90: 0 is the bottom.
	local ghost = Kit.frame(track, UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(255, 255, 255))
	ghost.Name = "Worlds"
	Kit.corner(ghost, 8)
	local ghostGradient = Instance.new("UIGradient")
	ghostGradient.Rotation = -90
	ghostGradient.Color = worldSequence(1)
	ghostGradient.Transparency = NumberSequence.new(0.7)
	ghostGradient.Parent = ghost
	local fill = Kit.frame(track, UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(255, 255, 255))
	fill.Name = "Fill"
	Kit.corner(fill, 8)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = -90
	fillGradient.Color = worldSequence(1)
	fillGradient.Transparency = reveal(0)
	fillGradient.Parent = fill
	-- a tick between worlds
	for i = 1, 9 do
		local tick = Kit.frame(track, UDim2.new(1, 0, 0, 2), UDim2.fromScale(0, 1 - i / 10), Kit.C.ink)
		tick.BackgroundTransparency = 0.5
		tick.ZIndex = 2
	end
	local markers = Kit.frame(side, UDim2.new(1, -Progress.TRACK_W - 4, 1, 0), UDim2.new(), nil)
	markers.Name = "Markers"

	-- level bar --------------------------------------------------------------------------------
	local level = Kit.region("LevelBar", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), Vector2.new(Progress.LEVEL_W, Progress.LEVEL_H))
	local sub = Kit.bold(level, "", UDim2.new(1, 0, 0, 18), UDim2.new(), Kit.C.white, nil, 16)
	sub.Name = "Tower"
	local bar = Kit.frame(level, UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 21), Color3.fromRGB(24, 28, 44))
	bar.Name = "Bar"
	bar.BackgroundTransparency = 0.35
	Kit.corner(bar, 14)
	Kit.stroke(bar, Kit.C.ink, 2.5)
	local total = Kit.frame(bar, UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(255, 255, 255))
	total.Name = "Total"
	Kit.corner(total, 14)
	local totalGradient = Instance.new("UIGradient")
	totalGradient.Color = ColorSequence.new(Color3.fromRGB(90, 220, 110), Color3.fromRGB(255, 210, 70))
	totalGradient.Transparency = reveal(0)
	totalGradient.Parent = total
	-- a tick on every summit (a gift waits on each)
	for i = 1, Layout.TOWERS - 1 do
		local tick = Kit.frame(bar, UDim2.new(0, 2, 1, 0), UDim2.fromScale(i / Layout.TOWERS, 0), Color3.fromRGB(255, 255, 255))
		tick.BackgroundTransparency = 0.45
		tick.ZIndex = 2
	end
	local label = Kit.bold(bar, "", UDim2.new(1, -16, 1, -4), UDim2.fromOffset(8, 2), Kit.C.white, nil, 19)
	label.Name = "Label"
	label.ZIndex = 3

	local shownFraction, shownTotal = -1, -1
	local shownTower = 1
	local shownSub = ""
	local shownStage = -1

	local dots: { [Player]: ImageLabel } = {}
	local function dotFor(p: Player): ImageLabel
		local d = dots[p]
		if d then
			return d
		end
		local isMe = p == Players.LocalPlayer
		local size = if isMe then 38 else 28
		local img = Instance.new("ImageLabel")
		img.Name = if isMe then "Me" else "Head"
		img.Size = UDim2.fromOffset(size, size)
		img.AnchorPoint = Vector2.new(1, 0.5)
		img.BackgroundColor3 = if isMe then Kit.C.yellow else Color3.fromRGB(230, 230, 245)
		img.ZIndex = if isMe then 5 else 4
		Kit.corner(img, size)
		Kit.stroke(img, if isMe then Kit.C.orange else Kit.C.ink, if isMe then 3 else 2)
		img.Parent = markers
		dots[p] = img
		return img
	end

	Players.PlayerRemoving:Connect(function(p)
		local d = dots[p]
		if d then
			d:Destroy()
			dots[p] = nil
		end
	end)

	task.spawn(function()
		while true do
			local me = Players.LocalPlayer
			local myStage = stageOf(me)
			local tower, slot = towerAndSlot(myStage, Net.state.base == true)
			if tower ~= shownTower then
				shownTower = tower
				ghostGradient.Color = worldSequence(tower)
				fillGradient.Color = worldSequence(tower)
			end
			local fraction = math.clamp(slot / Layout.STAGES, 0, 1)
			if fraction ~= shownFraction then
				shownFraction = fraction
				fillGradient.Transparency = reveal(fraction)
			end
			local whole = math.clamp(myStage / TOTAL, 0, 1)
			if whole ~= shownTotal then
				shownTotal = whole
				totalGradient.Transparency = reveal(whole)
			end
			local gift = Gifts.next(math.max(tonumber(Net.state.best) or 0, myStage))
			local subKey = ("%d:%d:%s"):format(tower, if gift then gift.id else 0, tostring(myStage))
			if subKey ~= shownSub then
				shownSub = subKey
				Kit.setText(label, "progress.label", { stage = myStage, total = TOTAL, pct = math.floor(myStage / TOTAL * 100) })
				if shownStage >= 0 and myStage > shownStage then
					Feel.punch(label, 0.2) -- the level counter pops when you climb
				end
				shownStage = myStage
				local name = { key = "tower." .. TowerStyle.mood(tower).key }
				if gift then
					Kit.setText(sub, "progress.sub", { n = tower, name = name, stage = gift.stage, gift = { key = "gift." .. gift.id .. ".name" } })
				else
					Kit.setText(sub, "progress.sub_done", { n = tower, name = name })
				end
			end
			local shown = 0
			for _, p in Players:GetPlayers() do
				if p == me or shown < 15 then
					if p ~= me then
						shown += 1
					end
					local d = dotFor(p)
					-- everybody on your tower is on the bar; players on other towers sit at its ends
					local theirTower, theirSlot = towerAndSlot(stageOf(p), p == me and Net.state.base == true)
					local y = if theirTower == tower then theirSlot / Layout.STAGES elseif theirTower < tower then 0 else 1
					d.Position = UDim2.new(1, 0, 1 - math.clamp(y, 0, 1), 0)
					if d.Image == "" then
						d.Image = headshot(p.UserId)
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

return Progress
