--!strict
-- The client's picture of every table: who sits where (lobby list from the server), the
-- state of its match (kept in step with the match events), and the things drawn on the
-- stage: the wheel, the podium desks with names and lives, the four screens, the
-- spotlights and the shield bubbles. One RenderStepped loop spins every wheel.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Wheel = require(script.Parent.Wheel)
local Lang = require(script.Parent.Parent.Lang)
local Net = require(script.Parent.Parent.Net)
local Prefs = require(script.Parent.Parent.Prefs)
local Audio = require(script.Parent.Parent.Audio)

local TableViews = {}

export type PlayerView = {
	id: string,
	name: string,
	bot: boolean,
	team: number,
	seat: number,
	userId: number,
	color: Color3,
	lives: number,
	shields: number,
	cards: number,
	alive: boolean,
	place: number,
}
export type Desk = { gui: SurfaceGui, name: TextLabel, hearts: TextLabel, extra: TextLabel, out: TextLabel, stroke: UIStroke, bar: Frame }
export type View = {
	id: string,
	index: number,
	origin: CFrame,
	theme: string,
	kind: string,
	mode: string,
	status: string,
	countdownEnds: number,
	private: boolean,
	host: string?,
	fill: boolean,
	duel: boolean,
	max: number,
	lobbySeats: { [number]: any }, -- seat -> { id, name, bot, userId, color }
	wheel: Wheel.Wheel,
	desks: { [number]: Desk },
	tops: { [number]: BasePart },
	podiums: { [number]: BasePart },
	podiumLook: { [number]: string },
	podiumBase: { color: Color3, material: Enum.Material },
	lifeTags: { [number]: TextLabel },
	beams: { [number]: Beam },
	bubbles: { [number]: Part },
	screens: { TextLabel },
	screenIcons: { TextLabel },
	glows: { BasePart },
	glowColors: { Color3 },
	-- match state
	playing: boolean,
	players: { [string]: PlayerView },
	order: { string },
	maxLives: number,
	round: number,
	modifier: string?,
	sudden: boolean,
	dmgBonus: number,
	spinner: string?,
	target: string?,
	slots: { string },
	hidden: boolean,
	skin: string,
	spin: { mode: string, t0: number, r0: number, speed: number, tb: number, phase: number, travel: number, duration: number, n: number },
	screenText: string,
}

TableViews.list = {} :: { View }
TableViews.byId = {} :: { [string]: View }
local changed = Instance.new("BindableEvent")
TableViews.Changed = changed.Event -- (tableId)
local ticked = Instance.new("BindableEvent")
TableViews.Ticked = ticked.Event -- (tableId, slot, speedSlotsPerSecond)
TableViews.ready = false
TableViews.ticks = 0

local folder: Folder

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function TableViews.seatCFrame(view: View, seat: number): CFrame
	return Layout.seatCFrame(view.origin, seat, Config.Seats)
end

function TableViews.seatOf(view: View, id: string): number?
	local p = view.players[id]
	if p then
		return p.seat
	end
	for seat, s in view.lobbySeats do
		if s.id == id then
			return seat
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Desks, screens, spotlights
---------------------------------------------------------------------------
local function buildDesk(part: BasePart): Desk
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DeskGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 16, 42)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = Color3.fromRGB(60, 66, 140)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bg
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, 0, 0.1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(60, 66, 140)
	bar.BorderSizePixel = 0
	bar.Parent = bg
	local function label(name: string, size: UDim2, pos: UDim2, font: Enum.Font): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Size = size
		t.Position = pos
		t.Font = font
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Text = ""
		t.Parent = bg
		return t
	end
	local name = label("Name", UDim2.fromScale(0.92, 0.3), UDim2.fromScale(0.04, 0.13), Enum.Font.FredokaOne)
	local hearts = label("Hearts", UDim2.fromScale(0.92, 0.34), UDim2.fromScale(0.04, 0.43), Enum.Font.FredokaOne)
	local extra = label("Extra", UDim2.fromScale(0.92, 0.2), UDim2.fromScale(0.04, 0.78), Enum.Font.FredokaOne)
	extra.TextColor3 = Color3.fromRGB(176, 182, 220)
	local out = label("Out", UDim2.fromScale(0.9, 0.62), UDim2.fromScale(0.05, 0.3), Enum.Font.LuckiestGuy)
	out.TextColor3 = Color3.fromRGB(255, 84, 96)
	out.Visible = false
	gui.Parent = part
	return { gui = gui, name = name, hearts = hearts, extra = extra, out = out, stroke = stroke, bar = bar }
end

local function heartsText(lives: number, maxLives: number): string
	local n = math.max(lives, 0)
	return string.rep("❤️", n) .. string.rep("🖤", math.max(0, math.min(maxLives, 6) - n))
end
TableViews.heartsText = heartsText

function TableViews.refreshDesk(view: View, seat: number)
	local desk = view.desks[seat]
	if not desk then
		return
	end
	local p: PlayerView? = nil
	for _, pl in view.players do
		if pl.seat == seat then
			p = pl
		end
	end
	local top = view.tops[seat]
	local life = view.lifeTags[seat]
	if life then
		local show = view.playing and p ~= nil and p.alive
		life.Visible = show
		if show and p then
			life.Text = heartsText(p.lives, p.lives) .. (if p.shields > 0 then " 🛡️" else "")
		end
	end
	if view.playing and p then
		local color = if Config.ModeById[view.mode].teams then rgb(Config.TeamColors[p.team] or Config.TeamColors[1]) else p.color
		desk.name.Text = (if p.bot then "🤖 " else "") .. p.name
		desk.bar.BackgroundColor3 = color
		desk.out.Visible = not p.alive
		desk.hearts.Visible = p.alive
		desk.extra.Visible = p.alive
		if p.alive then
			desk.hearts.Text = heartsText(p.lives, view.maxLives)
			desk.extra.Text = (if p.shields > 0 then string.rep("🛡️", p.shields) .. "  " else "") .. "🃏×" .. p.cards
			desk.name.TextTransparency = 0
		else
			desk.out.Text = "❌" .. (if p.place > 0 then " #" .. p.place else "")
			desk.name.TextTransparency = 0.5
		end
		local isSpinner = view.spinner == p.id
		local isTarget = view.target == p.id
		desk.stroke.Color = if isSpinner then Color3.fromRGB(255, 205, 60) elseif isTarget then Color3.fromRGB(255, 84, 96) else color:Lerp(Color3.new(0, 0, 0), 0.35)
		if top then
			top.Color = if not p.alive then Color3.fromRGB(46, 46, 66) elseif isTarget then Color3.fromRGB(255, 70, 80) elseif isSpinner then Color3.fromRGB(255, 215, 80) else color
		end
	else
		local s = view.lobbySeats[seat]
		desk.out.Visible = false
		desk.hearts.Visible = true
		desk.extra.Visible = false
		if s then
			local color = rgb(s.color)
			desk.name.Text = (if s.bot then "🤖 " else "") .. s.name
			desk.name.TextTransparency = 0
			desk.hearts.Text = "✅"
			desk.bar.BackgroundColor3 = color
			desk.stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
			if top then
				top.Color = color
			end
		else
			desk.name.Text = ""
			desk.hearts.Text = "＋"
			desk.bar.BackgroundColor3 = Color3.fromRGB(60, 66, 140)
			desk.stroke.Color = Color3.fromRGB(60, 66, 140)
			if top then
				top.Color = Color3.fromRGB(58, 62, 120)
			end
		end
	end
end

-- A player's table skin dresses their own podium (bots and empty seats: the stage default).
local function refreshPodium(view: View, seat: number)
	local part = view.podiums[seat]
	if not part then
		return
	end
	local skin = ""
	local s = view.lobbySeats[seat]
	if s and not s.bot and s.userId > 0 then
		local player = game:GetService("Players"):GetPlayerByUserId(s.userId)
		local id = player and player:GetAttribute("Cos_table")
		if type(id) == "string" and id ~= "t_default" and Config.CosmeticById[id] then
			skin = id
		end
	end
	if view.podiumLook[seat] == skin then
		return
	end
	view.podiumLook[seat] = skin
	if skin == "" then
		part.Color = view.podiumBase.color
		part.Material = view.podiumBase.material
	else
		local look = Config.CosmeticById[skin].look :: any
		part.Color = rgb(look.base)
		part.Material = (Enum.Material :: any)[look.material] or Enum.Material.SmoothPlastic
	end
end

function TableViews.refreshDesks(view: View)
	for seat = 1, Config.Seats do
		TableViews.refreshDesk(view, seat)
		refreshPodium(view, seat)
	end
end

-- Spotlights: nil = house lights (every taken seat softly lit).
function TableViews.spotlight(view: View, spinnerSeat: number?, targetSeat: number?)
	for seat, beam in view.beams do
		local taken = view.lobbySeats[seat] ~= nil
		if view.playing then
			taken = false
			for _, p in view.players do
				if p.seat == seat and p.alive then
					taken = true
				end
			end
		end
		if spinnerSeat == nil then
			beam.Enabled = taken
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 250, 225))
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 0.95) })
		elseif seat == spinnerSeat then
			beam.Enabled = true
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 235, 150))
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.75) })
		elseif seat == targetSeat then
			beam.Enabled = true
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 70, 80))
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.75) })
		else
			beam.Enabled = false
		end
	end
end

-- Recolours the stage's neon trim (sudden death turns the whole rig red). nil restores.
function TableViews.rigColor(view: View, color: Color3?)
	for i, part in view.glows do
		part.Color = color or view.glowColors[i]
	end
end

function TableViews.bubble(view: View, seat: number, shields: number)
	local existing = view.bubbles[seat]
	if shields <= 0 then
		if existing then
			existing.Transparency = 1
		end
		return
	end
	local b: Part = existing
	if not existing then
		b = Instance.new("Part")
		b.Name = "Shield" .. seat
		b.Shape = Enum.PartType.Ball
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.ForceField
		b.CFrame = TableViews.seatCFrame(view, seat)
		b.Parent = folder
		view.bubbles[seat] = b
	end
	b.Size = Vector3.one * (if shields >= 2 then 9 else 7.6)
	b.Color = if shields >= 2 then Color3.fromRGB(255, 215, 90) else Color3.fromRGB(70, 190, 255)
	b.Transparency = 0.2
end

local function refreshBubbles(view: View)
	for seat = 1, Config.Seats do
		local shields = 0
		if view.playing then
			for _, p in view.players do
				if p.seat == seat and p.alive then
					shields = p.shields
				end
			end
		end
		TableViews.bubble(view, seat, shields)
	end
end

function TableViews.screenLine(view: View): string
	local mode = Config.ModeById[view.mode]
	local title = mode.icon .. " " .. Lang.t("mode." .. view.mode .. ".name")
	local line
	if view.playing then
		if view.sudden then
			line = "💀 " .. Lang.t("match.sudden")
		elseif view.modifier then
			line = Config.ModifierById[view.modifier].icon .. " " .. Lang.t("mod." .. view.modifier .. ".name")
		else
			line = Lang.t("match.round", { n = view.round })
		end
	else
		local count = 0
		for _ in view.lobbySeats do
			count += 1
		end
		if view.status == "countdown" then
			local left = math.max(0, math.ceil(view.countdownEnds - serverNow()))
			line = Lang.t("table.starting", { n = left })
		elseif view.private then
			line = "🔒 " .. Lang.t("table.private_of", { name = view.host or "?" })
		elseif view.kind == "flex" then
			line = Lang.t("table.free")
		else
			line = Lang.t("table.waiting", { n = count, max = view.max })
		end
		-- what the winner gets, paid by the game (nobody puts anything in)
		line ..= "   🏆 +" .. Progression.matchRewards(view.mode, 1, mode.fillTo).coins .. " 🪙"
	end
	return title .. "\n" .. line
end

local function refreshScreen(view: View)
	local text = TableViews.screenLine(view)
	if text ~= view.screenText then
		view.screenText = text
		for _, label in view.screens do
			label.Text = text
		end
	end
end

function TableViews.screenIcon(view: View, icon: string?)
	for i, label in view.screenIcons do
		label.Visible = icon ~= nil
		label.Text = icon or ""
		view.screens[i].Visible = icon == nil
	end
end

---------------------------------------------------------------------------
-- Wheel look
---------------------------------------------------------------------------
-- The wheel wears the skin of whoever is spinning (bots and empty tables: the classic one).
function TableViews.skinOf(view: View, id: string?): string
	if id then
		local p = view.players[id]
		if p and not p.bot then
			local player = game:GetService("Players"):GetPlayerByUserId(p.userId)
			local skin = player and player:GetAttribute("Cos_wheel")
			if type(skin) == "string" and Config.CosmeticById[skin] then
				return skin
			end
		end
	end
	return "w_classic"
end

function TableViews.setWheel(view: View, slots: { string }, hidden: boolean, skin: string?)
	view.slots = table.clone(slots)
	view.hidden = hidden
	view.skin = skin or view.skin
	view.wheel:setSlots(slots, view.skin, Prefs.lite(), hidden)
end

function TableViews.wheelParts(): number
	local n = 0
	for _, view in TableViews.list do
		n += view.wheel.parts
	end
	return n
end

---------------------------------------------------------------------------
-- Match state
---------------------------------------------------------------------------
-- Loads a server snapshot (intro, every decide, spectators joining).
function TableViews.applySnapshot(view: View, snap: { [string]: any })
	view.playing = true
	view.mode = snap.mode
	view.maxLives = snap.maxLives
	view.round = snap.round
	view.modifier = snap.modifier
	view.sudden = snap.sudden
	view.dmgBonus = snap.dmgBonus
	view.spinner = snap.spinner
	view.target = snap.target
	local info = snap.info or {}
	local order = {}
	local seen: { [string]: boolean } = {}
	for _, p in snap.players do
		local extra = info[p.id] or {}
		local old = view.players[p.id]
		local seat = extra.seat or (old and old.seat) or p.seat
		view.players[p.id] = {
			id = p.id,
			name = p.name,
			bot = p.bot,
			team = p.team,
			seat = seat,
			userId = extra.userId or (old and old.userId) or 0,
			color = if extra.color then rgb(extra.color) else (if old then old.color else Color3.fromRGB(120, 200, 255)),
			lives = p.lives,
			shields = p.shields,
			cards = p.cards,
			alive = p.alive,
			place = p.place,
		}
		seen[p.id] = true
		table.insert(order, p.id)
	end
	for id in view.players do
		if not seen[id] then
			view.players[id] = nil
		end
	end
	table.sort(order, function(a, b)
		return view.players[a].seat < view.players[b].seat
	end)
	view.order = order
	local hidden = snap.modifier == "blackout"
	local same = #snap.wheel == #view.slots and hidden == view.hidden
	if same then
		for i, s in snap.wheel do
			same = same and view.slots[i] == s
		end
	end
	if not same then
		TableViews.setWheel(view, snap.wheel, hidden, nil)
	end
	TableViews.refreshDesks(view)
	refreshBubbles(view)
	refreshScreen(view)
	changed:Fire(view.id)
end

-- Keeps the numbers in step with a match event (the Director adds the show on top).
function TableViews.applyEvent(view: View, e: { [string]: any })
	local t = e.t
	local players = view.players
	if t == "intro" then
		view.players = {}
		TableViews.applySnapshot(view, e.snapshot)
		view.spinner = nil
	elseif t == "decide" then
		TableViews.applySnapshot(view, e.snapshot)
	elseif t == "turn" then
		view.spinner = e.spinner
		view.target = nil
	elseif t == "aim" then
		view.target = e.target
	elseif t == "spin" then
		view.target = e.target
		view.spin = { mode = "free", t0 = e.t0, r0 = e.r0, speed = e.speed, tb = 0, phase = 0, travel = 0, duration = 0, n = e.n }
		view.wheel:setHighlight(nil)
		view.wheel.angle = e.r0
		view.wheel:resetTicks()
	elseif t == "landed" then
		local sp = view.spin
		view.spin = { mode = "brake", t0 = sp.t0, r0 = sp.r0, speed = e.speed, tb = e.tb, phase = e.phase, travel = e.travel, duration = e.duration, n = e.n }
	elseif t == "cancel" then
		view.spin.mode = "idle"
	elseif t == "hit" then
		local p = players[e.target]
		if p then
			p.lives = e.lives
			p.shields = e.shields
		end
	elseif t == "heal" then
		local p = players[e.player]
		if p then
			p.lives = e.lives
		end
	elseif t == "shield" then
		local p = players[e.player]
		if p then
			p.shields = e.shields
		end
	elseif t == "card" or t == "draw" then
		local p = players[e.player]
		if p then
			p.cards = e.count
		end
	elseif t == "stolen" then
		if players[e.from] then
			players[e.from].cards = e.fromCount
		end
		if players[e.to] then
			players[e.to].cards = e.toCount
		end
	elseif t == "swap" then
		if players[e.a] then
			players[e.a].lives = e.aLives
		end
		if players[e.b] then
			players[e.b].lives = e.bLives
		end
	elseif t == "elim" then
		local p = players[e.player]
		if p then
			p.alive = false
			p.lives = 0
			p.shields = 0
			p.place = e.place
		end
	elseif t == "rescue" then
		local p = players[e.player]
		if p then
			p.alive = true
			p.lives = e.lives
			p.place = 0
		end
	elseif t == "sudden" then
		view.sudden = true
		view.modifier = nil
	elseif t == "escalate" then
		view.dmgBonus = e.bonus
	elseif t == "round" then
		view.round = e.round
		view.modifier = e.modifier
	elseif t == "ended" or t == "abort" then
		view.playing = false
		view.spinner = nil
		view.target = nil
		view.sudden = false
		view.modifier = nil
		view.spin.mode = "idle"
		view.players = {}
		view.order = {}
		TableViews.rigColor(view, nil)
		TableViews.spotlight(view, nil, nil)
		view.wheel:setHighlight(nil)
		TableViews.screenIcon(view, nil)
		TableViews.setWheel(view, Config.Wheels[Config.ModeById[view.mode].wheel], false, "w_classic")
	end
	TableViews.refreshDesks(view)
	refreshBubbles(view)
	refreshScreen(view)
	changed:Fire(view.id)
end

-- Wheel angle for the current moment of the spin.
function TableViews.spinAngle(view: View, now: number): (number, number)
	local sp = view.spin
	if sp.mode == "free" then
		return sp.r0 + sp.speed * (now - sp.t0), sp.speed
	elseif sp.mode == "brake" then
		local a = math.clamp((now - sp.tb) / math.max(sp.duration, 0.001), 0, 1)
		local p = Config.Wheel.easePower
		local angle = sp.phase + sp.travel * (1 - (1 - a) ^ p)
		local speed = if a >= 1 then 0 else sp.travel * p * (1 - a) ^ (p - 1) / math.max(sp.duration, 0.001)
		return angle, speed
	end
	return view.wheel.angle, 0
end

---------------------------------------------------------------------------
-- Lobby list
---------------------------------------------------------------------------
local function applyTables(list: { any })
	for _, t in list do
		local view = TableViews.byId[t.id]
		if view then
			local modeChanged = view.mode ~= t.mode
			view.mode = t.mode
			view.status = t.status
			view.countdownEnds = t.countdownEnds
			view.private = t.private
			view.host = t.host
			view.fill = t.fill
			view.duel = t.duel
			view.max = t.max
			local seats = {}
			for _, s in t.seats do
				seats[s.seat] = s
			end
			view.lobbySeats = seats
			if not view.playing then
				if modeChanged or #view.slots == 0 then
					TableViews.setWheel(view, Config.Wheels[Config.ModeById[view.mode].wheel], false, "w_classic")
				end
				TableViews.refreshDesks(view)
				TableViews.spotlight(view, nil, nil)
			end
			refreshScreen(view)
			changed:Fire(view.id)
		end
	end
end

local function build(stage: BasePart)
	local id = stage:GetAttribute("TableId") :: string
	local index = stage:GetAttribute("Index") :: number
	local def = Config.Tables[index]
	local tableFolder = stage.Parent :: Instance
	local origin = Layout.tableCFrame(index, #Config.Tables)
	local view: View = {
		id = id,
		index = index,
		origin = origin,
		theme = def.theme,
		kind = def.kind,
		mode = def.mode,
		status = "open",
		countdownEnds = 0,
		private = false,
		host = nil,
		fill = true,
		duel = false,
		max = Config.ModeById[def.mode].maxPlayers,
		lobbySeats = {},
		wheel = Wheel.new(origin, folder, "Wheel_" .. id),
		desks = {},
		tops = {},
		podiums = {},
		podiumLook = {},
		podiumBase = { color = Color3.new(), material = Enum.Material.SmoothPlastic },
		lifeTags = {},
		beams = {},
		bubbles = {},
		screens = {},
		screenIcons = {},
		glows = {},
		glowColors = {},
		playing = false,
		players = {},
		order = {},
		maxLives = 4,
		round = 1,
		modifier = nil,
		sudden = false,
		dmgBonus = 0,
		spinner = nil,
		target = nil,
		slots = {},
		hidden = false,
		skin = "w_classic",
		spin = { mode = "idle", t0 = 0, r0 = 0, speed = 0, tb = 0, phase = 0, travel = 0, duration = 0, n = 12 },
		screenText = "",
	}
	for _, d in tableFolder:GetChildren() do
		if d:IsA("BasePart") then
			local seat = d:GetAttribute("Seat")
			if CollectionService:HasTag(d, "PodiumDesk") and type(seat) == "number" then
				view.desks[seat] = buildDesk(d)
			elseif CollectionService:HasTag(d, "PodiumTop") and type(seat) == "number" then
				view.tops[seat] = d
				-- lives floating over the head of whoever stands here
				local bb = Instance.new("BillboardGui")
				bb.Name = "Lives"
				bb.Size = UDim2.fromScale(6, 1.1)
				bb.StudsOffset = Vector3.new(0, 8.4, 0)
				bb.LightInfluence = 0
				bb.MaxDistance = 140
				local hearts = Instance.new("TextLabel")
				hearts.BackgroundTransparency = 1
				hearts.Size = UDim2.fromScale(1, 1)
				hearts.Font = Enum.Font.FredokaOne
				hearts.TextScaled = true
				hearts.Visible = false
				hearts.Parent = bb
				bb.Parent = d
				view.lifeTags[seat] = hearts
			elseif d.Name:match("^Podium%d$") then
				view.podiums[tonumber(d.Name:sub(7)) :: number] = d
				view.podiumBase = { color = d.Color, material = d.Material }
			elseif CollectionService:HasTag(d, "TableScreen") then
				for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
					local gui = Instance.new("SurfaceGui")
					gui.Face = face
					gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
					gui.PixelsPerStud = 34
					gui.LightInfluence = 0
					gui.Brightness = 1.5
					local label = Instance.new("TextLabel")
					label.BackgroundTransparency = 1
					label.Size = UDim2.fromScale(0.92, 0.84)
					label.Position = UDim2.fromScale(0.04, 0.08)
					label.Font = Enum.Font.LuckiestGuy
					label.TextScaled = true
					label.TextColor3 = Color3.new(1, 1, 1)
					label.Parent = gui
					local icon = Instance.new("TextLabel")
					icon.BackgroundTransparency = 1
					icon.Size = UDim2.fromScale(0.9, 0.9)
					icon.Position = UDim2.fromScale(0.05, 0.05)
					icon.Font = Enum.Font.FredokaOne
					icon.TextScaled = true
					icon.Visible = false
					icon.Parent = gui
					gui.Parent = d
					table.insert(view.screens, label)
					table.insert(view.screenIcons, icon)
				end
			elseif d.Material == Enum.Material.Neon and (d.Name:find("TrussGlow") or d.Name:find("PillarGlow") or d.Name == "StageRim" or d.Name == "DrumBand") then
				table.insert(view.glows, d)
				table.insert(view.glowColors, d.Color)
			end
		end
	end
	-- spotlights: lamp -> podium
	for _, d in tableFolder:GetChildren() do
		if d:IsA("BasePart") and CollectionService:HasTag(d, "SeatLamp") then
			local seat = d:GetAttribute("Seat") :: number
			local top = view.tops[seat]
			if top then
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0, -1.4)
				a0.Parent = d
				local a1 = Instance.new("Attachment")
				a1.Parent = top
				local beam = Instance.new("Beam")
				beam.Attachment0 = a0
				beam.Attachment1 = a1
				beam.Width0 = 1
				beam.Width1 = 7
				beam.FaceCamera = true
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Segments = 1
				beam.Enabled = false
				beam.Parent = d
				view.beams[seat] = beam
			end
		end
	end
	TableViews.setWheel(view, Config.Wheels[Config.ModeById[def.mode].wheel], false, "w_classic")
	TableViews.refreshDesks(view)
	refreshScreen(view)
	table.insert(TableViews.list, view)
	TableViews.byId[id] = view
end

function TableViews.init()
	folder = Instance.new("Folder")
	folder.Name = "SpinTables"
	folder.Parent = Workspace
	local world = Workspace:WaitForChild("World", 60)
	if not world then
		return
	end
	-- wait for every stage to replicate
	local deadline = os.clock() + 30
	while #CollectionService:GetTagged("TableRoot") < #Config.Tables and os.clock() < deadline do
		task.wait(0.1)
	end
	task.wait(0.3)
	for _, stage in CollectionService:GetTagged("TableRoot") do
		if stage:IsA("BasePart") then
			build(stage)
		end
	end
	table.sort(TableViews.list, function(a, b)
		return a.index < b.index
	end)
	TableViews.ready = true

	Net.event("Tables").OnClientEvent:Connect(applyTables)
	task.spawn(function()
		local ok, list = Net.request("GetTables")
		if ok and type(list) == "table" then
			applyTables(list)
		end
	end)
	-- switching the lite profile rebuilds the wheels with the other part count
	local wasLite = Prefs.lite()
	Net.Changed:Connect(function()
		local lite = Prefs.lite()
		if lite ~= wasLite then
			wasLite = lite
			for _, view in TableViews.list do
				TableViews.setWheel(view, view.slots, view.hidden, nil)
			end
		end
	end)
	Lang.Changed:Connect(function()
		for _, view in TableViews.list do
			view.screenText = ""
			refreshScreen(view)
			TableViews.setWheel(view, view.slots, view.hidden, nil)
		end
	end)

	-- every wheel, one loop
	local slow = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = serverNow()
		for _, view in TableViews.list do
			local sp = view.spin
			if sp.mode ~= "idle" then
				local angle, speed = TableViews.spinAngle(view, now)
				view.wheel:setAngle(angle)
				local ticks = view.wheel:ticksSince()
				if ticks > 0 then
					TableViews.ticks += ticks
					view.wheel:kickFlapper(0.6)
					ticked:Fire(view.id, view.wheel:slotAtPointer(), speed)
				end
				if sp.mode == "brake" and now >= sp.tb + sp.duration then
					sp.mode = "idle"
					view.wheel:setAngle(sp.phase + sp.travel)
				end
			end
			view.wheel:stepFlapper(dt)
		end
		slow += dt
		if slow >= 0.5 then
			slow = 0
			for _, view in TableViews.list do
				if view.status == "countdown" then
					refreshScreen(view)
				end
			end
		end
	end)
	Audio.play("click", 0) -- warm the sound cache
end

return TableViews
