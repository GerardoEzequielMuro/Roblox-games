--!strict
-- Mining input. Click / tap a planet to target it; every click (or holding the button)
-- is a hit. Hits are counted locally, capped at the player's hits-per-second stat and sent
-- to the server in batches every FLUSH seconds: one RemoteEvent call per batch, never one
-- per click. The server validates range and rate again and answers with the real result.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Shared.Layout)
local Net = require(script.Parent.Net)
local PlanetField = require(script.Parent.PlanetField)

local Miner = {}

local FLUSH = 0.2
local HOLD_RATE = 4 -- hits per second while the button is held

local player = Players.LocalPlayer
local hitEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Hit") :: RemoteEvent

Miner.target = nil :: number? -- node index
Miner.enabled = true
Miner.sent = 0 -- hits sent this session (tests)
local pending: { [number]: number } = {}
local tokens = 0
local lastRefill = os.clock()
local holding = false
local holdAcc = 0

local hitSignal = Instance.new("BindableEvent")
Miner.Hit = hitSignal.Event -- (view) a local hit landed (tool swing, pets, sounds)
local blockedSignal = Instance.new("BindableEvent")
Miner.Blocked = blockedSignal.Event -- (reason: "range" | "none")
local targetSignal = Instance.new("BindableEvent")
Miner.TargetChanged = targetSignal.Event

local function rootPart(): BasePart?
	local char = player.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function setTarget(n: number?)
	if Miner.target ~= n then
		Miner.target = n
		targetSignal:Fire(n)
	end
end
Miner.setTarget = setTarget

function Miner.targetView(): PlanetField.View?
	local n = Miner.target
	local view = if n then PlanetField.views[n] else nil
	if view and view.alive then
		return view
	end
	return nil
end

-- True when a screen position belongs to the UI or to the Roblox touch controls.
function Miner.isBlocked(pos: Vector2, touch: boolean): boolean
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui then
		local inset = GuiService:GetGuiInset()
		for _, obj in gui:GetGuiObjectsAtPosition(pos.X, pos.Y - inset.Y) do
			if obj:IsA("GuiButton") or obj:IsA("TextBox") or obj:IsA("ScrollingFrame") or obj:GetAttribute("BlocksMining") then
				return true
			end
		end
		for _, obj in gui:GetGuiObjectsAtPosition(pos.X, pos.Y) do
			if obj:IsA("GuiButton") or obj:IsA("TextBox") or obj:IsA("ScrollingFrame") or obj:GetAttribute("BlocksMining") then
				return true
			end
		end
	end
	if touch then
		local cam = Workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			-- thumbstick (bottom-left) and jump button (bottom-right)
			if pos.Y > vp.Y * 0.55 and (pos.X < vp.X * 0.32 or pos.X > vp.X * 0.76) then
				return true
			end
		end
	end
	return false
end

local function range(): number
	local s = Net.state
	return if s then s.range else 30
end

-- One hit on the current target. Returns false when nothing could be hit.
local function strike(): boolean
	local root = rootPart()
	if not root or not Miner.enabled then
		return false
	end
	local found = Miner.targetView() or PlanetField.nearest(root.Position, range(), false)
	if not found then
		blockedSignal:Fire("none")
		return false
	end
	local view: PlanetField.View = found
	setTarget(view.n)
	if PlanetField.distance(view, root.Position) > range() then
		blockedSignal:Fire("range")
		return false
	end
	-- local rate cap (the server has the same one): extra clicks are simply dropped
	local now = os.clock()
	local s = Net.state
	local rate = if s then s.hitsPerSecond else 6
	tokens = math.min(rate, tokens + (now - lastRefill) * rate)
	lastRefill = now
	if tokens < 1 then
		return false
	end
	tokens -= 1
	pending[view.n] = (pending[view.n] or 0) + 1
	PlanetField.punch(view)
	hitSignal:Fire(view)
	return true
end

-- A click / tap at a screen position.
function Miner.click(pos: Vector2)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local view = PlanetField.pick(ray.Origin, ray.Direction)
	if view then
		setTarget(view.n)
	end
	strike()
end

-- Tests: hit a node directly.
function Miner.simulate(n: number): boolean
	setTarget(n)
	return strike()
end

function Miner.flush()
	for n, count in pending do
		if count > 0 then
			hitEvent:FireServer(n, count)
			Miner.sent += count
		end
	end
	table.clear(pending)
end

function Miner.setEnabled(on: boolean)
	Miner.enabled = on
	if not on then
		holding = false
	end
end

function Miner.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Miner.enabled then
			return
		end
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and not isTouch then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if Miner.isBlocked(pos, isTouch) then
			return
		end
		local root = rootPart()
		if root and Layout.inArena(root.Position.X, root.Position.Z) then
			return -- the arena has its own click handling (PvpClient)
		end
		holding = true
		holdAcc = 0
		Miner.click(pos)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
		end
	end)

	-- the target follows Auto Mine and clears when its planet breaks
	Net.event("Mine").OnClientEvent:Connect(function(msg)
		if msg.z ~= PlanetField.zone then
			return
		end
		if msg.drops and Miner.target == msg.n then
			setTarget(nil)
		elseif msg.a and not msg.drops and Miner.target == nil then
			setTarget(msg.n)
		end
	end)
	PlanetField.Changed:Connect(function(n)
		if n == nil then
			setTarget(nil)
			table.clear(pending)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if holding then
			holdAcc += dt * HOLD_RATE
			while holdAcc >= 1 do
				holdAcc -= 1
				strike()
			end
		end
		acc += dt
		if acc >= FLUSH then
			acc = 0
			Miner.flush()
		end
	end)
end

return Miner
