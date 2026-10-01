-- Playtest bot: Planet Crackers. Plays the tutorial loop like a new player: stand next to a planet and
-- click it (Miner.simulate = the same code path as a real click), break crust/mantle/core, walk onto the
-- Refinery to sell, open a capsule at the machine, buy tools and upgrades, rebirth when possible.
return function(bot)
	local Net, Miner, PlanetField, Windows, Purchase, Guide
	local Config = bot.shared("Shared.Config")
	local Formulas = bot.shared("Shared.Formulas")
	local Layout = bot.shared("Shared.Layout")
	local stats = { clicks = 0, sells = 0, capsules = 0, tools = 0, upgrades = 0, windows = 0, zonesMoved = 0, rebirths = 0, hatchedNew = 0, walks = 0, sellWalks = 0, planetsBroken = 0 }
	local mining = false

	local function S()
		return Net and Net.state or {}
	end
	local function srv()
		return bot.server("Services.Data").get(bot.player())
	end
	local function req(action, payload)
		bot.wait(0.14)
		return Net.request(action, payload)
	end
	local function v3(p, dy)
		return Vector3.new(p[1], dy or 4, p[3])
	end
	local function zone()
		return PlanetField.zone or 1
	end

	local function goTo(p, timeout)
		stats.walks += 1
		return bot.walkTo(v3(p), timeout or 40)
	end

	-- the planet to mine: alive regular planets of this galaxy, nearest to us, skipping the Titan/Gate
	local function pickNode()
		local me = bot.pos()
		local best, bd
		for n, view in PlanetField.views do
			if view.alive and n >= 1 and n <= Config.NodesPerZone then
				local pos = Layout.nodePosition(zone(), n)
				local d = (Vector3.new(pos[1], 0, pos[3]) - Vector3.new(me.X, 0, me.Z)).Magnitude
				if not bd or d < bd then
					best, bd = n, d
				end
			end
		end
		return best
	end

	local function mineSome(seconds)
		local t0 = bot.now()
		mining = true
		while bot.alive() and bot.now() - t0 < seconds do
			local n = pickNode()
			if not n then
				bot.wait(1)
			else
				local pos = Layout.nodePosition(zone(), n)
				local me = bot.pos()
				local flat = (Vector3.new(pos[1], 0, pos[3]) - Vector3.new(me.X, 0, me.Z)).Magnitude
				if flat > (S().range or Config.BaseRange) - 6 then
					bot.walkTo(Vector3.new(pos[1], 4, pos[3] - 14), 20)
				end
				-- a burst of clicks: like a player tapping for a second
				for _ = 1, 8 do
					if Miner.simulate(n) then
						stats.clicks += 1
					end
					bot.wait(0.11)
				end
				-- the cargo is full: sell
				local cargo = S().cargo
				if cargo and cargo.count >= cargo.cap then
					return "full"
				end
			end
		end
		return "time"
	end

	local function sell()
		-- walking onto the Refinery pad sells by hand (+20%)
		local z = zone()
		stats.sellWalks += 1
		goTo(Layout.refineryPosition(z), 60)
		bot.waitUntil(function()
			local c = S().cargo
			return c and c.count == 0
		end, 6, nil)
		stats.sells += 1
	end

	local function capsuleTrip()
		-- best capsule we can pay for in an unlocked galaxy
		local s = S()
		local best
		for _, cap in Config.Capsules do
			if not cap.exclusive and cap.zone <= (s.maxZone or 1) and (s.stardust or 0) >= cap.price then
				if not best or cap.price > best.price then
					best = cap
				end
			end
		end
		if not best then
			return
		end
		local pos = Layout.capsulePosition(best.id)
		goTo(pos, 60)
		bot.wait(0.5)
		local ok, res = req("Open", { capsule = best.id, count = 1 })
		if ok then
			stats.capsules += 1
			if type(res) == "table" and res[1] and res[1].new then
				stats.hatchedNew += 1
			end
		end
		bot.wait(Config.OpenCooldown)
		if bot.every("equipbest", 40) then
			req("EquipBest")
		end
	end

	local function spend()
		local s = S()
		-- the next tool in the list (any galaxy we own)
		local idx = Config.ToolIndex[s.tool] or 1
		local nextTool = Config.Tools[idx + 1]
		if nextTool and nextTool.zone <= (s.maxZone or 1) and (s.stardust or 0) >= nextTool.cost then
			if req("BuyTool", { id = nextTool.id }) then
				stats.tools += 1
				bot.log("bought tool " .. nextTool.id)
			end
		end
		-- the cheapest upgrade we can afford with stardust or crystals
		local bestU, bestCost
		for _, u in Config.Upgrades do
			local sys = Config.SystemById[u.system]
			if sys.zone <= (s.maxZone or 1) then
				local level = (s.upgrades or {})[u.id] or 0
				if level < u.max then
					local cost = Formulas.upgradeCost(u.id, level)
					local have = if u.currency == "stardust" then s.stardust elseif u.currency == "crystals" then s.crystals else (s.mats or {})[u.currency]
					if (have or 0) >= cost and (not bestCost or cost < bestCost) then
						bestU, bestCost = u, cost
					end
				end
			end
		end
		if bestU and req("Upgrade", { id = bestU.id }) then
			stats.upgrades += 1
		end
		if s.rebirthCost and s.stardust and s.stardust >= s.rebirthCost and bot.every("rebirth", 60) then
			if req("Rebirth") then
				stats.rebirths += 1
				bot.log("rebirth!")
			end
		end
	end

	-- the objective line of the tutorial says what to do next; the steps the mining loop does not hit by itself
	local function followTutorial()
		local step = Config.Tutorial[S().tutorial or 99]
		if step and step.id == "auto" then
			if req("SetAuto", { key = "mine", on = true }) then
				bot.log("tutorial: Auto Mine switched on")
			end
		end
	end

	local function claimThings()
		local s = S()
		local done = {}
		for _, i in s.giftsClaimed or {} do
			done[i] = true
		end
		for i, g in Config.Gifts do
			if not done[i] and (s.sessionElapsed or 0) >= g.minutes * 60 + 2 then
				req("ClaimGift", { index = i })
				break
			end
		end
		if bot.every("daily", 600) then
			req("ClaimDaily")
		end
		local q = s.quests
		if q and q.list and bot.every("quests", 15) then
			for i, e in q.list do
				if not e.claimed and (e.progress or 0) >= e.target then
					req("ClaimQuest", { i = i })
				end
			end
		end
		if bot.every("auto", 120) then
			bot.expectFail(function()
				req("SetAuto", { key = "best", on = true })
			end)
		end
	end

	local function windowTour()
		for _, name in { "pets", "upgrades", "rebirth", "teleport", "settings", "index", "capsule", "auto", "rewards", "quests", "invite", "store" } do
			if not bot.alive() then
				return
			end
			if bot.openWindow(name) then
				stats.windows += 1
			end
			bot.wait(1.2)
			bot.try("close window", function()
				Windows.close()
			end)
			bot.wait(0.3)
		end
	end

	local function settingsTour()
		for _, key in Config.AutoKeys do
			bot.expectFail(function()
				req("SetAuto", { key = key, on = true })
			end)
		end
		bot.wait(4)
		for _, key in Config.AutoKeys do
			req("SetAuto", { key = key, on = Config.AutoDefaults[key] == true })
		end
		for _, l in { "es", "ja", "en" } do
			req("SetLanguage", { lang = l })
			bot.wait(1.2)
		end
	end

	local function storeTour()
		bot.setPurchaseMode("grant")
		local prods, passes = {}, {}
		for _, p in Config.Products do
			if p.id ~= 0 then
				table.insert(prods, p.key)
			end
		end
		for _, p in Config.Passes do
			table.insert(passes, p.key)
		end
		for i = 1, math.min(3, #prods) do
			bot.try("Purchase.product " .. prods[i], Purchase.product, prods[i])
			bot.wait(3)
		end
		bot.try("Purchase.pass " .. passes[1], Purchase.pass, passes[1])
		bot.wait(3)
		bot.setPurchaseMode("cancel")
		bot.try("Purchase.product (cancel)", Purchase.product, prods[#prods])
		bot.wait(2)
		bot.setPurchaseMode("grant")
	end

	return {
		dsStore = "PlanetCrackers_v1",
		dsKey = function(uid)
			return "u_" .. uid
		end,
		profile = function()
			return srv()
		end,
		clientState = function()
			return Net and Net.state
		end,
		currencyKeys = { "stardust", "crystals" },
		nonDecreasing = { "totalMined", "planetsBroken" },
		snapshot = function()
			local p = srv()
			return { stardust = p.stardust, crystals = p.crystals, totalMined = p.totalMined, petCount = p.petCount }
		end,
		ready = function()
			return Net and Net.state ~= nil and bot.char() ~= nil and PlanetField and PlanetField.zone ~= nil
		end,
		stats = function()
			local p = srv()
			local pets = 0
			for _ in p.pets do
				pets += 1
			end
			return { stardust = math.floor(p.stardust), crystals = p.crystals, mined = math.floor(p.totalMined), planetsBroken = p.planetsBroken, tool = p.tool, pets = pets, tutorial = p.tutorial, hits = p.hits, rebirths = p.rebirths, zones = #p.zones }
		end,
		stuck = {
			{
				name = "mining income (bot clicks planets)",
				secs = 45,
				active = function()
					return mining
				end,
				sig = function()
					return srv().hits
				end,
			},
			{
				name = "tutorial step",
				secs = 120,
				active = function()
					return srv().tutorial <= #Config.Tutorial
				end,
				sig = function()
					return srv().tutorial
				end,
			},
		},
		summary = function()
			return stats
		end,
		run = function(bot)
			Net = bot.client("Net")
			Miner = bot.client("Miner")
			PlanetField = bot.client("PlanetField")
			Windows = bot.client("UI.Windows")
			Purchase = bot.client("Purchase")
			bot.waitUntil(function()
				return Net.state and bot.char() and PlanetField.zone
			end, 40, "state + character + planet field")
			bot.log("session started, tutorial step " .. tostring(S().tutorial))
			local total = bot.minutes * 60
			local t0 = bot.now()
			local didTour, didSettings, didStore, didRejoin = false, false, false, false
			while bot.alive() do
				local el = bot.now() - t0
				followTutorial()
				local how = mineSome(15)
				mining = false
				if how == "full" or (S().cargo and S().cargo.count > 0 and bot.every("sell", 40)) then
					sell()
				end
				claimThings()
				spend()
				if bot.every("capsule", 20) then
					capsuleTrip()
				end
				-- a gate galaxy: when the next galaxy is unlocked, travel there
				local s = S()
				if (s.maxZone or 1) > zone() and bot.every("zonemove", 60) then
					local ok = req("Teleport", { zone = s.maxZone })
					if ok then
						stats.zonesMoved += 1
						bot.log("teleported to galaxy " .. s.maxZone)
						bot.wait(3)
					end
				end
				if not didTour and el > total * 0.2 then
					didTour = true
					windowTour()
				end
				if not didSettings and el > total * 0.33 then
					didSettings = true
					settingsTour()
				end
				if not didStore and el > total * 0.45 then
					didStore = true
					storeTour()
				end
				if not didRejoin and el > total * 0.6 then
					didRejoin = true
					bot.log("rejoin (save + reload)")
					local giftsBefore = #(S().giftsClaimed or {})
					bot.rejoin("mid")
					Net = bot.client("Net")
					Miner = bot.client("Miner")
					PlanetField = bot.client("PlanetField")
					Windows = bot.client("UI.Windows")
					Purchase = bot.client("Purchase")
					bot.waitUntil(function()
						return bot.char() ~= nil and PlanetField.zone
					end, 20, "character + planet field after rejoin")
					if giftsBefore > 0 and #(S().giftsClaimed or {}) == 0 then
						bot.bug("the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining the " .. giftsBefore .. " claimed gifts are claimable again (State.giftsClaimed is per session, never in the profile)", "gifts-reset", { "anime-planet-clicker/src/server/Services/State.luau:42", "anime-planet-clicker/src/server/Services/Rewards.luau:121" })
					end
				end
			end
		end,
	}
end
