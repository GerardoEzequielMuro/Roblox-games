--!nocheck
-- uipreview runtime entry point (run with Lune):
--   lune run tools/uipreview/runtime/main.luau -- <config.json>
-- Boots the game's server + client scripts in a mocked, single-process Roblox (like a
-- Studio "Play Solo"), advances a virtual clock, optionally opens a window through the
-- fixture, and writes the PlayerGui tree + log as JSON for the Python layout/renderer.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local luau = require("@lune/luau")

local C = require("./core")
local I = require("./instance")
local T = require("./text")
local roblox = C.roblox
local S = I.S

local cfgPath = process.args[#process.args]
assert(cfgPath, "usage: lune run main.luau -- <config.json>")
local cfg = serde.decode("json", fs.readFile(cfgPath))

C.loadApi(cfg.apiPath)
T.load(cfg.metricsPath)
C.gamePrefix = cfg.gameName .. "/"
local Svc = require("./services")

------------------------------------------------------------------------------------------
-- Enum wrapper: Lune's enum database can lag behind Roblox; missing enums/items come from
-- the API dump as stand-in EnumItems so current code doesn't fail on them.
------------------------------------------------------------------------------------------
local fakeEnums = {}
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = EnumItemMT
EnumItemMT.__tostring = function(e)
	return "Enum." .. e._enum .. "." .. e.Name
end
function EnumItemMT:IsA(n)
	return n == self._enum
end
local function fakeEnum(name)
	if fakeEnums[name] then
		return fakeEnums[name]
	end
	local items = C.apiEnums[name]
	if not items then
		return nil
	end
	local en = { _name = name, _items = {} }
	for iname, v in items do
		en._items[iname] = setmetatable({ Name = iname, Value = v, _enum = name, EnumType = en }, EnumItemMT)
	end
	setmetatable(en, {
		__type = "Enum",
		__index = function(t, k)
			if k == "GetEnumItems" then
				return function()
					local out = {}
					for _, it in t._items do
						table.insert(out, it)
					end
					table.sort(out, function(a, b)
						return a.Value < b.Value
					end)
					return out
				end
			elseif k == "FromName" then
				return function(_, n)
					return t._items[n]
				end
			elseif k == "FromValue" then
				return function(_, v)
					for _, it in t._items do
						if it.Value == v then
							return it
						end
					end
					return nil
				end
			end
			local it = t._items[k]
			if it == nil then
				C.rterror(tostring(k) .. " is not a valid member of \"Enum." .. name .. '"')
			end
			return it
		end,
	})
	fakeEnums[name] = en
	return en
end

local enumCache = {}
local EnumProxy = setmetatable({}, {
	__index = function(_, name)
		local cached = enumCache[name]
		if cached then
			return cached
		end
		local ok, real = pcall(function()
			return roblox.Enum[name]
		end)
		local wrapper
		if ok and real then
			-- wrap to fall back to API-dump items missing in Lune
			wrapper = setmetatable({}, {
				__type = "Enum",
				__index = function(_, k)
					local ok2, item = pcall(function()
						return real[k]
					end)
					if ok2 and item ~= nil then
						return if type(item) == "function" then function(_, ...)
							return item(real, ...)
						end else item
					end
					local fe = fakeEnum(name)
					if fe then
						local it = rawget(fe, "_items")[k]
						if it then
							return it
						end
					end
					C.rterror(tostring(k) .. " is not a valid member of \"Enum." .. name .. '"')
				end,
				__tostring = function()
					return name
				end,
			})
		else
			wrapper = fakeEnum(name)
			if not wrapper then
				C.rterror(tostring(name) .. " is not a valid member of \"Enum\"")
			end
		end
		enumCache[name] = wrapper
		return wrapper
	end,
})

------------------------------------------------------------------------------------------
-- configuration visible to services
------------------------------------------------------------------------------------------
local fixture = {}
Svc.config = {
	screen = cfg.screen,
	fixture = fixture,
	userId = 0,
	locale = cfg.locale or "en-us",
	state = cfg.state,
}

------------------------------------------------------------------------------------------
-- DataModel
------------------------------------------------------------------------------------------
local game = I.new("DataModel", { name = "Game", src = {} })
Svc.game = game
local function svc(name)
	return I.methods.DataModel.GetService(game, name)
end
local Workspace = svc("Workspace")
local camera = I.new("Camera", { name = "Camera", src = {} })
I.setParent(camera, Workspace)
S[Workspace].props.CurrentCamera = camera
local terrain = I.new("Terrain", { name = "Terrain", src = {} })
I.setParent(terrain, Workspace)
local Players = svc("Players")
local ReplicatedStorage = svc("ReplicatedStorage")
svc("ReplicatedFirst")
local ServerScriptService = svc("ServerScriptService")
svc("ServerStorage")
local StarterGui = svc("StarterGui")
svc("StarterPack")
local StarterPlayer = svc("StarterPlayer")
local SPS = I.new("StarterPlayerScripts", { name = "StarterPlayerScripts", src = {} })
I.setParent(SPS, StarterPlayer)
local SCS = I.new("StarterCharacterScripts", { name = "StarterCharacterScripts", src = {} })
I.setParent(SCS, StarterPlayer)
svc("Lighting")
svc("SoundService")
svc("Teams")
svc("RunService")
local TCS = svc("TextChatService")
do
	local chans = I.new("Folder", { name = "TextChannels", src = {} })
	I.setParent(chans, TCS)
	for _, n in { "RBXGeneral", "RBXSystem" } do
		local ch = I.new("TextChannel", { name = n, src = {} })
		I.setParent(ch, chans)
	end
	local cmds = I.new("Folder", { name = "TextChatCommands", src = {} })
	I.setParent(cmds, TCS)
	for _, cn in { "ChatWindowConfiguration", "ChatInputBarConfiguration", "BubbleChatConfiguration" } do
		local x = I.new(cn, { name = cn, src = {} })
		I.setParent(x, TCS)
	end
end

------------------------------------------------------------------------------------------
-- globals
------------------------------------------------------------------------------------------
local moduleCache = { client = {}, server = {} }
local iconMap = {}
local loading = {}
local repoRoot = cfg.repoRoot

local sources = {} -- pre-read on the main Lune thread (fs calls yield to Lune's scheduler)
local function loadChunk(relPath: string, env)
	local src = sources[relPath]
	if not src then
		error("source not preloaded: " .. relPath)
	end
	return luau.load(src, { debugName = "@" .. relPath, environment = env })
end

local makeEnv -- forward

local function requireModule(target)
	if type(target) == "number" then
		C.rterror("require(assetId) is not supported in the preview (asset " .. target .. ")")
	end
	if not I.isInstance(target) then
		C.rterror("Attempted to call require with invalid argument(s).")
	end
	local st = S[target]
	if st.className ~= "ModuleScript" then
		C.rterror("Attempted to call require with invalid argument(s).")
	end
	local ctx = C.currentCtx()
	local cache = moduleCache[ctx]
	local entry = cache[target]
	if entry then
		if entry.err then
			C.rterror("Requested module experienced an error while loading")
		end
		return entry.value
	end
	local key = ctx .. ":" .. st.id
	if loading[key] then
		C.rterror("Requested module was required recursively")
	end
	local file = st.data.file
	if not file then
		C.rterror("ModuleScript " .. I.fullName(target) .. " has no source in the preview")
	end
	if string.match(file, "%.json$") then
		local v = serde.decode("json", sources[file])
		cache[target] = { value = v }
		return v
	end
	if st.data.builtin then
		local v = st.data.builtin()
		cache[target] = { value = v }
		return v
	end
	if fixture.stubModules and fixture.stubModules[I.fullName(target)] then
		local v = fixture.stubModules[I.fullName(target)]
		cache[target] = { value = v }
		return v
	end
	loading[key] = true
	local fn = loadChunk(file, makeEnv(target, ctx))
	local res = table.pack(pcall(fn))
	loading[key] = nil
	if not res[1] then
		cache[target] = { err = res[2] }
		error(res[2], 0)
	end
	if res.n ~= 2 then
		cache[target] = { err = "Module code did not return exactly one value" }
		C.addLog("error", "Module code did not return exactly one value: " .. file, { file .. ":1" })
		C.rterror("Module code did not return exactly one value")
	end
	local value = res[2]
	-- --icons: pretend the shared icon pack is uploaded (fake ids the renderer maps back)
	if cfg.fakeIcons and string.match(file, "src/shared/Icons%.luau$") and type(value) == "table" and type(value.ids) == "table" then
		local names = {}
		for name in value.ids do
			table.insert(names, name)
		end
		table.sort(names)
		for i, name in names do
			local id = tostring(990000000 + i)
			value.ids[name] = id
			iconMap[id] = name
		end
	end
	cache[target] = { value = value }
	return value
end

local function captureOut(kind)
	return function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		C.addLog(kind, table.concat(parts, " "), C.where(1))
	end
end

local settingsObj = setmetatable({}, {
	__index = function(t, k)
		local sub = setmetatable({}, {
			__index = function(_, kk)
				if kk == "QualityLevel" then
					return EnumProxy.QualityLevel.Automatic
				end
				return nil
			end,
			__newindex = function() end,
		})
		rawset(t, k, sub)
		return sub
	end,
})
local userGameSettings = I.new("UserGameSettings", { name = "UserGameSettings", src = {} })
do
	local g = I.getters.UserGameSettings or {}
	I.getters.UserGameSettings = g
	g.SavedQualityLevel = function()
		return EnumProxy.SavedQualitySetting.Automatic
	end
end
local userSettingsObj = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" or k == "GetFFlag" or k == "IsUserFeatureEnabled" then
			return function(_, name)
				if k ~= "GetService" then
					return false
				end
				if name == "UserGameSettings" then
					return userGameSettings
				end
				return svc(name)
			end
		elseif k == "GameSettings" then
			return userGameSettings
		end
		return nil
	end,
})

local baseGlobals = {}
local function buildGlobals(ctx)
	local g = {}
	g.game = game
	g.Game = game
	g.workspace = Workspace
	g.Workspace = Workspace
	g.Instance = {
		new = function(className, parent)
			if type(className) ~= "string" then
				C.rterror("Instance.new: className must be a string")
			end
			local info = C.classInfo(className)
			if not info then
				C.rterror('Unable to create an Instance of type "' .. className .. '"')
			end
			if info.notCreatable or info.service then
				C.rterror('Unable to create an Instance of type "' .. className .. '"')
			end
			local inst = I.new(className)
			if parent ~= nil then
				inst.Parent = parent
			end
			return inst
		end,
		fromExisting = function(x)
			return I.clone(x)
		end,
	}
	g.typeof = C.typeof
	g.task = {
		spawn = function(f, ...)
			return C.spawn(f, ...)
		end,
		defer = function(f, ...)
			return C.defer(f, ...)
		end,
		delay = function(t, f, ...)
			return C.delay(t, f, ...)
		end,
		wait = function(t)
			return C.wait(t)
		end,
		cancel = function(co)
			C.cancel(co)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	}
	g.wait = function(t)
		return C.wait(t or 1 / 30)
	end
	g.delay = function(t, f)
		C.delay(t, f)
	end
	g.spawn = function(f)
		C.defer(f)
	end
	g.tick = function()
		return C.epoch + C.now
	end
	g.time = function()
		return C.now
	end
	g.elapsedTime = function()
		return C.now
	end
	g.os = {
		clock = function()
			return C.now
		end,
		time = function(t)
			if t then
				return os.time(t)
			end
			return math.floor(C.epoch + C.now)
		end,
		date = function(fmt, t)
			return os.date(fmt, t or math.floor(C.epoch + C.now))
		end,
		difftime = os.difftime,
	}
	g.print = captureOut("print")
	g.warn = captureOut("warn")
	g.require = requireModule
	g._G = {}
	g.shared = g._G
	g.Enum = EnumProxy
	for _, n in {
		"UDim", "UDim2", "Vector2", "Vector3", "Color3", "CFrame", "BrickColor", "ColorSequence", "ColorSequenceKeypoint",
		"NumberSequence", "NumberSequenceKeypoint", "NumberRange", "Rect", "Font", "Faces", "Axes", "Ray", "Region3",
		"PhysicalProperties", "Vector2int16", "Vector3int16", "Region3int16",
	} do
		g[n] = roblox[n]
	end
	for n, v in C.DT do
		g[n] = v
	end
	g.settings = function()
		return settingsObj
	end
	g.UserSettings = function()
		return userSettingsObj
	end
	g.version = function()
		return "0.690.0.6900000"
	end
	g.stats = function()
		return svc("Stats")
	end
	g.plugin = nil
	local dbg = table.clone(debug)
	dbg.profilebegin = function() end
	dbg.profileend = function() end
	dbg.setmemorycategory = function() end
	dbg.resetmemorycategory = function() end
	g.debug = dbg
	g.collectgarbage = function(opt)
		if opt == "count" then
			return gcinfo()
		end
		C.rterror("collectgarbage must be called with 'count'")
	end
	g.loadstring = nil
	return g
end
baseGlobals.client = buildGlobals("client")
baseGlobals.server = buildGlobals("server")

makeEnv = function(scriptInst, ctx)
	local env = table.clone(baseGlobals[ctx])
	env.script = scriptInst
	return env
end

------------------------------------------------------------------------------------------
-- sourcemap -> instances
------------------------------------------------------------------------------------------
local sm = serde.decode("json", fs.readFile(cfg.sourcemap))
local scripts = {}

local function pickFile(paths)
	if not paths then
		return nil
	end
	for _, p in paths do
		if string.match(p, "%.luau?$") or string.match(p, "%.json$") and not string.match(p, "%.project%.json$") and not string.match(p, "%.meta%.json$") then
			return p
		end
	end
	return nil
end

local function build(node, parent, isTop)
	local inst
	if isTop then
		local ok, s = pcall(svc, node.className)
		if ok then
			inst = s
		end
	end
	if not inst then
		local cls = node.className
		if not C.classInfo(cls) then
			cls = "Folder"
		end
		inst = I.new(cls, { name = node.name, src = {} })
		I.setParent(inst, parent)
	end
	if node.className == "StarterPlayerScripts" then
		inst = SPS
	elseif node.className == "StarterCharacterScripts" then
		inst = SCS
	end
	local file = pickFile(node.filePaths)
	if file then
		S[inst].data.file = cfg.gameName .. "/" .. file
		sources[cfg.gameName .. "/" .. file] = fs.readFile(repoRoot .. "/" .. cfg.gameName .. "/" .. file)
		if node.className == "Script" or node.className == "LocalScript" then
			table.insert(scripts, inst)
		end
	end
	for _, child in node.children or {} do
		build(child, inst, false)
	end
	return inst
end
for _, child in sm.children or {} do
	build(child, game, true)
end

------------------------------------------------------------------------------------------
-- fixture
------------------------------------------------------------------------------------------
local fixtureEnv = table.clone(baseGlobals.client)
if cfg.fixture then
	local src = fs.readFile(cfg.fixture)
	local fn = luau.load(src, { debugName = cfg.fixture, environment = fixtureEnv })
	local ok, res = pcall(fn)
	if not ok then
		error("fixture failed: " .. tostring(res))
	end
	for k, v in res do
		fixture[k] = v
	end
end
Svc.config.userId = fixture.userId or 90000001
-- helpers handed to fixture functions that run before the client (e.g. midProfile)
Svc.fixtureHelpers = {
	shared = function(path)
		local cur = ReplicatedStorage
		for part in string.gmatch(path, "[^%.]+") do
			cur = I.findChild(cur, part)
			if not cur then
				error("fixture: no module ReplicatedStorage." .. path)
			end
		end
		return requireModule(cur)
	end,
	now = function()
		return math.floor(C.epoch + C.now)
	end,
	userId = function()
		return Svc.config.userId
	end,
}
if fixture.stubModules then
	-- given as { ["ServerScriptService.Server.World.WorldBuilder"] = {...} }
end

------------------------------------------------------------------------------------------
-- run
------------------------------------------------------------------------------------------
C.frameCallbacks = { Svc.runServiceFrame }

local function runScript(inst, ctx)
	local file = S[inst].data.file
	local co = C.newThread(function()
		local fn = loadChunk(file, makeEnv(inst, ctx))
		fn()
	end, file, ctx)
	C.resume(co)
end

local serverScripts, clientScripts = {}, {}
for _, s in scripts do
	local st = S[s]
	if st.className == "Script" then
		local rc = st.props.RunContext
		if I.methods.Instance.IsDescendantOf(s, ServerScriptService) or I.methods.Instance.IsDescendantOf(s, Workspace) then
			table.insert(serverScripts, s)
		end
		local _ = rc
	elseif st.className == "LocalScript" then
		if I.methods.Instance.IsDescendantOf(s, SPS) then
			table.insert(clientScripts, s)
		end
	end
end

local skipServer = cfg.noServer or fixture.noServer
if not skipServer then
	for _, s in serverScripts do
		if not (fixture.skipScripts and fixture.skipScripts[S[s].data.file]) then
			runScript(s, "server")
		end
	end
end
C.run(fixture.serverBoot or 1.0)

-- the player joins
local player = I.new("Player", { name = "PreviewPlayer", src = {} })
Svc.player = player
local playerGui = I.new("PlayerGui", { name = "PlayerGui", src = {} })
I.setParent(playerGui, player)
I.setParent(I.new("Backpack", { name = "Backpack", src = {} }), player)
local playerScripts = I.new("PlayerScripts", { name = "PlayerScripts", src = {} })
I.setParent(playerScripts, player)
do
	-- Roblox's default PlayerModule (controls + camera), as a stub
	local pm = I.new("ModuleScript", { name = "PlayerModule", src = {} })
	S[pm].data.builtin = function()
		local controls = {
			Enable = function() end,
			Disable = function() end,
			GetMoveVector = function()
				return roblox.Vector3.zero
			end,
			GetActiveController = function()
				return nil
			end,
			SelectComputerMovementModule = function() end,
		}
		return {
			GetControls = function()
				return controls
			end,
			GetCameras = function()
				return {}
			end,
			GetClickToMoveController = function()
				return nil
			end,
		}
	end
	I.setParent(pm, playerScripts)
end
I.setParent(player, Players)
I.signal(Players, "PlayerAdded"):Fire(player)
C.flushDeferred()
C.run(0.2)

for _, c in S[StarterGui].children do
	local cl = I.clone(c)
	if cl then
		I.setParent(cl, playerGui)
	end
end
local clientRun = {}
for _, c in S[SPS].children do
	local cl = I.clone(c)
	if cl then
		I.setParent(cl, playerScripts)
		if S[cl].className == "LocalScript" then
			table.insert(clientRun, cl)
		end
		I.eachDescendant(cl, function(d)
			if S[d].className == "LocalScript" then
				table.insert(clientRun, d)
			end
		end)
	end
end
C.threadCtx[coroutine.running()] = "client"
Svc.spawnCharacter(player)
for _, s in clientRun do
	if not (fixture.skipScripts and fixture.skipScripts[S[s].data.file]) then
		runScript(s, "client")
	end
end
C.run(cfg.bootSeconds or fixture.boot or 8)

-- open a window through the fixture
local openResult = nil
local function findClientScript()
	local byName = I.findChild(playerScripts, fixture.clientRoot or "Client")
	if byName then
		return byName
	end
	for _, c in S[playerScripts].children do
		if S[c].name ~= "PlayerModule" then
			return c
		end
	end
	return nil
end
local ctxApi = {}
ctxApi.player = player
ctxApi.gui = playerGui
ctxApi.state = cfg.state
ctxApi.screen = cfg.screen
function ctxApi.client(path)
	local cur = findClientScript()
	for part in string.gmatch(path, "[^%.]+") do
		cur = I.findChild(cur, part)
		if not cur then
			error("ctx.client: no module " .. path)
		end
	end
	return requireModule(cur)
end
function ctxApi.shared(path)
	local cur = ReplicatedStorage
	for part in string.gmatch(path, "[^%.]+") do
		cur = I.findChild(cur, part)
		if not cur then
			error("ctx.shared: no module " .. path)
		end
	end
	return requireModule(cur)
end
function ctxApi.find(name, root)
	return I.findChild(root or playerGui, name, true)
end
local function textOf(inst)
	local st = S[inst]
	local t = st.props.Text
	return t and tostring(t) or ""
end
-- first GuiButton whose own text / descendant label text / name matches the Lua pattern
function ctxApi.findButton(pattern, root)
	local found = nil
	I.eachDescendant(root or playerGui, function(d)
		if found then
			return
		end
		local st = S[d]
		if not st.info.isA.GuiButton then
			return
		end
		if string.find(st.name, pattern) or string.find(textOf(d), pattern) then
			found = d
			return
		end
		I.eachDescendant(d, function(x)
			if not found and S[x].info.isA.TextLabel and string.find(textOf(x), pattern) then
				found = d
			end
		end)
	end)
	return found
end
function ctxApi.click(btn)
	if not btn then
		error("ctx.click: button is nil")
	end
	for _, ev in { "MouseButton1Down", "InputBegan", "MouseButton1Up", "MouseButton1Click", "Activated" } do
		local s = S[btn].signals[ev]
		if s then
			if ev == "InputBegan" then
				-- skip: needs InputObject
			elseif ev == "Activated" then
				s:Fire(nil, 1)
			else
				s:Fire(Svc.config.screen.w / 2, Svc.config.screen.h / 2)
			end
		end
	end
end
function ctxApi.serverFire(remotePath, ...)
	local cur = ReplicatedStorage
	for part in string.gmatch(remotePath, "[^%.]+") do
		cur = I.findChild(cur, part)
	end
	I.methods.RemoteEvent.FireClient(cur, player, ...)
end
ctxApi.wait = C.wait
ctxApi.log = function(msg)
	C.addLog("info", "[fixture] " .. tostring(msg), {})
end

if cfg.open and cfg.open ~= "" then
	local fnOpen = fixture.windows and fixture.windows[cfg.open]
	if not fnOpen then
		openResult = "unknown window '" .. cfg.open .. "'"
	else
		local co = C.newThread(function()
			local ok, err = pcall(fnOpen, ctxApi)
			if not ok then
				openResult = "open failed: " .. tostring(err)
				C.addLog("error", "[fixture open " .. cfg.open .. "] " .. tostring(err), C.where(4))
			else
				openResult = "ok"
			end
		end, "open " .. cfg.open, "client")
		C.resume(co)
		local t0 = C.now
		while openResult == nil and C.now - t0 < 90 do
			C.step()
		end
		C.run(fixture.openSeconds or 2.5)
	end
end
if fixture.after then
	local co = C.newThread(function()
		fixture.after(ctxApi)
	end, "after", "client")
	C.resume(co)
	C.run(0.5)
end

------------------------------------------------------------------------------------------
-- dump
------------------------------------------------------------------------------------------
local function enc(v)
	local t = C.typeof(v)
	if t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	elseif t == "Vector2" then
		local x, y = v.X, v.Y
		if x == math.huge then
			x = 1e9
		end
		if y == math.huge then
			y = 1e9
		end
		return { x, y }
	elseif t == "Color3" then
		return { v.R, v.G, v.B }
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "Font" then
		return { family = v.Family, weight = v.Weight.Name, style = v.Style.Name }
	elseif t == "ColorSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		end
		return out
	elseif t == "NumberSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { k.Time, k.Value })
		end
		return out
	elseif t == "Rect" then
		return { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y }
	elseif t == "Instance" then
		return I.fullName(v)
	elseif t == "number" then
		if v ~= v then
			return 0
		end
		if v == math.huge then
			return 1e9
		end
		if v == -math.huge then
			return -1e9
		end
		return v
	elseif t == "string" or t == "boolean" then
		return v
	end
	return tostring(v)
end

local PROPS = {
	"Visible", "Size", "Position", "AnchorPoint", "ZIndex", "LayoutOrder", "BackgroundColor3", "BackgroundTransparency",
	"BorderSizePixel", "BorderColor3", "ClipsDescendants", "AutomaticSize", "Rotation", "SizeConstraint", "Active",
	"Interactable", "Text", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment", "TextYAlignment", "TextColor3",
	"TextTransparency", "TextStrokeTransparency", "TextStrokeColor3", "FontFace", "RichText", "LineHeight", "TextTruncate",
	"MaxVisibleGraphemes", "PlaceholderText", "Image", "ImageColor3", "ImageTransparency", "ScaleType", "ImageRectSize",
	"ImageRectOffset", "SliceCenter", "CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollingDirection",
	"ScrollBarThickness", "ScrollBarImageTransparency", "ScrollingEnabled", "Enabled", "DisplayOrder", "IgnoreGuiInset", "ScreenInsets", "ZIndexBehavior",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Wraps", "HorizontalFlex",
	"VerticalFlex", "CellSize", "CellPadding", "FillDirectionMaxCells", "StartCorner", "PaddingTop", "PaddingBottom",
	"PaddingLeft", "PaddingRight", "CornerRadius", "Color", "Thickness", "Transparency", "ApplyStrokeMode", "Offset",
	"Scale", "AspectRatio", "AspectType", "DominantAxis", "MinSize", "MaxSize", "MinTextSize", "MaxTextSize", "FlexMode",
	"GrowRatio", "ShrinkRatio", "GroupTransparency", "GroupColor3", "Selectable", "AutoButtonColor", "Modal",
}

local UI_CLASSES = { GuiBase2d = true, UIComponent = true, Folder = true }
local function isUi(st)
	for k in UI_CLASSES do
		if st.info.isA[k] then
			return true
		end
	end
	return false
end

local function dump(inst)
	local st = S[inst]
	if not isUi(st) then
		return nil
	end
	if st.info.isA.SurfaceGui or st.info.isA.BillboardGui then
		return nil
	end
	local node = { id = st.id, cls = st.className, name = st.name, src = st.src, props = {}, children = {} }
	for _, p in PROPS do
		if st.info.props[p] then
			local ok, v = pcall(function()
				return inst[p]
			end)
			if ok and v ~= nil then
				node.props[p] = enc(v)
			end
		end
	end
	if next(st.attrs) then
		node.attrs = {}
		for k, v in st.attrs do
			node.attrs[k] = enc(v)
		end
	end
	for _, c in st.children do
		local cn = dump(c)
		if cn then
			table.insert(node.children, cn)
		end
	end
	return node
end

local roots = {}
for _, c in S[playerGui].children do
	local n = dump(c)
	if n then
		table.insert(roots, n)
	end
end

local blocked = {}
for co, b in C.blocked do
	if coroutine.status(co) == "suspended" and not b.soft then
		table.insert(blocked, { desc = b.desc, where = b.where, since = b.since })
	end
end

local out = {
	game = cfg.gameName,
	state = cfg.state,
	screen = cfg.screen,
	open = cfg.open,
	openResult = openResult,
	virtualTime = C.now,
	roots = roots,
	log = C.log,
	blocked = blocked,
	coreGui = Svc.coreGui,
	iconMap = iconMap,
}
fs.writeFile(cfg.out, serde.encode("json", out))
print("ok", #roots, "roots", #C.log, "log entries")
process.exit(0)
