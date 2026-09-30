--!strict
-- Localizes world text built by the server. The server tags a TextLabel with the attributes
-- LocKey (+ optional LocArgs, a JSON object) and a ProximityPrompt with LocAction / LocObject;
-- this module writes the translated text locally and again whenever the language changes.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Lang = require(script.Parent.Parent.Lang)

local WorldText = {}

-- strong tables (weak Instance keys get collected while the Instance is alive); cleaned on Destroying
local labels: { [Instance]: boolean } = {}
local prompts: { [Instance]: boolean } = {}

local function decode(json: any): { [string]: any }?
	if type(json) ~= "string" or json == "" then
		return nil
	end
	local ok, t = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	return if ok and type(t) == "table" then t else nil
end

local function applyLabel(inst: Instance)
	local key = inst:GetAttribute("LocKey")
	if type(key) == "string" and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
		(inst :: any).Text = Lang.t(key, decode(inst:GetAttribute("LocArgs")))
	end
end

local function applyPrompt(inst: Instance)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	local action = inst:GetAttribute("LocAction")
	local object = inst:GetAttribute("LocObject")
	if type(action) == "string" then
		inst.ActionText = Lang.t(action)
	end
	if type(object) == "string" then
		inst.ObjectText = Lang.t(object)
	end
end

local function track(inst: Instance)
	if inst:GetAttribute("LocKey") ~= nil then
		labels[inst] = true
		inst.Destroying:Once(function()
			labels[inst] = nil
		end)
		applyLabel(inst)
		inst:GetAttributeChangedSignal("LocArgs"):Connect(function()
			applyLabel(inst)
		end)
		inst:GetAttributeChangedSignal("LocKey"):Connect(function()
			applyLabel(inst)
		end)
	elseif inst:IsA("ProximityPrompt") and (inst:GetAttribute("LocAction") ~= nil or inst:GetAttribute("LocObject") ~= nil) then
		prompts[inst] = true
		inst.Destroying:Once(function()
			prompts[inst] = nil
		end)
		applyPrompt(inst)
	end
end

function WorldText.init()
	for _, d in Workspace:GetDescendants() do
		track(d)
	end
	Workspace.DescendantAdded:Connect(function(d)
		task.defer(track, d) -- attributes are set before parenting, but be safe
	end)
	Lang.changed:Connect(function()
		for inst in labels do
			applyLabel(inst)
		end
		for inst in prompts do
			applyPrompt(inst)
		end
	end)
end

-- Exposed for other client modules that build localized world text themselves.
WorldText.track = track

return WorldText
