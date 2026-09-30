--!nocheck
-- uipreview runtime core: log, virtual clock + scheduler, signals, the Instance mock
-- (reflection-checked against the Roblox API dump) and the datatypes Lune lacks.
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local C = {}
C.roblox = roblox
C.Enum = roblox.Enum

------------------------------------------------------------------------------------------
-- Log
------------------------------------------------------------------------------------------
C.log = {} :: { any }
local seenLog = {}
C.gamePrefix = "" -- e.g. "huerta-tycoon/" (sources of the game start with this)
C.maxLog = 4000

local function isGameSource(src: string?): boolean
	return src ~= nil and string.sub(src, 1, #C.gamePrefix) == C.gamePrefix and C.gamePrefix ~= ""
end
C.isGameSource = isGameSource

-- game frames of the current stack: { "file:line", ... }
function C.where(maxFrames: number?): { string }
	local out = {}
	local limit = maxFrames or 4
	for level = 2, 60 do
		local src, line = debug.info(level, "sl")
		if src == nil then
			break
		end
		if isGameSource(src) and line and line > 0 then
			table.insert(out, src .. ":" .. line)
			if #out >= limit then
				break
			end
		end
	end
	return out
end

function C.addLog(kind: string, msg: string, where: { string }?, extra: any?, dedupeKey: string?)
	local key = dedupeKey or (kind .. "|" .. msg .. "|" .. (where and where[1] or ""))
	local prev = seenLog[key]
	if prev then
		prev.count += 1
		return
	end
	if #C.log >= C.maxLog then
		return
	end
	local e = { kind = kind, msg = msg, where = where or {}, count = 1, t = C.now, ctx = C.currentCtx(), extra = extra }
	seenLog[key] = e
	table.insert(C.log, e)
end

-- Error raised by a mock on behalf of the engine: blames the first game frame.
function C.rterror(msg: string)
	local w = C.where(1)
	if w[1] then
		error(w[1] .. ": " .. msg, 0)
	end
	error(msg, 0)
end

------------------------------------------------------------------------------------------
-- Virtual clock & scheduler
------------------------------------------------------------------------------------------
C.now = 0 -- virtual seconds since start
C.epoch = os.time() -- unix time at virtual 0
C.frame = 0
C.dt = 1 / 30

local threadCtx = setmetatable({}, { __mode = "k" }) -- thread -> "server" | "client"
local threadLabel = setmetatable({}, { __mode = "k" })
C.threadCtx = threadCtx

function C.currentCtx(): string
	local co = coroutine.running()
	return threadCtx[co] or C.defaultCtx or "client"
end
C.defaultCtx = "client"

local sleeping = {} -- { {co, wake, args} }
local deferred = {} -- { {co, args} }
local cancelled = setmetatable({}, { __mode = "k" })
C.blocked = setmetatable({}, { __mode = "k" }) -- co -> description (WaitForChild etc)

local function report(co, err)
	local msg = tostring(err)
	msg = string.gsub(msg, "^runtime error: ", "")
	local first = string.match(msg, "^[^\n]*") or msg
	-- frames from the traceback that belong to the game
	local frames = {}
	for line in string.gmatch(msg, "[^\n]+") do
		local f, l = string.match(line, "^%s*([^%s:]+%.luau?):(%d+)")
		if f and isGameSource(f) then
			table.insert(frames, f .. ":" .. l)
		end
	end
	local tb = debug.traceback(co)
	for line in string.gmatch(tb or "", "[^\n]+") do
		local f, l = string.match(line, "^%s*([^%s:]+%.luau?):(%d+)")
		if f and isGameSource(f) then
			local s = f .. ":" .. l
			if not table.find(frames, s) then
				table.insert(frames, s)
			end
		end
	end
	local loc = string.match(first, "^([^%s:]+%.luau?:%d+):")
	if loc and not table.find(frames, loc) then
		table.insert(frames, 1, loc)
	end
	C.addLog("error", first, frames, { label = threadLabel[co] })
	local e = C.log[#C.log]
	if e and e.msg == first then
		e.ctx = threadCtx[co] or e.ctx
	end
end
C.reportError = report

function C.resume(co, ...)
	if cancelled[co] or coroutine.status(co) ~= "suspended" then
		return
	end
	C.blocked[co] = nil
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(co, err)
	end
end

function C.newThread(fn, label: string?, ctx: string?)
	local co = coroutine.create(fn)
	threadCtx[co] = ctx or C.currentCtx()
	threadLabel[co] = label
	return co
end

function C.spawn(fn, ...)
	local co
	if type(fn) == "thread" then
		co = fn
	else
		co = C.newThread(fn)
	end
	C.resume(co, ...)
	return co
end

function C.defer(fn, ...)
	local co = if type(fn) == "thread" then fn else C.newThread(fn)
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end

function C.delay(t, fn, ...)
	local co = if type(fn) == "thread" then fn else C.newThread(fn)
	table.insert(sleeping, { co = co, wake = C.now + (tonumber(t) or 0), args = table.pack(...) })
	return co
end

function C.wait(t)
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		C.rterror("task.wait called from a non-yieldable context")
	end
	local start = C.now
	local dur = math.max(tonumber(t) or 0, 0)
	table.insert(sleeping, { co = co, wake = C.now + dur, args = nil, start = start })
	coroutine.yield()
	return C.now - start, C.now
end

function C.cancel(co)
	cancelled[co] = true
	pcall(coroutine.close, co)
end

-- generic suspension: returns a resume function
function C.suspend(desc: string?)
	local co = coroutine.running()
	if desc then
		C.blocked[co] = { desc = desc, where = C.where(4), since = C.now }
	end
	return co
end

C.frameCallbacks = {} :: { () -> () } -- called each frame (RunService events)

function C.step()
	C.frame += 1
	C.now += C.dt
	for _, cb in C.frameCallbacks do
		cb()
	end
	-- wake sleepers
	local ready = {}
	local keep = {}
	for _, s in sleeping do
		if s.wake <= C.now + 1e-9 then
			table.insert(ready, s)
		else
			table.insert(keep, s)
		end
	end
	sleeping = keep
	table.sort(ready, function(a, b)
		return a.wake < b.wake
	end)
	for _, s in ready do
		if s.args then
			C.resume(s.co, table.unpack(s.args, 1, s.args.n))
		else
			C.resume(s.co, C.now - (s.start or 0), C.now)
		end
	end
	C.flushDeferred()
end

function C.flushDeferred()
	local guard = 0
	while #deferred > 0 and guard < 50 do
		guard += 1
		local list = deferred
		deferred = {}
		for _, d in list do
			C.resume(d.co, table.unpack(d.args, 1, d.args.n))
		end
	end
end

function C.run(seconds: number)
	local target = C.now + seconds
	while C.now < target - 1e-9 do
		C.step()
	end
end

------------------------------------------------------------------------------------------
-- Signals
------------------------------------------------------------------------------------------
local SignalMT = {}
SignalMT.__index = SignalMT
SignalMT.__tostring = function(s)
	return "Signal " .. (s.name or "")
end
local ConnMT = {}
ConnMT.__index = ConnMT
C.SignalMT = SignalMT
C.ConnMT = ConnMT

function C.newSignal(name: string?)
	return setmetatable({ name = name, conns = {}, waiting = {} }, SignalMT)
end

function ConnMT:Disconnect()
	self.Connected = false
	local s = self._signal
	local i = table.find(s.conns, self)
	if i then
		table.remove(s.conns, i)
	end
end
ConnMT.disconnect = ConnMT.Disconnect

function SignalMT:Connect(fn)
	if type(fn) ~= "function" then
		C.rterror("Attempt to connect failed: Passed value is not a function")
	end
	local c = setmetatable({ Connected = true, _fn = fn, _signal = self, _ctx = C.currentCtx() }, ConnMT)
	table.insert(self.conns, c)
	if self.onConnect then
		self.onConnect(c)
	end
	return c
end
SignalMT.connect = SignalMT.Connect
SignalMT.ConnectParallel = SignalMT.Connect

function SignalMT:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end

function SignalMT:Wait()
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		C.rterror("Signal:Wait called from a non-yieldable context")
	end
	table.insert(self.waiting, co)
	C.blocked[co] = { desc = "Wait on " .. (self.name or "signal"), where = C.where(3), since = C.now, soft = true }
	return coroutine.yield()
end
SignalMT.wait = SignalMT.Wait

local fireDepth = 0
function SignalMT:Fire(...)
	if fireDepth > 60 then
		C.addLog("warn", "signal re-entrancy depth > 60 (possible event loop) on " .. tostring(self.name), C.where(3))
		return
	end
	fireDepth += 1
	local list = table.clone(self.conns)
	for _, c in list do
		if c.Connected then
			local co = C.newThread(c._fn, self.name, c._ctx)
			C.resume(co, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, co in w do
		C.resume(co, ...)
	end
	fireDepth -= 1
end

function SignalMT:DisconnectAll()
	for _, c in self.conns do
		c.Connected = false
	end
	self.conns = {}
end

------------------------------------------------------------------------------------------
-- API dump (reflection) + defaults
------------------------------------------------------------------------------------------
C.api = nil :: any
local classCache = {}

function C.loadApi(path: string)
	local d = serde.decode("json", fs.readFile(path))
	C.api = d.classes
	C.apiEnums = d.enums
end

-- merged info for a class: props/funcs/events/callbacks/isA
function C.classInfo(name: string)
	local info = classCache[name]
	if info then
		return info
	end
	local raw = C.api[name]
	if not raw then
		return nil
	end
	info = { name = name, props = {}, funcs = {}, events = {}, callbacks = {}, isA = {}, chain = {} }
	local cur = name
	while cur and C.api[cur] do
		local r = C.api[cur]
		info.isA[cur] = true
		table.insert(info.chain, cur)
		for k, v in r.p do
			if info.props[k] == nil then
				info.props[k] = v
			end
		end
		for _, k in r.f do
			info.funcs[k] = true
		end
		for _, k in r.e do
			info.events[k] = true
		end
		for _, k in r.cb do
			info.callbacks[k] = true
		end
		cur = r.s
		if cur == "<<<ROOT>>>" then
			break
		end
	end
	info.service = raw.svc
	info.notCreatable = raw.nc
	classCache[name] = info
	return info
end

local db = roblox.getReflectionDatabase()
local defaultCache = {}

local U2 = roblox.UDim2
local V2 = roblox.Vector2
local E = roblox.Enum
local LEGACY = roblox.Font.new("rbxasset://fonts/families/LegacyArial.json", E.FontWeight.Regular, E.FontStyle.Normal)

-- Instance.new defaults that differ from the place-file defaults in the reflection db
local defaultOverrides = {
	Frame = { Size = U2.fromOffset(100, 100) },
	ImageLabel = { Size = U2.fromOffset(100, 100) },
	ImageButton = { Size = U2.fromOffset(100, 100) },
	ScrollingFrame = { Size = U2.fromOffset(100, 100) },
	ViewportFrame = { Size = U2.fromOffset(100, 100) },
	CanvasGroup = { Size = U2.fromOffset(100, 100) },
	TextLabel = { Size = U2.fromOffset(200, 50), TextSize = 14, FontFace = LEGACY },
	TextButton = { Size = U2.fromOffset(200, 50), TextSize = 14, FontFace = LEGACY },
	TextBox = { Size = U2.fromOffset(200, 50), TextSize = 14, FontFace = LEGACY },
	UIListLayout = {
		FillDirection = E.FillDirection.Vertical,
		SortOrder = E.SortOrder.LayoutOrder,
		HorizontalAlignment = E.HorizontalAlignment.Left,
		VerticalAlignment = E.VerticalAlignment.Top,
		Wraps = false,
	},
	UIGridLayout = {
		FillDirection = E.FillDirection.Horizontal,
		SortOrder = E.SortOrder.LayoutOrder,
		HorizontalAlignment = E.HorizontalAlignment.Left,
		VerticalAlignment = E.VerticalAlignment.Top,
		StartCorner = E.StartCorner.TopLeft,
		FillDirectionMaxCells = 0,
	},
	UIStroke = { Transparency = 0, Enabled = true, LineJoinMode = E.LineJoinMode.Round },
	UIGradient = { Enabled = true, Rotation = 0, Offset = V2.zero },
	UIScale = { Scale = 1 },
	UIAspectRatioConstraint = { AspectType = E.AspectType.FitWithinMaxSize, DominantAxis = E.DominantAxis.Width },
	UISizeConstraint = { MinSize = V2.zero, MaxSize = V2.new(math.huge, math.huge) },
	UITextSizeConstraint = { MinTextSize = 1, MaxTextSize = 100 },
	ScreenGui = { Enabled = true, DisplayOrder = 0, IgnoreGuiInset = false, ZIndexBehavior = E.ZIndexBehavior.Sibling },
	Sound = { Volume = 0.5, PlaybackSpeed = 1 },
}

local function fallbackDefault(p)
	if not p then
		return nil
	end
	local t, c = p.t, p.c
	if c == "Enum" then
		local ok, en = pcall(function()
			return E[t]
		end)
		if ok and en then
			local items = en:GetEnumItems()
			for _, it in items do
				if it.Value == 0 then
					return it
				end
			end
			return items[1]
		end
		return nil
	end
	if t == "bool" then
		return false
	elseif t == "float" or t == "double" or t == "int" or t == "int64" then
		return 0
	elseif t == "string" or t == "Content" or t == "ContentId" then
		return ""
	elseif t == "UDim2" then
		return U2.new()
	elseif t == "UDim" then
		return roblox.UDim.new()
	elseif t == "Vector2" then
		return V2.zero
	elseif t == "Vector3" then
		return roblox.Vector3.zero
	elseif t == "CFrame" then
		return roblox.CFrame.identity
	elseif t == "Color3" then
		return roblox.Color3.new(1, 1, 1)
	end
	return nil
end

function C.defaultFor(className: string, prop: string, pinfo)
	local d = defaultCache[className]
	if not d then
		d = {}
		local ok, cls = pcall(function()
			return db:GetClass(className)
		end)
		if ok and cls then
			for k, v in cls.DefaultProperties do
				d[k] = v
			end
		end
		local info = C.classInfo(className)
		if info then
			for i = #info.chain, 1, -1 do
				local o = defaultOverrides[info.chain[i]]
				if o then
					for k, v in o do
						d[k] = v
					end
				end
			end
		end
		defaultCache[className] = d
	end
	local v = d[prop]
	if v == nil then
		v = fallbackDefault(pinfo)
	end
	return v
end

------------------------------------------------------------------------------------------
-- Extra datatypes
------------------------------------------------------------------------------------------
local DT = {}
C.DT = DT

-- TweenInfo
local TweenInfoMT = { __type = "TweenInfo" }
TweenInfoMT.__index = TweenInfoMT
TweenInfoMT.__tostring = function(t)
	return string.format("TweenInfo(%g)", t.Time)
end
DT.TweenInfo = {
	new = function(time, style, dir, repeatCount, reverses, delayTime)
		return setmetatable({
			Time = time or 1,
			EasingStyle = style or E.EasingStyle.Quad,
			EasingDirection = dir or E.EasingDirection.Out,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		}, TweenInfoMT)
	end,
}

-- Random (xorshift-ish, deterministic)
local RandomMT = { __type = "Random" }
RandomMT.__index = RandomMT
local function rnd(self)
	-- LCG 48-bit-ish on doubles
	self._s = (self._s * 1103515245 + 12345) % 2147483648
	return self._s / 2147483648
end
function RandomMT:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * rnd(self)
end
function RandomMT:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * rnd(self))
end
function RandomMT:NextUnitVector()
	local th = rnd(self) * math.pi * 2
	local z = rnd(self) * 2 - 1
	local r = math.sqrt(1 - z * z)
	return roblox.Vector3.new(r * math.cos(th), r * math.sin(th), z)
end
function RandomMT:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomMT:Clone()
	return setmetatable({ _s = self._s }, RandomMT)
end
DT.Random = {
	new = function(seed)
		return setmetatable({ _s = math.floor(tonumber(seed) or 1234567) % 2147483648 }, RandomMT)
	end,
}

-- DateTime
local DateTimeMT = { __type = "DateTime" }
DateTimeMT.__index = DateTimeMT
local function mkDate(ms)
	return setmetatable({ UnixTimestampMillis = math.floor(ms), UnixTimestamp = math.floor(ms / 1000) }, DateTimeMT)
end
local function toParts(self, utc)
	local t = os.date(if utc then "!*t" else "*t", self.UnixTimestamp)
	return {
		Year = t.year,
		Month = t.month,
		Day = t.day,
		Hour = t.hour,
		Minute = t.min,
		Second = t.sec,
		Millisecond = self.UnixTimestampMillis % 1000,
	}
end
function DateTimeMT:ToUniversalTime()
	return toParts(self, true)
end
function DateTimeMT:ToLocalTime()
	return toParts(self, true)
end
function DateTimeMT:ToIsoDate()
	return os.date("!%Y-%m-%dT%H:%M:%SZ", self.UnixTimestamp)
end
function DateTimeMT:FormatUniversalTime(fmt, _locale)
	local p = toParts(self, true)
	local months = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
	local s = tostring(fmt)
	s = string.gsub(s, "YYYY", tostring(p.Year))
	s = string.gsub(s, "MMMM", months[p.Month])
	s = string.gsub(s, "MMM", string.sub(months[p.Month], 1, 3))
	s = string.gsub(s, "MM", string.format("%02d", p.Month))
	s = string.gsub(s, "DD", string.format("%02d", p.Day))
	s = string.gsub(s, "HH", string.format("%02d", p.Hour))
	s = string.gsub(s, "mm", string.format("%02d", p.Minute))
	s = string.gsub(s, "ss", string.format("%02d", p.Second))
	s = string.gsub(s, "LL", string.format("%d/%d/%d", p.Month, p.Day, p.Year))
	return s
end
DateTimeMT.FormatLocalTime = DateTimeMT.FormatUniversalTime
DT.DateTime = {
	now = function()
		return mkDate((C.epoch + C.now) * 1000)
	end,
	fromUnixTimestamp = function(s)
		return mkDate(s * 1000)
	end,
	fromUnixTimestampMillis = function(ms)
		return mkDate(ms)
	end,
	fromUniversalTime = function(y, mo, d, h, mi, s, ms)
		local t = os.time({ year = y or 1970, month = mo or 1, day = d or 1, hour = h or 0, min = mi or 0, sec = s or 0 })
		-- os.time interprets local time; container runs in UTC
		return mkDate(t * 1000 + (ms or 0))
	end,
	fromLocalTime = function(y, mo, d, h, mi, s, ms)
		local t = os.time({ year = y or 1970, month = mo or 1, day = d or 1, hour = h or 0, min = mi or 0, sec = s or 0 })
		return mkDate(t * 1000 + (ms or 0))
	end,
	fromIsoDate = function(_s)
		return mkDate((C.epoch + C.now) * 1000)
	end,
}

-- RaycastParams / OverlapParams (plain bags)
local function bag(tn, defaults)
	local mt = { __type = tn }
	mt.__index = mt
	function mt:AddToFilter(x)
		table.insert(self.FilterDescendantsInstances, x)
	end
	return {
		new = function()
			local o = table.clone(defaults)
			o.FilterDescendantsInstances = {}
			return setmetatable(o, mt)
		end,
	}
end
DT.RaycastParams = bag("RaycastParams", { FilterType = E.RaycastFilterType.Exclude, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false })
DT.OverlapParams = bag("OverlapParams", { FilterType = E.RaycastFilterType.Exclude, MaxParts = 0, CollisionGroup = "Default", RespectCanCollide = false })

function C.typeof(v)
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt == C.InstanceMT then
			return "Instance"
		elseif mt == SignalMT then
			return "RBXScriptSignal"
		elseif mt == ConnMT then
			return "RBXScriptConnection"
		elseif type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return typeof(v)
end

return C
