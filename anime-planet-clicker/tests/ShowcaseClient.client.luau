-- Screenshot showcase: every time the runner resizes the window, move on to the next scene.
-- Workspace attributes: ShowcaseSet (1 = world + main UI, 2 = every window),
-- ShowcaseFrom (skip ahead), ShowcaseLow (force the lite profile and strip everything
-- graphics quality 1 does not draw: shadows, post effects, glow lights, particles).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local low = workspace:GetAttribute("ShowcaseLow") == true
if low then
	workspace:SetAttribute("ForceLite", true)
end

local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local UI = Client:WaitForChild("UI")
local Windows = require(UI:WaitForChild("Windows"))
local CapsulePanel = require(UI:WaitForChild("CapsulePanel"))
local CapsuleCinematic = require(UI:WaitForChild("CapsuleCinematic"))
local UpgradesWindow = require(UI:WaitForChild("UpgradesWindow"))
local PetsWindow = require(UI:WaitForChild("PetsWindow"))
local Miner = require(Client:WaitForChild("Miner"))
local PlanetField = require(Client:WaitForChild("PlanetField"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Layout = require(Shared:WaitForChild("Layout"))
local PetModel = require(Shared:WaitForChild("PetModel"))
local PlanetModel = require(Shared:WaitForChild("PlanetModel"))
local ToolModel = require(Shared:WaitForChild("ToolModel"))

local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart")
local showcase = ReplicatedStorage:WaitForChild("__Showcase") :: RemoteEvent
local Request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Request") :: RemoteFunction

if low then
	-- what a phone at graphics quality 1 does not get
	local okQ = pcall(function()
		(settings() :: any).Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	print("[TEST] showcase low: real quality switch ok=" .. tostring(okQ))
	task.spawn(function()
		while true do
			Lighting.GlobalShadows = false
			for _, e in Lighting:GetChildren() do
				if e:IsA("PostEffect") then
					e.Enabled = false
				elseif e:IsA("Atmosphere") then
					e:Destroy()
				end
			end
			for _, d in workspace:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d.Rate = d.Rate * 0.2
				elseif d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then
					d.Enabled = false
				end
			end
			task.wait(3)
		end
	end)
end

local camCF: CFrame? = nil
RunService.RenderStepped:Connect(function()
	if camCF then
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCF
	end
end)
local function freeCam()
	camCF = nil
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end
local function tp(x: number, y: number, z: number)
	showcase:FireServer("tp", { x, y, z })
end
local function lang(code: string)
	Request:InvokeServer("SetLanguage", { lang = code })
end

-- Wide shot of a galaxy from above its plaza.
local function zoneView(z: number)
	local c = Layout.zoneCenter(z)
	tp(c[1] + 6, 4, c[3] - 60)
	task.wait(2.2)
	camCF = CFrame.lookAt(Vector3.new(c[1] - 34, 46, c[3] - 128), Vector3.new(c[1] + 4, 8, c[3] + 6))
end

-- Character mining a planet, camera behind the shoulder.
local function miningView(z: number, node: number, kind: string)
	showcase:FireServer("node", { z, node, kind })
	local p = Layout.nodePosition(z, node)
	tp(p[1] + 3, 4, p[3] - 13)
	task.wait(2)
	PlanetField.reload()
	task.wait(1.2)
	camCF = CFrame.lookAt(Vector3.new(p[1] - 15, 10, p[3] - 27), Vector3.new(p[1] + 1, 8, p[3] - 3))
	task.spawn(function()
		for _ = 1, 40 do
			Miner.simulate(node)
			task.wait(0.16)
		end
	end)
end

local galleryFolder = Instance.new("Folder")
galleryFolder.Name = "Gallery"
galleryFolder.Parent = workspace
local GALLERY = Vector3.new(0, 320, -300)
local function backdrop()
	local wall = Instance.new("Part")
	wall.Anchored = true
	wall.Size = Vector3.new(90, 50, 1)
	wall.CFrame = CFrame.new(GALLERY + Vector3.new(0, 0, 14))
	wall.Color = Color3.fromRGB(38, 44, 84)
	wall.Material = Enum.Material.SmoothPlastic
	wall.Parent = galleryFolder
end
local function gallery(build: (any) -> Model, list: { any }, cols: number, spacing: number, distance: number)
	galleryFolder:ClearAllChildren()
	backdrop()
	for i, spec in list do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local rows = math.ceil(#list / cols)
		local m = build(spec)
		m:PivotTo(CFrame.new(GALLERY + Vector3.new((col - (cols - 1) / 2) * spacing, ((rows - 1) / 2 - row) * spacing * 0.95, 0)) * CFrame.Angles(0, math.rad(200), 0))
		m.Parent = galleryFolder
	end
	camCF = CFrame.lookAt(GALLERY + Vector3.new(0, 0, -distance), GALLERY)
end
local function petBatch(from: number, to: number): { any }
	local list = {}
	for i = from, math.min(to, #Config.Pets) do
		table.insert(list, { Config.Pets[i].id, 0 })
	end
	return list
end
local function buildPet(spec: any): Model
	return PetModel.build(spec[1], spec[2] or 0, { lights = false, lite = low })
end

local scenes = {
	function() -- 1: Dawn Belt from above the plaza
		zoneView(1)
	end,
	function() -- 2: mining a Fury planet (tool, pets, numbers, HUD)
		miningView(1, 2, "fury")
	end,
	function() -- 3: plaza close-up: capsule machine, refinery, workshop
		local c = Layout.zoneCenter(1)
		tp(c[1], 4, c[3] - 66)
		task.wait(2)
		camCF = CFrame.lookAt(Vector3.new(c[1] + 4, 13, c[3] - 28), Vector3.new(c[1] - 4, 6, c[3] - 78))
	end,
	function() -- 4: every planet kind
		local list = {}
		for _, k in Config.PlanetKinds do
			table.insert(list, k.id)
		end
		gallery(function(id)
			return PlanetModel.build(id, 1, { lite = low, scale = if id == "titan" then 0.5 elseif id == "gate" then 0.42 else 1 })
		end, list, 5, 17, 74)
	end,
	function() -- 5: pets 1-12
		gallery(buildPet, petBatch(1, 12), 6, 4.6, 24)
	end,
	function() -- 6: pets 13-24
		gallery(buildPet, petBatch(13, 24), 6, 4.8, 25)
	end,
	function() -- 7: pets 25-35 + Golden / Prism
		local list = petBatch(25, 99)
		for _, spec in { { "pebblepup", 1 }, { "cometcat", 2 }, { "frostwyrm", 1 }, { "roverbot", 2 }, { "nulldragon", 2 }, { "solarfox", 1 }, { "sporemoth", 2 } } do
			table.insert(list, spec)
		end
		gallery(buildPet, list, 6, 5, 28)
	end,
	function() -- 8: every tool
		local list = {}
		for _, t in Config.Tools do
			table.insert(list, t.id)
		end
		gallery(function(id)
			local m = ToolModel.build(id)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			m:PivotTo(CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(40)))
			return m
		end, list, 6, 6.5, 30)
	end,
	function() -- 9: Verdant Nebula
		galleryFolder:ClearAllChildren()
		zoneView(2)
	end,
	function() -- 10: Frost Halo
		zoneView(3)
	end,
	function() -- 11: Ember Forge
		zoneView(4)
	end,
	function() -- 12: Storm Reach
		zoneView(5)
	end,
	function() -- 13: Void Crown
		zoneView(6)
	end,
	function() -- 14: the Titan and the Gate of Frost Halo, from the deck
		local c = Layout.zoneCenter(3)
		tp(c[1] + 10, 4, c[3] - 30)
		task.wait(2.2)
		camCF = CFrame.lookAt(Vector3.new(c[1] + 26, 9, c[3] - 50), Vector3.new(c[1] - 4, 22, c[3] + 40))
	end,
	function() -- 15: Meteor Arena
		local a = Config.ArenaCenter
		tp(a[1], 4, a[3] - 40)
		task.wait(2.2)
		camCF = CFrame.lookAt(Vector3.new(a[1] - 40, 42, a[3] - 110), Vector3.new(a[1], 4, a[3]))
	end,
	function() -- 16: plain HUD while mining, player camera
		freeCam()
		miningView(1, 3, "aurum")
		task.wait(3.4)
		freeCam()
	end,
	function() -- 17: capsule panel
		local cp = Layout.capsulePosition("dawn")
		tp(cp[1] + 8, 4, cp[3] + 6)
		task.wait(1.5)
		CapsulePanel.open("dawn")
	end,
	function() -- 18: capsule cinematic x3 with a Legendary
		Windows.close()
		task.wait(3.6)
		CapsuleCinematic.play("dawn", {
			{ uid = "x1", id = "cometcat", tier = 0, chance = 12, rarity = "Rare", new = true },
			{ uid = "x2", id = "solarfox", tier = 1, chance = 0.1, rarity = "Legendary" },
			{ uid = "x3", id = "dustbunny", tier = 0, chance = 30, rarity = "Uncommon" },
		}, false)
	end,
	function() -- 19
		UpgradesWindow.open("tools")
	end,
	function() -- 20
		UpgradesWindow.open("stats")
	end,
	function() -- 21
		Windows.open("Pets")
		task.wait(0.6)
		PetsWindow.selectFirst()
	end,
	function() -- 22
		Windows.open("Store")
	end,
	function() -- 23
		Windows.open("Index")
	end,
	function()
		Windows.close()
	end,
}

-- Set 2: every other window and the popups.
local scenes2 = {
	function()
		local c = Layout.zoneCenter(1)
		tp(c[1] + 12, 4, c[3] - 40)
		UpgradesWindow.open("relics")
	end,
	function()
		UpgradesWindow.open("temper")
	end,
	function()
		UpgradesWindow.open("constellation")
	end,
	function()
		Windows.open("Rebirth")
	end,
	function()
		Windows.open("Teleport")
	end,
	function()
		Windows.open("Rewards")
	end,
	function()
		Windows.open("Quests")
	end,
	function()
		Windows.open("Auto")
	end,
	function()
		Windows.open("Settings")
	end,
	function()
		Windows.open("Invite")
	end,
	function()
		Windows.close()
		showcase:FireServer("offline")
	end,
	function() -- 12: capsule cinematic build-up
		local holder = player.PlayerGui.PlanetUI:FindFirstChild("PopupHolder")
		if holder then
			holder:Destroy()
		end
		task.wait(5.4)
		CapsuleCinematic.play("frost", { { uid = "z1", id = "frostwyrm", tier = 0, chance = 0.1, rarity = "Legendary", new = true } }, false)
	end,
	function() -- 13: index planets tab in German (longest words)
		lang("de")
		Windows.open("Index")
	end,
	function() -- 14: store in Russian
		lang("ru")
		Windows.open("Store")
	end,
	function() -- 15: HUD in Japanese
		lang("ja")
		Windows.close()
	end,
	function()
		lang("")
		Windows.close()
	end,
}
local set = tonumber(workspace:GetAttribute("ShowcaseSet")) or 1
if set == 2 then
	scenes = scenes2
end

local index = math.max(0, (tonumber(workspace:GetAttribute("ShowcaseFrom")) or 1) - 1)
local token = 0
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	token += 1
	local my = token
	task.delay(0.4, function()
		if my ~= token then
			return
		end
		index += 1
		local fn = scenes[index]
		if fn then
			print("[TEST] showcase scene " .. index)
			task.spawn(fn)
		end
	end)
end)
