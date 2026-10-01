--!strict
-- Plots, tiles, growth, mutations, harvesting, selling, upgrades, tiles and rebirths.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Odds = require(ReplicatedStorage.Shared.Odds)
local TrophyRules = require(ReplicatedStorage.Shared.Trophies)
local Goals = require(ReplicatedStorage.Shared.Goals)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Validate = require(script.Parent.Parent.Security.Validate)
local Weather = require(script.Parent.Weather)
local Events = require(script.Parent.Events)
local Rewards = require(script.Parent.Rewards)
local Social = require(script.Parent.Social)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local CropVisuals = require(script.Parent.Parent.World.CropVisuals)

local Garden = {}

local world: WorldBuilder.World? = nil
local plotOwner: { [number]: Player } = {}
local rng = Random.new()
local MAX_OFFLINE = 24 * 3600

type TileData = { seed: string, progress: number, mut: string?, size: string?, rg: boolean? }

local function logEconomy(player: Player, flow: Enum.AnalyticsEconomyFlowType, amount: number, balance: number, txType: string, sku: string)
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, flow, "Cash", math.max(1, math.floor(amount)), math.max(0, math.floor(balance)), txType, sku)
	end)
end
Garden.logEconomy = logEconomy

local function tileData(s: Session.S, i: number): TileData?
	return (s.profile.tiles :: any)[tostring(i)]
end

local function setTileData(s: Session.S, i: number, t: TileData?)
	(s.profile.tiles :: any)[tostring(i)] = t
end

local function growTime(t: TileData): number
	local seed = Config.SeedById[t.seed]
	return if t.rg and seed.regrowTime then seed.regrowTime else seed.growTime
end

function Garden.rollMutation(s: Session.S, weatherOnly: boolean?): string?
	-- chances come from Shared/Odds, the same module the "Chances" panel shows to the player
	local ctx: Odds.Ctx = {
		luck = Session.luckMult(s),
		weather = Weather.id(),
		goldenMult = Weather.goldenMult(),
		eventMult = Events.mutationMult(),
		exposure = weatherOnly == true, -- periodic roll while crops sit out in the weather
	}
	for _, m in Config.Mutations do
		local chance = Odds.mutationChance(m, ctx)
		if chance > 0 and rng:NextNumber() < chance then
			return m.id
		end
	end
	return nil
end

local function plotInfo(s: Session.S): WorldBuilder.PlotInfo?
	if not world or s.plotIndex == 0 then
		return nil
	end
	return world.plots[s.plotIndex]
end

function Garden.renderTile(s: Session.S, i: number)
	local plot = plotInfo(s)
	if not plot then
		return
	end
	local tile = plot.tiles[i]
	local p = s.profile
	local unlocked = i <= p.tilesOwned
	local t = tileData(s, i)
	tile:SetAttribute("Unlocked", unlocked)
	tile:SetAttribute("HasCrop", t ~= nil)
	tile:SetAttribute("Ripe", t ~= nil and t.progress >= 1)
	tile:SetAttribute("SeedId", if t then t.seed else "")
	tile:SetAttribute("Progress", if t then math.floor(math.min(t.progress, 1) * 50) / 50 else 0)
	tile:SetAttribute("Mutation", if t and t.mut then t.mut else "")
	local nextBuy = i == p.tilesOwned + 1
	CropVisuals.setTileState(tile, unlocked, t ~= nil, nextBuy, if nextBuy and p.tilesOwned < Config.MaxTiles then Formulas.tileCost(p.tilesOwned) else nil)
	CropVisuals.render(tile, if t then t.seed else nil, if t then t.progress else 0, if t and t.progress >= 1 then t.mut else nil, if t and t.progress >= 1 then t.size else nil)
end

-- The crops on the plot's pedestals (profile.trophies).
function Garden.renderTrophies(s: Session.S)
	local plot = plotInfo(s)
	if not plot then
		return
	end
	for i, pedestal in plot.pedestals do
		local old = pedestal:FindFirstChild("Crop")
		if old then
			old:Destroy()
		end
		local item = (s.profile.trophies or {})[i]
		local seed = if item then Config.SeedById[item.seed] else nil
		if item and seed then
			local top = pedestal.CFrame * CFrame.new(0, pedestal.Size.Y / 2, 0)
			local model = CropVisuals.buildModel(top, seed, CropVisuals.STAGES, item.mut, item.size, 0.7)
			model.Parent = pedestal
		end
	end
end

function Garden.renderAll(s: Session.S)
	for i = 1, Config.MaxTiles do
		Garden.renderTile(s, i)
	end
	Garden.renderTrophies(s)
end

local function clearPlot(index: number)
	if not world then
		return
	end
	local plot = world.plots[index]
	plot.model:SetAttribute("OwnerId", 0)
	plot.model:SetAttribute("OwnerName", "")
	WorldBuilder.setOwner(plot, nil, nil)
	for _, tile in plot.tiles do
		tile:SetAttribute("Unlocked", false)
		tile:SetAttribute("HasCrop", false)
		tile:SetAttribute("Ripe", false)
		tile:SetAttribute("SeedId", "")
		tile:SetAttribute("Progress", 0)
		tile:SetAttribute("Mutation", "")
		CropVisuals.setTileState(tile, false, false, false, nil)
		CropVisuals.render(tile, nil, 0, nil)
	end
	for _, pedestal in plot.pedestals do
		local old = pedestal:FindFirstChild("Crop")
		if old then
			old:Destroy()
		end
	end
end

function Garden.teleportHome(s: Session.S)
	local plot = plotInfo(s)
	local char = s.player.Character
	if plot and char then
		char:PivotTo(plot.spawn.CFrame * CFrame.new(0, 4, 0) * CFrame.Angles(0, math.pi, 0))
	end
end

function Garden.assignPlot(s: Session.S): boolean
	if not world then
		return false
	end
	for i = 1, #world.plots do
		if not plotOwner[i] then
			plotOwner[i] = s.player
			s.plotIndex = i
			local plot = world.plots[i]
			plot.model:SetAttribute("OwnerId", s.player.UserId)
			plot.model:SetAttribute("OwnerName", s.player.DisplayName)
			WorldBuilder.setOwner(plot, s.player.UserId, s.player.DisplayName)
			Garden.renderAll(s)
			return true
		end
	end
	return false
end

function Garden.releasePlot(s: Session.S)
	if s.plotIndex ~= 0 and plotOwner[s.plotIndex] == s.player then
		plotOwner[s.plotIndex] = nil
		clearPlot(s.plotIndex)
	end
	s.plotIndex = 0
end

-- Apply growth that happened while the player was offline (no weather bonus).
-- Returns how many crops ripened while the player was away.
function Garden.applyOffline(s: Session.S): number
	local ripened = 0
	local elapsed = math.clamp(os.time() - s.profile.savedAt, 0, MAX_OFFLINE)
	if elapsed <= 0 then
		return 0
	end
	local gm = Session.growthMult(s)
	for k, t in s.profile.tiles :: any do
		if t.progress < 1 then
			t.progress = math.min(1, t.progress + elapsed * gm / growTime(t))
			if t.progress >= 1 then
				t.mut = Garden.rollMutation(s)
				t.size = TrophyRules.rollSize(rng:NextNumber())
				ripened += 1
			end
		end
	end
	return ripened
end

function Garden.instantGrow(s: Session.S)
	for i = 1, s.profile.tilesOwned do
		local t = tileData(s, i)
		if t and t.progress < 1 then
			t.progress = 1
			t.mut = Garden.rollMutation(s)
			t.size = TrophyRules.rollSize(rng:NextNumber())
			Garden.renderTile(s, i)
		end
	end
	Session.markDirty(s)
end

-- Instant Grow (1): ripen the growing crop with the most time left. Returns false when nothing is growing.
function Garden.instantGrowOne(s: Session.S): boolean
	local growing: { Goals.Growing } = {}
	for i = 1, s.profile.tilesOwned do
		local t = tileData(s, i)
		if t and t.progress < 1 then
			table.insert(growing, { tile = i, remaining = (1 - t.progress) * growTime(t) })
		end
	end
	local pick = Goals.slowest(growing)
	if not pick then
		return false
	end
	local t = tileData(s, pick) :: TileData
	t.progress = 1
	t.mut = Garden.rollMutation(s)
	t.size = TrophyRules.rollSize(rng:NextNumber())
	Garden.renderTile(s, pick)
	Session.markDirty(s)
	return true
end

-- ===== actions =====
function Garden.harvest(s: Session.S, i: number, silent: boolean?): (boolean, Locale.Ref?)
	local t = tileData(s, i)
	if not t then
		return false, R("err.nothingPlanted")
	end
	if t.progress < 1 then
		return false, R("err.stillGrowing", { pct = math.floor(t.progress * 100) })
	end
	if Session.backpackCount(s) >= Session.backpackCap(s) then
		return false, R("err.basketFull")
	end
	local seed = Config.SeedById[t.seed]
	local key = Session.basketKey(t.seed, t.mut, t.size)
	s.profile.backpack[key] = (s.profile.backpack[key] or 0) + 1
	local value = Session.itemValue(s, t.seed, t.mut, t.size)
	local plot = plotInfo(s)
	if plot then
		Remotes.fire("HarvestFx", s.player, plot.tiles[i].Position + Vector3.new(0, 4, 0), t.seed, t.mut, value, t.size)
	end
	Rewards.recordIndex(s, t.seed, t.mut)
	if t.mut then
		local m = Config.MutationById[t.mut]
		-- Golden or rarer is a "happy moment": good time to offer event notifications
		if m and m.multiplier >= Config.MutationById.Golden.multiplier then
			Social.happyMoment(s)
		end
		if m and m.multiplier >= 8 then
			Remotes.notifyAll(R("msg.rareHarvest", { player = s.player.DisplayName, mutation = R("mutation." .. m.id), seed = Locale.seedName(seed.id) }), "rare")
		end
	end
	if seed.regrowTime then
		setTileData(s, i, { seed = t.seed, progress = 0, rg = true })
	else
		setTileData(s, i, nil)
	end
	Garden.renderTile(s, i)
	Session.markDirty(s)
	return true, if silent then nil else nil
end

function Garden.harvestAll(s: Session.S): (number, boolean)
	local n = 0
	local full = false
	for i = 1, s.profile.tilesOwned do
		local t = tileData(s, i)
		if t and t.progress >= 1 then
			local ok = Garden.harvest(s, i, true)
			if ok then
				n += 1
			else
				full = true
				break
			end
		end
	end
	return n, full
end

function Garden.plant(s: Session.S, i: number, seedId: string): (boolean, Locale.Ref?)
	local seed = Config.SeedById[seedId]
	if not seed then
		return false, R("err.unknownSeed")
	end
	if i < 1 or i > s.profile.tilesOwned then
		return false, R("err.tileLocked")
	end
	if tileData(s, i) then
		return false, R("err.tileTaken")
	end
	local have = s.profile.seeds[seedId] or 0
	if have <= 0 then
		return false, R("err.noSeedsOf", { seed = Locale.seedName(seed.id) })
	end
	if have - 1 > 0 then
		s.profile.seeds[seedId] = have - 1
	else
		s.profile.seeds[seedId] = nil
	end
	setTileData(s, i, { seed = seedId, progress = 0 })
	Garden.renderTile(s, i)
	Session.markDirty(s)
	return true
end

local function nearSellStand(s: Session.S): boolean
	if not world then
		return false
	end
	local char = s.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - world.sellStand.Position).Magnitude <= Config.SellRadius
end

function Garden.sell(s: Session.S, force: boolean?): (boolean, Locale.Ref?)
	if not force and not s.passes.SellAnywhere and not nearSellStand(s) then
		return false, R("err.sellFar")
	end
	local total = Session.backpackValue(s)
	local count = Session.backpackCount(s)
	if count == 0 then
		return false, R("err.basketEmpty")
	end
	table.clear(s.profile.backpack)
	Session.addCash(s, total, true)
	logEconomy(s.player, Enum.AnalyticsEconomyFlowType.Source, total, s.profile.cash, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "SellBasket")
	return true, R("msg.sold", { count = count, cash = Format.cash(total) })
end

-- ===== growth loop =====
function Garden.run()
	local weatherAcc = 0
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = math.min(5, now - last)
			last = now
			weatherAcc += dt
			local weatherRoll = false
			if weatherAcc >= 10 then
				weatherAcc = 0
				weatherRoll = Weather.id() ~= nil
			end
			local wg = Weather.growthMult() * Events.growthMult()
			for _, s in Session.sessions do
				if s.plotIndex == 0 then
					continue
				end
				local gm = Session.growthMult(s) * wg
				for i = 1, s.profile.tilesOwned do
					local t = tileData(s, i)
					if not t then
						continue
					end
					if t.progress < 1 then
						t.progress = math.min(1, t.progress + dt * gm / growTime(t))
						if t.progress >= 1 then
							t.mut = Garden.rollMutation(s)
							t.size = TrophyRules.rollSize(rng:NextNumber())
						end
						Garden.renderTile(s, i)
					elseif weatherRoll and not t.mut then
						local m = Garden.rollMutation(s, true)
						if m then
							t.mut = m
							Garden.renderTile(s, i)
						end
					end
				end
			end
		end
	end)
end

-- ===== remotes =====
local function withSession(fn: (s: Session.S, payload: any) -> (boolean, Locale.Ref?))
	return function(player: Player, payload: any): (boolean, Locale.Ref?)
		local s = Session.get(player)
		if not s or s.plotIndex == 0 then
			return false, R("err.loading")
		end
		return fn(s, payload)
	end
end

local function tileArg(payload: any): number?
	return Validate.integer(payload.tile, 1, Config.MaxTiles)
end

Remotes.handle("Plant", withSession(function(s, payload)
	local i = tileArg(payload)
	local seedId = Validate.key(payload.seedId, Config.SeedById)
	if not i or not seedId then
		return false, R("err.badTile")
	end
	return Garden.plant(s, i, seedId)
end))

Remotes.handle("PlantAll", withSession(function(s, payload)
	if not Validate.key(payload.seedId, Config.SeedById) then
		return false, R("err.pickSeed")
	end
	local n = 0
	for i = 1, s.profile.tilesOwned do
		if not tileData(s, i) and (s.profile.seeds[payload.seedId] or 0) > 0 then
			if Garden.plant(s, i, payload.seedId) then
				n += 1
			end
		end
	end
	if n == 0 then
		return false, if (s.profile.seeds[payload.seedId] or 0) == 0 then R("err.noSeedsType") else R("err.noEmptyTiles")
	end
	return true, R("msg.planted", { count = n })
end))

Remotes.handle("Harvest", withSession(function(s, payload)
	local i = tileArg(payload)
	if not i then
		return false, R("err.badTile")
	end
	return Garden.harvest(s, i)
end))

Remotes.handle("HarvestAll", withSession(function(s)
	local n, full = Garden.harvestAll(s)
	if n == 0 then
		return false, if full then R("err.basketFull") else R("err.nothingRipe")
	end
	return true, R(if full then "msg.harvestedFull" else "msg.harvested", { count = n })
end))

Remotes.handle("Shovel", withSession(function(s, payload)
	local i = tileArg(payload)
	if not i or not tileData(s, i) then
		return false, R("err.nothingToRemove")
	end
	setTileData(s, i, nil)
	Garden.renderTile(s, i)
	Session.markDirty(s)
	return true, R("msg.cropRemoved")
end))

Remotes.handle("SellAll", withSession(function(s)
	return Garden.sell(s)
end))

Remotes.handle("BuyTile", withSession(function(s)
	local p = s.profile
	if p.tilesOwned >= Config.MaxTiles then
		return false, R("err.allTiles")
	end
	local cost = Formulas.tileCost(p.tilesOwned)
	if not Session.trySpend(s, cost) then
		return false, R("err.need", { cash = Format.cash(cost) })
	end
	p.tilesOwned += 1
	logEconomy(s.player, Enum.AnalyticsEconomyFlowType.Sink, cost, p.cash, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Tile")
	Garden.renderTile(s, p.tilesOwned)
	if p.tilesOwned < Config.MaxTiles then
		Garden.renderTile(s, p.tilesOwned + 1)
	end
	return true, R("msg.tileUnlocked", { owned = p.tilesOwned, max = Config.MaxTiles })
end))

Remotes.handle("BuyUpgrade", withSession(function(s, payload)
	local u = if Validate.key(payload.id, Config.UpgradeById) then Config.UpgradeById[payload.id] else nil
	if not u then
		return false, R("err.unknownUpgrade")
	end
	local lvl = s.profile.upgrades[u.id] or 0
	if lvl >= u.maxLevel then
		return false, R("err.maxed")
	end
	local cost = Formulas.upgradeCost(u.id, lvl)
	if not Session.trySpend(s, cost) then
		return false, R("err.need", { cash = Format.cash(cost) })
	end
	s.profile.upgrades[u.id] = lvl + 1
	logEconomy(s.player, Enum.AnalyticsEconomyFlowType.Sink, cost, s.profile.cash, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Upgrade_" .. u.id)
	return true, R("msg.upgraded", { upgrade = R("upgrade." .. u.id .. ".name"), level = lvl + 1 })
end))

Remotes.handle("Rebirth", withSession(function(s)
	local p = s.profile
	local cost = Formulas.rebirthCost(p.rebirths)
	if p.cash < cost then
		return false, R("err.needRebirth", { cash = Format.cash(cost) })
	end
	p.rebirths += 1
	p.cash = Config.StartingCash
	p.tilesOwned = Config.StartingTiles
	for id in p.upgrades do
		local u = Config.UpgradeById[id]
		if not (u and u.keepOnRebirth) then
			p.upgrades[id] = 0
		end
	end
	table.clear(p.seeds)
	for id, n in Config.StartingSeeds :: { [string]: number } do
		p.seeds[id] = n
	end
	table.clear(p.backpack)
	table.clear(p.tiles)
	Garden.renderAll(s)
	Session.markDirty(s)
	Remotes.notifyAll(R("msg.rebirthAll", { player = s.player.DisplayName, n = p.rebirths }), "success")
	if p.rebirths == 1 then
		Social.happyMoment(s)
	end
	return true, R("msg.rebirthDone", { pct = math.floor(p.rebirths * Config.RebirthBonus * 100) })
end))

Remotes.handle("FinishTutorial", function(player)
	local s = Session.get(player)
	if s and not s.profile.tutorialDone then
		s.profile.tutorialDone = true
		-- first-minute reward: one time only (guarded by tutorialDone, saved in the profile) and only for players
		-- who really sold a harvest, so skipping the tutorial does not pay
		if s.profile.totalEarned > 0 then
			local text = Rewards.grant(s, Config.TutorialGift)
			Remotes.notify(player, R("msg.tutorialGift", { reward = text }), "success")
		end
		Session.markDirty(s)
	end
	return true
end)

function Garden.init(w: WorldBuilder.World)
	world = w
	for i in w.plots do
		clearPlot(i)
	end
	local prompt = w.sellStand:FindFirstChild("Prompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player)
		local s = Session.get(player)
		if not s then
			return
		end
		local ok, msg = Garden.sell(s)
		if msg then
			Remotes.notify(player, msg, if ok then "success" else "error")
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			local s = Session.get(player)
			if s then
				Garden.teleportHome(s)
			end
		end)
	end)
end

return Garden
