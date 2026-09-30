--!nonstrict
-- Clocks on screen: live events (Power Hour, Spark Weekend), the world boss and the Arena
-- Rush, each as a small chip with a countdown. Also the arena feedback (K.O. banner, shield
-- label) and the offline / notification popups.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Theme)
local Root = require(script.Parent.Root)
local Toasts = require(script.Parent.Toasts)
local Windows = require(script.Parent.Windows)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Parent.Net)
local Lang = require(script.Parent.Parent.Lang)
local Fx = require(script.Parent.Parent.Fx)
local CombatFx = require(script.Parent.Parent.CombatFx)

local EventsHud = {}
local new = Theme.new
local touch = Root.isTouch
local player = Players.LocalPlayer

local live: any = nil
local boss: any = nil
local arena: any = nil
local liveAt, bossAt, arenaAt = 0, 0, 0
EventsHud.state = function()
	return { live = live, boss = boss, arena = arena }
end

local chips: { [string]: { frame: Frame, text: TextLabel, g: UIGradient } } = {}

local function chip(parent: Instance, name: string, order: number)
	local f = new("Frame", { Name = "Chip_" .. name, Size = UDim2.fromOffset(196, 28), BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Visible = false, Parent = parent }, { Theme.corner(14), Theme.stroke(2.5) })
	local g = new("UIGradient", { Rotation = 90, Parent = f })
	local t = Theme.text({ Text = "", Size = UDim2.new(1, -14, 1, -6), Position = UDim2.fromOffset(7, 3), MaxTextSize = 14, Parent = f })
	chips[name] = { frame = f, text = t, g = g }
end

local function set(name: string, text: string?, color: Color3?)
	local c = chips[name]
	if not text then
		c.frame.Visible = false
		return
	end
	c.frame.Visible = true
	c.text.Text = text
	local col = color or Theme.Blue
	c.g.Color = ColorSequence.new(Theme.lighten(col, 0.15), Theme.darken(col, 0.35))
end

local function serverNow(at: number, payload): number
	return (payload.serverTime or os.time()) + (os.clock() - at)
end

local function tick()
	-- live events
	if live then
		local t = serverNow(liveAt, live)
		local cur = live.current
		if cur and cur.endsAt > t then
			local def = Config.LiveEventDefs[cur.id]
			set("live", (def and def.icon or "") .. " " .. Lang.t("event." .. cur.id) .. "  " .. Format.time(cur.endsAt - t), def and Theme.rgb(def.color) or Theme.Orange)
		elseif live.nextAt and live.nextAt > t then
			set("live", "⏳ " .. Lang.t("event." .. live.nextId) .. "  " .. Format.time(live.nextAt - t), Theme.Grey)
		else
			set("live", nil)
		end
	end
	-- world boss
	if boss then
		local t = serverNow(bossAt, boss)
		if boss.active and boss.endsAt > t then
			set("boss", "👹 " .. Lang.t("npc." .. (boss.npc or Config.WorldBoss.npc)) .. "  " .. Format.time(boss.endsAt - t), Theme.Red)
		elseif boss.nextAt and boss.nextAt > t then
			set("boss", "👹 " .. Lang.t("events.boss_in", { time = Format.time(boss.nextAt - t) }), Theme.Grey)
		else
			set("boss", nil)
		end
	end
	-- arena rush
	if arena then
		local t = serverNow(arenaAt, arena)
		if arena.rush and arena.at > t then
			local mine = 0
			for _, e in arena.top do
				if e.id == player.UserId then
					mine = e.score
				end
			end
			set("rush", "⚔️ " .. Lang.t("events.rush", { time = Format.time(arena.at - t), n = mine }), Theme.Red)
		elseif arena.at > t then
			set("rush", "⚔️ " .. Lang.t("events.rush_in", { time = Format.time(arena.at - t) }), Theme.Grey)
		else
			set("rush", nil)
		end
	end
	-- arena shield label
	local char = player.Character
	local s = Net.state
	local inArena = char and char:GetAttribute("InArena") == true
	if inArena and s and s.arena then
		set("pvp", if s.arena.protected then "🛡️ " .. Lang.t("events.protected") else "⚔️ " .. Lang.t("events.pvp_on"), if s.arena.protected then Theme.Green else Theme.Red)
	else
		set("pvp", nil)
	end
end

local function buildOffline()
	local ui: { [string]: any } = {}
	local w = Kit.window("Offline", "🌙", "menu.Offline", Theme.Purple, Vector2.new(480, 300), function(body)
		local s = Net.state
		local off = s and s.offline
		if not ui.built then
			ui.built = true
			ui.text = Kit.text(body, { Text = "", Size = UDim2.new(1, -20, 0, 60), Position = UDim2.fromOffset(10, 6), MaxTextSize = 20, TextWrapped = true })
			ui.amount = Kit.text(body, { Text = "", Font = Theme.Display, Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 72), MaxTextSize = 52, TextColor3 = Theme.Yellow })
			local b = Theme.button({ Key = "ui.claim", Color = Theme.Green, Size = UDim2.fromOffset(220, 54), Position = UDim2.new(0.5, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 1), TextSize = 26, ZIndex = 23, Parent = body, OnClick = function()
				Kit.request("ClaimOffline")
				Windows.close()
			end })
			for _, d in b:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 24
				end
			end
		end
		local total, stat = 0, "strength"
		if off and off.pending then
			for k, v in off.pending do
				total += v
				stat = k
			end
		end
		ui.text.Text = Lang.t("offline.text", { time = Format.time(off and off.seconds or 0), stat = Lang.t("stat." .. stat) })
		ui.amount.Text = "+" .. Format.abbrev(total) .. " " .. Config.StatInfo[stat].icon
	end)
	local _ = w
end

function EventsHud.init()
	local dock = new("Frame", {
		Name = "Events",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(196, 130),
		Position = if touch then UDim2.new(1, -8, 0, 6) else UDim2.new(1, -10, 0.28, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = Root.gui,
	}, { Theme.list(Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Right) })
	Root.mount(dock)
	chip(dock, "pvp", 1)
	chip(dock, "rush", 2)
	chip(dock, "boss", 3)
	chip(dock, "live", 4)

	Net.event("LiveEventUpdate").OnClientEvent:Connect(function(d)
		live, liveAt = d, os.clock()
		if type(d.started) == "table" then
			for _, id in d.started do
				local def = Config.LiveEventDefs[id]
				Toasts.banner((def and def.icon or "") .. " " .. Lang.t("toast.event_start", { event = Lang.t("event." .. id) }), def and Theme.rgb(def.color) or Theme.Orange)
			end
		end
		tick()
	end)
	Net.event("WorldBoss").OnClientEvent:Connect(function(d)
		boss, bossAt = d, os.clock()
		tick()
	end)
	Net.event("Arena").OnClientEvent:Connect(function(d)
		arena, arenaAt = d, os.clock()
		tick()
	end)
	-- the state snapshot carries the same data for clients that joined before the event
	Net.Changed:Connect(function(kind)
		if kind == "full" then
			local s = Net.state
			if s and s.worldBoss and not boss then
				boss, bossAt = s.worldBoss, os.clock()
			end
		end
	end)
	Net.event("Combat").OnClientEvent:Connect(function(kind, a)
		if kind == "arenaKill" then
			Toasts.banner("K.O.!  " .. Lang.t("toast.arena_kill", { player = a.name, rating = a.rating }), Theme.Red)
			Fx.kick(10)
		end
	end)
	CombatFx.on("ko", function(d)
		if d.p then
			Fx.burst(d.p, 3, 18, Color3.fromRGB(255, 80, 80), 0.5, 0.3)
			Fx.ring(d.p - Vector3.new(0, 2, 0), 3, 30, Color3.new(1, 1, 1), 0.6, 0.8)
		end
	end)
	CombatFx.on("worldBoss", function(d)
		local c = Color3.fromRGB(120, 255, 230)
		local pillar = Fx.get("cyl")
		pillar.Color = c
		pillar.Transparency = 0.3
		pillar.Size = Vector3.new(400, 14, 14)
		pillar.CFrame = CFrame.new(d.p + Vector3.new(0, 200, 0)) * CFrame.Angles(0, 0, math.rad(90))
		Fx.tween(pillar, 2, { Size = Vector3.new(400, 70, 70), Transparency = 1 })
		task.delay(2, Fx.release, pillar)
		Fx.ring(d.p + Vector3.new(0, 0.6, 0), 6, 90, c, 1.2, 1.2)
	end)
	CombatFx.on("rebirth", function(d)
		local plr = Players:GetPlayerByUserId(d.u)
		local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local c = Color3.fromRGB(190, 120, 255)
			Fx.burst(root.Position, 4, 40, c, 0.9, 0.3)
			Fx.ring(root.Position - Vector3.new(0, 2.6, 0), 4, 60, Color3.new(1, 1, 1), 1, 1)
			Fx.sparks(root.Position, c, 24, 90, 1)
		end
	end)

	-- popups
	buildOffline()
	local offlineShown = false
	Net.Changed:Connect(function(kind)
		local s = Net.state
		if kind == "full" and s and not offlineShown and s.offline and s.offline.pending then
			offlineShown = true
			task.delay(2, function()
				Windows.open("Offline")
			end)
		end
	end)
	Net.event("AskNotifications").OnClientEvent:Connect(function()
		pcall(function()
			local service = game:GetService("ExperienceNotificationService")
			if service:CanPromptOptInAsync() then
				service:PromptOptIn()
			end
		end)
	end)

	task.spawn(function()
		while true do
			tick()
			task.wait(1)
		end
	end)
end

return EventsHud
