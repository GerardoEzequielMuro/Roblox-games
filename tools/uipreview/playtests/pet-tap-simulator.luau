-- Playtest bot: Tap Pets Simulator. Plays like a new player: tap, hatch the first egg, spend gems,
-- buy zones, claim rewards, open every window, change language, buy things, rejoin.
return function(bot)
	local Net, Tapper, Windows, Purchase, Onboarding, HatchCinematic, Guide
	local Config = bot.shared("Shared.Config")
	local Formulas = bot.shared("Shared.Formulas")
	local req

	local function S()
		return Net.state or {}
	end
	local function srvProfile()
		local Data = bot.server("Services.Data")
		return Data.get(bot.player())
	end

	local function eggPos(id)
		local m = workspace:FindFirstChild("Egg_" .. id, true)
		if not m then
			return nil
		end
		local ped = m:FindFirstChild("Pedestal")
		return ped and ped.Position
	end

	local function goNearEgg(id)
		local pos = eggPos(id)
		if not pos then
			return false
		end
		local me = bot.pos()
		if me and (Vector3.new(me.X, 0, me.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 9 then
			return true
		end
		return bot.walkTo(Vector3.new(pos.X, 3, pos.Z - 7), 40)
	end

	local function ownsZone(i)
		for _, z in S().zones or {} do
			if z == i then
				return true
			end
		end
		return false
	end

	local function bestEgg()
		local s = S()
		local best
		for _, egg in Config.Eggs do
			if not egg.exclusive and ownsZone(egg.zone) and Formulas.eggUnlocked(egg.id, s.rebirths or 0) and (s.taps or 0) >= egg.price then
				if not best or egg.price > best.price then
					best = egg
				end
			end
		end
		return best
	end

	local function tapBurst(n)
		local vp = workspace.CurrentCamera.ViewportSize
		for _ = 1, n do
			Tapper.simulate(Vector2.new(vp.X * (0.35 + bot.rng:NextNumber() * 0.3), vp.Y * (0.35 + bot.rng:NextNumber() * 0.2)))
			bot.wait(0.12)
		end
	end

	local function closeWindow()
		bot.try("close window", function()
			Windows.close()
		end)
	end

	local counts = { hatches = 0, upgrades = 0, zones = 0, quests = 0, windows = 0, rebirths = 0, purchases = 0, langs = 0, taps = 0 }
	local lastHatch = -10

	local function tryHatch()
		local egg = bestEgg()
		if not egg then
			return
		end
		if bot.now() - lastHatch < Config.HatchCooldown + 0.3 then
			return
		end
		if HatchCinematic.isPlaying() then
			return
		end
		if goNearEgg(egg.id) then
			bot.wait(0.3)
			lastHatch = bot.now()
			local ok, res = req("Hatch", { egg = egg.id, count = 1 })
			if ok then
				counts.hatches += 1
				bot.try("HatchCinematic.play", function()
					HatchCinematic.play(egg.id, res, false)
				end)
			end
		end
	end

	local function trySpendGems()
		local s = S()
		for _, id in { "TapPower", "WalkSpeed", "Luck", "PetSlots", "AutoTap" } do
			local u = Config.UpgradeById[id]
			local level = (s.upgrades or {})[id] or 0
			if level < u.maxLevel then
				local cost = math.floor(u.baseCost * u.costGrowth ^ level)
				if (s.gems or 0) >= cost then
					local ok = req("Upgrade", { id = id })
					if ok then
						counts.upgrades += 1
					end
					return
				end
			end
		end
	end

	local function tryZone()
		local s = S()
		for i = 2, #Config.Zones do
			if not ownsZone(i) then
				if (s.taps or 0) >= Config.Zones[i].cost then
					local ok = req("BuyZone", { zone = i })
					if ok then
						counts.zones += 1
						bot.log("bought zone " .. i)
						req("Teleport", { zone = i })
						bot.wait(1)
					end
				end
				return
			end
		end
	end

	local function claimThings()
		local s = S()
		-- session gifts
		local done = {}
		for _, i in s.giftsClaimed or {} do
			done[i] = true
		end
		for i, g in Config.Gifts do
			if not done[i] and (s.sessionElapsed or 0) >= g.minutes * 60 + 2 then
				local ok = req("ClaimGift", { index = i })
				if ok then
					bot.log("claimed gift " .. i)
				end
				break
			end
		end
		-- daily
		local d = s.daily or {}
		if bot.every("daily", 30) and (s.serverTime or 0) - (d.last or 0) >= Config.DailyCooldown then
			local ok = req("ClaimDaily")
			if ok then
				bot.log("claimed daily")
			end
		end
		-- quests
		local q = s.quests
		if q and bot.every("quests", 10) then
			local allDone = #q.list > 0
			for i, e in q.list do
				if e.claimed then
				elseif e.progress >= e.target then
					if req("ClaimQuest", { i = i }) then
						counts.quests += 1
					end
				else
					allDone = false
				end
			end
			if allDone and not q.bonusClaimed then
				req("ClaimQuestBonus")
			end
		end
		-- index: the claim button only makes sense when every pet of the zone was discovered
		if bot.every("index", 20) then
			local Rewards = bot.server("Services.Rewards")
			for zi = 1, #Config.Zones do
				if (s.indexClaimed or {})[tostring(zi)] == nil then
					local complete = true
					for _, id in Rewards.zonePets(zi) do
						if not (s.discovered or {})[id] then
							complete = false
						end
					end
					if complete and req("ClaimIndex", { zone = zi }) then
						bot.log("claimed index " .. zi)
					end
				end
			end
		end
		if bot.every("offline", 60) then
			bot.expectFail(function()
				req("ClaimOffline")
			end)
		end
	end

	local function tourWindows()
		for _, name in { "pets", "upgrades", "rebirth", "teleport", "codes", "invite", "quests", "index", "store", "rewards", "egg" } do
			if not bot.alive() then
				return
			end
			if bot.openWindow(name) then
				counts.windows += 1
			end
			bot.wait(1.5)
			closeWindow()
			bot.wait(0.4)
		end
	end

	local function settingsTour()
		-- language buttons (real clicks), auto chips
		local Locale = bot.shared("Shared.Locale")
		bot.openWindow("codes")
		bot.wait(0.5)
		for _, l in Locale.Languages do
			if l.code ~= "en" and (l.code == "es" or l.code == "ja" or l.code == "de") then
				local b = bot.findButton(l.name)
				if b and bot.click(b, "language " .. l.code) then
					counts.langs += 1
					bot.wait(2.2)
				end
			end
		end
		local en = bot.findButton("English")
		if en then
			bot.click(en, "language en")
			bot.wait(2.2)
		end
		-- redeem a code through the real remote (and a wrong one)
		req("RedeemCode", { code = "RELEASE" })
		bot.expectFail(function()
			req("RedeemCode", { code = "NOPE" })
		end)
		closeWindow()
		for _, key in { "tap", "equip" } do
			bot.expectFail(function()
				req("SetAuto", { key = key, on = key == "equip" })
			end)
		end
	end

	local function equipping()
		local s = S()
		local pc = 0
		for _ in s.pets or {} do
			pc += 1
		end
		if pc > #(s.equipped or {}) and bot.every("equipbest", 25) then
			req("EquipBest")
		end
	end

	-- pets: craft 5 of a kind, lock/delete a spare, roll a trait, auto hatch, travel, the park
	local function petManagement()
		local s = S()
		local groups = {}
		for uid, pet in s.pets or {} do
			local key = pet.id .. ":" .. (pet.tier or 0)
			groups[key] = groups[key] or {}
			table.insert(groups[key], uid)
		end
		for key, list in groups do
			if #list >= Config.CraftCost then
				local ok = req("Craft", { uid = list[1] })
				if ok then
					bot.log("crafted a golden " .. key)
					break
				end
			end
		end
		s = S()
		local spare
		for uid, pet in s.pets or {} do
			if not table.find(s.equipped or {}, uid) and not pet.locked then
				spare = uid
				break
			end
		end
		if spare then
			req("Lock", { uid = spare, locked = true })
			bot.expectFail(function()
				req("Delete", { uids = { spare } }) -- locked: must be refused
			end)
			req("Lock", { uid = spare, locked = false })
			req("Delete", { uids = { spare } })
		end
		bot.wait(1)
		s = S()
		if (s.dice or 0) >= Config.TraitRollCost then
			for uid in s.pets or {} do
				req("RollTrait", { uid = uid })
				break
			end
		end
		local egg = bestEgg()
		if egg and goNearEgg(egg.id) then
			req("SetAutoHatch", { egg = egg.id })
			bot.wait(12)
			req("SetAutoHatch", {})
		end
		for z = #Config.Zones, 1, -1 do
			if ownsZone(z) then
				req("Teleport", { zone = z })
				bot.wait(1.5)
				req("Teleport", { zone = 1 })
				break
			end
		end
		bot.expectFail(function()
			req("GoPark")
		end)
		bot.wait(1)
	end

	local function storeTour()
		-- the real store buttons call Purchase.*: the mocked MarketplaceService delivers the receipt
		bot.setPurchaseMode("grant")
		bot.try("Purchase.product GemsSmall", Purchase.product, "GemsSmall")
		bot.wait(3)
		bot.try("Purchase.pass AutoTap", Purchase.pass, "AutoTap")
		bot.wait(3)
		bot.try("Purchase.product TapsSmall", Purchase.product, "TapsSmall")
		bot.wait(3)
		-- a player who cancels the prompt
		bot.setPurchaseMode("cancel")
		bot.try("Purchase.product GemsMedium (cancel)", Purchase.product, "GemsMedium")
		bot.wait(2)
		bot.setPurchaseMode("grant")
		counts.purchases += 3
	end

	return {
		dsStore = "TapPets_Profiles_v1",
		dsKey = function(uid)
			return "u_" .. uid
		end,
		profile = function()
			return srvProfile()
		end,
		clientState = function()
			return Net and Net.state
		end,
		currencyKeys = { "taps", "gems", "dice" },
		nonDecreasing = { "totalTaps", "totalHatched" },
		snapshot = function()
			local p = srvProfile()
			return { taps = p.taps, gems = p.gems, dice = p.dice, totalHatched = p.totalHatched, luckBoostLeft = p.luckBoostLeft, pets = p.petCount }
		end,
		ready = function()
			return Net and Net.state ~= nil
		end,
		stats = function()
			local p = srvProfile()
			local pets = 0
			for _ in p.pets do
				pets += 1
			end
			return {
				taps = math.floor(p.taps), gems = p.gems, totalTaps = math.floor(p.totalTaps), hatched = p.totalHatched,
				pets = pets, zones = #p.zones, rebirths = p.rebirths, upgrades = (function() local n = 0 for _, v in p.upgrades do n += v end return n end)(),
			}
		end,
		stuck = {
			{
				name = "tap income (bot taps all the time)",
				secs = 60,
				sig = function()
					return math.floor(srvProfile().totalTaps)
				end,
			},
			{
				name = "first-session tutorial step",
				secs = 90,
				active = function()
					return Onboarding and Net.state and Onboarding.evaluate(Net.state).id ~= "done"
				end,
				sig = function()
					local st = Onboarding.evaluate(Net.state)
					return st.id .. ":" .. (Net.state.totalHatched or 0) .. ":" .. math.floor((Net.state.taps or 0) / 50)
				end,
			},
		},
		summary = function()
			return counts
		end,
		run = function(bot)
			Net = bot.client("Net")
			Tapper = bot.client("Tapper")
			Windows = bot.client("UI.Windows")
			Purchase = bot.client("Purchase")
			Onboarding = bot.client("Onboarding")
			HatchCinematic = bot.client("UI.HatchCinematic")
			req = bot.pace(function(a, p)
				bot.wait(0.12)
				return Net.request(a, p)
			end)
			bot.waitUntil(function()
				return Net.state
			end, 30, "GetState")
			bot.log("session started")
			local total = bot.minutes * 60
			local didTour, didStore, didSettings, didRejoin, didPets = false, false, false, false, false
			local t0 = bot.now()
			while bot.alive() do
				local el = bot.now() - t0
				tapBurst(8)
				counts.taps += 8
				if bot.every("claim", 4) then
					claimThings()
				end
				if bot.every("trade", 1.5) then
					tryHatch()
					trySpendGems()
					tryZone()
					equipping()
				end
				if not didTour and el > total * 0.15 then
					didTour = true
					tourWindows()
				end
				if not didSettings and el > total * 0.30 then
					didSettings = true
					settingsTour()
				end
				if not didPets and el > total * 0.25 then
					didPets = true
					petManagement()
				end
				if not didStore and el > total * 0.40 then
					didStore = true
					storeTour()
				end
				if not didRejoin and el > total * 0.55 then
					didRejoin = true
					bot.log("rejoin (save + reload)")
					local giftsBefore = #(S().giftsClaimed or {})
					bot.rejoin("midgame")
					Net = bot.client("Net")
					Tapper = bot.client("Tapper")
					Windows = bot.client("UI.Windows")
					Purchase = bot.client("Purchase")
					Onboarding = bot.client("Onboarding")
					HatchCinematic = bot.client("UI.HatchCinematic")
					bot.log("back after rejoin")
					if giftsBefore > 0 and #(S().giftsClaimed or {}) == 0 then
						bot.bug("the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining all " .. giftsBefore .. " claimed gifts are claimable again, so gems/taps can be farmed by leaving and joining (State.giftsClaimed is per session, never in the profile)", "gifts-reset", { "pet-tap-simulator/src/server/Services/State.luau:39", "pet-tap-simulator/src/server/Services/Rewards.luau:130" })
					end
				end
				-- rebirth when it is the best thing to do
				local s = S()
				if s.taps and s.rebirthCost and s.taps >= s.rebirthCost and bot.every("rebirth", 30) then
					if req("Rebirth") then
						counts.rebirths += 1
						bot.log("rebirth!")
					end
				end
			end
		end,
	}
end
