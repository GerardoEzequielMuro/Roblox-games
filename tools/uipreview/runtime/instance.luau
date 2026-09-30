--!nocheck
-- The Instance mock. Every instance is an empty proxy table; its state lives in S[proxy].
-- Members are checked against the Roblox API dump: unknown members raise the same error
-- Roblox would ("X is not a valid member of Y"), API members that the mock doesn't
-- implement return a logged stub, property writes are type-checked.
local C = require("./core")
local roblox = C.roblox
local E = roblox.Enum

local I = {}
local S = {} -- proxy -> state
I.S = S
local InstanceMT = {}
C.InstanceMT = InstanceMT

-- class -> member -> function(self, ...) ; getters/setters: class -> prop -> fn
I.methods = {}
I.getters = {}
I.setters = {}
I.quiet = {} -- class -> member -> true : stub silently (no log)
I.all = setmetatable({}, { __mode = "k" }) -- every live instance (for CollectionService)
local nextId = 0

local function chainLookup(tbl, info, key)
	for _, cls in info.chain do
		local t = tbl[cls]
		if t then
			local v = t[key]
			if v ~= nil then
				return v
			end
		end
	end
	return nil
end

function I.state(inst)
	return S[inst]
end

function I.isInstance(v)
	return type(v) == "table" and getmetatable(v) == InstanceMT
end

local function fullName(inst)
	local parts = {}
	local cur = inst
	local guard = 0
	while cur and guard < 100 do
		local st = S[cur]
		if st.className == "DataModel" then
			break
		end
		table.insert(parts, 1, st.name)
		cur = st.parent
		guard += 1
	end
	return table.concat(parts, ".")
end
I.fullName = fullName

function I.signal(inst, name)
	local st = S[inst]
	local s = st.signals[name]
	if not s then
		s = C.newSignal(st.name .. "." .. name)
		st.signals[name] = s
	end
	return s
end

function I.propSignal(inst, prop)
	local st = S[inst]
	local s = st.propSignals[prop]
	if not s then
		s = C.newSignal(st.name .. ":GetPropertyChangedSignal(" .. prop .. ")")
		st.propSignals[prop] = s
	end
	return s
end

local function firePropChanged(inst, prop)
	local st = S[inst]
	local ps = st.propSignals[prop]
	if ps then
		ps:Fire()
	end
	local ch = st.signals.Changed
	if ch then
		if st.info.isA.ValueBase and prop == "Value" then
			ch:Fire(st.props.Value)
		else
			ch:Fire(prop)
		end
	end
end
I.firePropChanged = firePropChanged

------------------------------------------------------------------------------------------
-- creation
------------------------------------------------------------------------------------------
function I.new(className: string, opts: any?)
	local info = C.classInfo(className)
	if not info then
		C.rterror('Unable to create an Instance of type "' .. tostring(className) .. '"')
	end
	nextId += 1
	local proxy = setmetatable({}, InstanceMT)
	S[proxy] = {
		id = nextId,
		className = className,
		info = info,
		name = (opts and opts.name) or className,
		parent = nil,
		children = {},
		props = {},
		attrs = {},
		attrOrder = {},
		tags = {},
		signals = {},
		propSignals = {},
		attrSignals = {},
		callbacks = {},
		waiters = {},
		src = (opts and opts.src) or C.where(4),
		ctx = C.currentCtx(),
		destroyed = false,
		data = {},
	}
	I.all[proxy] = true
	local init = chainLookup(I.inits, info, "__init")
	if init then
		init(proxy)
	end
	return proxy
end
I.inits = {}

------------------------------------------------------------------------------------------
-- hierarchy
------------------------------------------------------------------------------------------
local function isAncestor(a, b) -- a is ancestor of b
	local cur = S[b].parent
	while cur do
		if cur == a then
			return true
		end
		cur = S[cur].parent
	end
	return false
end
I.isAncestor = isAncestor

local function eachDescendant(inst, fn)
	for _, c in S[inst].children do
		fn(c)
		eachDescendant(c, fn)
	end
end
I.eachDescendant = eachDescendant

local function checkWaiters(parent, child)
	local pst = S[parent]
	local name = S[child].name
	local list = pst.waiters[name]
	if list then
		pst.waiters[name] = nil
		for _, w in list do
			if not w.done then
				w.done = true
				C.resume(w.co, child)
			end
		end
	end
end
I.checkWaiters = checkWaiters

function I.setParent(inst, newParent)
	local st = S[inst]
	if newParent ~= nil and not I.isInstance(newParent) then
		C.rterror("Unable to assign property Parent. Object expected, got " .. C.typeof(newParent))
	end
	if st.parentLocked then
		C.rterror(
			"The Parent property of " .. fullName(inst) .. " is locked, current parent: NULL, new parent " .. (newParent and S[newParent].name or "NULL")
		)
	end
	if newParent == st.parent then
		return
	end
	if newParent == inst or (newParent and isAncestor(inst, newParent)) then
		C.rterror("Attempt to set parent of " .. fullName(inst) .. " to " .. fullName(newParent) .. " would result in circular reference")
	end
	local old = st.parent
	if old then
		local ost = S[old]
		local i = table.find(ost.children, inst)
		if i then
			table.remove(ost.children, i)
		end
	end
	st.parent = newParent
	if newParent then
		table.insert(S[newParent].children, inst)
	end
	-- events
	if old then
		local s = S[old].signals.ChildRemoved
		if s then
			s:Fire(inst)
		end
		local cur = old
		while cur do
			local ds = S[cur].signals.DescendantRemoving
			if ds then
				ds:Fire(inst)
			end
			cur = S[cur].parent
		end
	end
	local function ancestry(x)
		local s = S[x].signals.AncestryChanged
		if s then
			s:Fire(inst, newParent)
		end
		for _, c in S[x].children do
			ancestry(c)
		end
	end
	ancestry(inst)
	firePropChanged(inst, "Parent")
	if newParent then
		local s = S[newParent].signals.ChildAdded
		if s then
			s:Fire(inst)
		end
		local cur = newParent
		while cur do
			local ds = S[cur].signals.DescendantAdded
			if ds then
				ds:Fire(inst)
				eachDescendant(inst, function(d)
					ds:Fire(d)
				end)
			end
			cur = S[cur].parent
		end
		checkWaiters(newParent, inst)
		if I.onParented then
			I.onParented(inst, newParent)
		end
	end
end

function I.destroy(inst)
	local st = S[inst]
	if st.destroyed then
		return
	end
	local ds = st.signals.Destroying
	if ds then
		ds:Fire()
	end
	for _, c in table.clone(st.children) do
		I.destroy(c)
	end
	I.setParent(inst, nil)
	st.parentLocked = true
	st.destroyed = true
	for _, s in st.signals do
		s:DisconnectAll()
	end
	for _, s in st.propSignals do
		s:DisconnectAll()
	end
end

function I.findChild(inst, name, recursive)
	for _, c in S[inst].children do
		if S[c].name == name then
			return c
		end
	end
	if recursive then
		for _, c in S[inst].children do
			local r = I.findChild(c, name, true)
			if r then
				return r
			end
		end
	end
	return nil
end

function I.clone(inst)
	local st = S[inst]
	if st.props.Archivable == false then
		return nil
	end
	local n = I.new(st.className, { name = st.name, src = C.where(4) })
	local nst = S[n]
	for k, v in st.props do
		nst.props[k] = v
	end
	for k, v in st.attrs do
		nst.attrs[k] = v
	end
	nst.attrOrder = table.clone(st.attrOrder)
	for k, v in st.tags do
		nst.tags[k] = v
	end
	for k, v in st.data do
		nst.data[k] = v
	end
	for _, c in st.children do
		local cc = I.clone(c)
		if cc then
			I.setParent(cc, n)
		end
	end
	return n
end

------------------------------------------------------------------------------------------
-- property type checking
------------------------------------------------------------------------------------------
local numberTypes = { float = true, double = true, int = true, int64 = true }

local function coerce(inst, prop, pinfo, v)
	local t, c = pinfo.t, pinfo.c
	local tv = C.typeof(v)
	if c == "Primitive" then
		if t == "bool" then
			if tv ~= "boolean" then
				C.rterror("Unable to assign property " .. prop .. ". bool expected, got " .. tv)
			end
		elseif numberTypes[t] then
			if tv == "string" and tonumber(v) then
				return tonumber(v)
			end
			if tv ~= "number" then
				C.rterror("Unable to assign property " .. prop .. ". number expected, got " .. tv)
			end
			if v ~= v then
				C.addLog("warn", "NaN assigned to " .. S[inst].className .. "." .. prop, C.where(3))
			end
		elseif t == "string" then
			if tv == "number" then
				return tostring(v)
			end
			if tv ~= "string" then
				C.rterror("Unable to assign property " .. prop .. ". string expected, got " .. tv)
			end
		end
		return v
	elseif c == "Enum" then
		local ok, en = pcall(function()
			return E[t]
		end)
		if not ok or not en then
			return v
		end
		if tv == "EnumItem" then
			if v.EnumType ~= en then
				C.rterror("Unable to assign property " .. prop .. ". " .. t .. " expected, got " .. tostring(v))
			end
			return v
		elseif tv == "string" then
			local ok2, item = pcall(function()
				return en[v]
			end)
			if ok2 and item then
				return item
			end
			C.rterror("Unable to assign property " .. prop .. '. Invalid value "' .. v .. '" for enum ' .. t)
		elseif tv == "number" then
			for _, it in en:GetEnumItems() do
				if it.Value == v then
					return it
				end
			end
			C.rterror("Unable to assign property " .. prop .. ". Invalid value " .. v .. " for enum " .. t)
		end
		C.rterror("Unable to assign property " .. prop .. ". EnumItem expected, got " .. tv)
	elseif c == "DataType" then
		if t == "Content" or t == "ContentId" then
			if tv == "string" or tv == "Content" then
				return v
			end
			if tv == "number" then
				return tostring(v)
			end
			C.rterror("Unable to assign property " .. prop .. ". Content expected, got " .. tv)
		end
		if v == nil then
			C.rterror("Unable to assign property " .. prop .. ". " .. t .. " expected, got nil")
		end
		if tv ~= t and not (t == "Font" and tv == "Font") then
			-- a few loose conversions Roblox allows
			if t == "BrickColor" and tv == "string" then
				return roblox.BrickColor.new(v)
			end
			C.rterror("Unable to assign property " .. prop .. ". " .. t .. " expected, got " .. tv)
		end
		return v
	elseif c == "Class" then
		if v ~= nil and not I.isInstance(v) then
			C.rterror("Unable to assign property " .. prop .. ". Object expected, got " .. tv)
		end
		return v
	end
	return v
end

------------------------------------------------------------------------------------------
-- metatable
------------------------------------------------------------------------------------------
local stubLogged = {}
local function stubFor(className, member)
	return function(self, ...)
		local key = className .. ":" .. member
		local cls = S[self] and S[self].info
		local quiet = cls and chainLookup(I.quiet, cls, member)
		if not quiet then
			C.addLog("unknown_api", "unimplemented API " .. key .. "() (returned nil)", C.where(2), nil, "stub|" .. key)
		end
		return nil
	end
end

InstanceMT.__index = function(self, k)
	local st = S[self]
	local info = st.info
	local m = chainLookup(I.methods, info, k)
	if m ~= nil then
		return m
	end
	local g = chainLookup(I.getters, info, k)
	if g ~= nil then
		return g(self)
	end
	if k == "Name" then
		return st.name
	elseif k == "Parent" then
		return st.parent
	elseif k == "ClassName" then
		return st.className
	end
	local v = st.props[k]
	if v ~= nil then
		return v
	end
	local p = info.props[k]
	if p then
		if p.ns and not p.t then
			return nil
		end
		return C.defaultFor(st.className, k, p)
	end
	if info.events[k] then
		return I.signal(self, k)
	end
	if info.callbacks[k] then
		return nil -- write-only in Roblox, reading returns nil / errors
	end
	if info.funcs[k] then
		return stubFor(st.className, k)
	end
	local child = I.findChild(self, k)
	if child then
		return child
	end
	C.rterror(tostring(k) .. " is not a valid member of " .. st.className .. ' "' .. fullName(self) .. '"')
end

InstanceMT.__newindex = function(self, k, v)
	local st = S[self]
	local info = st.info
	local setter = chainLookup(I.setters, info, k)
	if setter then
		setter(self, v)
		return
	end
	if k == "Parent" then
		I.setParent(self, v)
		return
	elseif k == "Name" then
		if type(v) ~= "string" and type(v) ~= "number" then
			C.rterror("Unable to assign property Name. string expected, got " .. C.typeof(v))
		end
		v = tostring(v)
		if st.name ~= v then
			st.name = v
			firePropChanged(self, "Name")
			if st.parent then
				checkWaiters(st.parent, self)
			end
		end
		return
	end
	local p = info.props[k]
	if p then
		if p.ro then
			C.rterror("Unable to assign property " .. k .. ". Property is read only")
		end
		if p.dep then
			C.addLog("deprecated", "deprecated property " .. st.className .. "." .. k .. " assigned", C.where(2))
		end
		v = coerce(self, k, p, v)
		local old = st.props[k]
		if old == nil then
			old = C.defaultFor(st.className, k, p)
		end
		st.props[k] = v
		if old ~= v then
			firePropChanged(self, k)
		end
		return
	end
	if info.callbacks[k] then
		if v ~= nil and type(v) ~= "function" then
			C.rterror(k .. " callback must be a function")
		end
		st.callbacks[k] = v
		local cb = chainLookup(I.setters, info, "__callback")
		if cb then
			cb(self, k, v)
		end
		return
	end
	C.rterror(tostring(k) .. " is not a valid member of " .. st.className .. ' "' .. fullName(self) .. '"')
end

InstanceMT.__tostring = function(self)
	return S[self].name
end
InstanceMT.__type = "Instance"

------------------------------------------------------------------------------------------
-- Instance methods (all classes)
------------------------------------------------------------------------------------------
local M = {}
I.methods.Instance = M

function M:FindFirstChild(name, recursive)
	return I.findChild(self, name, recursive)
end
function M:FindFirstChildOfClass(cls)
	for _, c in S[self].children do
		if S[c].className == cls then
			return c
		end
	end
	return nil
end
function M:FindFirstChildWhichIsA(cls, recursive)
	for _, c in S[self].children do
		if S[c].info.isA[cls] then
			return c
		end
	end
	if recursive then
		for _, c in S[self].children do
			local r = M.FindFirstChildWhichIsA(c, cls, true)
			if r then
				return r
			end
		end
	end
	return nil
end
function M:FindFirstAncestor(name)
	local cur = S[self].parent
	while cur do
		if S[cur].name == name then
			return cur
		end
		cur = S[cur].parent
	end
	return nil
end
function M:FindFirstAncestorOfClass(cls)
	local cur = S[self].parent
	while cur do
		if S[cur].className == cls then
			return cur
		end
		cur = S[cur].parent
	end
	return nil
end
function M:FindFirstAncestorWhichIsA(cls)
	local cur = S[self].parent
	while cur do
		if S[cur].info.isA[cls] then
			return cur
		end
		cur = S[cur].parent
	end
	return nil
end
function M:FindFirstDescendant(name)
	return I.findChild(self, name, true)
end
function M:GetChildren()
	return table.clone(S[self].children)
end
M.getChildren = M.GetChildren
M.children = M.GetChildren
function M:GetDescendants()
	local out = {}
	eachDescendant(self, function(d)
		table.insert(out, d)
	end)
	return out
end
function M:IsA(cls)
	return S[self].info.isA[cls] == true
end
function M:IsDescendantOf(other)
	if other == nil then
		return false
	end
	return isAncestor(other, self)
end
function M:IsAncestorOf(other)
	return other ~= nil and isAncestor(self, other)
end
function M:GetFullName()
	return fullName(self)
end
function M:Destroy()
	I.destroy(self)
end
M.destroy = M.Destroy
function M:Remove()
	I.setParent(self, nil)
end
function M:ClearAllChildren()
	for _, c in table.clone(S[self].children) do
		I.destroy(c)
	end
end
function M:Clone()
	return I.clone(self)
end
M.clone = M.Clone
function M:GetDebugId()
	return tostring(S[self].id)
end
function M:GetActor()
	return nil
end

local WAIT_WARN = 5
function M:WaitForChild(name, timeout)
	local c = I.findChild(self, name)
	if c then
		return c
	end
	if not coroutine.isyieldable() then
		C.rterror("WaitForChild called from a non-yieldable context")
	end
	local co = coroutine.running()
	local w = { co = co, done = false }
	local st = S[self]
	st.waiters[name] = st.waiters[name] or {}
	table.insert(st.waiters[name], w)
	local where = C.where(3)
	local desc = 'WaitForChild("' .. tostring(name) .. '") on ' .. fullName(self)
	if timeout then
		C.delay(timeout, function()
			if not w.done then
				w.done = true
				C.addLog("wait_timeout", desc .. " timed out after " .. tostring(timeout) .. "s (returned nil)", where)
				C.resume(co, nil)
			end
		end)
	else
		C.delay(WAIT_WARN, function()
			if not w.done then
				C.addLog("infinite_yield", "Infinite yield possible on " .. desc, where)
			end
		end)
	end
	C.blocked[co] = { desc = desc, where = where, since = C.now }
	return coroutine.yield()
end

-- attributes
local attrTypes = {
	string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, Font = true, EnumItem = true,
}
function M:GetAttribute(name)
	return S[self].attrs[name]
end
function M:SetAttribute(name, value)
	local st = S[self]
	if value ~= nil and not attrTypes[C.typeof(value)] then
		C.rterror("SetAttribute: " .. C.typeof(value) .. " is not a supported attribute type")
	end
	local old = st.attrs[name]
	st.attrs[name] = value
	if old ~= value then
		local s = st.attrSignals[name]
		if s then
			s:Fire()
		end
		local ac = st.signals.AttributeChanged
		if ac then
			ac:Fire(name)
		end
	end
end
function M:GetAttributes()
	return table.clone(S[self].attrs)
end
function M:GetAttributeChangedSignal(name)
	local st = S[self]
	local s = st.attrSignals[name]
	if not s then
		s = C.newSignal(st.name .. ":GetAttributeChangedSignal(" .. name .. ")")
		st.attrSignals[name] = s
	end
	return s
end
function M:GetPropertyChangedSignal(prop)
	local st = S[self]
	if not st.info.props[prop] and prop ~= "Name" and prop ~= "Parent" then
		C.rterror(prop .. " is not a valid property name.")
	end
	return I.propSignal(self, prop)
end
-- tags
function M:AddTag(tag)
	local st = S[self]
	if not st.tags[tag] then
		st.tags[tag] = true
		if I.onTag then
			I.onTag(self, tag, true)
		end
	end
end
function M:RemoveTag(tag)
	local st = S[self]
	if st.tags[tag] then
		st.tags[tag] = nil
		if I.onTag then
			I.onTag(self, tag, false)
		end
	end
end
function M:HasTag(tag)
	return S[self].tags[tag] == true
end
function M:GetTags()
	local out = {}
	for k in S[self].tags do
		table.insert(out, k)
	end
	return out
end
function M:IsPropertyModified(p)
	return S[self].props[p] ~= nil
end
function M:ResetPropertyToDefault(p)
	S[self].props[p] = nil
end

return I
