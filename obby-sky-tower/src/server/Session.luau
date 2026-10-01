--!strict
-- Per-session (non-saved) player state, leaderstats, coin awarding and the State push to the client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LiveEvents = require(ReplicatedStorage.Shared.LiveEvents)
local Gifts = require(ReplicatedStorage.Shared.Gifts)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Powerups = require(ReplicatedStorage.Shared.Powerups)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Data = require(script.Parent.Data)
local Remotes = require(script.Parent.Remotes)

local Session = {}

export type S = {
	joined: number, -- os.clock() at join (play-time rewards are per session)
	collected: { [number]: boolean }, -- coin pickups taken this run
	playClaimed: { [number]: boolean },
	passes: { [string]: boolean },
	inLobby: boolean, -- pressed "Lobby": fall-catcher is off until next checkpoint/return
	lastCheckpointAt: number,
	loaded: boolean,
	at: number, -- highest pad reached since the last respawn (>= profile.stage; rest pads don't save)
	coinStage: number, -- highest stage already paid this run (rest pads can be re-reached after a fall)
	roam: string?, -- Winner's Lounge explore mode in use ("glider" | "cloud"): checkpoints don't count
	shieldUntil: number, -- os.clock() until which kill bricks are ignored (a shield just absorbed a hit)
	-- speedrun (P0-2): start = server time of the first checkpoint of the run (nil = not started);
	-- valid = false as soon as anything helped (Rules.ranked(help)): skips, coils, power-ups,
	-- abilities, the teleporter, or a session that started mid-run
	run: { start: number?, valid: boolean, finalMs: number?, dist: number? }, -- dist: pad-to-pad studs walked on foot (floor for a ranked time)
	lastPos: Vector3?, -- where the character was last put / last reached a pad (teleport plausibility)
	lastPosAt: number, -- os.clock() of lastPos
	help: Rules.Help,
	deaths: { stage: number, count: number }, -- death streak on the current stage (P0-1)
	lastOfferAt: number,
}

-- Admin /event override (P0-6), shared by every module through Session.
Session.eventOverride = nil :: LiveEvents.Active?

function Session.eventActive(id: string): boolean
	return LiveEvents.isActive(id, os.time(), Config.LiveEvents :: any, Session.eventOverride)
end

Session.data = {} :: { [Player]: S }

function Session.start(player: Player): S
	local s: S = {
		joined = os.clock(),
		collected = {},
		playClaimed = {},
		passes = {},
		inLobby = false,
		lastCheckpointAt = 0,
		loaded = false,
		at = 0,
		coinStage = 0,
		roam = nil,
		shieldUntil = 0,
		run = { start = nil, valid = true },
		help = {},
		deaths = { stage = -1, count = 0 },
		lastOfferAt = -math.huge,
		lastPos = nil,
		lastPosAt = 0,
	}
	Session.data[player] = s
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local stage = Instance.new("IntValue")
	stage.Name = "Stage"
	stage.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = ls
	ls.Parent = player
	return s
end

-- Studio-only test tools (free dev skips): Studio AND an explicit flag (Rules.studioTools).
function Session.studioTools(): boolean
	return Rules.studioTools(RunService:IsStudio(), Config.StudioFreeSkips, Workspace:GetAttribute(Config.StudioToolsAttribute) == true)
end

function Session.stop(player: Player)
	Session.data[player] = nil
end

function Session.get(player: Player): S?
	return Session.data[player]
end

function Session.hasPass(player: Player, name: string): boolean
	local s = Session.data[player]
	if not s then
		return false
	end
	if s.passes[name] then
		return true
	end
	-- Fusion = both coils in one pass (Pricing: 139 R$ vs 168 separately)
	if (name == "SpeedCoil" or name == "GravityCoil") and s.passes.Fusion then
		return true
	end
	-- Studio convenience (off by default): unconfigured passes count as owned so every pass can
	-- be tried without publishing. Off, a Studio session plays exactly like a new player's.
	return Config.StudioOwnsPasses and RunService:IsStudio() and Config.Passes[name] == 0
end

-- What is switched on for this player right now (pass + setting, or a timed shop power-up).
function Session.speedOn(player: Player, p: Data.Profile): boolean
	return (p.settings.speedCoil and Session.hasPass(player, "SpeedCoil")) or Powerups.active(p.boosts, "speed", os.time())
end

function Session.gravityOn(player: Player, p: Data.Profile): boolean
	return (p.settings.gravityCoil and Session.hasPass(player, "GravityCoil")) or Powerups.active(p.boosts, "gravity", os.time())
end

function Session.doubleJumpOn(player: Player, p: Data.Profile): boolean
	return Session.hasPass(player, "DoubleJump") or Powerups.active(p.boosts, "doublejump", os.time())
end

-- Extra jumps in the air (0, 1 = double jump, 2 = the lounge's triple jump).
function Session.airJumps(player: Player, p: Data.Profile): number
	return Perks.airJumps(p.perks.triplejump == true and Perks.unlocked(p.best), Session.doubleJumpOn(player, p))
end

-- Flags the run as assisted for every advantage that is on right now. Called when a run starts
-- and whenever a coil, power-up or ability is switched on.
function Session.refreshHelp(player: Player)
	local p = Data.get(player)
	local s = Session.data[player]
	if not p or not s then
		return
	end
	if Session.speedOn(player, p) or Session.gravityOn(player, p) then
		Session.assist(player, "coil")
	end
	if Session.doubleJumpOn(player, p) or Powerups.active(p.boosts, "magnet", os.time()) or (p.pocket ~= nil and p.pocket.stage == p.stage) then
		Session.assist(player, "powerup")
	end
	if Perks.unlocked(p.best) and (p.perks.dash == true or p.perks.triplejump == true) then
		Session.assist(player, "ability")
	end
end

-- Marks the current run as assisted: it will not be ranked (`key` = a field of Rules.Help).
function Session.assist(player: Player, key: string)
	local s = Session.data[player]
	if s then
		(s.help :: any)[key] = true
		s.run.valid = false
	end
end

-- Multiplier from time-limited sources (starter-pack boost, 2x Coins Weekend) and from the
-- permanent coin charms given at stages 300 and 900.
function Session.bonusMult(p: Data.Profile): number
	local mult = Gifts.coinMult(p.gifts)
	if os.time() < (p.boostEndsAt or 0) then
		mult *= 2
	end
	if Session.eventActive("DoubleCoinsWeekend") then
		mult *= 2
	end
	return mult
end

-- Awards coins with pass multipliers. Returns the amount actually given.
function Session.addCoins(player: Player, base: number): number
	local p = Data.get(player)
	if not p or base <= 0 then
		return 0
	end
	local mult = Session.bonusMult(p)
	if Session.hasPass(player, "DoubleCoins") then
		mult *= 2
	end
	if Session.hasPass(player, "VIP") then
		mult *= 1 + Config.VIPCoinBonus
	end
	local amount = math.floor(base * mult + 0.5)
	p.coins += amount
	p.totalCoins += amount
	return amount
end

local function dailyInfo(p: Data.Profile): (boolean, number, number)
	local now = os.time()
	local since = now - p.daily.lastClaim
	local can = since >= Config.DailyCooldown
	local streak = p.daily.streak
	if since > Config.DailyStreakWindow then
		streak = 0
	end
	local nextDay = streak + 1
	return can, math.max(0, Config.DailyCooldown - since), nextDay
end
Session.dailyInfo = dailyInfo

local pushHooks: { (Player) -> () } = {}
-- Called after every State push (stage / coins / win / rebirth changes), e.g. to refresh name tags.
function Session.onPush(fn: (Player) -> ())
	table.insert(pushHooks, fn)
end

function Session.push(player: Player)
	local p = Data.get(player)
	local s = Session.data[player]
	if not p or not s then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local st = ls:FindFirstChild("Stage") :: IntValue?
		local w = ls:FindFirstChild("Wins") :: IntValue?
		if st then
			st.Value = math.max(s.at, p.stage)
		end
		if w then
			w.Value = p.wins
		end
	end
	player:SetAttribute("Stage", math.max(s.at, p.stage))
	local canDaily, dailyIn, nextDay = dailyInfo(p)
	local claimed = {}
	for i in s.playClaimed do
		table.insert(claimed, i)
	end
	local passes = {}
	for name in Config.Passes do
		passes[name] = Session.hasPass(player, name)
	end
	local run = s.run
	local now = os.time()
	Remotes.fire("State", player, {
		run = { start = run.start, valid = run.valid, finalMs = run.finalMs, best = p.bestRunMs },
		starter = {
			available = Config.Products.StarterPack ~= 0 and not p.starterBought and now - p.firstJoin < Config.StarterPackWindow,
			endsAt = p.firstJoin + Config.StarterPackWindow,
			firstSession = now - p.firstJoin < Config.StarterPackWindow,
		},
		boostEndsAt = p.boostEndsAt,
		groupGift = Config.GroupId ~= 0 and not p.groupGiftClaimed,
		stage = p.stage,
		at = math.max(s.at, p.stage),
		base = p.base,
		best = p.best,
		gifts = p.gifts,
		boosts = p.boosts,
		charges = p.charges,
		perks = p.perks,
		roam = s.roam,
		pocket = p.pocket ~= nil and p.pocket.stage == p.stage,
		wins = p.wins,
		coins = p.coins,
		freeSkips = p.freeSkips,
		trails = p.trails,
		equippedTrail = p.equippedTrail,
		effects = p.effects,
		equippedEffect = p.equippedEffect,
		pets = p.pets,
		equippedPet = p.equippedPet,
		shine = p.shine,
		settings = p.settings,
		lang = p.lang,
		passes = passes,
		daily = { canClaim = canDaily, nextIn = dailyIn, day = nextDay },
		playSeconds = os.clock() - s.joined,
		playClaimed = claimed,
		persistent = Data.isPersistent(player),
		studio = RunService:IsStudio(),
		studioTools = Session.studioTools(),
	})
	for _, fn in pushHooks do
		task.spawn(fn, player)
	end
end

function Session.pushAll()
	for _, player in Players:GetPlayers() do
		Session.push(player)
	end
end

return Session
