--!strict
-- Meteor Arena on the client: click a rival (player or sparring drone) to zap it, the
-- arena HP bar, SAFE / PVP pill, Rookie Shield notice, zap beams and damage numbers.
-- The server decides every hit; the client only asks (rate-limited) and draws.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Miner = require(script.Parent.Miner)
local PlanetField = require(script.Parent.PlanetField)
local Theme = require(script.Parent.UI.Theme)
local Root = require(script.Parent.UI.Root)
local Toasts = require(script.Parent.UI.Toasts)

local PvpClient = {}

local player = Players.LocalPlayer
local zapEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Zap") :: RemoteEvent
local C = Config.Pvp

PvpClient.state = { hp = C.maxHp, max = C.maxHp, inArena = false, rookie = true, protected = 0 }
PvpClient.zapsSent = 0
local lastZap = 0

local beam = Instance.new("Part")
beam.Name = "ZapBeam"
beam.Anchored = true
beam.CanCollide = false
beam.CanQuery = false
beam.CanTouch = false
beam.CastShadow = false
beam.Material = Enum.Material.Neon
beam.Color = Color3.fromRGB(255, 90, 90)
beam.Transparency = 1
beam.Size = Vector3.new(0.5, 0.5, 1)
beam.Parent = Workspace
local beamUntil = 0

local function rootOf(p: Player): BasePart?
	local char = p.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function arenaFolder(): Instance?
	local world = Workspace:FindFirstChild("World")
	return if world then world:FindFirstChild("Arena") else nil
end

-- Every combatant the client can see: { id, position }.
local function targets(): { { id: number, pos: Vector3 } }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local root = rootOf(p)
			if root and Layout.inArena(root.Position.X, root.Position.Z) then
				table.insert(out, { id = p.UserId, pos = root.Position })
			end
		end
	end
	local arena = arenaFolder()
	if arena then
		for _, m in arena:GetChildren() do
			local id = m:GetAttribute("BotId")
			if m:IsA("Model") and type(id) == "number" and not m:GetAttribute("Down") then
				table.insert(out, { id = id, pos = m:GetPivot().Position })
			end
		end
	end
	return out
end
PvpClient.targets = targets

local function positionOf(id: number): Vector3?
	if id == player.UserId then
		local root = rootOf(player)
		return if root then root.Position else nil
	end
	for _, t in targets() do
		if t.id == id then
			return t.pos
		end
	end
	return nil
end

-- Sends one zap request (client-side cooldown mirrors the server's).
function PvpClient.zap(id: number): boolean
	local now = os.clock()
	if now - lastZap < C.cooldown then
		return false
	end
	lastZap = now
	PvpClient.zapsSent += 1
	zapEvent:FireServer(id)
	return true
end

local function click(pos: Vector2)
	local cam = Workspace.CurrentCamera
	local root = rootOf(player)
	if not cam or not root then
		return
	end
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local dir = ray.Direction.Unit
	local best: number?, bestScore = nil, math.huge
	for _, t in targets() do
		local oc = t.pos - ray.Origin
		local along = oc:Dot(dir)
		if along > 0 then
			local off = math.sqrt(math.max(0, oc:Dot(oc) - along * along))
			local dist = (t.pos - root.Position).Magnitude
			-- clicked on it, or it is the nearest one in range when clicking empty space
			local score = if off < 5 then off else 100 + dist
			if dist <= C.range + 2 and score < bestScore then
				best, bestScore = t.id, score
			end
		end
	end
	if best then
		PvpClient.zap(best)
	end
end

function PvpClient.init()
	-- HUD: arena HP bar + state pill, top centre under the galaxy name
	local panel = Theme.new("Frame", { Name = "ArenaHud", BackgroundTransparency = 1, Size = UDim2.fromOffset(360, 64), Position = UDim2.new(0.5, 0, 0, if Root.isTouch then 142 else 86), AnchorPoint = Vector2.new(0.5, 0), Visible = false, Parent = Root.gui })
	Root.mount(panel)
	local pill = Theme.text({ Name = "State", Text = "", Size = UDim2.new(1, 0, 0, 24), MaxTextSize = 20, Parent = panel })
	local hp = Theme.bar(panel, UDim2.new(1, 0, 0, 30), Theme.Red)
	hp.frame.Name = "ArenaHp"
	hp.frame.Position = UDim2.fromOffset(0, 28)

	local function paint()
		local st = PvpClient.state
		local root = rootOf(player)
		local onPlatform = root ~= nil and Layout.onArenaPlatform(root.Position.X, root.Position.Z)
		panel.Visible = onPlatform
		if not onPlatform then
			return
		end
		if st.inArena then
			pill.Text = if st.protected > 0 then ("🛡️ " .. Lang.t("pvp.protected")) elseif st.rookie then ("🛡️ " .. Lang.t("pvp.rookie")) else ("⚔️ " .. Lang.t("pvp.on"))
			pill.TextColor3 = if st.protected > 0 or st.rookie then Theme.Crystals else Theme.Red
		else
			pill.Text = "✅ " .. Lang.t("pvp.safe")
			pill.TextColor3 = Theme.Green
		end
		hp.frame.Visible = st.inArena
		hp:set(st.hp / st.max, math.ceil(st.hp) .. " / " .. st.max)
	end

	Net.event("Pvp").OnClientEvent:Connect(function(msg)
		if msg.kind == "self" then
			PvpClient.state = msg
			paint()
		elseif msg.kind == "zap" then
			local a, t = positionOf(msg.a), positionOf(msg.t)
			if a and t then
				local dist = (t - a).Magnitude
				beam.Size = Vector3.new(0.5, 0.5, dist)
				beam.CFrame = CFrame.lookAt(a, t) * CFrame.new(0, 0, -dist / 2)
				beam.Color = if msg.a == player.UserId then Color3.fromRGB(120, 230, 255) else Color3.fromRGB(255, 90, 90)
				beam.Transparency = 0.1
				beamUntil = os.clock() + 0.12
				PlanetField.float(t + Vector3.new(0, 3, 0), "-" .. msg.dmg, if msg.t == player.UserId then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(255, 230, 120), 1, 0.8)
				PlanetField.burst(t, Color3.fromRGB(255, 200, 90), 3, 18, 0.5)
			end
			Theme.play("hit", 0.3, 1.4)
		elseif msg.kind == "ko" then
			Toasts.milestone(Lang.t("pvp.ko"), "+" .. msg.points .. " 🏆   +" .. Format.abbrev(msg.stardust) .. " ✨", Theme.Yellow)
		elseif msg.kind == "down" then
			Toasts.milestone(Lang.t("pvp.down"), Lang.t("pvp.down_sub"), Theme.Red)
		elseif msg.kind == "blocked" then
			Toasts.show(Lang.t("pvp.blocked_" .. msg.reason), "info")
		end
	end)
	Net.Changed:Connect(function(kind)
		local s = Net.state
		if kind == "full" and s and s.pvp then
			PvpClient.state.rookie = s.pvp.rookie
			paint()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and not isTouch then
			return
		end
		local root = rootOf(player)
		if not root or not Layout.inArena(root.Position.X, root.Position.Z) then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if Miner.isBlocked(pos, isTouch) then
			return
		end
		click(pos)
	end)

	-- drone health bars
	local function tagBot(m: Instance)
		if not m:IsA("Model") or m:GetAttribute("BotId") == nil or m:FindFirstChild("BotGui", true) then
			return
		end
		local primary = m.PrimaryPart
		if not primary then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "BotGui"
		gui.Size = UDim2.fromScale(7, 1.6)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
		gui.MaxDistance = 120
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local name = Theme.text({ Key = "pvp.bot", Size = UDim2.fromScale(1, 0.5), Parent = gui })
		name.TextColor3 = Color3.fromRGB(255, 190, 120)
		local back = Theme.new("Frame", { Size = UDim2.fromScale(0.9, 0.36), Position = UDim2.fromScale(0.05, 0.56), BackgroundColor3 = Theme.PaperDark, Parent = gui }, { Theme.corner(6), Theme.stroke(2) })
		local fill = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Red, BorderSizePixel = 0, Parent = back }, { Theme.corner(6) })
		gui.Parent = primary
		local function update()
			local maxHp = (m:GetAttribute("MaxHp") :: number?) or C.botHp
			fill.Size = UDim2.fromScale(math.clamp(((m:GetAttribute("Hp") :: number?) or 0) / maxHp, 0, 1), 1)
			gui.Enabled = not m:GetAttribute("Down")
			for _, d in m:GetChildren() do
				if d:IsA("BasePart") then
					d.Transparency = if m:GetAttribute("Down") then 0.8 else 0
				end
			end
		end
		m:GetAttributeChangedSignal("Hp"):Connect(update)
		m:GetAttributeChangedSignal("Down"):Connect(update)
		update()
	end
	task.spawn(function()
		while true do
			local arena = arenaFolder()
			if arena then
				for _, m in arena:GetChildren() do
					tagBot(m)
				end
			end
			paint()
			if PvpClient.state.protected > 0 then
				PvpClient.state.protected = math.max(0, PvpClient.state.protected - 0.5)
			end
			task.wait(0.5)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if beam.Transparency < 1 and os.clock() > beamUntil then
			beam.Transparency = 1
		end
	end)
end

return PvpClient
