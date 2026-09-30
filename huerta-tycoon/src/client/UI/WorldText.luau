--!nonstrict
-- Re-renders server-tagged world text (Locale.stamp: LocKey/LocArgs attributes on SurfaceGui/BillboardGui labels
-- and ProximityPrompts) in this player's language. Changes are local to this client.
local HttpService = game:GetService("HttpService")

local I18n = require(script.Parent.I18n)

local WorldText = {}

local PROPS = { Text = "", ActionText = "_ActionText", ObjectText = "_ObjectText" }
local tracked: { [Instance]: boolean } = {}

local function render(inst: Instance)
	for prop, suffix in PROPS do
		local key = inst:GetAttribute("LocKey" .. suffix)
		if type(key) == "string" and key ~= "" then
			local rawArgs = inst:GetAttribute("LocArgs" .. suffix)
			local args = nil
			if type(rawArgs) == "string" and rawArgs ~= "" then
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, rawArgs)
				if ok and type(decoded) == "table" then
					args = decoded
				end
			end
			pcall(function()
				(inst :: any)[prop] = I18n.t(key, args)
			end)
		end
	end
end

local function track(inst: Instance)
	if tracked[inst] then
		return
	end
	if inst:GetAttribute("LocKey") == nil and inst:GetAttribute("LocKey_ActionText") == nil then
		return
	end
	tracked[inst] = true
	inst.Destroying:Once(function()
		tracked[inst] = nil
	end)
	render(inst)
	inst.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 3) == "Loc" then
			render(inst)
		end
	end)
	-- the server may rewrite the English text after the tag; translate it again (no loop: same value = no event)
	for prop, suffix in PROPS do
		if inst:GetAttribute("LocKey" .. suffix) ~= nil then
			inst:GetPropertyChangedSignal(prop):Connect(function()
				task.defer(render, inst)
			end)
		end
	end
end

function WorldText.init()
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(function(d)
		-- attributes replicate with the instance; defer one frame to be safe
		task.defer(track, d)
	end)
	I18n.onChanged(function()
		for inst in tracked do
			if inst.Parent then
				render(inst)
			end
		end
	end)
end

return WorldText
