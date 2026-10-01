--!nocheck
-- uipreview PLAYTEST mode (runs inside the same mocked Roblox as the static preview).
--
--   PT.install(env)  before any game script runs: patches the mocks (physics, Touched,
--                    raycasts, DataStore tracking, MarketplaceService receipts, remote
--                    tracking, BindToClose, ...).
--   PT.run(env)      after the client booted: runs the per-game bot (playtests/<game>.luau)
--                    for N virtual minutes, checks invariants, leaves/rejoins, shuts the
--                    server down and returns the result table (written as JSON by main).
--
-- Everything here is an APPROXIMATION of Roblox (see README.md, "Playtest").
local serde = require("@lune/serde")

local PT = {}

local C, I, S, Svc, cfg, roblox, E, V3, CF
local findings = {} -- ordered list
local findingKeys = {}
local timeline = {} -- { t, label, stats }
local events = {} -- bot achievements: { t, msg }
local remoteStats = {} -- "Remote:action" -> { calls, ok, fail, slow, reasons = {reason -> n}, expectedFail }
local notices = {} -- server notices (Notify/Toast...) -> sample
local fireStats = {} -- remote event -> { server = n, client = n }
local dsStats = {} -- store/key -> { reads, writes, lastWriteT, lastWriteValue }
local dsWindow = { Get = {}, Set = {}, Update = {} }
local dsBudgetFlags = {}
local receipts = { granted = 0, replayed = 0, byId = {} }
local purchases = { mode = "grant", log = {} }
local closers = {}
local instanceSamples = {}
local gameLog = {} -- reserved
local spec = nil -- the bot's declarative part
local state = { endT = 0, finishing = false, botDone = false, leaves = {}, rejoins = 0 }
local touch = { watch = {}, inside = {} }
local walkers = {}
local partCache = { t = -1e9, list = {} }

local function round(x, n)
	local m = 10 ^ (n or 2)
	return math.floor(x * m + 0.5) / m
end

local function fmtT(t)
	return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end

------------------------------------------------------------------------------------------
-- findings / events
------------------------------------------------------------------------------------------
-- kind: stuck | invariant | reject | save | receipt | datastore | bot | tool | leak | physics
local function finding(kind, msg, key, where)
	key = key or (kind .. "|" .. msg)
	local f = findingKeys[key]
	if f then
		f.count += 1
		f.lastT = round(C.now, 1)
		return f
	end
	f = { kind = kind, msg = msg, t = round(C.now, 1), lastT = round(C.now, 1), count = 1, where = where or {} }
	findingKeys[key] = f
	table.insert(findings, f)
	return f
end
PT.finding = finding

local function event(msg)
	table.insert(events, { t = round(C.now, 1), msg = msg })
end

local function stackFrames(tb, firstLine)
	local frames = {}
	for line in string.gmatch(tb or "", "[^\n]+") do
		local f, l = string.match(line, "^%s*([^%s:]+%.luau?):(%d+)")
		if f and C.isGameSource(f) then
			local s = f .. ":" .. l
			if not table.find(frames, s) then
				table.insert(frames, s)
			end
		end
	end
	local loc = string.match(firstLine or "", "^([^%s:]+%.luau?:%d+):")
	if loc and not table.find(frames, loc) then
		table.insert(frames, 1, loc)
	end
	return frames
end

-- logs an error caught by the playtest (not by a dead coroutine) with the game's stack
local function logCaught(msg, tb, label, ctx)
	msg = string.gsub(tostring(msg), "^runtime error: ", "")
	local first = string.match(msg, "^[^\n]*") or msg
	local frames = stackFrames(tb or msg, first)
	C.addLog("error", first, frames, { label = label })
	local e = C.log[#C.log]
	if e and e.msg == first and ctx then
		e.ctx = ctx
	end
end

------------------------------------------------------------------------------------------
-- tiny helpers
------------------------------------------------------------------------------------------
local function rawPos(part)
	local p = S[part].props.CFrame
	if p then
		return p.Position
	end
	return S[part].props.Position or V3.zero
end

local function isNum(x)
	return type(x) == "number"
end

local function deepScan(v, path, out, seen, depth)
	local t = type(v)
	if t == "number" then
		if v ~= v then
			table.insert(out, { path = path, bad = "NaN" })
		elseif v == math.huge or v == -math.huge then
			table.insert(out, { path = path, bad = "inf" })
		end
	elseif t == "table" and depth < 8 and not seen[v] and not I.isInstance(v) then
		seen[v] = true
		for k, x in v do
			deepScan(x, path .. "." .. tostring(k), out, seen, depth + 1)
		end
	end
end

local function deepCopy(v, seen)
	if type(v) ~= "table" or I.isInstance(v) then
		return v
	end
	seen = seen or {}
	if seen[v] then
		return seen[v]
	end
	local o = {}
	seen[v] = o
	for k, x in v do
		o[k] = deepCopy(x, seen)
	end
	return o
end

local function inCtx(ctx, fn, ...)
	local co = coroutine.running()
	local old = C.threadCtx[co]
	C.threadCtx[co] = ctx
	local res = table.pack(xpcall(fn, function(e)
		return { msg = e, tb = debug.traceback(tostring(e), 2) }
	end, ...))
	C.threadCtx[co] = old
	return res
end

------------------------------------------------------------------------------------------
-- install: patches
------------------------------------------------------------------------------------------
local installPhysics, installRemotes, installData, installMarketplace

function PT.install(env)
	C, I, S, Svc, cfg, roblox = env.C, env.I, env.S, env.Svc, env.cfg, env.roblox
	E, V3, CF = roblox.Enum, roblox.Vector3, roblox.CFrame
	PT.env = env
	C.maxLog = 12000
	if cfg.epoch then
		C.epoch = cfg.epoch
	end
	C.dt = 1 / (cfg.fps or 30)
	local seed = cfg.seed or 1
	math.randomseed(seed)
	C.randVaried = true
	C.randBase = 1234567 + seed * 104729
	installPhysics()
	installRemotes()
	installData()
	installMarketplace()
end

------------------------------------------------------------------------------------------
-- physics: BasePart transform sync, models, humanoid walking, Touched, raycast, spawn
------------------------------------------------------------------------------------------
local function setCF(inst, cf)
	local st = S[inst]
	st.props.CFrame = cf
	st.props.Position = cf.Position
	st.data.xf = nil
	I.firePropChanged(inst, "CFrame")
	I.firePropChanged(inst, "Position")
end

local function eachPart(inst, fn)
	if S[inst].info.isA.BasePart then
		fn(inst)
	end
	I.eachDescendant(inst, function(d)
		if S[d].info.isA.BasePart then
			fn(d)
		end
	end)
end

local function modelBounds(model)
	local mn, mx
	eachPart(model, function(p)
		local cf = S[p].props.CFrame or CF.identity
		local sz = p.Size
		local hx = (math.abs(cf.XVector.X) * sz.X + math.abs(cf.YVector.X) * sz.Y + math.abs(cf.ZVector.X) * sz.Z) / 2
		local hy = (math.abs(cf.XVector.Y) * sz.X + math.abs(cf.YVector.Y) * sz.Y + math.abs(cf.ZVector.Y) * sz.Z) / 2
		local hz = (math.abs(cf.XVector.Z) * sz.X + math.abs(cf.YVector.Z) * sz.Y + math.abs(cf.ZVector.Z) * sz.Z) / 2
		local pos = cf.Position
		local lo = V3.new(pos.X - hx, pos.Y - hy, pos.Z - hz)
		local hi = V3.new(pos.X + hx, pos.Y + hy, pos.Z + hz)
		mn = if mn then V3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z)) else lo
		mx = if mx then V3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z)) else hi
	end)
	return mn, mx
end

local function getPivot(inst)
	local st = S[inst]
	if st.info.isA.BasePart then
		return st.props.CFrame or CF.identity
	end
	local pp = st.props.PrimaryPart
	if pp then
		return S[pp].props.CFrame or CF.identity
	end
	if st.data.pivot then
		return st.data.pivot
	end
	local mn, mx = modelBounds(inst)
	if mn then
		return CF.new((mn + mx) / 2)
	end
	return CF.identity
end

local function pivotTo(inst, cf)
	local st = S[inst]
	if st.info.isA.BasePart then
		setCF(inst, cf)
		return
	end
	local old = getPivot(inst)
	local delta = cf * old:Inverse()
	eachPart(inst, function(p)
		setCF(p, delta * (S[p].props.CFrame or CF.identity))
	end)
	st.data.pivot = cf
end

local R15 = {
	{ "Head", 0, 2.0, 0, 1.2, 1.2, 1.2 },
	{ "UpperTorso", 0, 0.5, 0, 2, 1.6, 1 },
	{ "LowerTorso", 0, -0.7, 0, 2, 0.4, 1 },
	{ "LeftUpperArm", -1.5, 0.8, 0, 1, 1.2, 1 },
	{ "LeftLowerArm", -1.5, -0.2, 0, 1, 1.1, 1 },
	{ "LeftHand", -1.5, -0.9, 0, 1, 0.3, 1 },
	{ "RightUpperArm", 1.5, 0.8, 0, 1, 1.2, 1 },
	{ "RightLowerArm", 1.5, -0.2, 0, 1, 1.1, 1 },
	{ "RightHand", 1.5, -0.9, 0, 1, 0.3, 1 },
	{ "LeftUpperLeg", -0.5, -1.3, 0, 1, 1.2, 1 },
	{ "LeftLowerLeg", -0.5, -2.3, 0, 1, 1.2, 1 },
	{ "LeftFoot", -0.5, -2.9, 0, 1, 0.3, 1 },
	{ "RightUpperLeg", 0.5, -1.3, 0, 1, 1.2, 1 },
	{ "RightLowerLeg", 0.5, -2.3, 0, 1, 1.2, 1 },
	{ "RightFoot", 0.5, -2.9, 0, 1, 0.3, 1 },
}

local function makeCharacter(name)
	local model = I.new("Model", { name = name, src = {} })
	local hrp = I.new("Part", { name = "HumanoidRootPart", src = {} })
	I.setParent(hrp, model)
	S[hrp].props.Size = V3.new(2, 2, 1)
	for _, d in R15 do
		local p = I.new("Part", { name = d[1], src = {} })
		S[p].props.Size = V3.new(d[5], d[6], d[7])
		I.setParent(p, model)
		S[p].data.rel = CF.new(d[2], d[3], d[4])
	end
	local hum = I.new("Humanoid", { name = "Humanoid", src = {} })
	I.setParent(hum, model)
	S[hum].props.Health = 100
	S[hum].props.MaxHealth = 100
	S[hum].props.WalkSpeed = 16
	local animator = I.new("Animator", { name = "Animator", src = {} })
	I.setParent(animator, hum)
	S[model].props.PrimaryPart = hrp
	local origin = CF.new(0, 5, 0)
	setCF(hrp, origin)
	for _, d in R15 do
		local p = I.findChild(model, d[1])
		setCF(p, origin * S[p].data.rel)
	end
	return model
end

local function findSpawn()
	local best
	I.eachDescendant(Svc.services.Workspace, function(d)
		local st = S[d]
		if st.className == "SpawnLocation" and not best and st.props.Enabled ~= false then
			best = d
		end
	end)
	return best
end

local function charParts(player)
	local ch = player and S[player].data.character
	if not ch or S[ch].destroyed then
		return nil
	end
	local hrp = I.findChild(ch, "HumanoidRootPart")
	local hum = I.findChild(ch, "Humanoid")
	return ch, hrp, hum
end
PT.charParts = charParts

local respawnPending = false
local function spawnCharacter(player)
	local st = S[player]
	local old = st.data.character
	if old then
		I.destroy(old)
	end
	local ch = makeCharacter(st.name)
	st.data.character = ch
	local sp = findSpawn()
	if sp then
		local pos = S[sp].props.CFrame.Position + V3.new(0, S[sp].props.Size.Y / 2 + 3, 0)
		pivotTo(ch, CF.new(pos))
	end
	I.setParent(ch, Svc.services.Workspace)
	I.firePropChanged(player, "Character")
	I.signal(player, "CharacterAdded"):Fire(ch)
	C.delay(0.1, function()
		I.signal(player, "CharacterAppearanceLoaded"):Fire(ch)
	end)
end

function installPhysics()
	local function bpSetters()
		I.setters.BasePart = I.setters.BasePart or {}
		return I.setters.BasePart
	end
	local bs = bpSetters()
	bs.CFrame = function(self, v)
		if C.typeof(v) ~= "CFrame" then
			C.rterror("Unable to assign property CFrame. CFrame expected, got " .. C.typeof(v))
		end
		setCF(self, v)
	end
	bs.Position = function(self, v)
		if C.typeof(v) ~= "Vector3" then
			C.rterror("Unable to assign property Position. Vector3 expected, got " .. C.typeof(v))
		end
		local cf = S[self].props.CFrame or CF.identity
		setCF(self, CF.fromMatrix(v, cf.XVector, cf.YVector, cf.ZVector))
	end
	bs.Orientation = function(self, v)
		local cf = S[self].props.CFrame or CF.identity
		setCF(self, CF.new(cf.Position) * CF.fromEulerAnglesYXZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
	end
	bs.Rotation = bs.Orientation
	local bg = I.getters.BasePart or {}
	I.getters.BasePart = bg
	bg.Orientation = function(self)
		local x, y, z = (S[self].props.CFrame or CF.identity):ToEulerAnglesYXZ()
		return V3.new(math.deg(x), math.deg(y), math.deg(z))
	end
	bg.Rotation = bg.Orientation

	local PV = I.methods.PVInstance
	PV.GetPivot = function(self)
		return getPivot(self)
	end
	PV.PivotTo = function(self, cf)
		pivotTo(self, cf)
	end
	local MD = I.methods.Model
	MD.MoveTo = function(self, pos)
		pivotTo(self, CF.new(pos) * (getPivot(self) - getPivot(self).Position))
	end
	MD.SetPrimaryPartCFrame = function(self, cf)
		pivotTo(self, cf)
	end
	MD.GetPrimaryPartCFrame = function(self)
		return getPivot(self)
	end
	MD.GetBoundingBox = function(self)
		local mn, mx = modelBounds(self)
		if not mn then
			return CF.identity, V3.zero
		end
		return CF.new((mn + mx) / 2), mx - mn
	end
	MD.GetExtentsSize = function(self)
		local mn, mx = modelBounds(self)
		return if mn then mx - mn else V3.zero
	end
	MD.TranslateBy = function(self, d)
		pivotTo(self, getPivot(self) + d)
	end

	-- Humanoid ---------------------------------------------------------------------
	local HM = I.methods.Humanoid
	local hs = I.setters.Humanoid or {}
	I.setters.Humanoid = hs
	local hg = I.getters.Humanoid or {}
	I.getters.Humanoid = hg
	local function kill(hum)
		local st = S[hum]
		if st.data.dead then
			return
		end
		st.data.dead = true
		I.signal(hum, "Died"):Fire()
		local ch = st.parent
		local pl
		for _, c in S[Svc.services.Players].children do
			if S[c].data.character == ch then
				pl = c
			end
		end
		if pl and Svc.services.Players.CharacterAutoLoads ~= false then
			local rt = Svc.services.Players.RespawnTime
			C.delay(if type(rt) == "number" then rt else 5, function()
				if S[pl].parent and S[pl].data.character == ch then
					C.threadCtx[coroutine.running()] = "server"
					spawnCharacter(pl)
				end
			end)
		end
	end
	hs.Health = function(self, v)
		if type(v) ~= "number" then
			C.rterror("Unable to assign property Health. number expected, got " .. C.typeof(v))
		end
		local st = S[self]
		local mx = st.props.MaxHealth or 100
		if v ~= v then
			v = 0
		end
		v = math.clamp(v, 0, mx)
		local old = st.props.Health
		st.props.Health = v
		if old ~= v then
			I.firePropChanged(self, "Health")
			I.signal(self, "HealthChanged"):Fire(v)
		end
		if v <= 0 then
			kill(self)
		end
	end
	HM.TakeDamage = function(self, n)
		local hum = self
		hum.Health = hum.Health - n
	end
	HM.MoveTo = function(self, pos, _part)
		local st = S[self]
		st.data.moveTarget = pos
		st.data.moveT0 = C.now
		walkers[self] = true
	end
	HM.Move = function(self, dir)
		S[self].data.moveDir = dir
	end
	HM.CancelMoveTo = function(self)
		S[self].data.moveTarget = nil
	end
	hg.MoveDirection = function(self)
		return S[self].data.lastDir or V3.zero
	end
	hg.RootPart = function(self)
		local ch = S[self].parent
		return ch and I.findChild(ch, "HumanoidRootPart")
	end
	hg.FloorMaterial = function()
		return E.Material.Plastic
	end
	hg.SeatPart = function()
		return nil
	end
	hg.WalkToPoint = function(self)
		return S[self].data.moveTarget or V3.zero
	end

	Svc.makeCharacter = makeCharacter
	Svc.spawnCharacter = spawnCharacter

	-- Touched / TouchEnded: watched parts are only the ones with connections ---------
	local origSignal = I.signal
	I.signal = function(inst, name)
		local st = S[inst]
		local s = st.signals[name]
		if s == nil then
			s = origSignal(inst, name)
			if name == "Touched" or name == "TouchEnded" or name == "StoppedTouching" then
				s.onConnect = function()
					touch.watch[inst] = true
				end
			end
		end
		return s
	end

	-- Raycast against block approximations of parts ----------------------------------
	local function partList()
		if C.now - partCache.t > 0.5 then
			local list = {}
			for inst in I.all do
				local st = S[inst]
				if st.info.isA.BasePart and not st.destroyed and st.parent and st.props.CanQuery ~= false then
					table.insert(list, inst)
				end
			end
			partCache = { t = C.now, list = list }
		end
		return partCache.list
	end
	local function underWorkspace(inst)
		local cur = inst
		local ws = Svc.services.Workspace
		while cur do
			if cur == ws then
				return true
			end
			cur = S[cur].parent
		end
		return false
	end
	local function rayBox(part, o, d, maxT)
		local st = S[part]
		local cf = st.props.CFrame or CF.identity
		local sz = st.props.Size or V3.new(4, 1, 2)
		local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(d)
		local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
		local tmin, tmax = 0, maxT
		local nAxis, nSign = nil, 1
		local O = { lo.X, lo.Y, lo.Z }
		local D = { ld.X, ld.Y, ld.Z }
		local H = { hx, hy, hz }
		for a = 1, 3 do
			if math.abs(D[a]) < 1e-9 then
				if math.abs(O[a]) > H[a] then
					return nil
				end
			else
				local t1, t2 = (-H[a] - O[a]) / D[a], (H[a] - O[a]) / D[a]
				local sgn = -1
				if t1 > t2 then
					t1, t2 = t2, t1
					sgn = 1
				end
				if t1 > tmin then
					tmin = t1
					nAxis, nSign = a, sgn
				end
				tmax = math.min(tmax, t2)
				if tmin > tmax then
					return nil
				end
			end
		end
		if not nAxis then
			return nil -- origin inside the box
		end
		local n = { 0, 0, 0 }
		n[nAxis] = nSign
		return tmin, cf:VectorToWorldSpace(V3.new(n[1], n[2], n[3]))
	end
	local function filtered(part, params)
		if not params then
			return false
		end
		local list = params.FilterDescendantsInstances or {}
		local inList = false
		for _, f in list do
			if f == part or (I.isInstance(f) and I.isAncestor(f, part)) then
				inList = true
				break
			end
		end
		if params.FilterType == E.RaycastFilterType.Include then
			return not inList
		end
		return inList
	end
	local W = I.methods.Workspace
	W.Raycast = function(_self, origin, dir, params)
		local len = dir.Magnitude
		if len < 1e-6 then
			return nil
		end
		local d = dir / len
		local bestT, bestP, bestN
		for _, part in partList() do
			local st = S[part]
			if not st.destroyed and underWorkspace(part) and not filtered(part, params) then
				if not (params and params.RespectCanCollide and st.props.CanCollide == false) then
					local pos = (st.props.CFrame or CF.identity).Position
					local sz = st.props.Size or V3.new(4, 1, 2)
					local r = sz.Magnitude / 2
					local rel = pos - origin
					local proj = rel:Dot(d)
					local perp2 = rel:Dot(rel) - proj * proj
					if proj > -r and proj < len + r and perp2 <= r * r then
						local t, n = rayBox(part, origin, d, len)
						if t and (not bestT or t < bestT) then
							bestT, bestP, bestN = t, part, n
						end
					end
				end
			end
		end
		if not bestT then
			return nil
		end
		return {
			Instance = bestP,
			Position = origin + d * bestT,
			Normal = bestN,
			Material = E.Material.Plastic,
			Distance = bestT,
		}
	end

	-- PlayerGui:GetGuiObjectsAtPosition (approximate: the Luau-side layout ignores UIListLayout)
	I.methods.BasePlayerGui = I.methods.BasePlayerGui or {}
	local PGM = I.methods.BasePlayerGui
	PGM.GetGuiObjectsAtPosition = function(self, x, y)
		local out = {}
		local function visibleChain(g)
			local cur = g
			while cur and cur ~= self do
				local st = S[cur]
				if st.info.isA.GuiObject and cur.Visible == false then
					return false
				end
				if st.info.isA.LayerCollector and cur.Enabled == false then
					return false
				end
				cur = st.parent
			end
			return true
		end
		I.eachDescendant(self, function(d)
			local st = S[d]
			if st.info.isA.GuiObject and visibleChain(d) then
				local ax, ay, aw, ah = Svc.absRect(d)
				if aw > 0 and ah > 0 and x >= ax and x <= ax + aw and y >= ay and y <= ay + ah then
					table.insert(out, d)
				end
			end
		end)
		table.sort(out, function(a, b)
			return (S[a].props.ZIndex or 1) > (S[b].props.ZIndex or 1)
		end)
		return out
	end

	-- Camera projection ---------------------------------------------------------------
	local CM = I.methods.Camera
	local function V2or(_cam)
		return roblox.Vector2.new(Svc.config.screen.w, Svc.config.screen.h)
	end
	local function project(cam, p)
		local vp = V2or(cam)
		local cf = cam.CFrame
		local rel = cf:PointToObjectSpace(p)
		local depth = -rel.Z
		local fov = math.rad(cam.FieldOfView)
		local th = math.tan(fov / 2)
		local aspect = vp.X / vp.Y
		local ndcX = rel.X / (math.max(depth, 1e-4) * th * aspect)
		local ndcY = rel.Y / (math.max(depth, 1e-4) * th)
		local x = (ndcX + 1) / 2 * vp.X
		local y = (1 - ndcY) / 2 * vp.Y
		return V3.new(x, y, depth), depth > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
	end
	CM.WorldToViewportPoint = function(self, p)
		return project(self, p)
	end
	CM.WorldToScreenPoint = function(self, p)
		local v, on = project(self, p)
		local inset = Svc.config.screen.insets.top
		return V3.new(v.X, v.Y - inset, v.Z), on
	end
	CM.ViewportPointToRay = function(self, x, y)
		local vp = V2or(self)
		local th = math.tan(math.rad(self.FieldOfView) / 2)
		local aspect = vp.X / vp.Y
		local nx, ny = (x / vp.X) * 2 - 1, 1 - (y / vp.Y) * 2
		local dirLocal = V3.new(nx * th * aspect, ny * th, -1).Unit
		local cf = self.CFrame
		return roblox.Ray.new(cf.Position, cf:VectorToWorldSpace(dirLocal))
	end
	CM.ScreenPointToRay = function(self, x, y)
		return CM.ViewportPointToRay(self, x, y + Svc.config.screen.insets.top)
	end
end

-- per-frame physics: humanoid walking (every frame) + Touched (every 0.1 s)
local lastTouchT = -1
local function physicsFrame()
	local dt = C.dt
	for hum in walkers do
		local st = S[hum]
		if st.destroyed or not st.parent then
			walkers[hum] = nil
		else
			local tgt = st.data.moveTarget
			local ch = st.parent
			local hrp = ch and I.findChild(ch, "HumanoidRootPart")
			if tgt and hrp and not st.data.dead then
				local pos = rawPos(hrp)
				local speed = st.props.WalkSpeed or 16
				local d = tgt - pos
				local flat = V3.new(d.X, 0, d.Z)
				local step = speed * dt
				local newPos
				if flat.Magnitude <= step and math.abs(d.Y) <= 40 * dt then
					newPos = tgt
					st.data.moveTarget = nil
					st.data.lastDir = V3.zero
					walkers[hum] = nil
					pivotTo(ch, CF.new(newPos) * (getPivot(ch) - getPivot(ch).Position))
					I.signal(hum, "MoveToFinished"):Fire(true)
				else
					local dir = if flat.Magnitude > 1e-6 then flat.Unit else V3.zero
					local move = dir * math.min(step, flat.Magnitude)
					local dy = math.clamp(d.Y, -80 * dt, 40 * dt)
					newPos = pos + move + V3.new(0, dy, 0)
					st.data.lastDir = dir
					local look = if dir.Magnitude > 0 then CF.lookAt(newPos, newPos + dir) else getPivot(ch)
					pivotTo(ch, CF.new(newPos) * (look - look.Position))
					if C.now - st.data.moveT0 > 8 + (flat.Magnitude / math.max(speed, 1)) then
						st.data.moveTarget = nil
						walkers[hum] = nil
						I.signal(hum, "MoveToFinished"):Fire(false)
					end
				end
			else
				walkers[hum] = nil
			end
		end
	end
	if C.now - lastTouchT >= 0.1 then
		lastTouchT = C.now
		local player = Svc.player
		local ch, hrp, hum = charParts(player)
		if ch and hrp and not S[hum].data.dead then
			local cp = rawPos(hrp)
			local center = cp - V3.new(0, 0.5, 0)
			local cx, cy, cz = 2, 3.0, 1.5
			for part in touch.watch do
				local st = S[part]
				if st.destroyed or not st.parent then
					touch.watch[part] = nil
					touch.inside[part] = nil
				elseif st.props.CanTouch ~= false then
					local cf = st.props.CFrame or CF.identity
					local sz = st.props.Size or V3.new(4, 1, 2)
					local pos = cf.Position
					local r = sz.Magnitude / 2 + 6
					local dx, dy, dz = pos.X - center.X, pos.Y - center.Y, pos.Z - center.Z
					local overlap = false
					if dx * dx + dy * dy + dz * dz <= r * r then
						local lp = cf:PointToObjectSpace(center)
						-- the character box (world-aligned) projected on each of the part's axes
						local xv, yv, zv = cf.XVector, cf.YVector, cf.ZVector
						local rx = cx * math.abs(xv.X) + cy * math.abs(xv.Y) + cz * math.abs(xv.Z)
						local ry = cx * math.abs(yv.X) + cy * math.abs(yv.Y) + cz * math.abs(yv.Z)
						local rz = cx * math.abs(zv.X) + cy * math.abs(zv.Y) + cz * math.abs(zv.Z)
						overlap = math.abs(lp.X) <= sz.X / 2 + rx + 0.05
							and math.abs(lp.Y) <= sz.Y / 2 + ry + 0.05
							and math.abs(lp.Z) <= sz.Z / 2 + rz + 0.05
					end
					local was = touch.inside[part]
					if overlap and not was then
						touch.inside[part] = true
						local s = st.signals.Touched
						if s then
							s:Fire(hrp)
						end
					elseif was and not overlap then
						touch.inside[part] = nil
						for _, n in { "TouchEnded", "StoppedTouching" } do
							local s = st.signals[n]
							if s then
								s:Fire(hrp)
							end
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- remotes: tracking, error capture with stack, notices
------------------------------------------------------------------------------------------
local function reasonOf(v)
	if v == nil then
		return "?"
	end
	if type(v) == "table" then
		return tostring(v.key or v.reason or v.err or v.error or v.msg or v.message or "table")
	end
	return tostring(v)
end

local function recordRequest(remote, args, res, dur)
	local action = if type(args[1]) == "string" then args[1] else "?"
	local key = remote .. ":" .. action
	local rs = remoteStats[key]
	if not rs then
		rs = { calls = 0, ok = 0, fail = 0, expected = 0, slow = 0, reasons = {}, maxDur = 0, firstFailT = nil }
		remoteStats[key] = rs
	end
	rs.calls += 1
	rs.maxDur = math.max(rs.maxDur, dur)
	if dur > 5 then
		rs.slow += 1
	end
	local first = res[1]
	local failed = first == false
	local reason
	if failed then
		reason = reasonOf(res[2])
	elseif type(first) == "table" and (first.ok == false or first.success == false) then
		failed = true
		reason = reasonOf(first)
	end
	if failed then
		if PT.expectFail then
			rs.expected += 1
		else
			rs.fail += 1
			rs.reasons[reason] = (rs.reasons[reason] or 0) + 1
			rs.firstFailT = rs.firstFailT or round(C.now, 1)
			rs.samples = rs.samples or {}
			if #rs.samples < 6 then
				local p = args[2]
				local desc = {}
				if type(p) == "table" then
					for k, v in p do
						if type(v) ~= "table" then
							table.insert(desc, tostring(k) .. "=" .. tostring(v))
						end
					end
					table.sort(desc)
				end
				table.insert(rs.samples, string.format("t=%d %s(%s) -> %s", math.floor(C.now), action, table.concat(desc, ","), reason))
			end
		end
	else
		rs.ok += 1
	end
end

function installRemotes()
	local RF = I.methods.RemoteFunction
	RF.InvokeServer = function(self, ...)
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
		local args = table.pack(...)
		for i = 1, args.n do
			args[i] = Svc.remoteCopy(args[i], {}, "arg" .. i, C.where(2), false)
		end
		local t0 = C.now
		local res = inCtx("server", st.callbacks.OnServerInvoke, Svc.player, table.unpack(args, 1, args.n))
		if not res[1] then
			local e = res[2]
			local msg = if type(e) == "table" then e.msg else e
			logCaught(msg, if type(e) == "table" then e.tb else nil, "OnServerInvoke " .. st.name, "server")
			recordRequest(st.name, args, { false, "server error" }, C.now - t0)
			error("Server script error in " .. st.name, 0)
		end
		local out = table.pack(table.unpack(res, 2, res.n))
		recordRequest(st.name, args, out, C.now - t0)
		for i = 1, out.n do
			out[i] = Svc.remoteCopy(out[i], {}, "res" .. i, nil, false)
		end
		return table.unpack(out, 1, out.n)
	end

	local RE = I.methods.RemoteEvent
	local origFireClient = RE.FireClient
	local origFireServer = RE.FireServer
	local function fstat(name)
		local f = fireStats[name]
		if not f then
			f = { server = 0, client = 0 }
			fireStats[name] = f
		end
		return f
	end
	RE.FireClient = function(self, player, ...)
		local name = S[self].name
		fstat(name).client += 1
		if string.find(name, "Notify") or string.find(name, "Toast") or string.find(name, "Message") then
			local a, b = ...
			local text = reasonOf(a)
			local kind = if type(b) == "string" then b else (if type(a) == "table" and a.kind then tostring(a.kind) else "info")
			local k = name .. "|" .. kind .. "|" .. text
			local n = notices[k]
			if n then
				n.count += 1
			else
				notices[k] = { remote = name, kind = kind, text = text, count = 1, t = round(C.now, 1) }
			end
		end
		return origFireClient(self, player, ...)
	end
	RE.FireServer = function(self, ...)
		fstat(S[self].name).server += 1
		return origFireServer(self, ...)
	end
	I.methods.UnreliableRemoteEvent = RE
end

------------------------------------------------------------------------------------------
-- DataStore: validation (what real DataStores reject), budgets, write tracking
------------------------------------------------------------------------------------------
local function dsInvalid(v, path, seen, depth)
	local t = type(v)
	if t == "number" then
		if v ~= v then
			return path .. ": cannot store NaN"
		elseif v == math.huge or v == -math.huge then
			return path .. ": cannot store inf"
		end
		return nil
	elseif t == "string" then
		if utf8.len(v) == nil then
			return path .. ": string is not valid UTF-8"
		end
		return nil
	elseif t == "boolean" or t == "nil" then
		return nil
	elseif t == "table" then
		if I.isInstance(v) then
			return path .. ": cannot store an Instance"
		end
		if seen[v] then
			return path .. ": cyclic table"
		end
		if depth > 64 then
			return path .. ": too deep"
		end
		seen[v] = true
		local nNum, nStr, maxN, cnt = 0, 0, 0, 0
		for k in v do
			cnt += 1
			if type(k) == "number" then
				nNum += 1
				maxN = math.max(maxN, k)
				if k ~= math.floor(k) or k < 1 then
					return path .. ": numeric key " .. tostring(k) .. " is not a valid array index"
				end
			elseif type(k) == "string" then
				nStr += 1
				if utf8.len(k) == nil then
					return path .. ": key is not valid UTF-8"
				end
			else
				return path .. ": invalid key type " .. typeof(k)
			end
		end
		if nNum > 0 and nStr > 0 then
			return path .. ": mixed table (array + dictionary keys)"
		end
		if nNum > 0 and maxN ~= nNum then
			return path .. ": array with holes (" .. nNum .. " entries, max index " .. maxN .. "): cannot store sparse array / numeric-key dictionary"
		end
		for k, x in v do
			local bad = dsInvalid(x, path .. "." .. tostring(k), seen, depth + 1)
			if bad then
				return bad
			end
		end
		seen[v] = nil
		return nil
	end
	return path .. ": cannot store a " .. C.typeof(v)
end

local function dsRecordBudget(kind)
	local w = dsWindow[kind]
	local now = C.now
	table.insert(w, now)
	while w[1] and now - w[1] > 60 do
		table.remove(w, 1)
	end
	local players = #(S[Svc.services.Players].children)
	local cap = 60 + 10 * math.max(players, 1)
	if #w > cap then
		local f = finding("datastore", string.format("DataStore %s budget exceeded: %d requests in 60 s (limit %d with %d player)", kind, #w, cap, players), "dsbudget|" .. kind)
		f.where = C.where(3)
	end
	return cap - #w
end

function installData()
	local DS = I.methods.GlobalDataStore
	local ODS = I.methods.OrderedDataStore
	local function stat(store, key)
		local k = S[store].data.storeName .. "/" .. tostring(key)
		local st = dsStats[k]
		if not st then
			st = { reads = 0, writes = 0, store = S[store].data.storeName, key = tostring(key) }
			dsStats[k] = st
		end
		return st
	end
	local function checkKey(key, fn)
		if type(key) ~= "string" then
			C.rterror("invalid argument #2 to '" .. fn .. "' (string expected, got " .. typeof(key) .. ")")
		end
		if #key > 50 then
			C.rterror("104: Key name exceeds 50 character limit (" .. #key .. ")")
		end
	end
	local function checkValue(v, fn, key)
		local bad = dsInvalid(v, "value", {}, 0)
		if bad then
			local f = finding("datastore", fn .. "('" .. tostring(key) .. "'): " .. bad, "dsinvalid|" .. fn .. "|" .. bad)
			f.where = C.where(3)
			C.rterror("104: Cannot store " .. bad .. " in data store. Data stores can only accept valid UTF-8 characters.")
		end
		local ok, enc = pcall(serde.encode, "json", v)
		if ok and #enc > 4194304 then
			finding("datastore", fn .. ": value of " .. #enc .. " bytes exceeds the 4 MB limit", "dssize")
			C.rterror("105: Serialized value exceeds 4MB limit.")
		end
		if ok and #enc > 2000000 then
			finding("datastore", fn .. ": value of " .. #enc .. " bytes is over 2 MB (limit 4 MB)", "dssize-warn")
		end
	end
	local origGet, origSet, origUpdate, origInc, origRemove = DS.GetAsync, DS.SetAsync, DS.UpdateAsync, DS.IncrementAsync, DS.RemoveAsync
	DS.GetAsync = function(self, key)
		checkKey(key, "GetAsync")
		dsRecordBudget("Get")
		stat(self, key).reads += 1
		return origGet(self, key)
	end
	DS.SetAsync = function(self, key, value, ...)
		checkKey(key, "SetAsync")
		checkValue(value, "SetAsync", key)
		dsRecordBudget("Set")
		local r = origSet(self, key, value, ...)
		local st = stat(self, key)
		st.writes += 1
		st.lastWriteT = C.now
		return r
	end
	DS.UpdateAsync = function(self, key, fn)
		checkKey(key, "UpdateAsync")
		if type(fn) ~= "function" then
			C.rterror("invalid argument #3 to 'UpdateAsync' (function expected)")
		end
		dsRecordBudget("Update")
		local before = S[self].data.values[key]
		local wrapped = function(old, info)
			local newV, a, b = fn(old, info)
			if newV ~= nil then
				checkValue(newV, "UpdateAsync", key)
			end
			return newV, a, b
		end
		local a, b = origUpdate(self, key, wrapped)
		local st = stat(self, key)
		st.reads += 1
		if S[self].data.values[key] ~= before then
			st.writes += 1
			st.lastWriteT = C.now
		end
		return a, b
	end
	DS.IncrementAsync = function(self, key, d)
		checkKey(key, "IncrementAsync")
		dsRecordBudget("Set")
		local r = origInc(self, key, d)
		local st = stat(self, key)
		st.writes += 1
		st.lastWriteT = C.now
		return r
	end
	DS.RemoveAsync = function(self, key)
		checkKey(key, "RemoveAsync")
		dsRecordBudget("Set")
		return origRemove(self, key)
	end
	local origBudget = I.methods.DataStoreService.GetRequestBudgetForRequestType
	I.methods.DataStoreService.GetRequestBudgetForRequestType = function(_self, t)
		local name = tostring(t)
		local kind = if string.find(name, "Update") then "Update" elseif string.find(name, "Get") then "Get" else "Set"
		local w = dsWindow[kind]
		local now = C.now
		while w[1] and now - w[1] > 60 do
			table.remove(w, 1)
		end
		local players = #(S[Svc.services.Players].children)
		return math.max(0, 60 + 10 * math.max(players, 1) - #w)
	end
	local _ = origBudget
	local _o = ODS

	-- game:BindToClose
	I.methods.DataModel.BindToClose = function(_self, fn)
		table.insert(closers, { fn = fn, ctx = C.currentCtx() })
	end
end

PT.dsStats = dsStats

local function storedFor(storeName, key)
	-- finds the DataStore instance by name and returns its stored value (raw, shared reference)
	for inst in I.all do
		local st = S[inst]
		if st.data.values and st.data.storeName == storeName then
			return st.data.values[key], st
		end
	end
	return nil
end

------------------------------------------------------------------------------------------
-- MarketplaceService: purchases that really call ProcessReceipt
------------------------------------------------------------------------------------------
local receiptN = 0
local function makeReceipt(productId, robux)
	receiptN += 1
	return {
		PlayerId = Svc.config.userId,
		PlaceIdWherePurchased = Svc.config.fixture.placeId or 1818,
		PurchaseId = string.format("playtest-%06d-%d", receiptN, productId),
		ProductId = productId,
		CurrencyType = E.CurrencyType.Robux,
		CurrencySpent = robux or 99,
	}
end

local function callProcessReceipt(receipt)
	local ms = Svc.services.MarketplaceService
	local cb = ms and S[ms].callbacks.ProcessReceipt
	if not cb then
		finding("receipt", "MarketplaceService.ProcessReceipt was never set (a purchase would stay unprocessed)", "noreceipt")
		return nil
	end
	local res = inCtx("server", cb, receipt)
	if not res[1] then
		local e = res[2]
		logCaught(if type(e) == "table" then e.msg else e, if type(e) == "table" then e.tb else nil, "ProcessReceipt", "server")
		finding("receipt", "ProcessReceipt threw an error for product " .. receipt.ProductId .. ": " .. tostring(if type(e) == "table" then e.msg else e), "receipterr|" .. receipt.ProductId)
		return nil
	end
	return res[2]
end

-- Delivers a developer-product purchase like Roblox would (after the prompt is accepted).
-- `snapshot()` (optional) returns a table of numbers to prove the replay granted nothing.
function PT.deliverProduct(productId, snapshot)
	local receipt = makeReceipt(productId)
	local before = snapshot and snapshot()
	local r1 = callProcessReceipt(receipt)
	table.insert(purchases.log, { t = round(C.now, 1), product = productId, result = tostring(r1) })
	if r1 == E.ProductPurchaseDecision.PurchaseGranted then
		receipts.granted += 1
		local mid = snapshot and snapshot()
		-- Roblox may retry a receipt (server restart, timeout): replay the same PurchaseId
		local r2 = callProcessReceipt(receipt)
		receipts.replayed += 1
		local after = snapshot and snapshot()
		if r2 ~= E.ProductPurchaseDecision.PurchaseGranted then
			finding("receipt", "replayed receipt (same PurchaseId) for product " .. productId .. " returned " .. tostring(r2) .. " instead of PurchaseGranted: Roblox would keep retrying", "replayres|" .. productId)
		end
		if mid and after then
			for k, v in mid do
				-- the save inside ProcessReceipt yields, so the bot may earn a little meanwhile: only a change as big as
				-- the first grant counts as a double grant
				local firstGrant = if before and type(before[k]) == "number" then math.abs(v - before[k]) else 0
				if type(v) == "number" and type(after[k]) == "number" and after[k] ~= v and firstGrant > 0 and math.abs(after[k] - v) >= firstGrant * 0.5 then
					finding("receipt", string.format("RECEIPT GRANTED TWICE: product %d replayed with the same PurchaseId changed %s from %s to %s", productId, k, tostring(v), tostring(after[k])), "double|" .. productId .. "|" .. k)
				end
			end
		end
		if before and mid then
			local changed = false
			for k, v in mid do
				if before[k] ~= v then
					changed = true
				end
			end
			purchases.log[#purchases.log].changed = changed
		end
	end
	local ms = Svc.services.MarketplaceService
	if ms then
		I.signal(ms, "PromptProductPurchaseFinished"):Fire(Svc.config.userId, productId, r1 == E.ProductPurchaseDecision.PurchaseGranted)
	end
	return r1
end

function installMarketplace()
	local MS = I.methods.MarketplaceService
	local function deferred(fn)
		C.delay(0.8, function()
			C.threadCtx[coroutine.running()] = "server"
			fn()
		end)
	end
	MS.PromptProductPurchase = function(_self, _player, id)
		C.addLog("info", "MarketplaceService:PromptProductPurchase(" .. tostring(id) .. ") mode=" .. purchases.mode, C.where(2))
		table.insert(purchases.log, { t = round(C.now, 1), prompt = id, mode = purchases.mode })
		if purchases.mode == "grant" then
			deferred(function()
				PT.deliverProduct(id, PT.snapshot)
			end)
		else
			deferred(function()
				I.signal(Svc.services.MarketplaceService, "PromptProductPurchaseFinished"):Fire(Svc.config.userId, id, false)
			end)
		end
	end
	MS.PromptGamePassPurchase = function(_self, player, id)
		C.addLog("info", "MarketplaceService:PromptGamePassPurchase(" .. tostring(id) .. ") mode=" .. purchases.mode, C.where(2))
		table.insert(purchases.log, { t = round(C.now, 1), promptPass = id, mode = purchases.mode })
		deferred(function()
			local ok = purchases.mode == "grant"
			if ok then
				local fx = Svc.config.fixture
				fx.ownedPasses = fx.ownedPasses or {}
				if not table.find(fx.ownedPasses, id) then
					table.insert(fx.ownedPasses, id)
				end
			end
			I.signal(Svc.services.MarketplaceService, "PromptGamePassPurchaseFinished"):Fire(player, id, ok)
		end)
	end
	MS.PromptPremiumPurchase = function(_self, _p)
		C.addLog("info", "MarketplaceService:PromptPremiumPurchase", C.where(2))
	end
end

------------------------------------------------------------------------------------------
-- Players leaving / joining, server shutdown
------------------------------------------------------------------------------------------
local function playerCount()
	return #(S[Svc.services.Players].children)
end

-- Leaves like a real disconnect: PlayerRemoving, then Parent = nil right after the
-- synchronous part of the handlers. Handlers keep running (they yield on DataStore calls).
local function leavePlayer(player)
	-- the client of the player that leaves stops existing right away (threads + connections)
	C.clientGen += 1
	I.signal(Svc.services.Players, "PlayerRemoving"):Fire(player)
	C.flushDeferred()
	local ch = S[player].data.character
	I.setParent(player, nil)
	if ch and not S[ch].destroyed then
		I.destroy(ch)
	end
	-- Roblox destroys the Player (and its PlayerGui / Backpack) when it leaves
	I.destroy(player)
end

-- numeric top-level fields that differ between two profile tables
local IGNORE_DIFF = { savedAt = true, playTime = true, lock = true, lastSeen = true, lastSave = true, t = true }
local function diffProfiles(a, b)
	local out = {}
	for k, v in a do
		if type(v) == "number" and not IGNORE_DIFF[k] then
			-- b > a is just income earned between the snapshot and the (yielding) save; only a smaller saved value is lost progress
			if type(b[k]) ~= "number" or b[k] < v - 1e-6 then
				table.insert(out, string.format("%s: memoria=%s guardado=%s", k, tostring(v), tostring(b[k])))
			end
		end
	end
	table.sort(out)
	return out
end

local function checkSaved(label, preProfile, key, storeName)
	local stored = storedFor(storeName, key)
	if not stored then
		finding("save", label .. ": nothing was written to the DataStore for " .. key .. " (profile NOT saved)", "save|" .. label)
		return false
	end
	if preProfile then
		local d = diffProfiles(preProfile, stored)
		if #d > 0 then
			finding("save", label .. ": saved data differs from the profile in memory when leaving: " .. table.concat(d, "; "), "savediff|" .. label)
			return false
		end
	end
	return true
end

------------------------------------------------------------------------------------------
-- invariants
------------------------------------------------------------------------------------------
local function runInvariants()
	if not spec then
		return
	end
	local prof
	if spec.profile then
		local ok, p = pcall(spec.profile, PT.bot)
		if ok then
			prof = p
		end
	end
	if type(prof) == "table" then
		local bad = {}
		deepScan(prof, "profile", bad, {}, 0)
		for _, b in bad do
			finding("invariant", "profile contains " .. b.bad .. " at " .. b.path, "nan|" .. b.path)
		end
		for _, k in spec.currencyKeys or {} do
			local v = prof[k]
			if type(v) == "number" and v < 0 then
				finding("invariant", string.format("currency '%s' is negative on the server: %s", k, tostring(v)), "neg|" .. k)
			end
		end
		for _, k in spec.nonDecreasing or {} do
			local v = prof[k]
			state.maxSeen = state.maxSeen or {}
			if type(v) == "number" then
				local prev = state.maxSeen[k]
				if prev and v < prev - 1e-9 and not state.allowDecrease then
					finding("invariant", string.format("'%s' went down from %s to %s without a reset action", k, tostring(prev), tostring(v)), "dec|" .. k)
				end
				state.maxSeen[k] = math.max(prev or v, v)
			end
		end
	end
	if spec.clientState then
		local ok, cs = pcall(spec.clientState, PT.bot)
		if ok and type(cs) == "table" then
			local bad = {}
			deepScan(cs, "clientState", bad, {}, 0)
			for _, b in bad do
				finding("invariant", "client snapshot contains " .. b.bad .. " at " .. b.path, "cnan|" .. b.path)
			end
			for _, k in spec.currencyKeys or {} do
				local v = cs[k]
				if type(v) == "number" and v < 0 then
					finding("invariant", string.format("client shows negative '%s': %s", k, tostring(v)), "cneg|" .. k)
				end
			end
		end
	end
	for _, k in { "currencyKeys" } do
		local _ = k
	end
end

local stuckState = {}
local function runStuck()
	if not spec or not spec.stuck then
		return
	end
	for _, w in spec.stuck do
		local ok, active = pcall(w.active or function()
			return true
		end, PT.bot)
		local ok2, sig = pcall(w.sig, PT.bot)
		if ok and ok2 then
			local s = stuckState[w.name]
			if not s then
				s = { sig = nil, since = C.now, flagged = false }
				stuckState[w.name] = s
			end
			local sigS = tostring(sig)
			local proxy = nil
			if w.proxy then
				local okp, pv = pcall(w.proxy, PT.bot)
				proxy = if okp then tostring(pv) else nil
			end
			if not active or s.sig ~= sigS then
				s.sig = sigS
				s.since = C.now
				s.flagged = false
				s.proxy0 = proxy
			elseif not s.flagged and C.now - s.since > (w.secs or 60) then
				s.flagged = true
				local detail = ""
				if w.detail then
					local okd, dd = pcall(w.detail, PT.bot)
					if okd and dd then
						detail = " | " .. tostring(dd)
					end
				end
				local msg = string.format("'%s' did not progress for %d s of virtual time (state: %s)%s", w.name, math.floor(C.now - s.since), sigS:sub(1, 160), detail)
				if w.proxy and proxy ~= s.proxy0 then
					-- the goal needs a long grind (a proxy such as power/reps keeps moving): slow, not frozen
					finding("pacing", msg .. " | the bot kept making measurable progress toward it (a long grind, not a freeze)", "pacing|" .. w.name)
				else
					finding("stuck", msg, "stuck|" .. w.name)
				end
			end
		end
	end
end

local function sampleInstances()
	local n, parts, gui = 0, 0, 0
	I.eachDescendant(Svc.game, function(d)
		local st = S[d]
		n += 1
		if st.info.isA.BasePart then
			parts += 1
		elseif st.info.isA.GuiObject then
			gui += 1
		end
	end)
	table.insert(instanceSamples, { t = round(C.now, 1), total = n, parts = parts, gui = gui })
end

local function sampleStats(label)
	local row = { t = round(C.now, 1), label = label or "" }
	if spec and spec.stats then
		local ok, st = pcall(spec.stats, PT.bot)
		if ok and type(st) == "table" then
			row.stats = st
		elseif not ok then
			row.err = tostring(st)
		end
	end
	table.insert(timeline, row)
	return row
end

------------------------------------------------------------------------------------------
-- The bot API
------------------------------------------------------------------------------------------
local function makeBot(env)
	local bot = {}
	local ctxApi = env.ctx
	local DT = C.DT
	bot.game = cfg.gameName
	bot.seed = cfg.seed or 1
	bot.rng = DT.Random.new(1000 + bot.seed * 31)
	bot.ctx = ctxApi
	bot.E = E
	bot.V3 = V3
	bot.CF = CF
	bot.pt = PT
	bot.minutes = cfg.minutes or 10
	bot.state = cfg.state

	function bot.now()
		return C.now
	end
	function bot.alive()
		return C.now < state.endT and not state.finishing
	end
	function bot.remaining()
		return state.endT - C.now
	end
	function bot.wait(s)
		return C.wait(s or 0)
	end
	function bot.log(msg)
		event(msg)
	end
	function bot.finding(kind, msg, key)
		return finding(kind, msg, key)
	end
	function bot.bug(msg, key, where)
		return finding("bug", msg, key, where)
	end
	function bot.player()
		return Svc.player
	end
	function bot.char()
		local ch, hrp, hum = charParts(Svc.player)
		return ch, hrp, hum
	end
	function bot.hrp()
		local _, hrp = charParts(Svc.player)
		return hrp
	end
	function bot.client(path)
		return ctxApi.client(path)
	end
	function bot.shared(path)
		return ctxApi.shared(path)
	end
	function bot.server(path)
		local cur
		for _, c in S[Svc.services.ServerScriptService].children do
			cur = c
			break
		end
		-- paths are relative to the first child of ServerScriptService when it is a Folder/Script container
		local root = cur
		for part in string.gmatch(path, "[^%.]+") do
			local nxt = root and I.findChild(root, part)
			if not nxt and root == cur then
				nxt = I.findChild(Svc.services.ServerScriptService, part)
				root = nxt
			else
				root = nxt
			end
			if not root then
				error("bot.server: no module " .. path)
			end
		end
		return env.requireInCtx(root, "server")
	end
	function bot.find(name, root)
		return ctxApi.find(name, root)
	end
	function bot.findButton(pattern, root, plain)
		return ctxApi.findButton(pattern, root, plain)
	end

	-- visible = every ancestor GuiObject is Visible and the ScreenGui is Enabled
	function bot.isVisible(gui)
		local cur = gui
		while cur do
			local st = S[cur]
			if st.info.isA.GuiObject and cur.Visible == false then
				return false
			end
			if st.info.isA.ScreenGui or st.info.isA.LayerCollector then
				return cur.Enabled ~= false
			end
			cur = st.parent
		end
		return false
	end
	-- text of a button: its own Text, or the first descendant TextLabel/TextButton that has one
	function bot.buttonText(btn)
		local t = btn.Text
		if t and t ~= "" then
			return t
		end
		local found = ""
		I.eachDescendant(btn, function(x)
			if found == "" and (S[x].info.isA.TextLabel or S[x].info.isA.TextButton) then
				local xt = x.Text
				if xt and xt ~= "" then
					found = xt
				end
			end
		end)
		return found
	end
	-- visible GuiButtons under `root` whose text (see buttonText) matches the Lua pattern
	function bot.buttonsMatching(root, pattern)
		local out = {}
		I.eachDescendant(root, function(x)
			if S[x].info.isA.GuiButton and bot.isVisible(x) and string.find(bot.buttonText(x), pattern) then
				table.insert(out, x)
			end
		end)
		return out
	end
	function bot.click(btn, label)
		if not btn then
			finding("bot", "click(" .. tostring(label) .. "): button not found", "noclick|" .. tostring(label))
			return false
		end
		if not bot.isVisible(btn) then
			finding("bot", "click(" .. tostring(label or btn.Name) .. "): button exists but is hidden (a player could not press it)", "hidden|" .. tostring(label or btn.Name))
			return false
		end
		bot.try("click " .. tostring(label or btn.Name), ctxApi.click, btn)
		return true
	end
	function bot.try(label, fn, ...)
		local res = inCtx("client", fn, ...)
		if not res[1] then
			local e = res[2]
			local msg = if type(e) == "table" then e.msg else e
			logCaught(msg, if type(e) == "table" then e.tb else nil, label, "client")
			return false, msg
		end
		return true, table.unpack(res, 2, res.n)
	end
	function bot.tryServer(label, fn, ...)
		local res = inCtx("server", fn, ...)
		if not res[1] then
			local e = res[2]
			logCaught(if type(e) == "table" then e.msg else e, if type(e) == "table" then e.tb else nil, label, "server")
			return false
		end
		return true, table.unpack(res, 2, res.n)
	end

	function bot.waitUntil(fn, timeout, label)
		local t0 = C.now
		timeout = timeout or 10
		while C.now - t0 < timeout do
			local ok, v = pcall(fn)
			if ok and v then
				return v
			end
			C.wait(0.1)
			if not bot.alive() then
				return nil
			end
		end
		local ok, v = pcall(fn)
		if ok and v then
			return v
		end
		if label then
			if timeout >= 60 then
				finding("stuck", string.format("'%s' did not happen in %d s", label, timeout), "wait|" .. label)
			else
				finding("bot", string.format("timeout (%d s) waiting for '%s'", timeout, label), "timeout|" .. label)
			end
		end
		return nil
	end

	-- raw remotes -----------------------------------------------------------------
	local function remotesFolder()
		local rs = Svc.services.ReplicatedStorage
		return I.findChild(rs, "Remotes") or I.findChild(rs, "Net") or rs
	end
	function bot.remote(name)
		return I.findChild(remotesFolder(), name)
	end
	-- Request RemoteFunction with (action, payload...). Returns the raw results.
	function bot.request(action, ...)
		local rf = bot.remote("Request") or bot.remote("RF") or bot.remote("Remote")
		if not rf then
			error("bot.request: no Request RemoteFunction")
		end
		local res = table.pack(pcall(rf.InvokeServer, rf, action, ...))
		if not res[1] then
			return false, tostring(res[2])
		end
		return table.unpack(res, 2, res.n)
	end
	function bot.expectFail(fn, ...)
		PT.expectFail = true
		local res = table.pack(pcall(fn, ...))
		PT.expectFail = false
		if not res[1] then
			error(res[2], 0)
		end
		return table.unpack(res, 2, res.n)
	end
	function bot.fire(name, ...)
		local r = bot.remote(name)
		if not r then
			finding("bot", "fire('" .. name .. "'): remote not found", "nofire|" .. name)
			return
		end
		bot.try("FireServer " .. name, function(...)
			r:FireServer(...)
		end, ...)
	end
	local hooks = {}
	-- subscribes to a RemoteEvent's OnClientEvent; re-attaches itself after a rejoin
	function bot.on(name, fn)
		table.insert(hooks, { name = name, fn = fn })
		local r = bot.remote(name)
		if r then
			r.OnClientEvent:Connect(fn)
		end
	end
	function bot.rehook()
		for _, h in hooks do
			local r = bot.remote(h.name)
			if r then
				r.OnClientEvent:Connect(h.fn)
			end
		end
	end

	-- input ------------------------------------------------------------------------
	local function inputObject(utype, pos, keyCode)
		local obj = {
			UserInputType = utype,
			UserInputState = E.UserInputState.Begin,
			KeyCode = keyCode or E.KeyCode.Unknown,
			Position = V3.new(pos and pos.X or 0, pos and pos.Y or 0, 0),
			Delta = V3.zero,
		}
		function obj:IsModifierKeyDown()
			return false
		end
		return obj
	end
	function bot.pressKey(keyName, hold)
		local uis = Svc.services.UserInputService
		local key = E.KeyCode[keyName]
		local o = inputObject(E.UserInputType.Keyboard, nil, key)
		I.signal(uis, "InputBegan"):Fire(o, false)
		C.wait(hold or 0.05)
		local o2 = inputObject(E.UserInputType.Keyboard, nil, key)
		o2.UserInputState = E.UserInputState.End
		I.signal(uis, "InputEnded"):Fire(o2, false)
	end
	-- a tap/click on the screen at (x, y) (full-screen pixels minus the topbar inset, like InputObject.Position)
	function bot.tapAt(x, y, hold)
		local uis = Svc.services.UserInputService
		local touch = Svc.config.screen.touch
		local o = inputObject(if touch then E.UserInputType.Touch else E.UserInputType.MouseButton1, { X = x, Y = y })
		I.signal(uis, "InputBegan"):Fire(o, false)
		C.wait(hold or 0.03)
		local o2 = inputObject(if touch then E.UserInputType.Touch else E.UserInputType.MouseButton1, { X = x, Y = y })
		o2.UserInputState = E.UserInputState.End
		I.signal(uis, "InputEnded"):Fire(o2, false)
	end
	function bot.screen()
		return Svc.config.screen
	end

	-- character ---------------------------------------------------------------------
	function bot.pos()
		local _, hrp = charParts(Svc.player)
		return hrp and rawPos(hrp)
	end
	-- walks (Humanoid:MoveTo at WalkSpeed) and waits for MoveToFinished; returns reached
	function bot.walkTo(pos, timeout)
		local ch, hrp, hum = charParts(Svc.player)
		if not hum then
			return false
		end
		local done, ok = false, false
		local conn = I.signal(hum, "MoveToFinished"):Connect(function(reached)
			done, ok = true, reached
		end)
		hum:MoveTo(pos)
		local t0 = C.now
		while not done and C.now - t0 < (timeout or 60) and bot.alive() do
			C.wait(0.05)
			if S[hum].destroyed or S[hum].data.dead then
				break
			end
		end
		conn:Disconnect()
		return ok
	end
	function bot.teleport(cf)
		local ch = charParts(Svc.player)
		if ch then
			pivotTo(ch, cf)
		end
	end
	-- world-space top surface (centre) of a part, rotation aware
	function bot.topOf(part)
		local cf = part.CFrame
		local sz = part.Size
		local hy = (math.abs(cf.XVector.Y) * sz.X + math.abs(cf.YVector.Y) * sz.Y + math.abs(cf.ZVector.Y) * sz.Z) / 2
		return cf.Position + V3.new(0, hy, 0)
	end
	function bot.nearest(pred)
		local p = bot.pos()
		local best, bd
		I.eachDescendant(Svc.services.Workspace, function(d)
			if pred(d) then
				local dd = (rawPos(d) - p).Magnitude
				if not bd or dd < bd then
					best, bd = d, dd
				end
			end
		end)
		return best, bd
	end
	function bot.triggerPrompt(prompt)
		local p = bot.pos()
		local part = S[prompt].parent
		if part and S[part].info.isA.Attachment then
			part = S[part].parent
		end
		if not (part and p) then
			return false
		end
		if prompt.Enabled == false then
			return false
		end
		local d = (rawPos(part) - p).Magnitude
		if d > prompt.MaxActivationDistance + 2 then
			return false
		end
		I.signal(prompt, "PromptButtonHoldBegan"):Fire(Svc.player)
		C.wait(math.max(prompt.HoldDuration, 0))
		I.signal(prompt, "Triggered"):Fire(Svc.player)
		I.signal(prompt, "TriggerEnded"):Fire(Svc.player)
		return true
	end

	-- purchases ----------------------------------------------------------------------
	bot.purchases = purchases
	function bot.setPurchaseMode(m)
		purchases.mode = m
	end
	function bot.deliverProduct(id, snapshot)
		return PT.deliverProduct(id, snapshot or PT.snapshot)
	end
	function bot.grantPass(id)
		local fx = Svc.config.fixture
		fx.ownedPasses = fx.ownedPasses or {}
		if not table.find(fx.ownedPasses, id) then
			table.insert(fx.ownedPasses, id)
		end
	end

	-- rejoin: the driver (main thread) does the leave + save check + join, then resumes us
	function bot.rejoin(label)
		state.rejoinRequest = { co = coroutine.running(), label = label or "rejoin" }
		return coroutine.yield()
	end

	function bot.sample(label)
		return sampleStats(label)
	end
	-- true at most once every `secs` virtual seconds for this key (first call: true)
	local lastEvery = {}
	function bot.every(key, secs, first)
		local last = lastEvery[key]
		if last == nil then
			lastEvery[key] = C.now - (if first == false then 0 else secs)
			last = lastEvery[key]
		end
		if C.now - last >= secs then
			lastEvery[key] = C.now
			return true
		end
		return false
	end
	-- Wraps a client Net.request-like function: waits out "slow down" answers like a patient player
	-- (one retry), counts how often it had to.
	function bot.pace(requestFn, slowKey)
		return function(action, payload)
			local ok, res = requestFn(action, payload)
			if not ok and type(res) == "table" and res.key == (slowKey or "msg.slow_down") then
				bot.slowdowns = (bot.slowdowns or 0) + 1
				C.wait(1.2)
				ok, res = requestFn(action, payload)
			end
			return ok, res
		end
	end
	function bot.allowDecrease(v)
		state.allowDecrease = v
	end

	-- window helper: opens through the fixture (calls the game's own UI functions)
	function bot.openWindow(name)
		local fnOpen = env.fixture.windows and env.fixture.windows[name]
		if not fnOpen then
			finding("bot", "fixture has no window '" .. name .. "'", "nowin|" .. name)
			return false
		end
		return bot.try("open window " .. name, fnOpen, ctxApi)
	end
	function bot.windowNames()
		local out = {}
		for k in env.fixture.windows or {} do
			table.insert(out, k)
		end
		table.sort(out)
		return out
	end
	return bot
end

------------------------------------------------------------------------------------------
-- run
------------------------------------------------------------------------------------------
local function doRejoin(env, req)
	local bot = PT.bot
	local label = req.label
	local pre = nil
	if spec and spec.profile then
		local ok, p = pcall(spec.profile, bot)
		if ok and type(p) == "table" then
			pre = deepCopy(p)
		end
	end
	local player = Svc.player
	local tL = C.now
	event("rejoin: leaves (" .. label .. ")")
	leavePlayer(player)
	-- let the saves finish (retries + backoff can take a few seconds)
	C.run(12)
	local key = spec and spec.dsKey and spec.dsKey(Svc.config.userId)
	if key and spec.dsStore then
		checkSaved("rejoin '" .. label .. "'", pre, key, spec.dsStore)
		local st = dsStats[spec.dsStore .. "/" .. key]
		if st and st.lastWriteT and st.lastWriteT < tL then
			finding("save", "rejoin '" .. label .. "': no write to the DataStore after the player left", "nowrite|" .. label)
		end
	end
	-- leaked per-player tables (modules that export tracked(player))
	for mod, v in env.moduleCache.server do
		local val = v.value
		if type(val) == "table" and type(val.tracked) == "function" then
			local ok, n = pcall(val.tracked, player)
			if ok and type(n) == "number" and n > 0 then
				finding("leak", "a server module still tracks the player that left (tracked() = " .. n .. "): " .. tostring(I.fullName(mod)), "leak|" .. I.fullName(mod))
			end
		end
	end
	C.run(2)
	env.rejoinClient()
	state.rejoins += 1
	-- the profile is read the moment the server finished loading it (before the new character can pick
	-- anything up), then we wait for the new client to be ready (the bot spec says what ready means)
	local post
	if pre and spec.profile then
		local tl = C.now
		while C.now - tl < 15 do
			local okp, pp = pcall(spec.profile, bot)
			if okp and type(pp) == "table" then
				post = deepCopy(pp)
				break
			end
			C.step()
		end
	end
	local t0 = C.now
	if spec and spec.ready then
		while C.now - t0 < 60 do
			local ok, r = pcall(spec.ready, bot)
			if ok and r then
				break
			end
			C.run(0.5)
		end
		if C.now - t0 >= 60 then
			finding("stuck", "after rejoin the client was not ready after 60 s (spec.ready never became true)", "rejoinready|" .. label)
		end
	else
		C.run(8)
	end
	bot.rehook()
	if pre and spec.profile then
		if type(post) == "table" then
			local d = diffProfiles(pre, post)
			if #d > 0 then
				finding("save", "rejoin '" .. label .. "': the profile loaded after rejoining differs from the one in memory before leaving: " .. table.concat(d, "; "), "rejoindiff|" .. label)
			else
				event("rejoin ok: profile reloaded identical")
			end
		else
			finding("save", "rejoin '" .. label .. "': profile missing on the server after rejoin (15 s)", "rejoinmissing|" .. label)
		end
	end
end

function PT.run(env)
	local bot = makeBot(env)
	PT.bot = bot
	PT.snapshot = function()
		if spec and spec.snapshot then
			local ok, s = pcall(spec.snapshot, bot)
			if ok then
				return s
			end
		end
		return nil
	end

	-- load the bot spec
	local specFn = env.loadBot()
	local ok, res = pcall(specFn, bot)
	if not ok or type(res) ~= "table" then
		finding("tool", "bot script failed to load: " .. tostring(res), "botload")
		spec = {}
	else
		spec = res
	end

	local minutes = cfg.minutes or 10
	state.endT = C.now + minutes * 60
	local startT = C.now
	sampleStats("start")
	sampleInstances()

	-- the bot thread
	C.keepAlive = true
	local co = C.newThread(function()
		local r = inCtx("client", spec.run or function() end, bot)
		if not r[1] then
			local e = r[2]
			local msg = if type(e) == "table" then e.msg else e
			local tb = if type(e) == "table" then e.tb else ""
			-- an error in the bot's own code is a tool/bot bug, not a game error
			finding("bot", "bot script error: " .. tostring(msg) .. "\n" .. tostring(tb), "boterr|" .. tostring(msg))
		end
		state.botDone = true
		event("bot script finished" .. (if bot.alive() then " (early)" else ""))
	end, "bot", "client")
	C.keepAlive = false
	C.resume(co)

	local nextInv, nextSample, nextInst, nextStuck = C.now + 5, C.now + 30, C.now + 30, C.now + 5
	local frameCbs = C.frameCallbacks
	table.insert(frameCbs, physicsFrame)
	local clock = os.clock()
	while C.now < state.endT do
		C.step()
		if state.rejoinRequest then
			local req = state.rejoinRequest
			state.rejoinRequest = nil
			doRejoin(env, req)
			C.resume(req.co)
		end
		if C.now >= nextStuck then
			nextStuck = C.now + 5
			runStuck()
		end
		if C.now >= nextInv then
			nextInv = C.now + 5
			runInvariants()
		end
		if C.now >= nextSample then
			nextSample = C.now + 30
			sampleStats()
		end
		if C.now >= nextInst then
			nextInst = C.now + 30
			sampleInstances()
		end
	end
	state.finishing = true
	runInvariants()
	local finalRow = sampleStats("end")
	sampleInstances()

	-- final: the player leaves, the server shuts down (BindToClose)
	local pre = nil
	if spec.profile then
		local okp, p = pcall(spec.profile, bot)
		if okp and type(p) == "table" then
			pre = deepCopy(p)
		end
	end
	local player = Svc.player
	local tL = C.now
	leavePlayer(player)
	C.run(10)
	local key = spec.dsKey and spec.dsKey(Svc.config.userId)
	if key and spec.dsStore then
		checkSaved("leaving at the end", pre, key, spec.dsStore)
		local st = dsStats[spec.dsStore .. "/" .. key]
		if st and (not st.lastWriteT or st.lastWriteT < tL) then
			finding("save", "no write to the DataStore after the player left at the end of the session", "nowrite|end")
		end
	end
	for mod, v in env.moduleCache.server do
		local val = v.value
		if type(val) == "table" and type(val.tracked) == "function" then
			local okt, n = pcall(val.tracked, player)
			if okt and type(n) == "number" and n > 0 then
				finding("leak", "a server module still tracks the player that left (tracked() = " .. n .. "): " .. I.fullName(mod), "leak|" .. I.fullName(mod))
			end
		end
	end
	-- Roblox may deliver a receipt after the buyer left: the game must answer NotProcessedYet (never Granted)
	do
		local lastProd
		for i = #purchases.log, 1, -1 do
			if purchases.log[i].product then
				lastProd = purchases.log[i].product
				break
			end
		end
		if lastProd then
			local r = callProcessReceipt(makeReceipt(lastProd))
			if r == E.ProductPurchaseDecision.PurchaseGranted then
				finding("receipt", "ProcessReceipt returned PurchaseGranted for product " .. lastProd .. " when the buyer was no longer in the server (Roblox expects NotProcessedYet so it retries later)", "late-receipt")
			end
			event("late receipt for a player that left -> " .. tostring(r):gsub("Enum.ProductPurchaseDecision.", ""))
		end
	end
	local closing = 0
	for _, cl in closers do
		closing += 1
		local c = C.newThread(function()
			local r = inCtx("server", cl.fn)
			if not r[1] then
				local e = r[2]
				logCaught(if type(e) == "table" then e.msg else e, if type(e) == "table" then e.tb else nil, "BindToClose", "server")
			end
			closing -= 1
		end, "BindToClose", "server")
		C.resume(c)
	end
	local t0 = C.now
	while closing > 0 and C.now - t0 < 31 do
		C.run(0.5)
	end
	if closing > 0 then
		finding("save", "BindToClose handlers still running after 30 s (Roblox kills the server): " .. closing .. " pending", "bindtoclose")
	end

	-- results ----------------------------------------------------------------------
	local blocked = {}
	for cothread, b in C.blocked do
		if coroutine.status(cothread) == "suspended" and not b.soft then
			table.insert(blocked, { desc = b.desc, where = b.where, since = b.since })
		end
	end
	local rs = {}
	for k, v in remoteStats do
		table.insert(rs, {
			key = k, calls = v.calls, ok = v.ok, fail = v.fail, expected = v.expected, slow = v.slow,
			maxDur = round(v.maxDur, 2), reasons = v.reasons, firstFailT = v.firstFailT, samples = v.samples,
		})
	end
	table.sort(rs, function(a, b)
		return a.key < b.key
	end)
	local ds = {}
	for k, v in dsStats do
		table.insert(ds, { key = k, reads = v.reads, writes = v.writes, lastWriteT = v.lastWriteT and round(v.lastWriteT, 1) })
	end
	table.sort(ds, function(a, b)
		return a.key < b.key
	end)
	local nt = {}
	for _, n in notices do
		table.insert(nt, n)
	end
	table.sort(nt, function(a, b)
		return a.count > b.count
	end)
	local fs2 = {}
	for k, v in fireStats do
		table.insert(fs2, { remote = k, server = v.server, client = v.client })
	end
	table.sort(fs2, function(a, b)
		return a.remote < b.remote
	end)
	return {
		game = cfg.gameName,
		state = cfg.state,
		seed = cfg.seed or 1,
		minutes = minutes,
		virtualTime = C.now - startT,
		realSeconds = os.clock() - clock,
		log = C.log,
		findings = findings,
		timeline = timeline,
		events = events,
		remotes = rs,
		datastore = ds,
		notices = nt,
		fires = fs2,
		blocked = blocked,
		receipts = receipts,
		purchases = purchases.log,
		instances = instanceSamples,
		rejoins = state.rejoins,
		final = finalRow,
		summary = if spec.summary then (select(2, pcall(spec.summary, bot))) else nil,
	}
end

return PT
