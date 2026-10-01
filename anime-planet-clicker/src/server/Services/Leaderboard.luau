--!strict
-- leaderstats (player list) + three global OrderedDataStore boards: Stardust mined (stored
-- log-encoded so it never overflows the integer range), Rebirths and Arena points.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Security = require(ReplicatedStorage.Shared.Security)
local Data = require(script.Parent.Data)
local State = require(script.Parent.State)

local Leaderboard = {}

local SCALE = 1e9
local stores: { [string]: OrderedDataStore } = {}
do
	local ok, err = pcall(function()
		for key, name in Config.LeaderboardStores :: { [string]: string } do
			stores[key] = DataStoreService:GetOrderedDataStore(name)
		end
	end)
	if not ok then
		warn("[Leaderboard] OrderedDataStore unavailable:", err)
	end
end

function Leaderboard.encode(n: number): number
	if not Security.isFinite(n) then
		return 0 -- never publish NaN / inf
	end
	return math.floor(math.log10(math.max(1, n) + 1) * SCALE)
end
function Leaderboard.decode(v: number): number
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
	local power = Instance.new("StringValue")
	power.Name = "Power"
	power.Value = "0"
	power.Parent = ls
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
	local power = ls:FindFirstChild("Power") :: StringValue?
	local rebirths = ls:FindFirstChild("Rebirths") :: IntValue?
	if power then
		power.Value = Format.abbrev(State.basePower(player, p))
	end
	if rebirths then
		rebirths.Value = p.rebirths
	end
end

local pushed: { [string]: number } = {} -- last value sent per userId:board (skips unchanged writes)

local function pushScores()
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p and Data.isPersistent(player) then
			local key = tostring(player.UserId)
			local values = { mined = Leaderboard.encode(p.totalMined), rebirths = p.rebirths, arena = p.arenaPoints }
			for name, store in stores do
				local v: number = values[name] or 0
				-- only whole, finite, positive scores; UpdateAsync keeps the best value, so a
				-- stale server can never push a board entry down
				local pk = key .. ":" .. name
				if Security.isInt(v, 1, 2 ^ 52) and pushed[pk] ~= v then
					pushed[pk] = v
					pcall(function()
						store:UpdateAsync(key, function(old: any)
							if type(old) == "number" and old >= v then
								return nil :: any -- keep the better stored score
							end
							return v
						end)
					end)
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
	local empty = #rows == 0
	if empty then
		rows = { { name = "No scores yet", value = "" } }
	end
	local medals = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(220, 225, 235), Color3.fromRGB(230, 150, 90) }
	for i, row in rows do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0.095, 0)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = if empty then Color3.fromRGB(200, 210, 230) else (medals[i] or Color3.new(1, 1, 1))
		t.Text = if empty then row.name else string.format("#%d  %s  —  %s", i, row.name, row.value)
		t.LayoutOrder = i
		if empty then
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
	Players.PlayerRemoving:Connect(function(player)
		for name in stores do
			pushed[tostring(player.UserId) .. ":" .. name] = nil
		end
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				Leaderboard.updateStats(player)
			end
			task.wait(2)
		end
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			pcall(pushScores)
			local ok, err = pcall(function()
				local decoders = {
					mined = function(v: number): string
						return Format.abbrev(Leaderboard.decode(v))
					end,
					rebirths = function(v: number): string
						return tostring(v)
					end,
					arena = function(v: number): string
						return Format.commas(v)
					end,
				}
				for name, board in boards do
					renderBoard(board, fetch(stores[name], decoders[name]))
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
