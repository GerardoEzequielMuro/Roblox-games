-- Playtest bot: Spin Showdown. Plays full matches against the table bots through the real HUD
-- (MatchHud.press / pickTarget / result buttons), then visits the lobby systems.
return function(bot)
	local Net, MatchHud, Hud, Windows, Lang, TableViews, Director, Toasts
	local Config = bot.shared("Shared.Config")
	local stats = { maxGapS = 0, maxBotTurnGapS = 0, botTurnsSeen = 0, playAgainNoop = 0, playAgainOk = 0, matches = 0, wins = 0, ended = 0, aborted = 0, spins = 0, brakes = 0, cards = 0, targets = 0, eliminated = 0, leftMid = 0, afkTurns = 0, results = 0 }
	local modes = { "classic", "chaos", "teams", "classic", "chaos" }
	local lastResult, resultsSeen = nil, 0
	local lastEventT, lastEventType = nil, nil
	local endedAt = nil
	local botTurn = false

	local function S()
		return Net and Net.state or {}
	end
	local function srv()
		local Data = bot.server("Services.Data")
		return Data.get(bot.player())
	end
	local function myTable()
		return Net.get("table")
	end
	-- server truth: seated at a table whose match is not over (countdown or running)
	local function tableActive()
		local Tables = bot.server("Services.Tables")
		local tbl = Tables.seatOf(bot.player())
		return tbl ~= nil and (tbl.status == "countdown" or (tbl.runner ~= nil and not tbl.runner.done))
	end
	local function tableRunner()
		local Tables = bot.server("Services.Tables")
		local tbl = Tables.seatOf(bot.player())
		return tbl and tbl.runner, tbl
	end
	local function hookAll()
		bot.on("Result", function(r)
			lastResult = r
			resultsSeen += 1
			stats.results += 1
			if r.won then
				stats.wins += 1
			end
		end)
		bot.on("Match", function(_id, e)
			local now = bot.now()
			if lastEventT then
				local gap = now - lastEventT
				if gap > stats.maxGapS then
					stats.maxGapS = math.floor(gap * 10) / 10
					stats.maxGapAfter = tostring(lastEventType)
				end
				if botTurn and gap > stats.maxBotTurnGapS then
					stats.maxBotTurnGapS = math.floor(gap * 10) / 10
					stats.maxBotTurnGapAfter = tostring(lastEventType)
				end
			end
			if e.t == "decide" or e.t == "spin" then
				botTurn = type(e.spinner) == "string" and string.sub(e.spinner, 1, 1) ~= "u"
				if botTurn and e.t == "decide" then
					stats.botTurnsSeen += 1
				end
			end
			lastEventT, lastEventType = now, e.t
			if e.t == "ended" or e.t == "abort" then
				lastEventT = nil
			end
			if e.t == "ended" then
				endedAt = now
				stats.ended += 1
			elseif e.t == "abort" then
				stats.aborted += 1
			end
		end)
	end

	local function playCardMaybe()
		local hand = MatchHud.hand or {}
		if MatchHud.cardPlayed or #hand == 0 or bot.rng:NextNumber() > 0.7 then
			return
		end
		local card = hand[bot.rng:NextInteger(1, #hand)]
		local def = Config.CardById[card]
		if not def then
			return
		end
		local view = MatchHud.view
		local mine = view and view.players[MatchHud.myId]
		if card == "shield" and mine and mine.shields >= Config.MaxShields then
			return
		end
		if def.needsTarget then
			-- same two clicks a player makes: select the card, then a target
			local card_b = bot.find("Card_" .. card)
			if card_b and bot.click(card_b, "card " .. card) then
				bot.wait(0.4)
				for _, p in view.order do
					local pv = view.players[p]
					if pv.alive and pv.id ~= MatchHud.myId and (card ~= "magnet" or pv.cards > 0) then
						MatchHud.pickTarget(pv.id)
						stats.cards += 1
						return
					end
				end
			end
		else
			local b = bot.find("Card_" .. card)
			if b and bot.click(b, "card " .. card) then
				stats.cards += 1
			end
		end
	end

	local function pickTarget()
		local view = MatchHud.view
		if not view then
			return
		end
		local list = {}
		for _, id in view.order do
			local pv = view.players[id]
			if pv.alive and id ~= MatchHud.myId then
				local mine = view.players[MatchHud.myId]
				local teams = Config.ModeById[view.mode].teams
				if not (teams and mine and pv.team == mine.team) then
					table.insert(list, pv.id)
				end
			end
		end
		if #list > 0 then
			MatchHud.pickTarget(list[bot.rng:NextInteger(1, #list)])
			stats.targets += 1
		end
	end

	-- plays the match the bot is seated in, until the result screen. Returns "result" | "gone" | "timeout".
	local function playMatch(opts)
		opts = opts or {}
		local started = bot.now()
		local ownTurns, lastPhaseT = 0, bot.now()
		local lastAction = ""
		while bot.alive() do
			if MatchHud.resultVisible() then
				return "result"
			end
			if not myTable() and not MatchHud.isVisible() then
				return "gone"
			end
			if opts.leaveAfter and bot.now() - started > opts.leaveAfter and MatchHud.isVisible() then
				return "leave"
			end
			if bot.now() - started > 600 then
				return "timeout"
			end
			if MatchHud.myTurn and MatchHud.phase == "decide" then
				local key = "decide" .. tostring(MatchHud.view and MatchHud.view.turn)
				if key ~= lastAction then
					lastAction = key
					ownTurns += 1
					if opts.afkTurns and ownTurns <= opts.afkTurns then
						-- AFK: leave the clock run out; the server must play for us and keep going
						stats.afkTurns += 1
						bot.wait(Config.Timing.decide + 2)
					else
						bot.wait(0.8 + bot.rng:NextNumber() * 1.6)
						if MatchHud.myTurn and MatchHud.phase == "decide" then
							playCardMaybe()
							bot.wait(1.8) -- the card animation (a PASS card hands the turn over)
							if MatchHud.myTurn and MatchHud.phase == "decide" then
								pickTarget()
								bot.wait(0.4)
								MatchHud.press()
								stats.spins += 1
							end
						end
					end
				end
			elseif MatchHud.myTurn and MatchHud.phase == "spin" then
				local key = "spin" .. tostring(MatchHud.view and MatchHud.view.turn)
				if key ~= lastAction then
					lastAction = key
					bot.wait(0.9 + bot.rng:NextNumber() * 2.2)
					if MatchHud.phase == "spin" then
						MatchHud.press()
						stats.brakes += 1
					end
				end
			end
			bot.wait(0.2)
		end
		return "stopped"
	end

	local function leaveResult()
		-- result screen: "Play again" (or "Keep watching" if I was eliminated)
		local againText = Lang.t("match.play_again")
		local watchText = Lang.t("match.keep_watching")
		local b = bot.findButton(againText, nil, true) or bot.findButton(watchText, nil, true)
		if b then
			bot.click(b, "result button")
		else
			MatchHud.closeResult()
		end
	end

	local function startMatch(mode)
		local before = resultsSeen
		-- the PLAY button (a brand-new player goes straight to the guided first match)
		local ok, res
		if mode == nil and not S().tutorialDone then
			bot.click(Hud.buttons.Play, "PLAY")
			bot.wait(0.8)
		else
			mode = mode or "classic"
			ok, res = Net.request("QuickPlay", { mode = mode })
			if not ok then
				bot.finding("bot", "QuickPlay " .. mode .. " refused: " .. tostring(type(res) == "table" and res.key or res))
				return false
			end
		end
		return bot.waitUntil(function()
			return myTable() ~= nil
		end, 10, "seated at a table")
	end

	local function waitMatchStart()
		local ok = bot.waitUntil(function()
			return MatchHud.isVisible()
		end, 60, "match HUD visible after sitting down")
		if not ok then
			-- diagnostics for the report: what do the server and the client think?
			local r, tbl = tableRunner()
			local t = Net.get("table")
			bot.log(string.format(
				"DIAG no match HUD: client table=%s server status=%s countdownEnds-now=%s runner=%s phase=%s client view=%s view.playing=%s",
				t and t.id or "nil", tbl and tbl.status or "nil",
				tbl and string.format("%.1f", tbl.countdownEnds - workspace:GetServerTimeNow()) or "nil",
				r and "yes" or "no", r and tostring(r.m.phase) or "-",
				tostring(TableViews.byId[t and t.id or "t1"] ~= nil), tostring(TableViews.byId[t and t.id or "t1"] and TableViews.byId[t and t.id or "t1"].playing)))
		end
		return ok
	end

	local function lobbyTour()
		for _, w in { "Play", "Shop", "Season", "Locker", "Ranking", "Rewards", "Quests", "Invite", "Settings" } do
			if not bot.alive() then
				return
			end
			if bot.openWindow(w:lower()) then
				bot.wait(1.2)
			end
			bot.try("close window", function()
				Windows.close()
			end)
			bot.wait(0.3)
		end
	end

	local function lobbyActions()
		local s = S()
		local p = srv()
		-- gifts
		local done = {}
		for _, i in s.giftsClaimed or {} do
			done[i] = true
		end
		for i, g in Config.Gifts do
			if not done[i] and (s.sessionElapsed or 0) >= g.minutes * 60 + 2 then
				Net.request("ClaimGift", { index = i })
				break
			end
		end
		if bot.every("daily", 600) then
			local ok = Net.request("ClaimDaily")
			if ok then
				bot.log("claimed daily")
			end
		end
		-- quests
		local q = s.quests
		if q and q.list and bot.every("quests", 15) then
			for i, e in q.list do
				if not (q.claimed or {})[i] and ((q.progress or {})[i] or 0) >= e.target then
					Net.request("ClaimQuest", { index = i })
					bot.wait(0.6)
				end
			end
		end
		-- cosmetics: buy the cheapest affordable one and equip it
		if bot.every("buy", 40) then
			local best
			for _, c in Config.Cosmetics do
				if c.unlock.type == "coins" and not (s.owned and s.owned[c.id]) and (s.coins or 0) >= c.unlock.n then
					if not best or c.unlock.n < best.unlock.n then
						best = c
					end
				end
			end
			if best then
				local ok = Net.request("Buy", { id = best.id })
				if ok then
					bot.log("bought cosmetic " .. best.id)
					if best.kind ~= "emote" then
						Net.request("Equip", { id = best.id })
					end
				end
			end
		end
		if bot.every("settings", 90) then
			bot.openWindow("settings")
			bot.wait(0.5)
			Net.request("SetSetting", { key = "music", value = 0.3 })
			Net.request("SetSetting", { key = "shake", value = false })
			Net.request("SetSetting", { key = "shake", value = true })
			bot.try("close", function()
				Windows.close()
			end)
		end
	end

	local function storeTour()
		bot.setPurchaseMode("grant")
		local MenuWindows = bot.client("UI.MenuWindows")
		bot.try("buyProduct CoinsS", MenuWindows.buyProduct, "CoinsS")
		bot.wait(3)
		bot.try("buyProduct CoinsM", MenuWindows.buyProduct, "CoinsM")
		bot.wait(3)
		bot.try("buyPass DoubleCoins", MenuWindows.buyPass, "DoubleCoins")
		bot.wait(3)
		bot.setPurchaseMode("cancel")
		bot.try("buyProduct CoinsL (cancel)", MenuWindows.buyProduct, "CoinsL")
		bot.wait(2)
		bot.setPurchaseMode("grant")
	end

	return {
		dsStore = "SpinShowdown_v1",
		dsKey = function(uid)
			return "u_" .. uid
		end,
		profile = function()
			return srv()
		end,
		clientState = function()
			return Net and Net.state
		end,
		currencyKeys = { "coins", "xp", "trophies" },
		nonDecreasing = { "matches", "wins", "bestTrophies", "elims" },
		snapshot = function()
			local p = srv()
			return { coins = p.coins, xp = p.xp, level = p.level, trophies = p.trophies, matches = p.matches, wins = p.wins }
		end,
		ready = function()
			return Net and Net.state ~= nil and TableViews and TableViews.ready
		end,
		stats = function()
			local p = srv()
			return { coins = p.coins, level = p.level, xp = p.xp, trophies = p.trophies, matches = p.matches, wins = p.wins, streak = p.streak, elims = p.elims, tutorialDone = p.tutorialDone and 1 or 0 }
		end,
		stuck = {
			{
				name = "match progress (server events)",
				secs = 60,
				active = function()
					local r = tableRunner()
					return r ~= nil and not r.done
				end,
				sig = function()
					local r = tableRunner()
					return r and (r.events .. ":" .. tostring(r.m.phase) .. ":" .. tostring(r.m.turn)) or ""
				end,
			},
			{
				name = "client match view follows the server",
				secs = 60,
				active = function()
					local r = tableRunner()
					return r ~= nil and not r.done and MatchHud ~= nil and MatchHud.isVisible()
				end,
				sig = function()
					return (MatchHud.phase or "") .. ":" .. tostring(MatchHud.view and MatchHud.view.turn) .. ":" .. tostring(MatchHud.view and MatchHud.view.spinner)
				end,
			},
			{
				name = "table lobby (countdown must end)",
				secs = 60,
				active = function()
					local _, tbl = tableRunner()
					return tbl ~= nil and tbl.status ~= "playing"
				end,
				sig = function()
					local _, tbl = tableRunner()
					return tbl and (tbl.status .. ":" .. tostring(math.floor(tbl.countdownEnds))) or ""
				end,
			},
		},
		summary = function()
			return stats
		end,
		run = function(bot)
			Net = bot.client("Net")
			MatchHud = bot.client("UI.MatchHud")
			Hud = bot.client("UI.Hud")
			Windows = bot.client("UI.Windows")
			Lang = bot.client("Lang")
			TableViews = bot.client("Arena.TableViews")
			Director = bot.client("Arena.Director")
			Toasts = bot.client("UI.Toasts")
			hookAll()
			bot.waitUntil(function()
				return Net.state and TableViews.ready
			end, 40, "state + table views ready")
			bot.log("lobby ready")
			local total = bot.minutes * 60
			local t0 = bot.now()
			local n = 0
			local didStore, didRejoin, didTour = false, false, false
			local lobbyVisits = 0
			local inMatch = false
			while bot.alive() do
				if MatchHud.resultVisible() then
					-- result screen: "Play again" queues the next match by itself (or "Keep watching" when
					-- eliminated); every 3rd time go to the lobby instead. A player reads the screen for a second or two.
					local shownAt = bot.now()
					if endedAt then
						stats.resultAfterEnded = math.floor((shownAt - endedAt) * 10) / 10
					end
					bot.wait(1.5 + bot.rng:NextNumber() * 1.5)
					lobbyVisits += 1
					local wantLobby = lobbyVisits % 3 == 0
					local b = if wantLobby then bot.find("Lobby") else bot.find("Again")
					local final = b and b.Name == "Again" and b:GetAttribute("Final") == true
					local hadTable = myTable() ~= nil
					if endedAt and not stats.releasedAfterEnded then
						-- how long does the server keep me seated after the 'ended' event?
						task.spawn(function()
							local t1 = endedAt
							while bot.alive() and myTable() ~= nil and bot.now() - t1 < 30 do
								bot.wait(0.1)
							end
							stats.releasedAfterEnded = math.floor((bot.now() - t1) * 10) / 10
						end)
					end
					if not (b and bot.click(b, "result button")) then
						MatchHud.closeResult()
					elseif final and not wantLobby then
						-- "Play again" must put me in a new match (or at least at a table); check 12 s later
						local at = bot.now()
						bot.wait(12)
						if tableActive() or MatchHud.isVisible() then
							stats.playAgainOk += 1
						else
							stats.playAgainNoop += 1
							bot.bug(string.format("'Play again' pressed %.1f s after the result screen appeared (the server still had me at the table: %s) ends in the lobby without a new match: Main.client.luau:96 onPlayAgain only calls QuickPlay when Net.get('table') is nil, but the table is not released until MatchRunner finishes T.ending (%d s) after the 'ended' event", at - shownAt, tostring(hadTable), Config.Timing.ending), "playagain-noop", { "ruleta-pvp/src/client/Main.client.luau:96", "ruleta-pvp/src/server/Services/MatchRunner.luau:198", "ruleta-pvp/src/server/Services/Tables.luau:327" })
						end
					end
					bot.wait(1.5)
				elseif tableActive() then
					if not inMatch then
						n += 1
						inMatch = true
						bot.log("match " .. n .. " seated")
					end
					waitMatchStart()
					local opts = {}
					if n == 2 then
						opts.afkTurns = 2
					elseif n == 4 then
						opts.leaveAfter = 25
					end
					local how = playMatch(opts)
					if how == "leave" then
						inMatch = false
						stats.leftMid += 1
						bot.log("leaves mid match")
						MatchHud.onLeave()
						bot.wait(3)
					elseif how == "result" then
						local r = lastResult
						local final = bot.find("Again") and bot.find("Again"):GetAttribute("Final") == true
						if final then
							stats.matches += 1
							inMatch = false
						else
							stats.eliminated += 1
						end
						bot.log(string.format("match %d %s: place %s/%s %s coins +%s xp +%s trophies +%s", n, if final then "result" else "eliminated (keeps watching)", tostring(r and r.place), tostring(r and r.n), tostring(r and r.mode), tostring(r and r.coins), tostring(r and r.xp), tostring(r and r.trophies)))
					else
						inMatch = false
						bot.log("match " .. n .. " ended without a result screen: " .. how)
						if MatchHud.isVisible() and not MatchHud.resultVisible() then
							MatchHud.onLeave()
						end
					end
				else
					-- lobby
					if MatchHud.isVisible() then
						bot.wait(1)
					else
						lobbyActions()
						if not didTour then
							didTour = true
							lobbyTour()
						end
						local el = bot.now() - t0
						if not didStore and el > total * 0.4 then
							didStore = true
							storeTour()
						end
						if not didRejoin and el > total * 0.6 then
							didRejoin = true
							local giftsBefore = #(S().giftsClaimed or {})
							bot.rejoin("mid")
							Net = bot.client("Net")
							MatchHud = bot.client("UI.MatchHud")
							Hud = bot.client("UI.Hud")
							Windows = bot.client("UI.Windows")
							Lang = bot.client("Lang")
							TableViews = bot.client("Arena.TableViews")
							Director = bot.client("Arena.Director")
							Toasts = bot.client("UI.Toasts")
							hookAll()
							if giftsBefore > 0 and #(S().giftsClaimed or {}) == 0 then
								bot.bug("the session gifts (Config.Gifts, 'minutes since joining') are not saved: after rejoining the " .. giftsBefore .. " claimed gifts are claimable again (State.giftsClaimed is per session, never in the profile)", "gifts-reset", { "ruleta-pvp/src/server/Services/State.luau:32", "ruleta-pvp/src/server/Services/Rewards.luau:83" })
							end
						end
						local mode = if stats.matches == 0 and n == 0 then nil else modes[(n % #modes) + 1]
						if not startMatch(mode) then
							bot.wait(3)
						end
					end
				end
				bot.wait(0.5)
			end
		end,
	}
end
