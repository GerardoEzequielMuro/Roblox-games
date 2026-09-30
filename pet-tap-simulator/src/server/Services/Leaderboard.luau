--!strict
-- leaderstats (player list) + global OrderedDataStore boards (Total Taps, Rebirths) shown
-- on the SurfaceGui boards in spawn. Total Taps is stored log-encoded so it never
-- overflows the OrderedDataStore integer range.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)

local Leaderboard = {}

local SCALE = 1e9
local tapsStore: OrderedDataStore? = nil
local rebirthStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		tapsStore = DataStoreService:GetOrderedDataStore(Config.LeaderboardTapsStore)
		rebirthStore = DataStoreService:GetOrderedDataStore(Config.LeaderboardRebirthStore)
	end)
	if not ok then
		warn("[Leaderboard] OrderedDataStore unavailable:", err)
	end
end

local function encodeTaps(n: number): number
	return math.floor(math.log10(math.max(1, n) + 1) * SCALE)
end
local function decodeTaps(v: number): number
	return 10 ^ (v / SCALE) - 1
end

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local n = if ok and name then name else ("#" .. userId)
	nameCache[userId] = n
	return n
end

function Leaderboard.setup(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local taps = Instance.new("StringValue")
	taps.Name = "Taps"
	taps.Value = "0"
	taps.Parent = ls
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = ls
	ls.Parent = player
end

function Leaderboard.updateStats(player: Player)
	local p = Data.get(player)
	local ls = player:FindFirstChild("leaderstats")
	if not p or not ls then
		return
	end
	local taps = ls:FindFirstChild("Taps") :: StringValue?
	local rebirths = ls:FindFirstChild("Rebirths") :: IntValue?
	if taps then
		taps.Value = Format.abbrev(p.totalTaps)
	end
	if rebirths then
		rebirths.Value = p.rebirths
	end
end

local function pushScores()
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p and Data.isPersistent(player) then
			local key = tostring(player.UserId)
			if tapsStore then
				pcall(function()
					(tapsStore :: OrderedDataStore):SetAsync(key, encodeTaps(p.totalTaps))
				end)
			end
			if rebirthStore and p.rebirths > 0 then
				pcall(function()
					(rebirthStore :: OrderedDataStore):SetAsync(key, p.rebirths)
				end)
			end
		end
	end
end

local function renderBoard(board: BasePart, rows: { { name: string, value: string } })
	local gui = board:FindFirstChild("BoardGui")
	local list = gui and gui:FindFirstChild("List")
	if not list then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if #rows == 0 then
		rows = { { name = "No scores yet", value = "" } }
	end
	local medals = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(220, 225, 235), Color3.fromRGB(230, 150, 90) }
	for i, row in rows do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0.095, 0)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = medals[i] or Color3.new(1, 1, 1)
		t.Text = if row.value == "" then row.name else string.format("#%d  %s  —  %s", i, row.name, row.value)
		t.LayoutOrder = i
		if row.value == "" then
			t:SetAttribute("LocKey", "world.board_empty")
		end
		t.Parent = list
	end
end

local function fetch(store: OrderedDataStore?, decode: (number) -> string): { { name: string, value: string } }
	local rows = {}
	if not store then
		return rows
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		return rows
	end
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		local e = entry :: any
		table.insert(rows, { name = nameOf(tonumber(e.key) or 0), value = decode(e.value) })
	end
	return rows
end

function Leaderboard.init(boards: { [string]: BasePart })
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				Leaderboard.updateStats(player)
			end
			task.wait(1)
		end
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			pcall(pushScores)
			local ok, err = pcall(function()
				if boards.taps then
					renderBoard(boards.taps, fetch(tapsStore, function(v)
						return Format.abbrev(decodeTaps(v))
					end))
				end
				if boards.rebirths then
					renderBoard(boards.rebirths, fetch(rebirthStore, function(v)
						return tostring(v)
					end))
				end
			end)
			if not ok then
				warn("[Leaderboard]", err)
			end
			task.wait(Config.LeaderboardUpdateInterval)
		end
	end)
end

return Leaderboard
