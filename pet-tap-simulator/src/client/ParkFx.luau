--!strict
-- Pet Park, client side: puts each owner's equipped pets on the pedestals of their plot,
-- writes the owner's name on the sign, and shows what is waiting in your own chest.
-- Cheap on purpose: statues are "lite" pet builds (no particles, lights or joints), they are
-- only built for plots near the camera, and everything is refreshed by one loop once a second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)
local Quality = require(script.Parent.Quality)

local ParkFx = {}

local RANGE = 110 -- studs from the camera: statues of other players' plots
local PEDESTALS = 6

type Shown = { key: string, models: { Model } }
local shown: { [Instance]: Shown } = {}

local folder = Instance.new("Folder")
folder.Name = "ParkPets"
folder.Parent = Workspace

local function clear(plot: Instance)
	local s = shown[plot]
	if s then
		for _, m in s.models do
			m:Destroy()
		end
		shown[plot] = nil
	end
end

local function ownerOf(plot: Instance): Player?
	local id = plot:GetAttribute("OwnerId")
	if type(id) ~= "number" or id == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

local function build(plot: Instance, key: string)
	clear(plot)
	local models: { Model } = {}
	local slot = 0
	for entry in key:gmatch("[^,]+") do
		local id, tier = entry:match("^(.-):(%d)$")
		slot += 1
		local pedestal = plot:FindFirstChild("Pedestal" .. slot)
		if id and pedestal and pedestal:IsA("BasePart") and slot <= PEDESTALS then
			local m = PetModel.build(id, tonumber(tier) or 0, { lite = true })
			local foot = (m:GetAttribute("FootY") :: number?) or -1.3
			local facing = plot:GetAttribute("Facing")
			local yaw = if type(facing) == "number" then facing else 0
			-- stand on top of the pedestal (an upright cylinder: its X size is the height)
			local top = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2 - foot, 0)
			m:PivotTo(CFrame.new(top) * CFrame.Angles(0, yaw, 0))
			m.Parent = folder
			table.insert(models, m)
		end
	end
	shown[plot] = { key = key, models = models }
end

-- Statues currently built, plots tracked (playtest).
function ParkFx.counts(): (number, number)
	local statues, plots = 0, 0
	for _, s in shown do
		plots += 1
		statues += #s.models
	end
	return statues, plots
end

local function refresh(park: Instance)
	local camera = Workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local state = Net.state
	local me = Players.LocalPlayer
	for _, plot in park:GetChildren() do
		if not plot:IsA("Model") then
			continue
		end
		local owner = ownerOf(plot)
		local mine = owner == me
		-- sign
		local sign = plot:FindFirstChild("OwnerText", true)
		if sign and sign:IsA("TextLabel") then
			local name = plot:GetAttribute("OwnerName")
			local text = if owner and type(name) == "string" and name ~= "" then name else Lang.t("park.free")
			if sign.Text ~= text then
				sign.Text = text
				sign.TextColor3 = if owner then Color3.new(1, 1, 1) else Color3.fromRGB(190, 190, 205)
			end
		end
		-- chest label: only your own chest tells you what is inside
		local label = plot:FindFirstChild("ChestText", true)
		if label and label:IsA("TextLabel") then
			local text = ""
			local ready = false
			if mine and state then
				local pending = if state.offline then state.offline.pending or 0 else 0
				ready = pending > 0
				text = if ready then Lang.t("park.pending", { n = Format.abbrev(pending) }) else Lang.t("park.empty")
			end
			if label.Text ~= text then
				label.Text = text
				label.TextColor3 = if ready then Color3.fromRGB(255, 225, 90) else Color3.fromRGB(235, 235, 245)
			end
			local glow = plot:FindFirstChild("ChestGlow", true)
			if glow and glow:IsA("BasePart") then
				glow.Transparency = if ready then 0.25 else 1
			end
		end
		-- statues
		local key = ""
		if owner then
			local pos = plot:GetPivot().Position
			local near = (pos - camPos).Magnitude < RANGE
			if near and (mine or not Quality.lite) then
				local eq = owner:GetAttribute("EquippedPets")
				key = if type(eq) == "string" then eq else ""
			end
		end
		local s = shown[plot]
		if key == "" then
			if s then
				clear(plot)
			end
		elseif not s or s.key ~= key then
			build(plot, key)
		end
	end
	-- plots that streamed out
	for plot in shown do
		if not plot.Parent then
			clear(plot)
		end
	end
end

function ParkFx.init()
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 60)
		local park = world and world:WaitForChild("Park", 60)
		if not park then
			return
		end
		while true do
			local ok, err = pcall(function()
				refresh(park)
			end)
			if not ok then
				warn("[ParkFx]", err)
			end
			task.wait(1)
		end
	end)
end

return ParkFx
