--!strict
-- Global boards in the lobby, each backed by an OrderedDataStore:
--   "Top Wins" (most wins, descending), "Fastest Climb" (best unassisted run 0 -> 100 in ms,
--   ascending) and "Highest Stage" (best stage of the 1,000, descending).
-- Rows are localized on each client (LocKey / LocArgs attributes, see client/World/WorldText).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RunTime = require(ReplicatedStorage.Shared.RunTime)
local StageGenerator = require(script.Parent.StageGenerator)

local Leaderboard = {}

local ROWS = 10
local REFRESH = 60

local function openStore(name: string): OrderedDataStore?
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		return result
	end
	warn("[Leaderboard] OrderedDataStore unavailable:", result)
	return nil
end

local winsStore = openStore(Config.WinsBoardStore)
local fastStore = openStore(Config.FastestBoardStore)
local stageStore = openStore(Config.StageBoardStore)

local nameCache: { [number]: string } = {}
local lastWrite: { [number]: number } = {}
local lastStageWrite: { [number]: number } = {}

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		nameCache[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else ("User " .. userId)
	nameCache[userId] = result
	return result
end

local function write(ds: OrderedDataStore?, userId: number, value: number)
	if not ds then
		return
	end
	local store = ds :: OrderedDataStore
	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync(tostring(userId), value)
		end)
		if not ok then
			warn("[Leaderboard] write failed", err)
		end
	end)
end

function Leaderboard.record(player: Player, wins: number, force: boolean?)
	if wins <= 0 then
		return
	end
	local now = os.clock()
	if not force and lastWrite[player.UserId] and now - lastWrite[player.UserId] < 30 then
		return
	end
	lastWrite[player.UserId] = now
	write(winsStore, player.UserId, wins)
end

-- Best stage ever reached (1..1000). Throttled: a climber sets a new best every few seconds.
function Leaderboard.recordStage(player: Player, best: number, force: boolean?)
	if best <= 0 then
		return
	end
	local now = os.clock()
	if not force and lastStageWrite[player.UserId] and now - lastStageWrite[player.UserId] < 60 then
		return
	end
	lastStageWrite[player.UserId] = now
	write(stageStore, player.UserId, best)
end

-- New personal best run (ms). Lower is better.
function Leaderboard.recordFastest(player: Player, ms: number)
	if ms > 0 then
		write(fastStore, player.UserId, ms)
	end
end

local function buildBoard(board: BasePart, titleKey: string, titleColor: Color3): { TextLabel }
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.14)
	title.BackgroundColor3 = titleColor
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(60, 40, 10)
	StageGenerator.loc(title, titleKey)
	title.Parent = sg
	local rows = {}
	for i = 1, ROWS do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.fromScale(0.94, 0.078)
		row.Position = UDim2.fromScale(0.03, 0.155 + (i - 1) * 0.084)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(55, 60, 105) else Color3.fromRGB(70, 76, 130)
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1 then Color3.fromRGB(255, 220, 80) elseif i <= 3 then Color3.fromRGB(220, 230, 255) else Color3.fromRGB(255, 255, 255)
		row.Text = ("%d. ..."):format(i)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.03, 0)
		pad.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = row
		row.Parent = sg
		table.insert(rows, row)
	end
	sg.Parent = board
	return rows
end

local function runBoard(rows: { TextLabel }, ds: OrderedDataStore?, ascending: boolean, rowKey: string, format: (number) -> any)
	task.spawn(function()
		while true do
			if ds then
				local store = ds :: OrderedDataStore
				local ok, pages = pcall(function()
					return store:GetSortedAsync(ascending, ROWS)
				end)
				if ok and pages then
					local entries = pages:GetCurrentPage()
					for i = 1, ROWS do
						local e = entries[i]
						if e then
							local uid = tonumber(e.key) or 0
							StageGenerator.loc(rows[i], rowKey, { rank = i, name = nameOf(uid), value = format(e.value) })
						else
							rows[i]:SetAttribute("LocKey", nil)
							rows[i].Text = ("%d. -"):format(i)
						end
					end
				end
			else
				StageGenerator.loc(rows[1], "board.unavailable")
			end
			task.wait(REFRESH)
		end
	end)
end

function Leaderboard.init(winsBoard: BasePart, fastBoard: BasePart, stageBoard: BasePart)
	runBoard(buildBoard(stageBoard, "board.stage", Color3.fromRGB(150, 255, 170)), stageStore, false, "board.row", function(v)
		return v
	end)
	runBoard(buildBoard(winsBoard, "board.wins", Color3.fromRGB(255, 190, 50)), winsStore, false, "board.row", function(v)
		return v
	end)
	runBoard(buildBoard(fastBoard, "board.fastest", Color3.fromRGB(120, 220, 255)), fastStore, true, "board.row_time", function(v)
		return RunTime.format(v)
	end)
end

return Leaderboard
