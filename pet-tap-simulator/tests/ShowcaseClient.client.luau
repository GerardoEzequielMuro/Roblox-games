-- Screenshot showcase: every time the runner resizes the window, move on to the next scene.
-- Scene list (one screenshot each): see `scenes` below. The workspace attribute
-- "ShowcaseFrom" skips ahead (e.g. 10 starts at the zone overviews).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local UI = Client:WaitForChild("UI")
local EggPanel = require(UI:WaitForChild("EggPanel"))
local Windows = require(UI:WaitForChild("Windows"))
local HatchCinematic = require(UI:WaitForChild("HatchCinematic"))
local Tapper = require(Client:WaitForChild("Tapper"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PetModel = require(ReplicatedStorage.Shared:WaitForChild("PetModel"))

local char = player.Character or player.CharacterAdded:Wait()
char:WaitForChild("HumanoidRootPart")

local camCF: CFrame? = nil
RunService.RenderStepped:Connect(function()
	if camCF then
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCF
	end
end)
local Request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Request") :: RemoteFunction
local showcase = ReplicatedStorage:WaitForChild("__Showcase") :: RemoteEvent
local function lang(code: string)
	Request:InvokeServer("SetLanguage", { lang = code })
end

local function place(pos: Vector3, look: Vector3)
	char:PivotTo(CFrame.lookAt(pos, pos + look))
end

local L = Config.ZoneLength

-- Walks the character into zone z and looks at it from above the path.
local function zoneView(z: number)
	local zc = (z - 1) * L
	place(Vector3.new(6, 4, zc - 58), Vector3.new(0, 0, 1))
	task.wait(1)
	camCF = CFrame.lookAt(Vector3.new(-20, 24, zc - 96), Vector3.new(4, 6, zc + 10))
end

-- Close-up of a batch of pets floating over the spawn plaza.
local galleryFolder = Instance.new("Folder")
galleryFolder.Name = "Gallery"
galleryFolder.Parent = workspace
local function gallery(list: { { any } })
	galleryFolder:ClearAllChildren()
	place(Vector3.new(0, 4, -75), Vector3.new(0, 0, 1))
	local cols = 6
	for i, spec in list do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local m = PetModel.build(spec[1], spec[2] or 0, { lights = false })
		m:PivotTo(CFrame.new((col - (cols - 1) / 2) * 4.4 + 1.5, 45.2 - row * 4.6, -20) * CFrame.Angles(0, math.rad(-22), 0))
		m.Parent = galleryFolder
	end
	camCF = CFrame.lookAt(Vector3.new(0, 44.6, -40), Vector3.new(0, 44.6, -20))
end
local function petBatch(from: number, to: number): { { any } }
	local list = {}
	for i = from, math.min(to, #Config.Pets) do
		table.insert(list, { Config.Pets[i].id, 0 })
	end
	return list
end

local function tapBurst(seconds: number)
	task.spawn(function()
		local t0 = os.clock()
		local cam = workspace.CurrentCamera
		while os.clock() - t0 < seconds do
			local vp = cam.ViewportSize
			Tapper.simulate(Vector2.new(vp.X * (0.55 + math.random() * 0.12), vp.Y * (0.38 + math.random() * 0.12)))
			task.wait(0.09)
		end
	end)
end

-- Minimum graphics preview (showcase_low.project.json). Tries the real setting first; either
-- way it then switches off everything graphics level 1 drops (shadows, bloom, sun rays,
-- colour grade, atmosphere, clouds) so the screenshots show the worst case.
if workspace:GetAttribute("ShowcaseLow") then
	local okReal = pcall(function()
		(settings() :: any).Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	local okSaved = pcall(function()
		UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
	end)
	print("[TEST] low graphics: Rendering.QualityLevel set = " .. tostring(okReal) .. ", SavedQualityLevel set = " .. tostring(okSaved))
	workspace:SetAttribute("ForceLite", true)
	local Lighting = game:GetService("Lighting")
	task.spawn(function()
		while true do
			Lighting.GlobalShadows = false
			for _, fx in Lighting:GetChildren() do
				if fx:IsA("PostEffect") then
					fx.Enabled = false
				elseif fx:IsA("Atmosphere") then
					fx.Density = 0
					fx.Haze = 0
					fx.Glare = 0
				end
			end
			local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
			if clouds then
				clouds.Enabled = false
			end
			task.wait(0.25)
		end
	end)
end

local basic = Vector3.new(-30, 4, 30)
local scenes = {
	function() -- 1: spawn plaza
		place(Vector3.new(0, 4, -75), Vector3.new(0, 0, 1))
		task.wait(1)
		camCF = CFrame.lookAt(Vector3.new(30, 20, -22), Vector3.new(-4, 7, -92))
	end,
	function() -- 2: meadow, pets following, egg panel open
		local p = basic + Vector3.new(10, 0, -8)
		place(p, Vector3.new(0, 0, -1))
		task.wait(1.5)
		camCF = CFrame.lookAt(p + Vector3.new(-2, 8, -22), p + Vector3.new(-3, 1.5, 4))
		task.wait(1)
		EggPanel.open("basic", basic)
	end,
	function() -- 3: hatch cinematic x3 (Legendary in the middle), just after the burst
		EggPanel.close()
		task.wait(4.3)
		HatchCinematic.play("spotted", {
			{ uid = "x1", id = "fox", tier = 0, chance = 10.5, rarity = "Rare", new = true },
			{ uid = "x2", id = "unicorn", tier = 1, chance = 0.1, rarity = "Legendary" },
			{ uid = "x3", id = "chick", tier = 0, chance = 32, rarity = "Uncommon" },
		}, false)
	end,
	function() -- 4: pets window
		Windows.open("Pets")
	end,
	function() -- 5-8: every pet, close up
		Windows.close()
		gallery(petBatch(1, 12))
	end,
	function()
		gallery(petBatch(13, 24))
	end,
	function()
		gallery(petBatch(25, 36))
	end,
	function()
		local list = petBatch(37, 99)
		for _, spec in { { "dog", 1 }, { "dog", 2 }, { "fox", 1 }, { "unicorn", 2 }, { "firedragon", 1 }, { "galaxydragon", 2 }, { "bear", 1 } } do
			table.insert(list, spec)
		end
		gallery(list)
	end,
	function() -- 9: meadow overview with pets, tapping (combo + numbers)
		galleryFolder:ClearAllChildren()
		local p = Vector3.new(6, 4, -20)
		place(p, Vector3.new(0, 0, 1))
		task.wait(1)
		camCF = CFrame.lookAt(Vector3.new(-3, 13, -52), Vector3.new(8, 4, 24))
		task.wait(2.5)
		tapBurst(4)
	end,
	function() -- 10: candy land
		zoneView(2)
	end,
	function() -- 11: frost peak
		zoneView(3)
	end,
	function() -- 12: lava caves
		zoneView(4)
	end,
	function() -- 13: locked gate close up
		local zc = 3 * L
		place(Vector3.new(4, 4, zc + 78), Vector3.new(0, 0, 1))
		task.wait(1)
		camCF = CFrame.lookAt(Vector3.new(-12, 9, zc + 70), Vector3.new(1, 9, zc + 110))
	end,
	function() -- 14: cosmic void
		showcase:FireServer("unlock5")
		task.wait(1.2)
		zoneView(5)
	end,
	function() -- 15: cosmic landmarks
		local zc = 4 * L
		place(Vector3.new(0, 4, zc + 30), Vector3.new(0, 0, 1))
		task.wait(1)
		camCF = CFrame.lookAt(Vector3.new(14, 12, zc + 10), Vector3.new(-14, 14, zc + 90))
	end,
	function() -- 16: Magic Egg at spawn
		local magic = Vector3.new(45, 4, -72)
		place(magic + Vector3.new(-9, 0, -6), Vector3.new(1, 0, 0.4))
		task.wait(1.2)
		camCF = CFrame.lookAt(magic + Vector3.new(-16, 8, -14), magic + Vector3.new(0, 4, 0))
	end,
	function() -- 17: Pet Park (own plot with a full chest, entrance arch behind)
		showcase:FireServer("offline")
		Request:InvokeServer("GoPark")
		task.wait(1.5)
		local holder = player.PlayerGui.TapPetsUI:FindFirstChild("PopupHolder")
		if holder then
			holder:Destroy()
		end
		local me = char:GetPivot().Position
		camCF = CFrame.lookAt(me + Vector3.new(26, 20, if me.Z > -144 then -30 else 30), me + Vector3.new(-6, 1, if me.Z > -144 then 14 else -14))
	end,
	-- 920x505-ish viewport from here on
	function() -- 18: plain HUD, meadow
		camCF = nil
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		place(basic + Vector3.new(10, 0, -8), Vector3.new(0, 0, -1))
	end,
	function() -- 18
		Windows.open("Pets")
	end,
	function() -- 19
		Windows.close()
		EggPanel.open("basic", basic)
	end,
	function() -- 20
		EggPanel.close()
		Windows.open("Index")
	end,
	function() -- 21: hatch reveal (single, Epic)
		Windows.close()
		task.wait(4.3)
		HatchCinematic.play("basic", { { uid = "y1", id = "bear", tier = 0, chance = 1, rarity = "Epic", new = true } }, false)
	end,
	-- 570x345-ish viewport
	function() -- 22
		Windows.open("Pets")
	end,
	function() -- 23
		Windows.close()
		EggPanel.open("basic", basic)
	end,
	function() -- 24
		EggPanel.close()
		lang("de")
		Windows.open("Rewards")
	end,
	function()
		lang("")
		Windows.close()
	end,
}

-- Set 2: every other window, popups and the hatch build-up (run it at the phone-ish size).
local function hatchAt(delay: number, egg: string, results: { any }, auto: boolean)
	Windows.close()
	EggPanel.close()
	task.wait(delay)
	HatchCinematic.play(egg, results, auto)
end
local scenes2 = {
	function()
		place(basic + Vector3.new(10, 0, -8), Vector3.new(0, 0, -1))
		Windows.open("Upgrades")
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
		Windows.open("Store")
	end,
	function()
		Windows.open("Codes")
	end,
	function()
		Windows.open("Invite")
	end,
	function() -- 9: offline earnings popup
		Windows.close()
		showcase:FireServer("offline")
	end,
	function() -- 10: hatch build-up (cracks + glow), Mythic inside
		local holder = player.PlayerGui.TapPetsUI:FindFirstChild("PopupHolder")
		if holder then
			holder:Destroy()
		end
		hatchAt(5.2, "magma", { { uid = "z1", id = "hellhound", tier = 0, chance = 0.019, rarity = "Mythic", new = true } }, false)
	end,
	function() -- 11: Mythic reveal (the same job is still on screen)
		task.wait(1.5)
		hatchAt(2.6, "cosmic", { { uid = "z2", id = "galaxydragon", tier = 2, chance = 0.019, rarity = "Mythic" } }, false)
	end,
	function() -- 12: auto-hatch (compact) x3
		hatchAt(5.2, "basic", {
			{ uid = "a1", id = "dog", tier = 0, chance = 49, rarity = "Common" },
			{ uid = "a2", id = "cat", tier = 0, chance = 25, rarity = "Uncommon" },
			{ uid = "a3", id = "bunny", tier = 1, chance = 24, rarity = "Rare", new = true },
		}, true)
	end,
	function() -- 13: pets window with a pet selected (detail stage)
		Windows.open("Pets")
		task.wait(0.5)
		require(UI:WaitForChild("PetsWindow")).selectFirst()
	end,
	function() -- 14: tapping with a long combo
		Windows.close()
		tapBurst(6.2)
	end,
	function()
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
