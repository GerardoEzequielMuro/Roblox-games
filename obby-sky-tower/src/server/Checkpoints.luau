--!strict
-- Progress through the 1,000 stages: checkpoints (saving pads and rest pads), respawning,
-- fall-catching, skips, summits (win, gift, portal to the next tower) and rebirth.
-- The rules themselves are in Shared/Rules (pure, unit-tested); this module applies them.
-- Anti-exploit: checkpoints must be reached in order (at most Config.MaxStageJump ahead, never
-- across a portal), the character must really be standing near the pad, and only the server ever
-- changes stage / coins.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local StageGenerator = require(script.Parent.StageGenerator)
local Towers = require(script.Parent.Towers)
local Referrals = require(script.Parent.Referrals)
local Cosmetics = require(script.Parent.Cosmetics)

local Checkpoints = {}

local L = Layout :: any
local lobbySpawn = CFrame.new(0, 4, 115)
export type WinInfo = { runMs: number?, newBest: boolean }
local onWin: ((Player, WinInfo) -> ())? = nil
local onBest: ((Player, number) -> ())? = nil
local MIN_SECONDS_PER_CHECKPOINT = 0.8

local function awardBadge(player: Player, badgeId: number)
	if badgeId == 0 then
		return
	end
	task.spawn(function()
		local ok, has = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)
		if ok and not has then
			pcall(function()
				BadgeService:AwardBadge(player.UserId, badgeId)
			end)
		end
	end)
end

-- The highest pad the player holds right now.
local function atOf(p: Data.Profile, s: Session.S): number
	return math.max(s.at, p.stage)
end

local function pocketOf(p: Data.Profile, s: Session.S): CFrame?
	local pk = p.pocket
	if pk and pk.stage == p.stage and p.stage > 0 and not s.inLobby then
		return CFrame.new(pk.x, pk.y, pk.z)
	end
	return nil
end

-- Where the character is put for the saved checkpoint. Builds the tower if needed (may yield).
function Checkpoints.spawnCFrame(player: Player): CFrame
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return lobbySpawn
	end
	local pocket = pocketOf(p, s)
	if pocket then
		return pocket
	end
	local spot = Rules.spawn(L, p.stage, s.inLobby, p.base)
	if not spot then
		return lobbySpawn
	end
	return Towers.standing(spot)
end

-- Puts the character on its checkpoint (after a death, a fall, a skip, a portal...). Yields while
-- a tower is built or the destination streams in.
function Checkpoints.teleport(player: Player)
	local cf = Checkpoints.spawnCFrame(player)
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 4)
	end)
	local p = Data.get(player)
	local s = Session.get(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not p or not s or not char or not root then
		return
	end
	-- back on the checkpoint: progress since the last save is lost (pocket checkpoints keep it)
	local pk = p.pocket
	s.at = if pk and pk.stage == p.stage and not s.inLobby then math.max(pk.at, p.stage) else p.stage
	root.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(cf)
end

local function grantGift(player: Player, p: Data.Profile, gift: Gifts.Gift)
	p.gifts[tostring(gift.id)] = true
	if gift.kind == "trail" then
		p.trails[gift.value :: string] = true
	elseif gift.kind == "effect" then
		p.effects[gift.value :: string] = true
	elseif gift.kind == "skin" then
		p.perks.glow = "glow_rainbow"
	end
	Remotes.fire("Gift", player, { id = gift.id, stage = gift.stage })
	Cosmetics.applyAll(player)
end

-- Moves the player's progress to pad `g` (already validated) and rewards new progress.
-- reason "reach" = walked onto it; anything else (skip, freeSkip, ad, coins) saves there.
local function advanceTo(player: Player, g: number, reason: string)
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return
	end
	local from = atOf(p, s)
	if g <= from then
		return
	end
	g = math.min(g, Layout.TOTAL)
	-- speedrun: the run starts on leaving stage 0; anything that helps makes it unranked
	local run = s.run
	if from == 0 and run.start == nil then
		run.start = Workspace:GetServerTimeNow()
		Session.refreshHelp(player)
	end
	if reason ~= "reach" then
		Session.assist(player, "skipped")
	end
	s.deaths = { stage = g, count = 0 }
	local coins = 0
	for stage = from + 1, g do
		if stage > s.coinStage then
			coins += Session.addCoins(player, Rules.coinsForStage(stage))
		end
	end
	s.coinStage = math.max(s.coinStage, g)
	s.at = g
	local save = reason ~= "reach" or Layout.isSave(g)
	if save then
		p.stage = g
		p.base = false
		p.pocket = nil
	end
	local isBest = g > p.best
	p.best = math.max(p.best, g)
	s.lastCheckpointAt = os.clock()
	s.inLobby = false
	local summit = Rules.isSummit(L, g)
	local newWorld = (g // 10) > (from // 10) and not summit
	Remotes.fire("Celebrate", player, {
		stage = g,
		coins = coins,
		reason = reason,
		save = save,
		world = if newWorld then g // 10 + 1 else nil,
		style = if newWorld then Layout.themeFor(g + 1) else nil,
	})
	if g >= 50 and from < 50 then
		awardBadge(player, Config.BadgeIds.Stage50)
	end
	Referrals.onStage(player, g)
	-- notification opt-in: first world change (stage 10) or a summit, at most once a week
	if ((from < 10 and g >= 10) or summit) and os.time() - p.notifAskedAt > Config.NotifyAskCooldown then
		p.notifAskedAt = os.time()
		Remotes.fire("AskNotifications", player)
	end
	if summit then
		local tower = g // Layout.STAGES
		Session.addCoins(player, Config.CoinsPerTower)
		local gift = Gifts.at(g)
		local newGift = gift ~= nil and not p.gifts[tostring(gift.id)]
		if gift and newGift then
			grantGift(player, p, gift)
		end
		local info: WinInfo = { runMs = nil, newBest = false }
		if tower == 1 then
			p.wins += 1
			awardBadge(player, Config.BadgeIds.Winner)
			if p.wins == 1 and p.equippedTrail == "" then
				p.equippedTrail = "rebirth"
			end
			if run.start and run.valid then
				local ms = math.floor((Workspace:GetServerTimeNow() - run.start) * 1000)
				run.finalMs = ms
				info.runMs = ms
				if p.bestRunMs == 0 or ms < p.bestRunMs then
					p.bestRunMs = ms
					info.newBest = true
				end
			elseif run.start then
				run.finalMs = math.floor((Workspace:GetServerTimeNow() - run.start) * 1000)
			end
		end
		Remotes.fire("Win", player, {
			tower = tower,
			wins = p.wins,
			runMs = info.runMs,
			newBest = info.newBest,
			best = p.bestRunMs,
			gift = if newGift and gift then gift.id else nil,
		})
		if tower == 1 and onWin then
			onWin(player, info)
		end
	end
	if isBest and onBest then
		onBest(player, p.best)
	end
	Session.push(player)
end

-- Returns "ok", "ignore" (never counts) or "retry" (might count a moment later: cooldown, or the
-- server hasn't seen the character arrive yet - Touched can fire before the replicated position).
function Checkpoints.reach(player: Player, g: number): string
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return "ignore"
	end
	if s.roam then
		return "ignore" -- explore mode (glider / cloud): pads don't count
	end
	if g == p.stage and s.inLobby then
		s.inLobby = false -- walked back to their pad
		return "ok"
	end
	if not Rules.canReach(L, atOf(p, s), g, Config.MaxStageJump, p.base) then
		return "ignore" -- behind, too far ahead, or on the other side of a portal
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return "ignore"
	end
	if os.clock() - s.lastCheckpointAt < MIN_SECONDS_PER_CHECKPOINT then
		return "retry"
	end
	local pad = Towers.pad(g)
	if not pad then
		return "ignore"
	end
	local d = root.Position - pad.Position
	if Vector3.new(d.X, 0, d.Z).Magnitude > Config.CheckpointTouchRadius or d.Y < -3 or d.Y > 12 then
		return "retry"
	end
	advanceTo(player, g, "reach")
	return "ok"
end

-- A player standing still on a pad does not fire Touched again, so a touch that was too early
-- (cooldown / position not replicated yet) is re-checked for a couple of seconds.
local pending: { [Player]: { [number]: boolean } } = {}
local function onPadTouched(player: Player, k: number)
	if Checkpoints.reach(player, k) ~= "retry" then
		return
	end
	local mine = pending[player]
	if not mine then
		mine = {}
		pending[player] = mine
	end
	if mine[k] then
		return
	end
	mine[k] = true
	task.spawn(function()
		for _ = 1, 10 do
			task.wait(0.25)
			if not player.Parent or Checkpoints.reach(player, k) ~= "retry" then
				break
			end
		end
		mine[k] = nil
	end)
end

local busy: { [Player]: boolean } = {} -- a teleport / portal is in flight
Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
	busy[player] = nil
end)

local function teleportAsync(player: Player)
	if busy[player] then
		return
	end
	busy[player] = true
	task.spawn(function()
		local ok, err = (pcall :: any)(Checkpoints.teleport, player)
		busy[player] = nil
		if not ok then
			warn("[Checkpoints] teleport failed:", err)
		end
	end)
end
Checkpoints.teleportAsync = teleportAsync

-- Paid / free / coin skips. Returns false when there is nothing to skip (summit before the
-- portal, or stage 1000). A skip never crosses a portal.
function Checkpoints.skip(player: Player, n: number, reason: string): boolean
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return false
	end
	local target = Rules.skipTarget(L, atOf(p, s), n, p.base)
	if not target then
		return false
	end
	advanceTo(player, target, reason)
	teleportAsync(player)
	return true
end

function Checkpoints.canSkip(player: Player): boolean
	local p = Data.get(player)
	local s = Session.get(player)
	return p ~= nil and s ~= nil and Rules.skipTarget(L, atOf(p, s), 1, p.base) ~= nil
end

-- Back to stage 0 for a new ranked run. Everything earned (best stage, gifts, coins, wins) stays,
-- and the lounge teleporter still reaches every world already visited.
function Checkpoints.rebirth(player: Player): (boolean, any?)
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return false, nil
	end
	if atOf(p, s) < Layout.STAGES then
		return false, Remotes.M("err.reach_100")
	end
	p.stage = 0
	p.base = false
	p.pocket = nil
	s.at = 0
	s.coinStage = 0
	s.collected = {}
	s.inLobby = false
	s.roam = nil
	player:SetAttribute("Roam", nil)
	s.run = { start = nil, valid = true }
	s.help = {}
	s.deaths = { stage = 0, count = 0 }
	Session.push(player)
	teleportAsync(player)
	local c = Config.RebirthColors[((math.max(p.wins, 1) - 1) % #Config.RebirthColors) + 1]
	Remotes.notify(player, Remotes.M("msg.rebirth", { n = p.wins }), "success")
	player:SetAttribute("RebirthColor", c)
	if p.wins == 1 then
		awardBadge(player, Config.BadgeIds.FirstRebirth)
	end
	return true
end

-- A death or a fall on the current stage. Every Config.SkipOfferAfterDeaths in a row (and at most
-- once per Config.SkipOfferCooldown) the client gets an OfferSkip card.
function Checkpoints.noteDeath(player: Player)
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s or s.inLobby or Rules.skipTarget(L, p.stage, 1, p.base) == nil then
		return
	end
	if s.deaths.stage ~= p.stage then
		s.deaths = { stage = p.stage, count = 0 }
	end
	s.deaths.count += 1
	local n = s.deaths.count
	if n % Config.SkipOfferAfterDeaths == 0 and os.clock() - s.lastOfferAt >= Config.SkipOfferCooldown then
		s.lastOfferAt = os.clock()
		Remotes.fire("OfferSkip", player, { stage = p.stage + 1, freeSkips = p.freeSkips, adAvailableHint = true })
	end
end

-- The portal at the summit of `tower`: on to the base of the next one. Open for anybody who has
-- ever reached that summit.
local lastPortal: { [Player]: number } = {}
function Checkpoints.enterPortal(player: Player, tower: number): boolean
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s or busy[player] then
		return false
	end
	if os.clock() - (lastPortal[player] or 0) < 2 then
		return false
	end
	lastPortal[player] = os.clock()
	if not Rules.portalOpen(L, p.best, tower) then
		Remotes.notify(player, Remotes.M("err.portal_locked", { n = tower * Layout.STAGES }), "info")
		return false
	end
	local summit = tower * Layout.STAGES
	if p.stage ~= summit then
		Session.assist(player, "travelled") -- came here by the teleporter / exploring
	end
	p.stage = summit
	p.base = true
	p.pocket = nil
	s.at = summit
	s.inLobby = false
	s.roam = nil
	player:SetAttribute("Roam", nil)
	busy[player] = true
	task.spawn(function()
		local ok, err = pcall(function()
			Towers.ensure(tower + 1)
			Checkpoints.teleport(player)
		end)
		busy[player] = nil
		if not ok then
			warn("[Checkpoints] portal failed:", err)
		end
		Remotes.fire("TowerEnter", player, { tower = tower + 1 })
		Session.push(player)
	end)
	return true
end

function Checkpoints.goToLobby(player: Player): boolean
	local s = Session.get(player)
	if not s then
		return false
	end
	s.inLobby = true
	s.roam = nil
	player:SetAttribute("Roam", nil)
	teleportAsync(player)
	Session.push(player)
	return true
end

-- Lounge teleporter: `stage` is a world start already reached (validated by the caller).
function Checkpoints.travel(player: Player, stage: number)
	local p = Data.get(player)
	local s = Session.get(player)
	if not p or not s then
		return
	end
	Session.assist(player, "travelled")
	p.stage = stage
	p.base = false
	p.pocket = nil
	s.at = stage
	s.inLobby = false
	s.roam = nil
	player:SetAttribute("Roam", nil)
	s.deaths = { stage = stage, count = 0 }
	Session.push(player)
	teleportAsync(player)
end

function Checkpoints.init(lobby: StageGenerator.Lobby, winCallback: (Player, WinInfo) -> (), bestCallback: (Player, number) -> ())
	lobbySpawn = lobby.lobbySpawn
	onWin = winCallback
	onBest = bestCallback

	Towers.onBuilt(function(tower)
		for g, pad in tower.pads do
			pad.Touched:Connect(function(hit)
				local model = hit:FindFirstAncestorOfClass("Model")
				local player = model and Players:GetPlayerFromCharacter(model)
				if player then
					onPadTouched(player, g)
				end
			end)
		end
		local portal = tower.portal
		if portal then
			portal.Touched:Connect(function(hit)
				local model = hit:FindFirstAncestorOfClass("Model")
				local player = model and Players:GetPlayerFromCharacter(model)
				if player then
					Checkpoints.enterPortal(player, tower.tower)
				end
			end)
		end
		for _, pr in tower.prompts do
			if pr.kind == "rebirth" then
				pr.prompt.Triggered:Connect(function(player)
					local p = Data.get(player)
					if p and p.best >= Layout.STAGES then
						Remotes.fire("OpenPanel", player, "win")
					end
				end)
			elseif pr.kind == "portal" then
				pr.prompt.Triggered:Connect(function(player)
					Checkpoints.enterPortal(player, tower.tower)
				end)
			elseif pr.kind == "home" then
				pr.prompt.Triggered:Connect(function(player)
					Checkpoints.goToLobby(player)
				end)
			end
		end
	end)

	Remotes.handle("ReturnToCheckpoint", function(player)
		local s = Session.get(player)
		if s then
			s.inLobby = false
		end
		teleportAsync(player)
		return true
	end)
	Remotes.handle("GoToLobby", function(player)
		return Checkpoints.goToLobby(player)
	end)
	Remotes.handle("Rebirth", function(player)
		return Checkpoints.rebirth(player)
	end)
	Remotes.handle("EnterPortal", function(player)
		-- HUD button on a summit: same as walking into the portal
		local p = Data.get(player)
		local s = Session.get(player)
		if not p or not s or not Rules.isSummit(L, p.stage) or p.base then
			return false, Remotes.M("err.not_available")
		end
		return Checkpoints.enterPortal(player, p.stage // Layout.STAGES)
	end)
	Remotes.handle("UseFreeSkip", function(player)
		local p = Data.get(player)
		if not p or p.freeSkips <= 0 then
			return false, Remotes.M("err.no_free_skips")
		end
		if not Checkpoints.canSkip(player) then
			return false, Remotes.M("err.at_top")
		end
		p.freeSkips -= 1
		Checkpoints.skip(player, 1, "freeSkip")
		return true
	end)
	-- Studio-only: product IDs are 0 while developing, so let the Skip button work for free.
	Remotes.handle("DevSkip", function(player, payload)
		if not (RunService:IsStudio() and Config.StudioFreeSkips) then
			return false, Remotes.M("err.not_available")
		end
		local n = if payload.n == 10 then 10 else 1
		return Checkpoints.skip(player, n, "skip")
	end)

	-- Fall catcher: far below your last pad => back to the checkpoint (no death). Only the living:
	-- a dead body sliding off the pad is already counted by Humanoid.Died.
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local p = Data.get(player)
				local s = Session.get(player)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if p and s and root and hum and hum.Health > 0 and not s.inLobby and not s.roam and not busy[player] then
					local at = atOf(p, s)
					local floorY: number? = nil
					if at > 0 then
						local spot = Rules.spawn(L, at, false, p.base and Rules.isSummit(L, at))
						local tower = spot and Towers.get(spot.tower)
						if spot and tower then
							floorY = if spot.pad == 0 then tower.baseCFrame.Position.Y else (tower.padCFrames[at] or tower.baseCFrame).Position.Y
						end
					end
					local pk = p.pocket
					if floorY and pk and pk.stage == p.stage then
						floorY = math.min(floorY, pk.y)
					end
					if floorY and root.Position.Y < floorY - Config.FallLimit then
						Checkpoints.noteDeath(player)
						teleportAsync(player)
					end
				end
			end
		end
	end)
end

return Checkpoints
