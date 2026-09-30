--!strict
-- leaderstats (player list) + global OrderedDataStore boards: all-time wins, this season's
-- trophies and this week's wins. The rows are cached and served to the lobby boards and the
-- Ranking window.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)

local Leaderboard = {}

export type Row = { name: string, value: number, userId: number }
Leaderboard.rows = { wins = {}, season = {}, weekly = {} } :: { [string]: { Row } }

function Leaderboard.week(now: number): number
	return (now + 3 * 86400) // (7 * 86400) -- weeks start on Monday 00:00 UTC
end

local function storeFor(kind: string): OrderedDataStore?
	local name = Config.DataStoreName .. "_lb_" .. kind
	if kind == "season" then
		name ..= "_" .. Progression.season(os.time())
	elseif kind == "weekly" then
		name ..= "_" .. Leaderboard.week(os.time())
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
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
	for _, name in { "Wins", "Trophies", "Level" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player
end

function Leaderboard.updateStats(player: Player)
	local p = Data.get(player)
	local ls = player:FindFirstChild("leaderstats")
	if not p or not ls then
		return
	end
	local function set(name: string, value: number)
		local v = ls:FindFirstChild(name) :: IntValue?
		if v and v.Value ~= value then
			v.Value = value
		end
	end
	set("Wins", p.wins)
	set("Trophies", p.trophies)
	set("Level", p.level)
end

local function values(p: Data.Profile): { [string]: number }
	local now = os.time()
	local weekly = if p.weekly.week == Leaderboard.week(now) then p.weekly.wins else 0
	-- trophies only count on this season's board once the profile has rolled into it
	local season = if p.season == Progression.season(now) then p.trophies else 0
	return { wins = p.wins, season = season, weekly = weekly }
end

local function pushScores()
	for _, player in Players:GetPlayers() do
		if State.ready[player] then
			-- a server that stays up across the 1st of the month rolls its players over here
			State.checkSeason(player)
		end
		local p = Data.get(player)
		if p and Data.isPersistent(player) then
			for kind, value in values(p) do
				local store = storeFor(kind)
				if store and value > 0 then
					pcall(function()
						store:SetAsync(tostring(player.UserId), value)
					end)
				end
			end
		end
	end
end

local function fetch(kind: string): { Row }
	local rows: { Row } = {}
	local store = storeFor(kind)
	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, Config.LeaderboardSize)
		end)
		if ok and pages then
			for _, entry in (pages :: DataStorePages):GetCurrentPage() do
				local e = entry :: any
				local userId = tonumber(e.key) or 0
				table.insert(rows, { name = nameOf(userId), value = e.value, userId = userId })
			end
		end
	end
	return rows
end

-- Without DataStore access (Studio, unpublished) the boards show this server's players.
local function localRows(kind: string): { Row }
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p then
			local value = values(p)[kind]
			if value > 0 then
				table.insert(rows, { name = player.DisplayName, value = value, userId = player.UserId })
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	while #rows > Config.LeaderboardSize do
		table.remove(rows)
	end
	return rows
end

function Leaderboard.refresh()
	for kind in Leaderboard.rows do
		local rows = if game.PlaceId ~= 0 then fetch(kind) else {}
		if #rows == 0 then
			rows = localRows(kind)
		end
		Leaderboard.rows[kind] = rows
	end
end

function Leaderboard.init()
	Remotes.handle("GetBoards", function()
		return true, { rows = Leaderboard.rows, seasonEndsAt = Progression.seasonEndsAt(os.time()) }
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				Leaderboard.updateStats(player)
			end
			task.wait(1)
		end
	end)
	task.spawn(function()
		task.wait(8)
		while true do
			if game.PlaceId ~= 0 then
				pcall(pushScores)
			end
			local ok, err = pcall(function()
				Leaderboard.refresh()
			end)
			if not ok then
				warn("[Leaderboard]", err)
			end
			task.wait(Config.LeaderboardRefresh)
		end
	end)
end

return Leaderboard
