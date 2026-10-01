-- Playtest bot: Ki Warriors. Follows the story like a new player: train (punch), charge, blast, fly,
-- walk to the camp and fight the enemies, buy gear, train in zones, transform. When a step does not
-- progress for a long time it presses "skip" like a stuck player would (and the run reports it).
return function(bot)
	local Net, Controls, Flight, Windows, Purchase, NpcRender
	local Config = bot.shared("Shared.Config")
	local Formulas = bot.shared("Shared.Formulas")
	local stats = { punches = 0, blasts = 0, beams = 0, kills = 0, deaths = 0, forms = 0, charges = 0, flights = 0, skipped = 0, windows = 0, tech = 0, relics = 0, stepsDone = 0, walks = 0 }
	local training = false
	local lastReps = 0

	local function Fighters()
		return bot.server("Services.Fighters")
	end
	local function srv()
		return bot.server("Services.Data").get(bot.player())
	end
	local function S()
		return Net and Net.state or {}
	end
	local function alive()
		local _, _, hum = bot.char()
		return hum ~= nil and hum.Health > 0
	end
	local function req(action, payload)
		bot.wait(0.15)
		return Net.request(action, payload)
	end
	local function planetCenter()
		local cx, cy, cz = Config.planetCenter(S().planet or 1)
		return Vector3.new(cx, cy, cz)
	end
	local function atOffset(o, planet)
		local cx, cy, cz = Config.planetCenter(planet or S().planet or 1)
		return Vector3.new(cx, cy, cz) + Vector3.new(o[1], 0, o[3])
	end

	local function punchFor(seconds)
		local t0 = bot.now()
		training = true
		while bot.alive() and bot.now() - t0 < seconds do
			-- a window (e.g. the "welcome back" offline-earnings popup opened by EventsHud) owns the input: a player closes it
			if Controls.enabled == false and Windows then
				Windows.close()
			end
			if alive() then
				Controls.punch()
				stats.punches += 1
			end
			bot.wait(0.14 + bot.rng:NextNumber() * 0.05)
		end
		training = false
	end

	local function nearestNpc(npcId)
		local me = bot.pos()
		if not me then
			return nil
		end
		local best, bd
		for _, f in Fighters().list do
			if f.kind == "npc" and f.alive and (npcId == nil or (f.def and f.def.id == npcId)) then
				local pos = Fighters().position(f)
				if pos then
					local d = (pos - me).Magnitude
					if not bd or d < bd then
						best, bd = f, d
					end
				end
			end
		end
		return best, bd
	end

	local function goto2(pos, timeout)
		stats.walks += 1
		return bot.walkTo(Vector3.new(pos.X, 3, pos.Z), timeout or 40)
	end

	-- fight `npcId` (nil = any) until `count` of them died (by the server's own kill counter) or timeout
	local function fight(npcId, count, timeout)
		local t0 = bot.now()
		local k0 = srv().kills
		while bot.alive() and bot.now() - t0 < timeout and srv().kills - k0 < count do
			if not alive() then
				stats.deaths += 1
				bot.wait(6)
			else
				local f = nearestNpc(npcId)
				if not f then
					bot.wait(1)
				else
					local pos = Fighters().position(f)
					local me = bot.pos()
					if (pos - me).Magnitude > 6 then
						-- walk next to it
						local dir = (me - pos)
						dir = Vector3.new(dir.X, 0, dir.Z)
						dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
						bot.walkTo(Vector3.new(pos.X, 3, pos.Z) + dir * 4, 3)
					else
						Controls.punch()
						stats.punches += 1
						if Controls.ki() > 0.5 and bot.rng:NextNumber() < 0.15 then
							Controls.blast()
							stats.blasts += 1
						end
						bot.wait(0.15)
					end
				end
			end
		end
		local d = srv() -- nil when the run ended (the player left) while fighting
		local got = if d then d.kills - k0 else 0
		stats.kills += got
		return got
	end

	-- a player who learned (story step "train in a zone") keeps training in the best zone they can enter
	local function trainBest(seconds)
		local p = srv()
		local power = math.max(Formulas.power(p.stats), p.bestPower or 0)
		local pl = Config.Planets[S().planet or 1]
		local best
		for _, z in pl.zones do
			if power >= z.reqPower and (not best or z.mult > best.mult) then
				best = z
			end
		end
		if best then
			local me = bot.pos()
			local c = atOffset(best.offset)
			if not me or (Vector3.new(me.X, 0, me.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude > best.radius - 6 then
				goto2(c, 90)
			end
		end
		training = true
		punchFor(seconds)
	end

	local function doStep(step, idx)
		local k = step.kind
		if k == "reps" or k == "power" then
			trainBest(8)
		elseif k == "charge" then
			Controls.charge(true)
			stats.charges += 1
			bot.wait(3)
			Controls.charge(false)
		elseif k == "blasts" then
			for _ = 1, 4 do
				Controls.blast()
				stats.blasts += 1
				bot.wait(0.5)
			end
		elseif k == "beam" then
			Controls.beamBegin()
			bot.wait(1.2)
			Controls.beamEnd()
			stats.beams += 1
			bot.wait(1.6)
		elseif k == "fly" then
			Controls.toggleFly()
			stats.flights += 1
			bot.wait(2)
			Controls.toggleFly()
		elseif k == "defeat" or k == "boss" then
			local camp
			local npcDef = Config.Npcs[step.npc]
			if npcDef and npcDef.planet ~= (S().planet or 1) then
				req("Travel", { planet = npcDef.planet })
				bot.wait(3)
			end
			local pl = Config.Planets[S().planet or 1]
			for _, c in pl.camps do
				if c.npc == step.npc then
					camp = c
				end
			end
			if k == "boss" then
				camp = pl.boss
			end
			if camp then
				goto2(atOffset(camp.offset, npcDef and npcDef.planet), 90)
			end
			fight(step.npc, step.target, 60)
		elseif k == "gear" then
			local nextTier = Config.Gear[(srv().gear or 1) + 1]
			if nextTier and (srv().sparks or 0) >= nextTier.cost then
				req("BuyGear")
			else
				-- earn sparks: fight whatever is closest
				fight(nil, 2, 40)
			end
		elseif k == "zone" then
			local z = Config.ZoneById[step.zone]
			if z then
				if z.planet ~= (S().planet or 1) then
					-- the zone lives on another planet (the "mid" fixture can be ahead of its story): travel there
					req("Travel", { planet = z.planet })
					bot.wait(3)
				end
				goto2(atOffset(z.offset, z.planet), 90)
				punchFor(10)
			end
		elseif k == "form" then
			if (S().forms or 0) >= 1 then
				Controls.transform(1)
				stats.forms += 1
				bot.wait(3)
				Controls.transform(0)
			else
				trainBest(10)
			end
		elseif k == "technique" then
			local t = Config.Techniques[1]
			local ok, why = req("BuyTechnique", { id = t.id })
			if ok then
				bot.wait(0.5)
				Controls.technique(t.id)
				stats.tech += 1
			else
				-- "not enough power" (the toast tells the player to train): train a bit and retry
				trainBest(10)
			end
		elseif k == "relic" then
			-- the seals the server lists (Net.state.relics.list): walk to the next one and pick it up
			local list = (S().relics and S().relics.list) or {}
			local target
			for _, r in list do
				if not r.found then
					target = r
					break
				end
			end
			if target then
				if target.planet ~= (S().planet or 1) then
					req("Travel", { planet = target.planet })
					bot.wait(3)
				end
				goto2(target.pos, 90)
				local ok = req("CollectRelic", { i = target.i })
				if ok then
					stats.relics += 1
				end
			else
				bot.wait(5) -- no seal available (cooldown): wait like a player would
			end
		elseif k == "travel" then
			req("Travel", { planet = step.planet })
			bot.wait(2)
		else
			trainBest(6)
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
		if bot.every("upgrades", 25) then
			for _, u in Config.Upgrades do
				if (srv().gems or 0) >= (u.cost or 1e18) and ((srv().upgrades or {})[u.id] or 0) < u.max then
					bot.expectFail(function()
						req("BuyUpgrade", { id = u.id })
					end)
					break
				end
			end
		end
		if bot.every("spin", 90) then
			bot.expectFail(function()
				req("SpinAura", {})
			end)
		end
	end

	local function windowTour()
		for _, name in { "warrior", "forms", "moves", "upgrades", "ascend", "travel", "quests", "rewards", "shop", "auras", "wish", "ranking", "invite", "settings", "wardrobe", "season" } do
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
		for _, key in { "autoTrain", "autoFight", "autoCharge" } do
			req("SetSetting", { key = key, value = true })
		end
		bot.wait(4)
		for _, key in { "autoTrain", "autoFight", "autoCharge" } do
			req("SetSetting", { key = key, value = false })
		end
		for _, st in { "ki", "defense", "agility", "jump", "strength" } do
			req("SetStat", { stat = st })
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
			if p.kind ~= "starter" then
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
		dsStore = "KiWarriors_Profiles_v1",
		dsKey = function(uid)
			return "u_" .. uid
		end,
		profile = function()
			return srv()
		end,
		clientState = function()
			return Net and Net.state
		end,
		currencyKeys = { "sparks", "gems", "spins", "wishes" },
		nonDecreasing = { "totalReps", "bestPower", "kills" },
		snapshot = function()
			local p = srv()
			return { sparks = p.sparks, gems = p.gems, spins = p.spins, totalReps = p.totalReps, kills = p.kills, bestPower = p.bestPower }
		end,
		ready = function()
			return Net and Net.state ~= nil and bot.char() ~= nil
		end,
		stats = function()
			local p = srv()
			local pw = bot.shared("Shared.Formulas").power
			local ok, power = pcall(pw, p.stats)
			return { power = ok and math.floor(power) or -1, story = p.story.step, progress = p.story.progress, sparks = math.floor(p.sparks), gems = p.gems, reps = p.totalReps, kills = p.kills, gear = p.gear, forms = p.forms, planet = p.planet }
		end,
		stuck = {
			{
				name = "story step progress",
				secs = 90,
				sig = function()
					local p = srv()
					return p.story.step .. ":" .. p.story.progress
				end,
				-- training keeps adding reps: a long grind is "slow", not frozen
				proxy = function()
					local pos = bot.pos()
					return srv().totalReps .. ":" .. (pos and (math.floor(pos.X / 25) .. "," .. math.floor(pos.Z / 25)) or "")
				end,
				detail = function()
					local p = srv()
					local step = Config.Story[p.story.step]
					if not step then
						return nil
					end
					local power = math.floor(Formulas.power(p.stats))
					local need
					if step.kind == "zone" then
						need = Config.ZoneById[step.zone].reqPower
					elseif step.kind == "technique" then
						need = Config.Techniques[1].reqPower
					elseif step.kind == "power" then
						need = step.target
					end
					return string.format("step %d (%s): power %d%s", p.story.step, step.kind, power, if need then " / needs " .. need else "")
				end,
			},
			{
				name = "training reps while punching",
				secs = 40,
				active = function()
					return training and alive()
				end,
				sig = function()
					return srv().totalReps
				end,
			},
		},
		summary = function()
			return stats
		end,
		run = function(bot)
			Net = bot.client("Net")
			Controls = bot.client("Controls")
			Windows = bot.client("UI.Windows")
			Purchase = bot.client("Purchase")
			bot.waitUntil(function()
				return Net.state and bot.char()
			end, 40, "state + character")
			bot.log("session started, story step " .. tostring(S().story and S().story.step))
			local total = bot.minutes * 60
			local t0 = bot.now()
			local lastStep, stepSince, stepProgress = 0, bot.now(), -1
			local didTour, didSettings, didStore, didRejoin = false, false, false, false
			while bot.alive() do
				local el = bot.now() - t0
				local story = srv().story
				local step = Config.Story[story.step]
				if story.step ~= lastStep then
					if lastStep > 0 then
						stats.stepsDone += 1
					end
					bot.log("story step " .. story.step .. (step and (" (" .. step.kind .. ")") or " (done)"))
					lastStep, stepSince, stepProgress = story.step, bot.now(), story.progress
				elseif story.progress ~= stepProgress then
					stepProgress, stepSince = story.progress, bot.now()
				end
				if not alive() then
					stats.deaths += 1
					bot.wait(5)
				elseif step then
					-- stuck for a long time on a step: a player presses the skip button
					if bot.now() - stepSince > 150 then
						bot.log("pressing SKIP on story step " .. story.step)
						local ok = req("SkipStep")
						stats.skipped += 1
						stepSince = bot.now()
					else
						doStep(step, story.step)
					end
				else
					training = true
					trainBest(5)
				end
				if bot.every("claim", 12) then
					claimThings()
				end
				if not didTour and el > total * 0.2 then
					didTour = true
					training = false
					windowTour()
				end
				if not didSettings and el > total * 0.33 then
					didSettings = true
					training = false
					settingsTour()
				end
				if not didStore and el > total * 0.45 then
					didStore = true
					training = false
					storeTour()
				end
				if not didRejoin and el > total * 0.6 then
					didRejoin = true
					training = false
					bot.log("rejoin (save + reload)")
					local giftsBefore = 0
					for _ in S().giftsClaimed or {} do
						giftsBefore += 1
					end
					bot.rejoin("mid")
					Net = bot.client("Net")
					Controls = bot.client("Controls")
					Windows = bot.client("UI.Windows")
					Purchase = bot.client("Purchase")
					bot.waitUntil(function()
						return bot.char() ~= nil
					end, 20, "character after rejoin")
					local giftsAfter = 0
					for _ in S().giftsClaimed or {} do
						giftsAfter += 1
					end
					if giftsBefore > 0 and giftsAfter == 0 then
						bot.bug("the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining the " .. giftsBefore .. " claimed gifts are claimable again (State.giftsClaimed is per session, never in the profile)", "gifts-reset", { "ki-warriors/src/server/Services/State.luau:34", "ki-warriors/src/server/Services/Rewards.luau:141" })
					end
				end
			end
		end,
	}
end
