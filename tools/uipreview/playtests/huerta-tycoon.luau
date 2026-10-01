-- Playtest bot: Crop Kingdom (huerta-tycoon). The farming loop of a new player: buy seeds, plant, wait for
-- the crops to grow, harvest, teleport to the sell stand (the game's own button code), sell, buy tiles and
-- upgrades, claim gifts/daily/index, open every panel, buy things, rejoin.
return function(bot)
	local Net, State, Teleport, Panels, Tutorial
	local Config = bot.shared("Shared.Config")
	local Formulas = bot.shared("Shared.Formulas")
	local stats = { seedsBought = 0, planted = 0, harvests = 0, sells = 0, tiles = 0, upgrades = 0, panels = 0, claimed = 0, rebirths = 0, tpSell = 0 }
	local farming = false

	local function sess()
		return bot.server("Services.Session").get(bot.player())
	end
	local function prof()
		local s = sess()
		return s and s.profile
	end
	local function d()
		return State and State.data or {}
	end
	local function req(action, payload, opts)
		bot.wait(0.2)
		return Net.request(action, payload, opts or { quiet = true, silentOk = true })
	end

	local function emptyAndRipe()
		local p = prof()
		local empty, ripe, growing = 0, 0, 0
		for i = 1, p.tilesOwned do
			local t = p.tiles[tostring(i)]
			if not t then
				empty += 1
			elseif t.progress >= 1 then
				ripe += 1
			else
				growing += 1
			end
		end
		return empty, ripe, growing
	end

	local function bestSeed()
		-- the priciest seed that we own or can afford soon (stock from the shop)
		local p = prof()
		local best
		for _, seed in Config.Seeds do
			if (p.seeds[seed.id] or 0) > 0 then
				best = seed
			end
		end
		return best
	end

	local function buySeeds()
		local p = prof()
		local s = sess()
		local empty = emptyAndRipe()
		-- cheapest ROI: the best seed we can afford 5 of that is in stock
		local choice
		for _, seed in Config.Seeds do
			local stock = (s.stock or {})[seed.id] or 0
			if stock > 0 and p.cash >= seed.price * 3 and seed.growTime <= 240 then
				choice = seed
			end
		end
		if choice and (p.seeds[choice.id] or 0) < empty + 2 then
			local amount = math.min(5, ((s.stock or {})[choice.id] or 1))
			local ok = req("BuySeed", { seedId = choice.id, amount = amount })
			if ok then
				stats.seedsBought += amount
			end
		end
	end

	local function plantAndHarvest()
		local empty, ripe = emptyAndRipe()
		if ripe > 0 then
			if req("HarvestAll") then
				stats.harvests += ripe
			end
		end
		empty = emptyAndRipe()
		if empty > 0 then
			local seed = bestSeed()
			if seed then
				local ok = req("PlantAll", { seedId = seed.id })
				if ok then
					stats.planted += empty
				end
			end
		end
	end

	local function sellTrip()
		local count = d().backpackCount or 0
		if count <= 0 then
			return
		end
		-- the HUD's "Teleport to sell" (client PivotTo next to the stand) then the sell button
		bot.try("Teleport.toSellStand", Teleport.toSellStand)
		stats.tpSell += 1
		bot.wait(1)
		local ok = req("SellAll")
		if ok then
			stats.sells += 1
		end
		bot.try("Teleport.toGarden", Teleport.toGarden)
		bot.wait(0.5)
	end

	local function invest()
		local p = prof()
		local s = d()
		if s.tileCost and p.cash >= s.tileCost * 1.2 then
			if req("BuyTile") then
				stats.tiles += 1
			end
		end
		for _, u in Config.Upgrades do
			local cost = (s.upgradeCosts or {})[u.id]
			if cost and p.cash >= cost * 1.5 then
				if req("BuyUpgrade", { id = u.id }) then
					stats.upgrades += 1
					bot.log("upgrade " .. u.id)
				end
				break
			end
		end
		if s.rebirthCost and p.cash >= s.rebirthCost and bot.every("rebirth", 60) then
			if req("Rebirth") then
				stats.rebirths += 1
				bot.log("rebirth!")
			end
		end
	end

	local function claimThings()
		local s = d()
		if bot.every("gift", 8) then
			for i, g in Config.PlaytimeGifts do
				local ready = false
				for _, r in s.gifts and s.gifts.ready or {} do
					if r == i then
						ready = true
					end
				end
				if ready then
					req("ClaimGift", { index = i })
					stats.claimed += 1
					break
				end
			end
		end
		if bot.every("daily", 600) and s.daily and s.daily.canClaim then
			req("ClaimDaily")
			stats.claimed += 1
		end
		if bot.every("index", 60) then
			for id, row in s.index or {} do
				if row.found >= row.total and not row.claimed then
					req("ClaimIndex", { seedId = id })
					stats.claimed += 1
				end
			end
		end
		if bot.every("code", 400) then
			bot.expectFail(function()
				req("RedeemCode", { code = "release" })
			end)
		end
	end

	local function panelTour()
		for _, name in { "Shop", "Upgrades", "Rebirth", "Store", "Odds", "Daily", "Codes", "Language", "Gifts", "Index", "Invite", "Starter", "Auto", "Trophies" } do
			if not bot.alive() then
				return
			end
			if bot.try("open " .. name, Panels.open, name) then
				stats.panels += 1
			end
			bot.wait(1.0)
			bot.try("close " .. name, Panels.close)
			bot.wait(0.3)
		end
	end

	local function settingsTour()
		for _, l in { "es", "ja", "de", "en" } do
			req("SetLanguage", { lang = l })
			bot.wait(1.5)
		end
		-- auto farm needs the Farmhand upgrade: a locked one must be refused
		bot.expectFail(function()
			req("SetAuto", { mode = "harvest", on = true })
		end)
		req("SetAutoSeed", { seedId = "carrot" })
	end

	local function storeTour()
		bot.setPurchaseMode("grant")
		bot.try("open Store", Panels.open, "Store")
		bot.wait(1)
		local clicked = 0
		for i = 1, 4 do
			local panel = bot.find("StorePanel")
			local buttons = panel and bot.buttonsMatching(panel, "R%$") or {}
			local c = if i == 1 then buttons[1] else buttons[#buttons - (4 - i)]
			if c then
				bot.click(c, "store buy")
				clicked += 1
				bot.wait(3)
				bot.setPurchaseMode(if clicked == 3 then "cancel" else "grant")
			end
		end
		bot.setPurchaseMode("grant")
		bot.try("close Store", Panels.close)
		bot.log("store: clicked " .. clicked .. " buy buttons")
	end

	return {
		dsStore = "CropKingdom_v1",
		dsKey = function(uid)
			return "u_" .. uid
		end,
		profile = function()
			return prof()
		end,
		clientState = function()
			return State and State.data
		end,
		currencyKeys = { "cash" },
		nonDecreasing = { "totalEarned" },
		snapshot = function()
			local p = prof()
			return { cash = p.cash, totalEarned = p.totalEarned, rebirths = p.rebirths, tilesOwned = p.tilesOwned }
		end,
		ready = function()
			return State and State.data and State.data.cash ~= nil and bot.char() ~= nil and State.data.plotIndex ~= nil and State.data.plotIndex > 0
		end,
		stats = function()
			local p = prof()
			local empty, ripe, growing = emptyAndRipe()
			return { cash = math.floor(p.cash), earned = math.floor(p.totalEarned), tiles = p.tilesOwned, empty = empty, growing = growing, ripe = ripe, rebirths = p.rebirths, tutorial = p.tutorialDone and 1 or 0 }
		end,
		stuck = {
			{
				name = "farm income (totalEarned)",
				secs = 150,
				active = function()
					return farming
				end,
				sig = function()
					return math.floor(prof().totalEarned)
				end,
			},
			{
				name = "first-session tutorial",
				secs = 150,
				active = function()
					return prof() and not prof().tutorialDone
				end,
				sig = function()
					local p = prof()
					return math.floor(p.cash) .. ":" .. p.totalEarned .. ":" .. tostring(next(p.tiles) ~= nil)
				end,
			},
		},
		summary = function()
			return stats
		end,
		run = function(bot)
			Net = bot.client("UI.Net")
			State = bot.client("UI.State")
			Teleport = bot.client("UI.Teleport")
			Panels = bot.client("UI.Panels")
			bot.waitUntil(function()
				return State.data and State.data.cash ~= nil and bot.char() and State.data.plotIndex and State.data.plotIndex > 0
			end, 40, "state + character + plot")
			bot.log("session started")
			local total = bot.minutes * 60
			local t0 = bot.now()
			local didTour, didSettings, didStore, didRejoin = false, false, false, false
			while bot.alive() do
				local el = bot.now() - t0
				farming = true
				buySeeds()
				plantAndHarvest()
				local count = d().backpackCount or 0
				local cap = d().backpackCap or 25
				if count >= cap * 0.5 or (count > 0 and bot.every("sell", 45)) then
					sellTrip()
				end
				invest()
				claimThings()
				bot.wait(2 + bot.rng:NextNumber())
				if not didTour and el > total * 0.2 then
					didTour = true
					farming = false
					panelTour()
				end
				if not didSettings and el > total * 0.33 then
					didSettings = true
					farming = false
					settingsTour()
				end
				if not didStore and el > total * 0.45 then
					didStore = true
					farming = false
					storeTour()
				end
				if not didRejoin and el > total * 0.6 then
					didRejoin = true
					farming = false
					bot.log("rejoin (save + reload)")
					bot.rejoin("mid")
					Net = bot.client("UI.Net")
					State = bot.client("UI.State")
					Teleport = bot.client("UI.Teleport")
					Panels = bot.client("UI.Panels")
					bot.waitUntil(function()
						return State.data and State.data.cash ~= nil and bot.char()
					end, 20, "state after rejoin")
				end
			end
		end,
	}
end
