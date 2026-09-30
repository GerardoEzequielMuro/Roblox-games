--!strict
-- Localizes the world text the server builds (capsule signs, galaxy names, gate signs,
-- board titles, prompts). The server tags each TextLabel with a Loc* attribute; this module
-- writes it in the player's language, and again when the language changes or when the part
-- streams in.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Lang = require(script.Parent.Lang)

local WorldText = {}

local function render(obj: Instance)
	if obj:IsA("TextLabel") then
		local capsule = obj:GetAttribute("LocCapsule")
		local gate = obj:GetAttribute("LocGate")
		local zone = obj:GetAttribute("LocZone")
		local key = obj:GetAttribute("LocKey")
		if type(capsule) == "string" then
			local cap = Formulas.CapsuleById[capsule]
			if cap then
				local price = if cap.exclusive then ('<font color="#D9A0FF">R$ ' .. Lang.t("capsule.robux_only") .. "</font>") else ('<font color="#FFD650">' .. Format.abbrev(cap.price) .. " ✨</font>")
				obj.Text = Lang.capsule(capsule) .. "\n" .. price
			end
		elseif type(gate) == "number" and Config.Zones[gate] then
			obj.Text = Lang.t("world.gate_sign", { zone = Lang.upper(Lang.zone(gate)) })
		elseif type(zone) == "number" then
			obj.Text = Lang.upper(Lang.zone(zone))
		elseif type(key) == "string" then
			obj.Text = Lang.upper(Lang.t(key))
		end
	elseif obj:IsA("ProximityPrompt") then
		local open = obj:GetAttribute("Open")
		if open == "Capsule" then
			obj.ActionText = Lang.t("prompt.open")
			obj.ObjectText = Lang.capsule(obj:GetAttribute("CapsuleId") :: string)
		elseif open == "Upgrades" then
			local system = obj:GetAttribute("System")
			obj.ActionText = Lang.t("prompt.open")
			obj.ObjectText = if type(system) == "string" then Lang.t("system." .. system .. ".name") else Lang.t("world.workshop")
		elseif open == "Teleport" then
			obj.ActionText = Lang.t("prompt.warp")
			obj.ObjectText = Lang.t("win.teleport")
		end
	end
end

function WorldText.init()
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		local function all()
			for _, d in world:GetDescendants() do
				render(d)
			end
		end
		all()
		world.DescendantAdded:Connect(function(d)
			task.defer(render, d)
		end)
		Lang.Changed:Connect(all)
	end)
end

return WorldText
