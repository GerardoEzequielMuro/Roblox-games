--!strict
-- Localizes the world text the server builds (egg labels, gate signs, leaderboard titles,
-- proximity prompts). The server tags each TextLabel with a Loc* attribute; this module
-- rewrites it in the player's language and again whenever the language changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Lang = require(script.Parent.Lang)
local Net = require(script.Parent.Net)

local WorldText = {}

local function render(obj: Instance)
	if obj:IsA("TextLabel") then
		local eggId = obj:GetAttribute("LocEgg")
		local gate = obj:GetAttribute("LocGate")
		local zone = obj:GetAttribute("LocZone")
		local key = obj:GetAttribute("LocKey")
		if type(eggId) == "string" then
			local egg = Formulas.EggById[eggId]
			if egg then
				local state = Net.state
				local need = Formulas.eggMinRebirths(eggId)
				local price = if egg.exclusive
					then ('<font color="#7CFF7C">' .. Lang.t("world.robux_exclusive") .. "</font>")
					elseif state and (state.rebirths or 0) < need then ('<font color="#FF8A8A">' .. Lang.t("world.egg_locked", { n = need }) .. "</font>")
					else Lang.t("world.price_taps", { n = Format.abbrev(egg.price) })
				obj.Text = string.format('%s\n<font color="#FFE066">%s</font>', Lang.egg(eggId), price)
			end
		elseif type(gate) == "number" and Config.Zones[gate] then
			obj.Text = Lang.t("world.gate_locked") .. "\n" .. Lang.t("world.price_taps", { n = Format.abbrev(Config.Zones[gate].cost) })
		elseif type(zone) == "number" then
			obj.Text = Lang.upper(Lang.zone(zone))
		elseif type(key) == "string" then
			obj.Text = Lang.t(key)
		end
	elseif obj:IsA("ProximityPrompt") then
		local eggId = obj:GetAttribute("EggId")
		local zone = obj:GetAttribute("Zone")
		if obj:GetAttribute("Chest") then
			obj.ActionText = Lang.t("prompt.collect")
			obj.ObjectText = Lang.t("park.chest_name")
		elseif type(eggId) == "string" then
			obj.ActionText = Lang.t("prompt.open")
			obj.ObjectText = Lang.egg(eggId)
		elseif type(zone) == "number" and Config.Zones[zone] then
			obj.ActionText = Lang.t("prompt.unlock", { cost = Format.abbrev(Config.Zones[zone].cost) })
			obj.ObjectText = Lang.zone(zone)
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
		-- leaderboard rows are rebuilt every minute
		world.DescendantAdded:Connect(function(d)
			task.defer(render, d)
		end)
		Lang.Changed:Connect(all)
		-- rebirth-gated egg signs flip from "locked" to the price when the player rebirths
		local lastRebirths = -1
		Net.Changed:Connect(function(kind)
			local r = (Net.get("rebirths") :: number?) or 0
			if kind == "full" and r ~= lastRebirths then
				lastRebirths = r
				all()
			end
		end)
	end)
end

return WorldText
