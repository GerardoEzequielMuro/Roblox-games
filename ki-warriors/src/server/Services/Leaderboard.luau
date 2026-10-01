--!strict
-- leaderstats (player list) + global OrderedDataStore boards (Power, Ascensions, Arena rating)
-- shown on the SurfaceGui boards in the plaza and in the ranking window. Power is stored
-- log-encoded so it never overflows the OrderedDataStore integer range.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Leaderboard = {}

local SCALE = 1e9
local stores: { [string]: OrderedDataStore } = {}
do
	for id, name in Config.BoardStores do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(name :: string)
		end)
		if ok then
			stores[id :: string] = store :: any
		else
			warn("[Leaderboard] OrderedDataStore unavailable:", tostring(store))
		end
	end
end

local function encodePower(n: number): number
	return math.floor(math.log10(math.max(1, n) + 1) * SCALE)
end
local function decodePower(v: number): number
	return 10 ^ (v / SCALE) - 1
end
Leaderboard.encodePower = encodePower
Leaderboard.decodePower = decodePower

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

-- Latest rows per board: { { name, value } }
Leaderboard.rows = { power = {}, rebirths = {}, arena = {} } :: { [string]: { { name: string, value: string } } }

function Leaderboard.onReady(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local power = Instance.new("StringValue")
	power.Name = "Power"
	power.Value = "0"
	power.Parent = ls
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Ascensions"
	rebirths.Parent = ls
	ls.Parent = player
end

local function updateStats(player: Player)
	local p = Data.get(player)
	local ls = player:FindFirstChild("leaderstats")
	if not p or not ls then
		return
	end
	local power = ls:FindFirstChild("Power") :: StringValue?
	local rebirths = ls:FindFirstChild("Ascensions") :: IntValue?
	if power then
		power.Value = Format.abbrev(State.power(p))
	end
	if rebirths then
		rebirths.Value = p.rebirths
	end
end

-- Scores come only from the server's own profile (never from a client). Written with
-- UpdateAsync: power and ascensions only ever go up (a lagging server cannot lower them), the
-- arena rating is a plain latest value. Skipped when unchanged and when the budget is low.
local lastPushed: { [Player]: { [string]: number } } = {}
local MONOTONIC = { power = true, rebirths = true }

local function finiteScore(v: number): number?
	if v ~= v or v == math.huge or v == -math.huge or v < 0 or v > 2 ^ 52 then
		return nil
	end
	return math.floor(v)
end
Leaderboard.finiteScore = finiteScore

local function pushScores()
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p and Data.isPersistent(player) then
			local key = tostring(player.UserId)
			local values = { power = encodePower(math.max(p.bestPower, State.power(p))), rebirths = p.rebirths, arena = p.pvp.rating }
			local last = lastPushed[player] or {}
			lastPushed[player] = last
			for id, store in stores do
				local v = finiteScore(values[id] or 0)
				if v and last[id] ~= v and (id ~= "rebirths" or p.rebirths > 0) and (id ~= "arena" or p.pvp.kills > 0) then
					local okBudget, budget = pcall(function()
						return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
					end)
					if okBudget and budget < 4 then
						break -- leave the rest for the next round; profile saves come first
					end
					local ok = pcall(function()
						store:UpdateAsync(key, function(old: any)
							if MONOTONIC[id] and type(old) == "number" and old >= v then
								return nil :: any
							end
							return v
						end)
					end)
					if ok then
						last[id] = v
					end
				end
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
	local shown = rows
	if #shown == 0 then
		shown = { { name = "No scores yet", value = "" } }
	end
	local medals = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(220, 225, 235), Color3.fromRGB(230, 150, 90) }
	for i, row in shown do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0.095, 0)
		t.Font = Enum.Font.GothamBold
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

function Leaderboard.init(world: { [string]: any })
	local boards: { [string]: BasePart } = world.boards or {}
	for _, board in boards do
		renderBoard(board, {})
	end
	Players.PlayerRemoving:Connect(function(player)
		lastPushed[player] = nil
	end)
	Remotes.handle("GetBoards", function()
		return true, Leaderboard.rows
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				updateStats(player)
			end
			task.wait(1)
		end
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			pcall(pushScores)
			local ok, err = pcall(function()
				Leaderboard.rows.power = fetch(stores.power, function(v)
					return Format.abbrev(decodePower(v))
				end)
				Leaderboard.rows.rebirths = fetch(stores.rebirths, function(v)
					return tostring(v)
				end)
				Leaderboard.rows.arena = fetch(stores.arena, function(v)
					return tostring(v)
				end)
				for id, board in boards do
					renderBoard(board, Leaderboard.rows[id] or {})
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
