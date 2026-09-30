--!strict
-- Bodies at the tables: finds the model behind a seat (a player's character or a bot),
-- plays reactions and emotes on it by pivoting it locally, and dresses players with their
-- title tag and aura. One RenderStepped loop drives every animation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lang = require(script.Parent.Parent.Lang)
local Prefs = require(script.Parent.Parent.Prefs)

local Avatars = {}

export type SeatInfo = { id: string, bot: boolean, userId: number, name: string }

function Avatars.model(info: SeatInfo): Model?
	if info.bot then
		local world = Workspace:FindFirstChild("World")
		local bots = world and world:FindFirstChild("Bots")
		return if bots then bots:FindFirstChild(info.id) :: Model? else nil
	end
	local player = Players:GetPlayerByUserId(info.userId)
	return if player then player.Character else nil
end

function Avatars.headPosition(model: Model?, fallback: Vector3): Vector3
	if model then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head.Position
		end
	end
	return fallback
end

---------------------------------------------------------------------------
-- Animations: a function of normalised time returning an offset from the base CFrame
---------------------------------------------------------------------------
type Anim = { model: Model, base: CFrame, fn: (number) -> CFrame, t: number, dur: number, restore: boolean, world: boolean }
local anims: { Anim } = {}
Avatars.played = 0

local MOVES: { [string]: (number) -> CFrame } = {
	hop = function(a)
		return CFrame.new(0, math.sin(a * math.pi) * 1.6, 0)
	end,
	shake = function(a)
		return CFrame.new(math.sin(a * 44) * 0.28 * (1 - a), 0, 0)
	end,
	lean = function(a)
		local k = math.sin(a * math.pi)
		return CFrame.Angles(math.rad(14) * k, 0, 0) * CFrame.new(0, 0, 0.5 * k)
	end,
	spin = function(a)
		return CFrame.new(0, math.sin(a * math.pi) * 1.2, 0) * CFrame.Angles(0, a * math.pi * 2, 0)
	end,
	stomp = function(a)
		return CFrame.new(0, math.abs(math.sin(a * math.pi * 3)) * 0.7, 0)
	end,
	-- knocked back by a hit
	flinch = function(a)
		local k = if a < 0.18 then a / 0.18 else 1 - (a - 0.18) / 0.82
		return CFrame.new(math.sin(a * 50) * 0.15 * k, 0.3 * k, 1.5 * k) * CFrame.Angles(math.rad(-20) * k, 0, 0)
	end,
	cheer = function(a)
		return CFrame.new(0, math.abs(math.sin(a * math.pi * 3)) * 1.8, 0) * CFrame.Angles(0, a * math.pi * 4, 0)
	end,
	-- a nervous tremble while the wheel slows down
	tremble = function(a)
		return CFrame.new(math.sin(a * 90) * 0.07, 0, math.cos(a * 70) * 0.05)
	end,
}
Avatars.Moves = MOVES

local function stop(model: Model)
	for i = #anims, 1, -1 do
		if anims[i].model == model then
			table.remove(anims, i)
		end
	end
end

-- Plays a move on a model standing at `base`.
function Avatars.react(model: Model?, base: CFrame, move: string, duration: number?)
	local fn = MOVES[move]
	if not model or not model.Parent or not fn then
		return
	end
	stop(model)
	Avatars.played += 1
	table.insert(anims, { model = model, base = base, fn = fn, t = 0, dur = duration or 0.7, restore = true, world = false })
end

-- Drives a model through world space (finishers): fn(a) returns the world CFrame. The model
-- is left where the animation ends; the server moves it to the bench afterwards.
function Avatars.drive(model: Model?, duration: number, fn: (number) -> CFrame)
	if not model or not model.Parent then
		return
	end
	stop(model)
	Avatars.played += 1
	table.insert(anims, { model = model, base = CFrame.new(), fn = fn, t = 0, dur = duration, restore = false, world = true })
end

function Avatars.activeCount(): number
	return #anims
end

RunService.RenderStepped:Connect(function(dt)
	if #anims == 0 then
		return
	end
	for i = #anims, 1, -1 do
		local an = anims[i]
		an.t += dt
		local a = math.clamp(an.t / an.dur, 0, 1)
		if not an.model.Parent then
			table.remove(anims, i)
		else
			if an.world then
				an.model:PivotTo(an.fn(a))
			else
				an.model:PivotTo(an.base * an.fn(a))
			end
			if a >= 1 then
				if an.restore then
					an.model:PivotTo(an.base)
				end
				table.remove(anims, i)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Emote bubble
---------------------------------------------------------------------------
function Avatars.bubble(model: Model?, icon: string)
	if not model then
		return
	end
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("EmoteBubble")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "EmoteBubble"
	bb.Size = UDim2.fromScale(3.4, 3.4)
	bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(10, 10, 28)
	stroke.Parent = bg
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(0.76, 0.76)
	t.Position = UDim2.fromScale(0.12, 0.12)
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.Text = icon
	t.Parent = bg
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = bg
	bb.Parent = head
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(1.9, function()
		if bb.Parent then
			local tw = TweenService:Create(scale, TweenInfo.new(0.18), { Scale = 0 })
			tw:Play()
			tw.Completed:Wait()
			bb:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Tags: bots get a name plate; players get their title and league under the Roblox name
---------------------------------------------------------------------------
local function tag(parent: BasePart, name: string, height: number): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.fromScale(7, 1.1)
	bb.StudsOffset = Vector3.new(0, height, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 90
	local t = Instance.new("TextLabel")
	t.Name = "T"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 2.5
	st.Color = Color3.fromRGB(10, 10, 28)
	st.Parent = t
	bb.Parent = parent
	return bb, t
end

local function dressBot(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local head = model:WaitForChild("Head", 5)
	if head and head:IsA("BasePart") and not head:FindFirstChild("NameTag") then
		local _, t = tag(head, "NameTag", 2.6)
		t.Text = "🤖 " .. tostring(model:GetAttribute("BotName") or "Bot")
	end
end

local auras: { [Player]: { parts: { Part }, emitter: ParticleEmitter?, shape: string } } = {}

local function clearAura(player: Player)
	local a = auras[player]
	if a then
		for _, p in a.parts do
			p:Destroy()
		end
		if a.emitter then
			a.emitter:Destroy()
		end
		auras[player] = nil
	end
end

local function dressPlayer(player: Player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not head or not head:IsA("BasePart") or not hrp or not hrp:IsA("BasePart") then
		return
	end
	-- title
	local bb = head:FindFirstChild("TitleTag") :: BillboardGui?
	local label: TextLabel
	if not bb then
		local created, t = tag(head, "TitleTag", 1.55)
		created.Size = UDim2.fromScale(6, 0.8)
		bb, label = created, t
	else
		label = bb:FindFirstChild("T") :: TextLabel
	end
	local titleId = player:GetAttribute("Cos_title")
	local league = player:GetAttribute("League")
	local leagueIcon = ""
	for _, l in Config.Leagues do
		if l.id == league then
			leagueIcon = l.icon .. " "
			label.TextColor3 = Color3.fromRGB(l.color[1], l.color[2], l.color[3]):Lerp(Color3.new(1, 1, 1), 0.35)
		end
	end
	label.Text = leagueIcon .. (if type(titleId) == "string" and Config.CosmeticById[titleId] then Lang.t("cos." .. titleId) else "")
	-- aura
	local auraId = player:GetAttribute("Cos_aura")
	local item = if type(auraId) == "string" then Config.CosmeticById[auraId] else nil
	clearAura(player)
	if item and item.look then
		local look = item.look :: any
		local color = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
		local entry = { parts = {} :: { Part }, emitter = nil :: ParticleEmitter?, shape = look.shape :: string }
		local lite = Prefs.lite()
		if look.shape == "orbit" or lite then
			for _ = 1, (if lite then 1 else 3) do
				local p = Instance.new("Part")
				p.Name = "AuraOrb"
				p.Shape = Enum.PartType.Ball
				p.Size = Vector3.one * 0.7
				p.Material = Enum.Material.Neon
				p.Color = color
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Parent = char
				table.insert(entry.parts, p)
			end
		else
			local e = Instance.new("ParticleEmitter")
			e.Name = "Aura"
			e.Rate = 7
			e.Lifetime = NumberRange.new(0.8, 1.3)
			e.Speed = NumberRange.new(if look.shape == "rise" then 3 else 1, if look.shape == "rise" then 5 else 2)
			e.SpreadAngle = Vector2.new(if look.shape == "rise" then 20 else 180, if look.shape == "rise" then 20 else 180)
			e.Color = ColorSequence.new(color)
			e.LightEmission = 0.9
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
			e.Parent = hrp
			entry.emitter = e
		end
		auras[player] = entry
	end
end
Avatars.dressPlayer = dressPlayer

function Avatars.auraCount(): number
	local n = 0
	for _ in auras do
		n += 1
	end
	return n
end

function Avatars.init()
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 60)
		local bots = world and world:WaitForChild("Bots", 30)
		if bots then
			for _, m in bots:GetChildren() do
				task.spawn(dressBot, m)
			end
			bots.ChildAdded:Connect(function(m)
				task.spawn(dressBot, m)
			end)
		end
	end)
	local function watch(player: Player)
		local function later()
			task.delay(0.5, dressPlayer, player)
		end
		player.CharacterAdded:Connect(later)
		for _, attr in { "Cos_title", "Cos_aura", "League" } do
			player:GetAttributeChangedSignal(attr):Connect(function()
				dressPlayer(player)
			end)
		end
		if player.Character then
			later()
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clearAura)
	Lang.Changed:Connect(function()
		for _, player in Players:GetPlayers() do
			dressPlayer(player)
		end
	end)
	-- orbiting aura orbs: one loop, 20 updates a second
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.05 or next(auras) == nil then
			return
		end
		acc = 0
		local t = os.clock()
		for player, a in auras do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				for i, p in a.parts do
					local ang = t * 2.2 + i * (math.pi * 2 / #a.parts)
					p.CFrame = CFrame.new(hrp.Position + Vector3.new(math.cos(ang) * 2.4, math.sin(t * 3 + i) * 0.8, math.sin(ang) * 2.4))
				end
			end
		end
	end)
end

return Avatars
