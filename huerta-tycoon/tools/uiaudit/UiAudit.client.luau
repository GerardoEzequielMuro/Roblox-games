-- Prints a layout report every time the viewport size settles (the runner resizes the Studio window).
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local MIN_TOUCH = 40

local function visible(g: GuiObject): boolean
	local node: Instance? = g
	while node and not node:IsA("ScreenGui") do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return node ~= nil and (node :: ScreenGui).Enabled
end

local function audit()
	local vp = camera.ViewportSize
	local off, small, overflow, total = {}, {}, {}, 0
	for _, sg in player.PlayerGui:GetChildren() do
		if not sg:IsA("ScreenGui") or not sg.Enabled then continue end
		for _, g in sg:GetDescendants() do
			if not g:IsA("GuiObject") or not visible(g) then continue end
			if g.AbsoluteSize.X < 2 or g.AbsoluteSize.Y < 2 then continue end
			total += 1
			local p, s = g.AbsolutePosition, g.AbsoluteSize
			local inset = game:GetService("GuiService"):GetGuiInset()
			local top = p.Y + (if sg.IgnoreGuiInset then 0 else inset.Y)
			-- only report top-level-ish things: parent is ScreenGui or a full-screen container
			if (p.X < -4 or top < -4 or p.X + s.X > vp.X + 4 or top + s.Y > vp.Y + 4) and g.BackgroundTransparency < 1 then
				table.insert(off, g:GetFullName():gsub("^.-PlayerGui%.", "") .. string.format(" @%d,%d %dx%d", p.X, top, s.X, s.Y))
			end
			if (g:IsA("TextButton") or g:IsA("ImageButton")) and g.Active and math.min(s.X, s.Y) < MIN_TOUCH then
				table.insert(small, g:GetFullName():gsub("^.-PlayerGui%.", "") .. string.format(" %dx%d", s.X, s.Y))
			end
			if (g:IsA("TextLabel") or g:IsA("TextButton")) and not g.TextScaled and g.Text ~= "" and not g.TextFits then
				table.insert(overflow, g:GetFullName():gsub("^.-PlayerGui%.", ""))
			end
		end
	end
	print(string.format("[TEST] UI viewport %dx%d: %d visible, %d offscreen, %d small buttons, %d text overflow", vp.X, vp.Y, total, #off, #small, #overflow))
	for i = 1, math.min(12, #off) do print("[TEST]   offscreen " .. off[i]) end
	for i = 1, math.min(12, #small) do print("[TEST]   small " .. small[i]) end
	for i = 1, math.min(8, #overflow) do print("[TEST]   overflow " .. overflow[i]) end
end

task.wait(8)
local token = 0
local function schedule()
	token += 1
	local my = token
	task.delay(2.5, function()
		if my == token then audit() end
	end)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(schedule)
schedule()
