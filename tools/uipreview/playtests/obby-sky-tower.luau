-- Playtest bot: Sky Tower Obby. Walks pad to pad at WalkSpeed like a legit climber (straight
-- lines, no obstacle avoidance: the simulator has no gravity or collisions, hazards only kill
-- through the emulated Touched), spends coins, opens every panel, buys things, rejoins.
return function(bot)
	local Net, Kit, Prompts
	local Config = bot.shared("Shared.Config")
	local Layout = bot.shared("Shared.Layout")
	local Powerups = bot.shared("Shared.Powerups")
	local stats = { padsReached = 0, deaths = 0, falls = 0, skipsOffered = 0, skipsUsed = 0, walks = 0, walkFails = 0, retries = 0, shopBuys = 0, panels = 0, towerBest = 0 }
	local climbing = false
	local function Towers()
		return bot.server("Towers")
	end
	local function Session()
		return bot.server("Session")
	end
	local function srv()
		return bot.server("Data").get(bot.player())
	end
	local function at()
		local p = srv()
		local s = Session().get(bot.player())
		return math.max(s.at, p.stage), p, s
	end
	local function req(action, payload)
		bot.wait(0.35)
		return Net.request(action, payload)
	end

	local function alive()
		local _, _, hum = bot.char()
		return hum ~= nil and hum.Health > 0
	end

	-- one pad: walk to it and wait for the server to count it
	local function climbOne()
		local cur, p, s = at()
		local g = cur + 1
		if g > Layout.TOTAL then
			return "top"
		end
		local pad = Towers().pad(g)
		if not pad then
			bot.wait(1)
			return "nopad"
		end
		local target = bot.topOf(pad) + Vector3.new(0, 3, 0)
		stats.walks += 1
		-- a legit player jumps: lift the path a little above the straight line
		local me = bot.pos()
		if not me then
			bot.wait(1)
			return "nochar"
		end
		local mid = (me + target) / 2 + Vector3.new(0, 5, 0)
		bot.walkTo(mid, 30)
		if not alive() then
			return "dead"
		end
		bot.walkTo(target, 30)
		if not alive() then
			return "dead"
		end
		-- the server re-checks a touch for a couple of seconds
		local ok = bot.waitUntil(function()
			local a = at()
			return a >= g
		end, 4, nil)
		if ok then
			stats.padsReached += 1
			return "reached"
		end
		-- nudge: step off and back onto the pad (Touched fires again)
		stats.retries += 1
		bot.walkTo(target + Vector3.new(6, 0, 0), 10)
		bot.walkTo(target, 10)
		bot.wait(1)
		return "retry"
	end

	local function panelTour()
		for _, name in { "menu", "shop", "store", "rewards", "settings", "travel", "starter", "win" } do
			if not bot.alive() then
				return
			end
			if bot.openWindow(name) then
				stats.panels += 1
			end
			bot.wait(1.2)
			bot.try("Kit.close", Kit.close)
			bot.wait(0.3)
		end
	end

	local function spendCoins()
		local _, p = at()
		-- power-ups first (shield makes the next hazards survivable), then a trail
		for _, id in { "shield", "magnet", "speed" } do
			local item = Powerups.get(id)
			local haveCharges = (p.charges[id] or 0)
			local full = (item.kind == "charge" and haveCharges >= (item.max or 1))
				or (item.kind == "timed" and Powerups.remaining(p.boosts, id, os.time()) + (item.seconds or 0) > Powerups.MAX_TIMED)
			if p.coins >= item.price + 20 and not full then
				local ok = req("BuyPower", { id = id })
				if ok then
					stats.shopBuys += 1
					bot.log("bought power " .. id)
					p = srv()
				end
			end
		end
		for _, t in Config.Trails do
			if not t.pass and not t.exclusive and not t.tower and not p.trails[t.id] and p.coins >= t.price then
				local ok = req("BuyTrail", { id = t.id })
				if ok then
					stats.shopBuys += 1
					bot.log("bought trail " .. t.id)
				end
				break
			end
		end
		for _, e in Config.Effects do
			if not e.exclusive and not e.tower and not p.effects[e.id] and p.coins >= e.price then
				local ok = req("BuyEffect", { id = e.id })
				if ok then
					stats.shopBuys += 1
				end
				break
			end
		end
	end

	local function claimThings()
		local s = Net.state
		if bot.every("daily", 3600) then
			req("ClaimDaily")
		end
		for i in Config.PlaytimeRewards do
			local claimed = false
			for _, c in s.playClaimed or {} do
				if c == i then
					claimed = true
				end
			end
			local pr = Config.PlaytimeRewards[i]
			if not claimed and Net.playSeconds() >= (pr.minutes or pr.seconds / 60) * 60 + 3 then
				req("ClaimPlaytime", { index = i })
				break
			end
		end
	end

	local function storeTour()
		bot.setPurchaseMode("grant")
		bot.openWindow("store")
		bot.wait(1)
		-- click the Robux buttons of the store panel like a player would
		local clicked = 0
		for i = 1, 4 do
			-- the panel rebuilds its cards after every purchase: look the buttons up again each time
			local buttons = bot.buttonsMatching(bot.client("UI.Kit").gui(), "R%$")
			local c = if i == 1 then buttons[1] else buttons[#buttons - (4 - i)]
			if c then
				bot.click(c, "store buy")
				clicked += 1
				bot.wait(3)
				bot.setPurchaseMode(if clicked == 3 then "cancel" else "grant")
			end
		end
		bot.setPurchaseMode("grant")
		bot.try("Kit.close", Kit.close)
		bot.log("store: clicked " .. clicked .. " buy buttons")
	end

	local function settingsTour()
		bot.openWindow("settings")
		bot.wait(0.5)
		for _, kv in { { "effects", false }, { "effects", true }, { "speedCoil", true }, { "speedCoil", false } } do
			req("SetSetting", { key = kv[1], value = kv[2] })
		end
		for _, l in { "es", "de", "en" } do
			req("SetLanguage", { lang = l })
			bot.wait(1.2)
		end
		bot.expectFail(function()
			req("SetSetting", { key = "bogus", value = true })
		end)
		bot.try("Kit.close", Kit.close)
	end

	return {
		dsStore = "SkyTowerObby_v1",
		dsKey = function(uid)
			return "u_" .. uid
		end,
		profile = function()
			return srv()
		end,
		clientState = function()
			return Net and Net.state
		end,
		currencyKeys = { "coins", "totalCoins", "freeSkips" },
		nonDecreasing = { "best", "totalCoins", "wins" },
		snapshot = function()
			local p = srv()
			return { coins = p.coins, totalCoins = p.totalCoins, freeSkips = p.freeSkips, stage = p.stage, best = p.best, wins = p.wins }
		end,
		ready = function()
			return Net and Net.state and Net.state.stage ~= nil and bot.char() ~= nil
		end,
		stats = function()
			local a, p = at()
			local pos = bot.pos()
			return { stage = p.stage, at = a, best = p.best, coins = p.coins, totalCoins = p.totalCoins, wins = p.wins, deaths = stats.deaths, y = pos and math.floor(pos.Y) or 0 }
		end,
		stuck = {
			{
				name = "climb progress (best stage)",
				secs = 90,
				active = function()
					return climbing
				end,
				sig = function()
					return srv().best
				end,
			},
		},
		summary = function()
			return stats
		end,
		run = function(bot)
			Net = bot.client("Net")
			Kit = bot.client("UI.Kit")
			bot.waitUntil(function()
				return Net.state and Net.state.stage ~= nil and bot.char()
			end, 40, "state + character")
			bot.on("OfferSkip", function(d)
				stats.skipsOffered += 1
				if (d.freeSkips or 0) > 0 then
					task.spawn(function()
						bot.wait(1.5)
						local ok = Net.request("UseFreeSkip")
						if ok then
							stats.skipsUsed += 1
						end
					end)
				end
			end)
			bot.on("Win", function(d)
				bot.log("WIN tower " .. tostring(d.tower) .. " runMs=" .. tostring(d.runMs))
			end)
			bot.log("session started at stage " .. tostring(srv().stage))
			local total = bot.minutes * 60
			local t0 = bot.now()
			local didTour, didStore, didSettings, didRejoin = false, false, false, false
			local lastDead = false
			local consecutiveFail = 0
			while bot.alive() do
				local el = bot.now() - t0
				if not alive() then
					if not lastDead then
						stats.deaths += 1
						lastDead = true
					end
					bot.wait(0.5)
				else
					lastDead = false
					climbing = true
					local r = climbOne()
					if r == "reached" then
						consecutiveFail = 0
					elseif r == "retry" then
						consecutiveFail += 1
					elseif r == "top" then
						climbing = false
						bot.log("top of the last tower")
						bot.wait(5)
					end
					-- summit of a tower: the portal to the next one (HUD button / walking into it)
					local cur2 = at()
					if cur2 > 0 and cur2 % Layout.STAGES == 0 and cur2 < Layout.TOTAL and srv().stage == cur2 and not srv().base then
						climbing = false
						bot.log("summit of tower " .. cur2 // Layout.STAGES .. ": entering the portal")
						bot.wait(2)
						local ok = req("EnterPortal")
						bot.wait(6)
						if ok then
							bot.log("in tower " .. (cur2 // Layout.STAGES + 1) .. " at stage " .. at())
						end
						climbing = true
					end
					if consecutiveFail >= 12 then
						bot.bug(string.format("the bot could not get pad %d counted after %d retries (standing next to it); position=%s pad=%s", at() + 1, consecutiveFail, tostring(bot.pos()), tostring(Towers().pad(at() + 1) and Towers().pad(at() + 1).Position)), "padstuck|" .. tostring(at()))
						consecutiveFail = 0
						bot.wait(3)
					end
					if bot.every("claim", 20) then
						climbing = false
						claimThings()
						spendCoins()
						climbing = true
					end
				end
				if not didTour and el > total * 0.18 then
					didTour = true
					climbing = false
					panelTour()
				end
				if not didSettings and el > total * 0.3 then
					didSettings = true
					climbing = false
					settingsTour()
				end
				if not didStore and el > total * 0.45 then
					didStore = true
					climbing = false
					storeTour()
				end
				if not didRejoin and el > total * 0.6 then
					didRejoin = true
					climbing = false
					bot.log("rejoin (save + reload)")
					local pcBefore = #(Net.state.playClaimed or {})
					bot.rejoin("midclimb")
					Net = bot.client("Net")
					Kit = bot.client("UI.Kit")
					bot.waitUntil(function()
						return bot.char() ~= nil
					end, 20, "character after rejoin")
					bot.log("back at stage " .. tostring(srv() and srv().stage))
					if pcBefore > 0 and #(Net.state.playClaimed or {}) == 0 then
						bot.bug("the play-time rewards (Config.PlaytimeRewards, 'minutes in this session') are not saved: after rejoining the " .. pcBefore .. " claimed rewards are claimable again (Session.playClaimed is per session, never in the profile)", "gifts-reset", { "obby-sky-tower/src/server/Session.luau:55", "obby-sky-tower/src/server/Rewards.luau:127" })
					end
				end
			end
		end,
	}
end
