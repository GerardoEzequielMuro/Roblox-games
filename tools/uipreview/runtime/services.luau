--!nocheck
-- Class/service behaviour: DataModel, Players, RunService, TweenService, remotes, GUI
-- measurement getters, DataStores, Marketplace, etc. Everything not here falls back to
-- the reflection-checked generic Instance (unimplemented API calls are logged).
local C = require("./core")
local I = require("./instance")
local T = require("./text")
local roblox = C.roblox
local E = roblox.Enum
local V2 = roblox.Vector2
local S = I.S

local Svc = {}
Svc.config = nil -- set by main: { screen = {...}, fixture = {...}, userId = n }

local function methods(cls)
	I.methods[cls] = I.methods[cls] or {}
	return I.methods[cls]
end
local function getters(cls)
	I.getters[cls] = I.getters[cls] or {}
	return I.getters[cls]
end
local function setters(cls)
	I.setters[cls] = I.setters[cls] or {}
	return I.setters[cls]
end
local function quiet(cls, list)
	I.quiet[cls] = I.quiet[cls] or {}
	for _, k in list do
		I.quiet[cls][k] = true
	end
end

------------------------------------------------------------------------------------------
-- deep copy (remote / bindable serialization)
------------------------------------------------------------------------------------------
local function remoteCopy(v, seen, path, warnWhere, keepFns)
	if type(v) ~= "table" or I.isInstance(v) or getmetatable(v) == C.SignalMT then
		if type(v) == "function" and not keepFns then
			return nil
		end
		return v
	end
	if seen[v] then
		return seen[v]
	end
	local out = {}
	seen[v] = out
	local n = #v
	local hasStr, hasNum, maxNum, cnt = false, false, 0, 0
	for k in v do
		if type(k) == "number" then
			hasNum = true
			maxNum = math.max(maxNum, k)
			cnt += 1
		else
			hasStr = true
		end
	end
	if warnWhere and hasNum and hasStr then
		C.addLog("remote_serialization", "mixed table (array + dictionary keys) sent through a remote at " .. path .. ": Roblox drops part of it", warnWhere)
	elseif warnWhere and hasNum and not hasStr and cnt ~= maxNum then
		C.addLog("remote_serialization", "sparse numeric table sent through a remote at " .. path .. " (Roblox may lose entries)", warnWhere)
	end
	for k, val in v do
		out[k] = remoteCopy(val, seen, path .. "." .. tostring(k), warnWhere, keepFns)
	end
	local _ = n
	return out
end
Svc.remoteCopy = remoteCopy
local function copyArgs(where, keepFns, ...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = remoteCopy(args[i], {}, "arg" .. i, where, keepFns)
	end
	return args
end

local function withCtx(ctx, fn, ...)
	local co = coroutine.running()
	local old = C.threadCtx[co]
	C.threadCtx[co] = ctx
	local res = table.pack(pcall(fn, ...))
	C.threadCtx[co] = old
	if not res[1] then
		error(res[2], 0)
	end
	return table.unpack(res, 2, res.n)
end

------------------------------------------------------------------------------------------
-- Remotes & bindables
------------------------------------------------------------------------------------------
do
	local RE = methods("RemoteEvent")
	function RE:FireServer(...)
		local args = copyArgs(C.where(2), false, ...)
		local player = Svc.player
		C.defer(function()
			I.signal(self, "OnServerEvent"):Fire(player, table.unpack(args, 1, args.n))
		end)
		local co = C.threadCtx
		local _ = co
	end
	function RE:FireClient(player, ...)
		if not I.isInstance(player) or not S[player].info.isA.Player then
			C.rterror("FireClient: player argument must be a Player object")
		end
		local args = copyArgs(C.where(2), false, ...)
		local ev = I.signal(self, "OnClientEvent")
		local co = C.newThread(function()
			ev:Fire(table.unpack(args, 1, args.n))
		end, "OnClientEvent", "client")
		C.defer(co)
	end
	function RE:FireAllClients(...)
		local p = Svc.player
		if p and S[p].parent then
			RE.FireClient(self, p, ...)
		end
	end
	I.methods.UnreliableRemoteEvent = RE

	local RF = methods("RemoteFunction")
	function RF:InvokeServer(...)
		local st = S[self]
		local waited = 0
		while not st.callbacks.OnServerInvoke do
			if not coroutine.isyieldable() or waited > 30 then
				C.addLog("warn", "InvokeServer on " .. I.fullName(self) .. " never got an OnServerInvoke handler", C.where(2))
				C.suspend("InvokeServer " .. I.fullName(self) .. " (no handler)")
				return coroutine.yield()
			end
			C.wait(0.1)
			waited += 0.1
		end
		local args = copyArgs(C.where(2), false, ...)
		local res = table.pack(withCtx("server", st.callbacks.OnServerInvoke, Svc.player, table.unpack(args, 1, args.n)))
		local out = copyArgs(nil, false, table.unpack(res, 1, res.n))
		return table.unpack(out, 1, out.n)
	end
	function RF:InvokeClient(_player, ...)
		local st = S[self]
		if not st.callbacks.OnClientInvoke then
			C.rterror("InvokeClient: OnClientInvoke is not set")
		end
		return withCtx("client", st.callbacks.OnClientInvoke, ...)
	end

	local BE = methods("BindableEvent")
	function BE:Fire(...)
		local args = copyArgs(nil, true, ...)
		I.signal(self, "Event"):Fire(table.unpack(args, 1, args.n))
	end
	local BF = methods("BindableFunction")
	function BF:Invoke(...)
		local st = S[self]
		local waited = 0
		while not st.callbacks.OnInvoke and waited < 10 and coroutine.isyieldable() do
			C.wait(0.1)
			waited += 0.1
		end
		if not st.callbacks.OnInvoke then
			C.rterror("BindableFunction:Invoke - OnInvoke not set")
		end
		return st.callbacks.OnInvoke(...)
	end
end

------------------------------------------------------------------------------------------
-- DataModel
------------------------------------------------------------------------------------------
Svc.services = {}
do
	local DM = methods("DataModel")
	local serviceAlias = { UserGameSettings = true }
	function DM:GetService(name)
		local s = Svc.services[name]
		if s then
			return s
		end
		local info = C.classInfo(name)
		if not info or (not info.service and not serviceAlias[name]) then
			C.rterror("'" .. tostring(name) .. "' is not a valid Service name")
		end
		s = I.new(name, { name = name, src = {} })
		Svc.services[name] = s
		I.setParent(s, Svc.game)
		return s
	end
	DM.getService = DM.GetService
	DM.service = DM.GetService
	function DM:FindService(name)
		return Svc.services[name]
	end
	function DM:IsLoaded()
		return true
	end
	function DM:BindToClose(_fn) end
	function DM:GetJobsInfo()
		return {}
	end
	local g = getters("DataModel")
	g.PlaceId = function()
		return Svc.config.fixture.placeId or 1818
	end
	g.GameId = function()
		return Svc.config.fixture.gameId or 1818
	end
	g.JobId = function()
		return "00000000-preview-job"
	end
	g.PrivateServerId = function()
		return ""
	end
	g.PrivateServerOwnerId = function()
		return 0
	end
	g.CreatorId = function()
		return Svc.config.fixture.creatorId or 1
	end
	g.Workspace = function()
		return Svc.services.Workspace
	end
	g.Lighting = function()
		return DM.GetService(Svc.game, "Lighting")
	end
end

------------------------------------------------------------------------------------------
-- Workspace / Camera
------------------------------------------------------------------------------------------
do
	local W = methods("Workspace")
	function W:GetServerTimeNow()
		return C.epoch + C.now
	end
	function W:Raycast()
		return nil
	end
	function W:GetPartBoundsInBox()
		return {}
	end
	function W:GetPartBoundsInRadius()
		return {}
	end
	function W:GetPartsInPart()
		return {}
	end
	function W:Blockcast()
		return nil
	end
	function W:Spherecast()
		return nil
	end
	function W:FindPartOnRay()
		return nil
	end
	function W:GetRealPhysicsFPS()
		return 60
	end
	function W:BulkMoveTo() end
	local wg = getters("Workspace")
	wg.Terrain = function(self)
		return I.methods.Instance.FindFirstChildOfClass(self, "Terrain")
	end
	wg.DistributedGameTime = function()
		return C.now
	end
	local Cam = getters("Camera")
	Cam.ViewportSize = function()
		return V2.new(Svc.config.screen.w, Svc.config.screen.h)
	end
	local CM = methods("Camera")
	function CM:WorldToViewportPoint(_p)
		return roblox.Vector3.new(-1, -1, -1), false
	end
	CM.WorldToScreenPoint = CM.WorldToViewportPoint
	function CM:ViewportPointToRay(x, y)
		return roblox.Ray.new(roblox.Vector3.zero, roblox.Vector3.new(0, 0, -1))
	end
	CM.ScreenPointToRay = CM.ViewportPointToRay
	function CM:GetPartsObscuringTarget()
		return {}
	end
	local TRN = methods("Terrain")
	function TRN:ReadVoxels(region, res)
		local sz = region.Size / (res or 4)
		local nx, ny, nz = math.max(1, math.round(sz.X)), math.max(1, math.round(sz.Y)), math.max(1, math.round(sz.Z))
		local mats, occ = { Size = roblox.Vector3.new(nx, ny, nz) }, { Size = roblox.Vector3.new(nx, ny, nz) }
		for x = 1, nx do
			mats[x], occ[x] = {}, {}
			for y = 1, ny do
				mats[x][y], occ[x][y] = {}, {}
				for z = 1, nz do
					mats[x][y][z] = E.Material.Air
					occ[x][y][z] = 0
				end
			end
		end
		return mats, occ
	end
	quiet("Terrain", { "FillBlock", "FillBall", "FillCylinder", "FillWedge", "FillRegion", "Clear", "ReplaceMaterial", "SetMaterialColor", "WriteVoxels" })
	local PV = methods("PVInstance")
	function PV:GetPivot()
		local st = S[self]
		if st.info.isA.BasePart then
			return self.CFrame
		end
		local pp = st.props.PrimaryPart
		if pp then
			return pp.CFrame
		end
		return st.data.pivot or roblox.CFrame.identity
	end
	function PV:PivotTo(cf)
		local st = S[self]
		if st.info.isA.BasePart then
			self.CFrame = cf
		else
			st.data.pivot = cf
		end
	end
	local MD = methods("Model")
	function MD:GetBoundingBox()
		return PV.GetPivot(self), roblox.Vector3.new(4, 4, 4)
	end
	function MD:GetExtentsSize()
		return roblox.Vector3.new(4, 4, 4)
	end
	function MD:SetPrimaryPartCFrame(cf)
		PV.PivotTo(self, cf)
	end
	function MD:GetPrimaryPartCFrame()
		return PV.GetPivot(self)
	end
	function MD:ScaleTo(_s) end
	function MD:GetScale()
		return 1
	end
	quiet("Model", { "MoveTo", "TranslateBy", "BreakJoints", "MakeJoints" })
	quiet("BasePart", { "SetNetworkOwner", "ApplyImpulse", "ApplyAngularImpulse", "BreakJoints", "MakeJoints", "SetNetworkOwnershipAuto" })
	local BP = methods("BasePart")
	function BP:GetMass()
		return 1
	end
	function BP:GetNetworkOwner()
		return nil
	end
	function BP:GetTouchingParts()
		return {}
	end
	function BP:CanSetNetworkOwnership()
		return true, nil
	end
	function BP:GetConnectedParts()
		return {}
	end
	function BP:GetVelocityAtPosition()
		return roblox.Vector3.zero
	end
end

------------------------------------------------------------------------------------------
-- Players / Player / character
------------------------------------------------------------------------------------------
do
	local P = methods("Players")
	function P:GetPlayers()
		local out = {}
		for _, c in S[self].children do
			if S[c].info.isA.Player then
				table.insert(out, c)
			end
		end
		return out
	end
	function P:GetPlayerByUserId(id)
		local p = Svc.player
		if p and S[p].parent and id == Svc.config.userId then
			return p
		end
		return nil
	end
	function P:GetPlayerFromCharacter(ch)
		local p = Svc.player
		if p and ch and S[p].data.character == ch then
			return p
		end
		return nil
	end
	function P:GetUserThumbnailAsync(id, _t, _s)
		return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150", true
	end
	function P:GetNameFromUserIdAsync(id)
		return "Player" .. tostring(id)
	end
	function P:GetUserIdFromNameAsync(_n)
		return 1
	end
	function P:GetFriendsAsync(_id)
		return Svc.pages({})
	end
	function P:GetCharacterAppearanceInfoAsync()
		return {}
	end
	function P:GetHumanoidDescriptionFromUserId()
		return I.new("HumanoidDescription")
	end
	function P:CreateHumanoidModelFromDescription()
		return Svc.makeCharacter("Dummy")
	end
	function P:CreateHumanoidModelFromUserId()
		return Svc.makeCharacter("Dummy")
	end
	local pg = getters("Players")
	pg.LocalPlayer = function(self)
		if C.currentCtx() == "server" then
			return nil
		end
		return Svc.player
	end
	pg.MaxPlayers = function()
		return 12
	end

	local PL = methods("Player")
	function PL:Kick(msg)
		C.addLog("kick", "Player:Kick(" .. tostring(msg) .. ")", C.where(2))
	end
	function PL:GetMouse()
		local st = S[self]
		if not st.data.mouse then
			st.data.mouse = I.new("PlayerMouse", { name = "Mouse", src = {} })
		end
		return st.data.mouse
	end
	function PL:IsFriendsWith()
		return false
	end
	function PL:GetRankInGroup()
		return Svc.config.fixture.groupRank or 0
	end
	function PL:GetRoleInGroup()
		return "Guest"
	end
	function PL:IsInGroup()
		return (Svc.config.fixture.groupRank or 0) > 0
	end
	function PL:GetFriendsOnline()
		return {}
	end
	function PL:HasAppearanceLoaded()
		return true
	end
	function PL:GetJoinData()
		return { LaunchData = nil, SourcePlaceId = nil, Members = {} }
	end
	function PL:LoadCharacter()
		Svc.spawnCharacter(self)
	end
	PL.LoadCharacterAsync = PL.LoadCharacter
	function PL:ClearCharacterAppearance() end
	function PL:DistanceFromCharacter()
		return 0
	end
	function PL:RequestStreamAroundAsync() end
	function PL:GetNetworkPing()
		return 0.05
	end
	function PL:SetAttributeSilent() end
	local plg = getters("Player")
	plg.UserId = function()
		return Svc.config.userId
	end
	plg.DisplayName = function(self)
		return S[self].props.DisplayName or "PreviewPlayer"
	end
	plg.AccountAge = function()
		return Svc.config.fixture.accountAge or 120
	end
	plg.MembershipType = function()
		return if Svc.config.fixture.premium then E.MembershipType.Premium else E.MembershipType.None
	end
	plg.LocaleId = function()
		return Svc.config.locale
	end
	plg.Character = function(self)
		return S[self].data.character
	end
	local pls = setters("Player")
	pls.Character = function(self, v)
		S[self].data.character = v
		I.firePropChanged(self, "Character")
	end

	local H = methods("Humanoid")
	function H:GetState()
		return E.HumanoidStateType.Running
	end
	function H:ChangeState() end
	function H:SetStateEnabled() end
	function H:GetStateEnabled()
		return true
	end
	function H:LoadAnimation(_a)
		return Svc.animTrack()
	end
	function H:GetAppliedDescription()
		return I.new("HumanoidDescription")
	end
	function H:GetPlayingAnimationTracks()
		return {}
	end
	quiet("Humanoid", { "MoveTo", "Move", "TakeDamage", "EquipTool", "UnequipTools", "ApplyDescription", "ApplyDescriptionReset", "AddAccessory", "RemoveAccessories", "BuildRigFromAttachments" })
	local AN = methods("Animator")
	function AN:LoadAnimation(_a)
		return Svc.animTrack()
	end
	function AN:GetPlayingAnimationTracks()
		return {}
	end
end

function Svc.animTrack()
	local tr = I.new("AnimationTrack", { src = {} })
	return tr
end
quiet("AnimationTrack", { "Play", "Stop", "AdjustSpeed", "AdjustWeight", "GetMarkerReachedSignal" })
do
	local AT = methods("AnimationTrack")
	function AT:GetMarkerReachedSignal(name)
		return C.newSignal("Marker " .. tostring(name))
	end
end

function Svc.makeCharacter(name)
	local model = I.new("Model", { name = name, src = {} })
	local hrp = I.new("Part", { name = "HumanoidRootPart", src = {} })
	I.setParent(hrp, model)
	local head = I.new("Part", { name = "Head", src = {} })
	I.setParent(head, model)
	local torso = I.new("Part", { name = "UpperTorso", src = {} })
	I.setParent(torso, model)
	local hum = I.new("Humanoid", { name = "Humanoid", src = {} })
	I.setParent(hum, model)
	local animator = I.new("Animator", { name = "Animator", src = {} })
	I.setParent(animator, hum)
	S[model].props.PrimaryPart = hrp
	hrp.CFrame = roblox.CFrame.new(0, 5, 0)
	return model
end

function Svc.spawnCharacter(player)
	local st = S[player]
	local old = st.data.character
	if old then
		I.destroy(old)
	end
	local ch = Svc.makeCharacter(st.name)
	st.data.character = ch
	I.setParent(ch, Svc.services.Workspace)
	I.firePropChanged(player, "Character")
	I.signal(player, "CharacterAdded"):Fire(ch)
	C.delay(0.1, function()
		I.signal(player, "CharacterAppearanceLoaded"):Fire(ch)
	end)
end

------------------------------------------------------------------------------------------
-- RunService
------------------------------------------------------------------------------------------
do
	local R = methods("RunService")
	function R:IsClient()
		return C.currentCtx() == "client"
	end
	function R:IsServer()
		return C.currentCtx() == "server"
	end
	function R:IsStudio()
		return Svc.config.fixture.isStudio == true
	end
	function R:IsRunning()
		return true
	end
	function R:IsRunMode()
		return false
	end
	function R:IsEdit()
		return false
	end
	local bound = {}
	function R:BindToRenderStep(name, prio, fn)
		bound[name] = { prio = prio, fn = fn, ctx = C.currentCtx() }
	end
	function R:UnbindFromRenderStep(name)
		bound[name] = nil
	end
	function Svc.runServiceFrame()
		local rs = Svc.services.RunService
		if not rs then
			return
		end
		local list = {}
		for n, b in bound do
			table.insert(list, b)
		end
		table.sort(list, function(a, b)
			return a.prio < b.prio
		end)
		for _, b in list do
			C.resume(C.newThread(b.fn, "BindToRenderStep", b.ctx), C.dt)
		end
		local st = S[rs]
		for _, ev in { "PreRender", "RenderStepped", "PreAnimation", "PreSimulation", "Stepped", "PostSimulation", "Heartbeat" } do
			local s = st.signals[ev]
			if s and (#s.conns > 0 or #s.waiting > 0) then
				if ev == "Stepped" or ev == "PreSimulation" and false then
					s:Fire(C.now, C.dt)
				else
					s:Fire(C.dt)
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- TweenService (end state applied immediately)
------------------------------------------------------------------------------------------
do
	local TS = methods("TweenService")
	function TS:Create(inst, info, goals)
		if not I.isInstance(inst) then
			C.rterror("TweenService:Create - instance argument is not an Instance")
		end
		if C.typeof(info) ~= "TweenInfo" then
			C.rterror("TweenService:Create - TweenInfo expected, got " .. C.typeof(info))
		end
		if type(goals) ~= "table" then
			C.rterror("TweenService:Create - property table expected")
		end
		for k, v in goals do
			local p = S[inst].info.props[k]
			if not p then
				C.rterror("TweenService:Create no property named '" .. tostring(k) .. "' for object '" .. S[inst].name .. "'")
			end
		end
		local tw = I.new("Tween", { name = "Tween", src = C.where(4) })
		S[tw].data.target = inst
		S[tw].data.goals = goals
		S[tw].data.info = info
		S[tw].props.PlaybackState = E.PlaybackState.Begin
		return tw
	end
	function TS:GetValue(alpha, _style, _dir)
		return alpha
	end
	function TS:SmoothDamp(cur, target, vel, _t)
		return target, vel
	end
	local TW = methods("Tween")
	function TW:Play()
		local st = S[self]
		local target = st.data.target
		if not target or S[target].destroyed then
			return
		end
		local info = st.data.info
		local delayT = info.DelayTime or 0
		local function apply()
			for k, v in st.data.goals do
				local ok, err = pcall(function()
					target[k] = v
				end)
				if not ok then
					C.addLog("error", "Tween goal " .. tostring(k) .. ": " .. tostring(err), st.src)
				end
			end
			st.props.PlaybackState = E.PlaybackState.Completed
			if info.RepeatCount ~= -1 then
				C.defer(function()
					I.signal(self, "Completed"):Fire(E.PlaybackState.Completed)
				end)
			end
		end
		st.props.PlaybackState = E.PlaybackState.Playing
		if delayT > 0 then
			C.delay(math.min(delayT, 0.2), apply)
		else
			apply()
		end
	end
	function TW:Cancel()
		S[self].props.PlaybackState = E.PlaybackState.Cancelled
	end
	function TW:Pause()
		S[self].props.PlaybackState = E.PlaybackState.Paused
	end
end

------------------------------------------------------------------------------------------
-- Input / GUI services
------------------------------------------------------------------------------------------
do
	local ug = getters("UserInputService")
	ug.TouchEnabled = function()
		return Svc.config.screen.touch
	end
	ug.KeyboardEnabled = function()
		return not Svc.config.screen.touch
	end
	ug.MouseEnabled = function()
		return not Svc.config.screen.touch
	end
	ug.GamepadEnabled = function()
		return false
	end
	ug.VREnabled = function()
		return false
	end
	ug.AccelerometerEnabled = function()
		return Svc.config.screen.touch
	end
	ug.GyroscopeEnabled = function()
		return Svc.config.screen.touch
	end
	ug.PreferredInput = function()
		return if Svc.config.screen.touch then E.PreferredInput.Touch else E.PreferredInput.KeyboardAndMouse
	end
	local U = methods("UserInputService")
	function U:GetLastInputType()
		return if Svc.config.screen.touch then E.UserInputType.Touch else E.UserInputType.MouseMovement
	end
	function U:GetMouseLocation()
		return V2.new(Svc.config.screen.w / 2, Svc.config.screen.h / 2)
	end
	function U:IsKeyDown()
		return false
	end
	function U:IsMouseButtonPressed()
		return false
	end
	function U:GetKeysPressed()
		return {}
	end
	function U:GetMouseButtonsPressed()
		return {}
	end
	function U:GetConnectedGamepads()
		return {}
	end
	function U:GetNavigationGamepads()
		return {}
	end
	function U:GetGamepadConnected()
		return false
	end
	function U:GetFocusedTextBox()
		return nil
	end
	function U:GetStringForKeyCode(k)
		return k and k.Name or ""
	end
	function U:GetImageForKeyCode()
		return ""
	end
	function U:GetGamepadState()
		return {}
	end
	function U:GetSupportedGamepadKeyCodes()
		return {}
	end
	function U:GetMouseDelta()
		return V2.zero
	end

	local G = methods("GuiService")
	function G:GetGuiInset()
		return V2.new(0, Svc.config.screen.insets.top), V2.new(0, 0)
	end
	function G:IsTenFootInterface()
		return false
	end
	function G:GetScreenResolution()
		return V2.new(Svc.config.screen.w, Svc.config.screen.h)
	end
	function G:GetEmotesMenuOpen()
		return false
	end
	function G:GetInspectMenuEnabled()
		return true
	end
	quiet("GuiService", { "InspectPlayerFromUserId", "CloseInspectMenu", "SetEmotesMenuOpen", "SetInspectMenuEnabled", "Select", "AddSelectionParent", "RemoveSelectionGroup", "OpenBrowserWindow" })
	local gg = getters("GuiService")
	gg.TopbarInset = function()
		local sc = Svc.config.screen
		return roblox.Rect.new(sc.insets.left + 104, 0, sc.w - sc.insets.right - 60, sc.insets.top)
	end
	gg.MenuIsOpen = function()
		return false
	end
	gg.ReducedMotionEnabled = function()
		return false
	end
	gg.PreferredTransparency = function()
		return 1
	end
	gg.PreferredTextSize = function()
		return E.PreferredTextSize.Medium
	end
	gg.ViewportDisplaySize = function()
		return if Svc.config.screen.touch and Svc.config.screen.h < 500 then E.DisplaySize.Small else E.DisplaySize.Large
	end

	local SG = methods("StarterGui")
	local core = {}
	Svc.coreGui = core
	function SG:SetCoreGuiEnabled(t, on)
		core[tostring(t)] = on
	end
	function SG:GetCoreGuiEnabled(t)
		local v = core[tostring(t)]
		if v == nil then
			return true
		end
		return v
	end
	function SG:SetCore(name, value)
		if name == "SendNotification" and type(value) == "table" then
			C.addLog("info", "SetCore SendNotification: " .. tostring(value.Title) .. " / " .. tostring(value.Text), C.where(2))
		end
		core["SetCore." .. tostring(name)] = tostring(value)
	end
	function SG:GetCore(name)
		if name == "ChatActive" then
			return false
		end
		return nil
	end
end

------------------------------------------------------------------------------------------
-- Monetization, policy, localization, text, http, social...
------------------------------------------------------------------------------------------
function Svc.pages(items)
	local pg = { IsFinished = true, _items = items }
	function pg:GetCurrentPage()
		return self._items
	end
	function pg:AdvanceToNextPageAsync() end
	return pg
end

do
	local MS = methods("MarketplaceService")
	function MS:GetProductInfo(id, infoType)
		local fx = Svc.config.fixture
		local price = (fx.prices and fx.prices[id]) or 99
		return {
			Name = "Product " .. tostring(id),
			Description = "",
			PriceInRobux = price,
			IsForSale = true,
			IconImageAssetId = 0,
			ProductId = id,
			AssetId = id,
			TargetId = id,
			ProductType = tostring(infoType),
		}
	end
	MS.GetProductInfoAsync = MS.GetProductInfo
	function MS:UserOwnsGamePassAsync(_uid, passId)
		local owned = Svc.config.fixture.ownedPasses
		return owned ~= nil and table.find(owned, passId) ~= nil
	end
	function MS:PlayerOwnsAsset()
		return false
	end
	function MS:PlayerOwnsBundle()
		return false
	end
	function MS:GetDeveloperProductsAsync()
		return Svc.pages({})
	end
	function MS:GetSubscriptionProductInfoAsync()
		return {}
	end
	function MS:GetUserSubscriptionStatusAsync()
		return { IsSubscribed = false, IsRenewing = false }
	end
	for _, n in { "PromptProductPurchase", "PromptGamePassPurchase", "PromptPremiumPurchase", "PromptPurchase", "PromptBundlePurchase", "PromptSubscriptionPurchase" } do
		MS[n] = function(_self, _p, id)
			C.addLog("info", "MarketplaceService:" .. n .. "(" .. tostring(id) .. ")", C.where(2))
		end
	end

	local PS = methods("PolicyService")
	function PS:GetPolicyInfoForPlayerAsync(_p)
		local fx = Svc.config.fixture
		return {
			ArePaidRandomItemsRestricted = fx.paidRandomRestricted == true,
			AllowedExternalLinkReferences = { "Discord", "YouTube", "Twitch", "Facebook", "X" },
			IsPaidItemTradingAllowed = true,
			IsSubjectToChinaPolicies = false,
			IsContentSharingAllowed = true,
			IsEligibleToPurchaseSubscription = true,
			AreAdsAllowed = true,
		}
	end
	function PS:CanViewBrandProjectAsync()
		return true
	end

	local lg = getters("LocalizationService")
	lg.RobloxLocaleId = function()
		return Svc.config.locale
	end
	lg.SystemLocaleId = function()
		return Svc.config.locale
	end
	local LS = methods("LocalizationService")
	function LS:GetCountryRegionForPlayerAsync()
		return "US"
	end
	function LS:GetTranslatorForPlayerAsync()
		local tr = I.new("Translator", { src = {} })
		return tr
	end
	LS.GetTranslatorForPlayer = LS.GetTranslatorForPlayerAsync
	LS.GetTranslatorForLocaleAsync = LS.GetTranslatorForPlayerAsync
	local TR = methods("Translator")
	function TR:Translate(_ctx, text)
		return text
	end
	function TR:FormatByKey(key)
		return key
	end
	getters("Translator").LocaleId = function()
		return Svc.config.locale
	end

	local TX = methods("TextService")
	function TX:GetTextSize(text, size, font, frame)
		local key = T.fontKey(roblox.Font.fromEnum(if C.typeof(font) == "EnumItem" then font else E.Font.SourceSans))
		local wrap = frame and frame.X < 1e5 and frame.X or nil
		local w, h = T.bounds(tostring(text), key, size, wrap)
		return V2.new(math.ceil(w), math.ceil(h))
	end
	function TX:GetTextBoundsAsync(params)
		local key = T.fontKey(params.Font)
		local wrap = params.Width and params.Width > 0 and params.Width < 1e5 and params.Width or nil
		local text = params.Text or ""
		if params.RichText then
			text = T.stripRich(text)
		end
		local w, h = T.bounds(text, key, params.Size or 14, wrap)
		return V2.new(math.ceil(w), math.ceil(h))
	end
	function TX:FilterStringAsync(text)
		local r = I.new("TextFilterResult", { src = {} })
		S[r].data.text = text
		return r
	end
	function TX:GetFamilyInfoAsync()
		return { Name = "Font", Faces = {} }
	end
	local TF = methods("TextFilterResult")
	function TF:GetNonChatStringForBroadcastAsync()
		return S[self].data.text
	end
	TF.GetNonChatStringForUserAsync = TF.GetNonChatStringForBroadcastAsync
	TF.GetChatForUserAsync = TF.GetNonChatStringForBroadcastAsync

	local serde = require("@lune/serde")
	local HS = methods("HttpService")
	function HS:JSONEncode(v)
		return serde.encode("json", v)
	end
	function HS:JSONDecode(s)
		return serde.decode("json", s)
	end
	local guidN = 0
	function HS:GenerateGUID(braces)
		guidN += 1
		local s = string.format("%08X-0000-4000-8000-%012X", guidN, guidN * 7919)
		if braces ~= false then
			s = "{" .. s .. "}"
		end
		return s
	end
	function HS:UrlEncode(s)
		return (string.gsub(tostring(s), "[^%w%-_%.~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end
	function HS:GetAsync()
		C.rterror("Http requests are not enabled. Enable via game settings")
	end
	HS.PostAsync = HS.GetAsync
	HS.RequestAsync = HS.GetAsync

	local SS = methods("SocialService")
	function SS:CanSendGameInviteAsync()
		return true
	end
	function SS:PromptGameInvite()
		C.addLog("info", "SocialService:PromptGameInvite", C.where(2))
	end
	function SS:CanSendCallInviteAsync()
		return false
	end
	function SS:GetEventRsvpStatusAsync()
		return E.RsvpStatus.None
	end
	local EN = methods("ExperienceNotificationService")
	function EN:CanPromptOptInAsync()
		return false
	end
	local AD = methods("AdService")
	function AD:GetAdAvailabilityNowAsync()
		return { AdAvailabilityResult = E.AdAvailabilityResult.NoFill }
	end
	local GS = methods("GroupService")
	function GS:GetGroupInfoAsync(id)
		return { Name = "Group " .. tostring(id), Id = id, Owner = { Name = "Owner", Id = 1 }, MemberCount = 1234 }
	end
	function GS:GetGroupsAsync()
		return {}
	end
	function GS:PromptJoinAsync()
		C.addLog("info", "GroupService:PromptJoinAsync", C.where(2))
		return E.GroupMembershipStatus.None
	end
	local BS = methods("BadgeService")
	function BS:AwardBadge()
		return true
	end
	function BS:UserHasBadgeAsync()
		return false
	end
	function BS:GetBadgeInfoAsync(id)
		return { Name = "Badge " .. tostring(id), Description = "", IconImageId = 0, IsEnabled = true }
	end
	function BS:CheckUserBadgesAsync()
		return {}
	end
	local an = C.classInfo("AnalyticsService")
	if an then
		I.quiet.AnalyticsService = {}
		for f in an.funcs do
			I.quiet.AnalyticsService[f] = true
		end
	end
	local MG = methods("MessagingService")
	function MG:SubscribeAsync(_topic, _fn)
		return C.newSignal("msg"):Connect(function() end)
	end
	function MG:PublishAsync() end
	local DB = methods("Debris")
	function DB:AddItem(inst, t)
		C.delay(t or 10, function()
			if I.isInstance(inst) then
				I.destroy(inst)
			end
		end)
	end
	local CP = methods("ContentProvider")
	function CP:PreloadAsync(_list, cb) end
	getters("ContentProvider").RequestQueueSize = function()
		return 0
	end
	quiet("PhysicsService", { "RegisterCollisionGroup", "CollisionGroupSetCollidable", "CreateCollisionGroup", "SetPartCollisionGroup", "UnregisterCollisionGroup", "RenameCollisionGroup" })
	local PHS = methods("PhysicsService")
	function PHS:IsCollisionGroupRegistered()
		return false
	end
	function PHS:CollisionGroupsAreCollidable()
		return true
	end
	function PHS:GetRegisteredCollisionGroups()
		return {}
	end
	quiet("Sound", { "Play", "Stop", "Pause", "Resume" })
	quiet("SoundService", { "PlayLocalSound", "SetListener" })
	quiet("ParticleEmitter", { "Emit", "Clear" })
	quiet("Explosion", {})
	quiet("TeleportService", { "SetTeleportGui" })
	quiet("ProximityPrompt", { "InputHoldBegin", "InputHoldEnd" })
	local TPS = methods("TeleportService")
	function TPS:TeleportAsync()
		C.addLog("info", "TeleportService:TeleportAsync", C.where(2))
	end
	TPS.Teleport = TPS.TeleportAsync
	function TPS:GetLocalPlayerTeleportData()
		return nil
	end
	function TPS:ReserveServer()
		return "code", "id"
	end
	local TCS = methods("TextChatService")
	function TCS:DisplayBubble() end
	function TCS:CanUsersChatAsync()
		return true
	end
	function TCS:CanUserChatAsync()
		return true
	end
	local TCH = methods("TextChannel")
	function TCH:DisplaySystemMessage(msg)
		C.addLog("info", "system chat: " .. tostring(msg), C.where(2))
	end
	function TCH:SendAsync() end
	function TCH:AddUserAsync()
		return nil, true
	end
	local VC = methods("VoiceChatService")
	function VC:IsVoiceEnabledForUserIdAsync()
		return false
	end
	local PF = methods("PathfindingService")
	function PF:CreatePath()
		return I.new("Path", { src = {} })
	end
	quiet("Path", { "ComputeAsync" })
	local PA = methods("Path")
	function PA:GetWaypoints()
		return {}
	end
	getters("Path").Status = function()
		return E.PathStatus.NoPath
	end
end

------------------------------------------------------------------------------------------
-- DataStores (fixture profile for the player key in the "mid" state)
------------------------------------------------------------------------------------------
do
	local stores = {}
	local function storeFor(name, scope, ordered)
		local k = (if ordered then "O:" else "D:") .. tostring(name) .. "/" .. tostring(scope or "global")
		local s = stores[k]
		if not s then
			s = I.new(if ordered then "OrderedDataStore" else "DataStore", { name = tostring(name), src = {} })
			S[s].data.values = {}
			S[s].data.ordered = ordered
			S[s].data.storeName = tostring(name)
			stores[k] = s
		end
		return s
	end
	local DSS = methods("DataStoreService")
	function DSS:GetDataStore(name, scope)
		return storeFor(name, scope, false)
	end
	function DSS:GetGlobalDataStore()
		return storeFor("global", nil, false)
	end
	function DSS:GetOrderedDataStore(name, scope)
		return storeFor(name, scope, true)
	end
	function DSS:GetRequestBudgetForRequestType()
		return 1000
	end
	function DSS:ListDataStoresAsync()
		return Svc.pages({})
	end

	local function fixtureValue(store, key)
		local fx = Svc.config.fixture
		local st = S[store]
		if st.data.ordered then
			return nil
		end
		if fx.profileStore == st.data.storeName and Svc.config.state == "mid" and fx.midProfile
			and string.find(tostring(key), tostring(Svc.config.userId), 1, true) then
			local mp = fx.midProfile
			if type(mp) == "function" then
				mp = mp(Svc.fixtureHelpers)
			end
			return mp
		end
		local ds = fx.datastore
		if type(ds) == "function" then
			return ds(st.data.storeName, key, Svc.config.state)
		end
		return nil
	end

	local function get(store, key)
		local vals = S[store].data.values
		if vals[key] == nil then
			local fv = fixtureValue(store, key)
			if fv ~= nil then
				vals[key] = fv
			end
		end
		local v = vals[key]
		if v == nil then
			return nil
		end
		return remoteCopy(v, {}, "ds", nil, false)
	end
	local DS = methods("GlobalDataStore")
	local function keyInfo()
		return { Version = "1", CreatedTime = 0, UpdatedTime = 0, GetUserIds = function()
			return {}
		end, GetMetadata = function()
			return {}
		end }
	end
	function DS:GetAsync(key)
		C.wait(0.05)
		return get(self, key), keyInfo()
	end
	function DS:SetAsync(key, value)
		C.wait(0.02)
		S[self].data.values[key] = remoteCopy(value, {}, "ds", nil, false)
		return "1"
	end
	function DS:UpdateAsync(key, fn)
		C.wait(0.05)
		local cur = get(self, key)
		local new = fn(cur, keyInfo())
		if new ~= nil then
			S[self].data.values[key] = remoteCopy(new, {}, "ds", nil, false)
		end
		return new, keyInfo()
	end
	function DS:IncrementAsync(key, delta)
		local cur = get(self, key) or 0
		cur += delta or 1
		S[self].data.values[key] = cur
		return cur
	end
	function DS:RemoveAsync(key)
		local cur = get(self, key)
		S[self].data.values[key] = nil
		return cur
	end
	function DS:ListKeysAsync()
		return Svc.pages({})
	end
	local ODS = methods("OrderedDataStore")
	function ODS:GetSortedAsync(_asc, size)
		local fx = Svc.config.fixture
		local rows = {}
		if fx.leaderboard then
			for i, r in fx.leaderboard do
				if i > (size or 100) then
					break
				end
				table.insert(rows, { key = r.key, value = r.value })
			end
		end
		return Svc.pages(rows)
	end
end

------------------------------------------------------------------------------------------
-- CollectionService
------------------------------------------------------------------------------------------
do
	local added, removed = {}, {}
	local CS = methods("CollectionService")
	function CS:GetTagged(tag)
		local out = {}
		for inst in I.all do
			local st = S[inst]
			if st.tags[tag] and not st.destroyed and st.parent then
				table.insert(out, inst)
			end
		end
		table.sort(out, function(a, b)
			return S[a].id < S[b].id
		end)
		return out
	end
	function CS:GetInstanceAddedSignal(tag)
		added[tag] = added[tag] or C.newSignal("TagAdded " .. tag)
		return added[tag]
	end
	function CS:GetInstanceRemovedSignal(tag)
		removed[tag] = removed[tag] or C.newSignal("TagRemoved " .. tag)
		return removed[tag]
	end
	function CS:AddTag(inst, tag)
		I.methods.Instance.AddTag(inst, tag)
	end
	function CS:RemoveTag(inst, tag)
		I.methods.Instance.RemoveTag(inst, tag)
	end
	function CS:HasTag(inst, tag)
		return S[inst].tags[tag] == true
	end
	function CS:GetTags(inst)
		return I.methods.Instance.GetTags(inst)
	end
	function CS:GetAllTags()
		return {}
	end
	I.onTag = function(inst, tag, on)
		local s = if on then added[tag] else removed[tag]
		if s then
			s:Fire(inst)
		end
	end
end

------------------------------------------------------------------------------------------
-- GUI: approximate live measurements (the authoritative layout is done in Python)
------------------------------------------------------------------------------------------
local function screenRect(sg)
	local sc = Svc.config.screen
	local st = S[sg]
	local ignore = st.props.IgnoreGuiInset == true
	local insets = st.props.ScreenInsets or E.ScreenInsets.CoreUISafeInsets
	if ignore or insets == E.ScreenInsets.None then
		return 0, 0, sc.w, sc.h
	end
	local ins = sc.insets
	if insets == E.ScreenInsets.DeviceSafeInsets then
		return ins.left, 0, sc.w - ins.left - ins.right, sc.h - ins.bottom
	end
	return ins.left, ins.top, sc.w - ins.left - ins.right, sc.h - ins.top - ins.bottom
end
Svc.screenRect = screenRect

local function guiParent(inst)
	local cur = S[inst].parent
	while cur do
		local info = S[cur].info
		if info.isA.GuiBase2d then
			return cur
		end
		if info.isA.BasePlayerGui or info.isA.DataModel then
			return nil
		end
		cur = S[cur].parent
	end
	return nil
end

local function contentBox(inst)
	-- returns x, y, w, h of the area children are laid out in (after UIPadding)
	local st = S[inst]
	local x, y, w, h
	if st.info.isA.LayerCollector then
		if st.info.isA.ScreenGui then
			x, y, w, h = screenRect(inst)
		else
			local sz = V2.new(100, 100)
			x, y, w, h = 0, 0, sz.X, sz.Y
		end
	else
		local ax, ay, aw, ah = Svc.absRect(inst)
		x, y, w, h = ax, ay, aw, ah
		if st.info.isA.ScrollingFrame then
			local cs = st.props.CanvasSize or roblox.UDim2.new(0, 0, 2, 0)
			w = cs.X.Scale * aw + cs.X.Offset
			h = cs.Y.Scale * ah + cs.Y.Offset
			if w <= 0 then
				w = aw
			end
			if h <= 0 then
				h = ah
			end
		end
	end
	for _, c in st.children do
		if S[c].className == "UIPadding" then
			local p = S[c].props
			local l = p.PaddingLeft or roblox.UDim.new()
			local r = p.PaddingRight or roblox.UDim.new()
			local t = p.PaddingTop or roblox.UDim.new()
			local b = p.PaddingBottom or roblox.UDim.new()
			local pl, pr = l.Scale * w + l.Offset, r.Scale * w + r.Offset
			local pt, pb = t.Scale * h + t.Offset, b.Scale * h + b.Offset
			x += pl
			y += pt
			w -= pl + pr
			h -= pt + pb
		end
	end
	return x, y, math.max(w, 0), math.max(h, 0)
end

function Svc.absRect(inst, depth)
	depth = (depth or 0) + 1
	if depth > 60 then
		return 0, 0, 0, 0
	end
	local st = S[inst]
	if st.info.isA.ScreenGui then
		return screenRect(inst)
	end
	local parent = guiParent(inst)
	local px, py, pw, ph
	if parent then
		px, py, pw, ph = contentBox(parent)
	else
		return 0, 0, 0, 0
	end
	local size = inst.Size
	local pos = inst.Position
	local ap = inst.AnchorPoint
	local w = size.X.Scale * pw + size.X.Offset
	local h = size.Y.Scale * ph + size.Y.Offset
	local sc = st.props.SizeConstraint
	if sc == E.SizeConstraint.RelativeXX then
		h = size.Y.Scale * pw + size.Y.Offset
	elseif sc == E.SizeConstraint.RelativeYY then
		w = size.X.Scale * ph + size.X.Offset
	end
	for _, c in st.children do
		local cst = S[c]
		if cst.className == "UIAspectRatioConstraint" then
			local ar = cst.props.AspectRatio or 1
			if ar > 0 then
				if w / math.max(h, 1e-6) > ar then
					w = h * ar
				else
					h = w / ar
				end
			end
		elseif cst.className == "UISizeConstraint" then
			local mn = cst.props.MinSize or V2.zero
			local mx = cst.props.MaxSize or V2.new(math.huge, math.huge)
			w = math.clamp(w, mn.X, math.max(mn.X, mx.X))
			h = math.clamp(h, mn.Y, math.max(mn.Y, mx.Y))
		end
	end
	local x = px + pos.X.Scale * pw + pos.X.Offset - ap.X * w
	local y = py + pos.Y.Scale * ph + pos.Y.Offset - ap.Y * h
	return x, y, math.max(w, 0), math.max(h, 0)
end

do
	local g = getters("GuiBase2d")
	g.AbsoluteSize = function(self)
		local _, _, w, h = Svc.absRect(self)
		return V2.new(w, h)
	end
	g.AbsolutePosition = function(self)
		local x, y = Svc.absRect(self)
		return V2.new(x, y)
	end
	g.AbsoluteRotation = function(self)
		return self.Rotation or 0
	end
	local lg = getters("LayerCollector")
	lg.AbsoluteSize = function(self)
		if S[self].info.isA.ScreenGui then
			local _, _, w, h = screenRect(self)
			return V2.new(w, h)
		end
		return V2.new(100, 100)
	end
	lg.AbsolutePosition = function(self)
		if S[self].info.isA.ScreenGui then
			local x, y = screenRect(self)
			return V2.new(x, y)
		end
		return V2.zero
	end
	local sf = getters("ScrollingFrame")
	sf.AbsoluteCanvasSize = function(self)
		local _, _, w, h = contentBox(self)
		return V2.new(w, h)
	end
	sf.AbsoluteWindowSize = function(self)
		local _, _, w, h = Svc.absRect(self)
		return V2.new(w, h)
	end
	local function textBounds(self)
		local st = S[self]
		local key = T.fontKey(self.FontFace)
		local text = tostring(self.Text or "")
		if self.RichText then
			text = T.stripRich(text)
		end
		local _, _, bw, bh = Svc.absRect(self)
		local size = self.TextSize
		if self.TextScaled then
			size = T.scaledSize(text, key, bw, bh, true)
		end
		local w, h = T.bounds(text, key, size, if self.TextWrapped or self.TextScaled then bw else nil, self.LineHeight)
		if text == "" then
			w, h = 0, size
		end
		return w, h, bw, bh
	end
	for _, cls in { "TextLabel", "TextButton", "TextBox" } do
		local tg = getters(cls)
		tg.TextBounds = function(self)
			local w, h = textBounds(self)
			return V2.new(math.ceil(w), math.ceil(h))
		end
		tg.TextFits = function(self)
			local w, h, bw, bh = textBounds(self)
			return w <= bw + 0.5 and h <= bh + 0.5
		end
		tg.ContentText = function(self)
			local t = tostring(self.Text or "")
			return if self.RichText then T.stripRich(t) else t
		end
		tg.Font = function(self)
			local st = S[self]
			if st.data.fontEnum then
				return st.data.fontEnum
			end
			local fam = string.match(tostring(self.FontFace.Family), "families/([%w]+)%.json") or "Legacy"
			local ok, en = pcall(function()
				return E.Font[fam]
			end)
			if ok and en then
				return en
			end
			return E.Font.Legacy
		end
		setters(cls).Font = function(self, v)
			local item = v
			if type(v) == "string" then
				item = E.Font[v]
			elseif type(v) == "number" then
				for _, it in E.Font:GetEnumItems() do
					if it.Value == v then
						item = it
					end
				end
			end
			if C.typeof(item) ~= "EnumItem" or item.EnumType ~= E.Font then
				C.rterror("Unable to assign property Font. Font expected, got " .. C.typeof(v))
			end
			local st = S[self]
			st.data.fontEnum = item
			local ok, f = pcall(roblox.Font.fromEnum, item)
			if ok and f then
				st.props.FontFace = f
			end
			I.firePropChanged(self, "Font")
			I.firePropChanged(self, "FontFace")
		end
		setters(cls).FontFace = function(self, v)
			if C.typeof(v) ~= "Font" then
				C.rterror("Unable to assign property FontFace. Font expected, got " .. C.typeof(v))
			end
			S[self].props.FontFace = v
			S[self].data.fontEnum = nil
			I.firePropChanged(self, "FontFace")
		end
	end
	-- UIListLayout / UIGridLayout content size (sum of children along the axis)
	local function contentSize(self)
		local st = S[self]
		local parent = st.parent
		if not parent then
			return V2.zero
		end
		local items = {}
		for _, c in S[parent].children do
			local cst = S[c]
			if cst.info.isA.GuiObject and c.Visible then
				table.insert(items, c)
			end
		end
		if st.info.isA.UIGridLayout then
			local _, _, pw = contentBox(parent)
			local cell = self.CellSize
			local pad = self.CellPadding
			local cw = cell.X.Scale * pw + cell.X.Offset
			local ch = cell.Y.Scale * pw + cell.Y.Offset
			local cols = math.max(1, math.floor((pw + pad.X.Offset) / math.max(cw + pad.X.Offset, 1)))
			if self.FillDirectionMaxCells > 0 then
				cols = math.min(cols, self.FillDirectionMaxCells)
			end
			local rows = math.ceil(#items / cols)
			return V2.new(cols * cw + (cols - 1) * pad.X.Offset, rows * ch + math.max(rows - 1, 0) * pad.Y.Offset)
		end
		local vertical = self.FillDirection == E.FillDirection.Vertical
		local _, _, pw, ph = contentBox(parent)
		local pad = self.Padding
		local padPx = pad.Scale * (if vertical then ph else pw) + pad.Offset
		local total, cross = 0, 0
		for i, c in items do
			local _, _, w, h = Svc.absRect(c)
			if vertical then
				total += h
				cross = math.max(cross, w)
			else
				total += w
				cross = math.max(cross, h)
			end
			if i > 1 then
				total += padPx
			end
		end
		return if vertical then V2.new(cross, total) else V2.new(total, cross)
	end
	getters("UIGridStyleLayout").AbsoluteContentSize = contentSize
	getters("UIGridLayout").AbsoluteCellSize = function(self)
		local parent = S[self].parent
		local _, _, pw, ph = if parent then contentBox(parent) else 0, 0, 0, 0
		local cell = self.CellSize
		return V2.new(cell.X.Scale * pw + cell.X.Offset, cell.Y.Scale * ph + cell.Y.Offset)
	end
	getters("GuiButton").Selected = function(self)
		return S[self].props.Selected == true
	end
end

-- common quiet stubs on GUI objects
quiet("GuiObject", { "TweenSize", "TweenPosition", "TweenSizeAndPosition" })
do
	local GO = methods("GuiObject")
	local function tweenish(self, props, cb)
		for k, v in props do
			self[k] = v
		end
		if type(cb) == "function" then
			C.defer(cb, E.TweenStatus.Completed)
		end
		return true
	end
	function GO:TweenSize(size, _d, _s, _t, _o, cb)
		return tweenish(self, { Size = size }, cb)
	end
	function GO:TweenPosition(pos, _d, _s, _t, _o, cb)
		return tweenish(self, { Position = pos }, cb)
	end
	function GO:TweenSizeAndPosition(size, pos, _d, _s, _t, _o, cb)
		return tweenish(self, { Size = size, Position = pos }, cb)
	end
	local SF = methods("ScrollingFrame")
	function SF:ScrollToTop() end
	local TB = methods("TextBox")
	function TB:CaptureFocus() end
	function TB:ReleaseFocus() end
	function TB:IsFocused()
		return false
	end
	local UP = methods("UIPageLayout")
	function UP:JumpTo(page)
		S[self].props.CurrentPage = page
	end
	function UP:JumpToIndex(_i) end
	function UP:Next() end
	function UP:Previous() end
end

return Svc
