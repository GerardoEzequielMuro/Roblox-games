--!strict
-- Global "Top Farmers" board by total cash earned (OrderedDataStore).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Session = require(script.Parent.Session)

local Leaderboard = {}

local ok, store = pcall(function()
	return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
end)
local ordered: OrderedDataStore? = if ok then store else nil

local rows: { TextLabel } = {}
local nameCache: { [number]: string } = {}

local function buildBoard(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
	bg.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.12)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 90)
	Locale.stamp(title, "world.leaderboard")
	title.Parent = bg
	local list = Instance.new("Frame")
	list.Position = UDim2.fromScale(0.04, 0.13)
	list.Size = UDim2.fromScale(0.92, 0.85)
	list.BackgroundTransparency = 1
	list.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0.005, 0)
	layout.Parent = list
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.fromScale(1, 0.095)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(55, 80, 55) else Color3.fromRGB(65, 95, 65)
		row.Font = Enum.Font.FredokaOne
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1 then Color3.fromRGB(255, 215, 0) elseif i == 2 then Color3.fromRGB(220, 220, 230) elseif i == 3 then Color3.fromRGB(230, 150, 90) else Color3.new(1, 1, 1)
		row.Text = "  " .. i .. ". ---"
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = row
		row.Parent = list
		rows[i] = row
	end
	gui.Parent = board
	for _, face in { Enum.NormalId.Back } do
		local g2 = gui:Clone()
		g2.Face = face
		g2.Parent = board
	end
end

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok2, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok2 then name else "Player"
	return nameCache[userId]
end

local function refresh(board: BasePart)
	if not ordered then
		return
	end
	local s = ordered :: OrderedDataStore
	for _, sess in Session.sessions do
		pcall(function()
			s:SetAsync(tostring(sess.player.UserId), math.floor(sess.profile.totalEarned))
		end)
	end
	local ok2, pages = pcall(function()
		return s:GetSortedAsync(false, 10)
	end)
	if not ok2 then
		return
	end
	local entries = (pages :: DataStorePages):GetCurrentPage()
	for i = 1, 10 do
		local e = entries[i]
		local text = if e then "  " .. i .. ". " .. nameOf(tonumber(e.key) or 0) .. " — " .. Format.cash(e.value) else "  " .. i .. ". ---"
		for _, g in board:GetChildren() do
			if g:IsA("SurfaceGui") then
				local list = (g:FindFirstChildOfClass("Frame") :: Frame):FindFirstChildOfClass("Frame") :: Frame
				local labels = {}
				for _, c in list:GetChildren() do
					if c:IsA("TextLabel") then
						table.insert(labels, c)
					end
				end
				if labels[i] then
					labels[i].Text = text
				end
			end
		end
	end
end

function Leaderboard.run(board: BasePart)
	buildBoard(board)
	task.spawn(function()
		task.wait(5)
		while true do
			pcall(refresh, board)
			task.wait(90)
		end
	end)
end

return Leaderboard
