--!nonstrict
-- Device profile. "Lite" = phones and players who set a low graphics level: same game, fewer cosmetics.
-- Everything it switches off is decoration; nothing here changes gameplay or what the server sends.
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local Perf = {}

Perf.lite = false

-- Pure decision (unit-tested in the playtest): phone-sized touch screens and manual quality levels 1-3 are lite.
-- quality: 0 = automatic, 1..10 = the level the player picked in the Roblox menu.
function Perf.decide(touchOnly: boolean, quality: number, shortSide: number): boolean
	if quality >= 1 and quality <= 3 then
		return true
	end
	return touchOnly and shortSide < 700
end

-- Cosmetic budgets per profile.
function Perf.budget(lite: boolean): { [string]: number }
	if lite then
		return { harvestPop = 5, harvestLeaves = 0, coins = 6, confetti = 12, floatHz = 10 }
	end
	return { harvestPop = 9, harvestLeaves = 5, coins = 14, confetti = 40, floatHz = 30 }
end

-- Purely ornamental world parts a lite device can do without (flowers, pennants, straps...).
Perf.ORNAMENTS = {
	Stem = true,
	Bloom = true,
	Pennant = true,
	BuntingString = true,
	CrateBand = true,
	BarrelBand = true,
	HayBand = true,
	Valance = true,
	Reed = true,
	ReedHead = true,
	Vine = true,
	VineLeaf = true,
	LilyPad = true,
	LilyBloom = true,
	Mushroom = true,
	LogEnd = true,
	WindowBar = true,
	Branch = true,
	BaleEnd = true,
}

function Perf.isOrnament(inst: Instance): boolean
	return inst:IsA("BasePart") and Perf.ORNAMENTS[inst.Name] == true and not inst.CanCollide
end

Perf.removed = 0

local function quality(): number
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return if ok and type(level) == "number" then level else 0
end

function Perf.init()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	Perf.lite = Perf.decide(touchOnly, quality(), math.min(vp.X, vp.Y))
	if not Perf.lite then
		return
	end
	-- screen-space extras off (the engine already drops them at the lowest levels; this covers "automatic" phones)
	for _, e in Lighting:GetChildren() do
		if e:IsA("DepthOfFieldEffect") or e:IsA("SunRaysEffect") then
			e.Enabled = false
		end
	end
	-- drop ornaments locally (they still exist on the server and for everyone else)
	local function cull(inst: Instance)
		if Perf.isOrnament(inst) then
			Perf.removed += 1
			inst:Destroy()
		end
	end
	task.spawn(function()
		local n = 0
		for _, d in workspace:GetDescendants() do
			cull(d)
			n += 1
			if n % 400 == 0 then
				task.wait() -- never stall a frame on a phone
			end
		end
		workspace.DescendantAdded:Connect(function(d)
			task.defer(cull, d)
		end)
	end)
end

return Perf
