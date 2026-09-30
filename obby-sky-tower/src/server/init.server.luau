--!strict
-- Sky Tower Obby: server bootstrap. Builds the lobby and the first tower, wires services, handles
-- the player lifecycle. Towers 2..10 are built on demand (Towers.luau).
local Players = game:GetService("Players")

local Data = require(script.Data)
local Remotes = require(script.Remotes)
local Session = require(script.Session)
local StageGenerator = require(script.StageGenerator)
local Obstacles = require(script.Obstacles)
local Towers = require(script.Towers)
local Cosmetics = require(script.Cosmetics)
local Checkpoints = require(script.Checkpoints)
local Shops = require(script.Shops)
local Lounge = require(script.Lounge)
local Monetization = require(script.Monetization)
local Rewards = require(script.Rewards)
local Leaderboard = require(script.Leaderboard)
local Referrals = require(script.Referrals)
local Events = require(script.Events)
local Nametags = require(script.Nametags)

Players.RespawnTime = 1.5

local lobby = StageGenerator.buildLobby()
Obstacles.init()
Cosmetics.init()
Rewards.init()
Checkpoints.init(lobby, function(player, info)
	local p = Data.get(player)
	if p then
		Leaderboard.record(player, p.wins, true)
		if info.newBest and info.runMs then
			Leaderboard.recordFastest(player, info.runMs)
		end
		Data.save(player)
	end
end, function(player, best)
	Leaderboard.recordStage(player, best, best % 100 == 0)
end)
Shops.init()
Lounge.init()
Towers.init() -- builds tower 1 (yields a few frames) and starts the on-demand sweep
Referrals.init()
Events.init()
Nametags.init()
Monetization.init()
Leaderboard.init(lobby.board, lobby.fastBoard, lobby.stageBoard)
Data.startAutosave()

for panel, prompt in lobby.stalls do
	prompt.Triggered:Connect(function(player)
		Remotes.fire("OpenPanel", player, panel)
	end)
end

Remotes.handle("GetState", function(player)
	Session.push(player)
	Events.sendTo(player) -- the join-time LiveEventUpdate can arrive before the client listens
	return true
end)

local function onCharacter(player: Player, char: Model)
	-- CharacterAdded and the "already spawned" path can both fire for the first character
	if char:GetAttribute("SetUp") then
		return
	end
	char:SetAttribute("SetUp", true)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root or not Data.get(player) then
		return
	end
	task.wait() -- let the default spawn finish before moving
	local s = Session.get(player)
	if s and s.roam then
		-- died while exploring: explore mode ends with the character
		s.roam = nil
		player:SetAttribute("Roam", nil)
	end
	Checkpoints.teleport(player) -- may build the player's tower first
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			Checkpoints.noteDeath(player) -- death streak -> skip offer (P0-1)
		end)
	end
	-- The avatar's body parts and accessories can still be arriving (CharacterAppearanceLoaded
	-- fires after CharacterAdded). Pieces welded to a Head / Torso that the appearance then
	-- replaces are left loose and fall off the character ("disassembled" look), so the welded
	-- extras wait for the full appearance, and are re-applied if a body part is swapped later.
	Cosmetics.applyTrail(player)
	Cosmetics.applyEffect(player)
	Cosmetics.applyCoils(player)
	Session.push(player)
	if not player:HasAppearanceLoaded() then
		local loaded = false
		local conn = player.CharacterAppearanceLoaded:Connect(function()
			loaded = true
		end)
		local t0 = os.clock()
		while not loaded and os.clock() - t0 < 8 and char.Parent and player.Parent do
			task.wait(0.1)
		end
		conn:Disconnect()
	end
	if not char.Parent or player.Character ~= char then
		return
	end
	char:WaitForChild("Head", 5)
	Cosmetics.applyAll(player)
	Nametags.update(player)
	Session.push(player)
	local pendingRefresh = false
	char.ChildAdded:Connect(function(child)
		if pendingRefresh or not (child.Name == "Head" or child.Name == "UpperTorso" or child.Name == "Torso") then
			return
		end
		pendingRefresh = true
		task.delay(0.2, function()
			pendingRefresh = false
			if char.Parent and player.Character == char then
				Cosmetics.applyExtras(player)
				Nametags.update(player)
			end
		end)
	end)
end

local function onPlayerAdded(player: Player)
	Session.start(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	Data.load(player)
	if not player.Parent then
		return
	end
	Monetization.loadPasses(player)
	local s = Session.get(player)
	local p = Data.get(player)
	if s and p then
		s.loaded = true
		s.at = p.stage
		s.coinStage = p.stage
		-- a session that starts mid-climb can't set a ranked time (P0-2)
		s.run = { start = nil, valid = p.stage == 0 }
		if p.stage ~= 0 then
			s.help.joinedMidRun = true
		end
	end
	Towers.sweep() -- start building the tower this player will need
	Referrals.onJoin(player)
	Session.push(player)
	if not Data.isPersistent(player) then
		Remotes.notify(player, Remotes.M("warn.no_save"), "warn")
	end
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local p = Data.get(player)
	if p then
		Leaderboard.record(player, p.wins, true)
		Leaderboard.recordStage(player, p.best, true)
	end
	Data.release(player)
	Session.stop(player)
	Remotes.forget(player)
end)

-- Keep clients' play-time counters honest.
task.spawn(function()
	while true do
		task.wait(60)
		Session.pushAll()
	end
end)
