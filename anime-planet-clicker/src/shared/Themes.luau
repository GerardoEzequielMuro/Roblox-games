--!strict
-- Look of each galaxy: station colours (baked into the parts, so they read the same at
-- graphics quality 1), prop style, the painted sky (client SkyRig) and the lighting.
local Themes = {}

local rgb = Color3.fromRGB

export type Theme = {
	ground: Color3, -- station deck
	groundAlt: Color3, -- painted rings / paths on the deck
	rim: Color3,
	under: Color3, -- hull below the deck
	accent: Color3, -- lights, signs, pads
	accent2: Color3,
	prop: string, -- scenery style
	propColor: Color3,
	propColor2: Color3,
	groundMaterial: Enum.Material,
	-- sky (SkyRig): dome colour, horizon band, star tint, nebula blobs, far planets
	skyTop: Color3,
	skyHorizon: Color3,
	nebula: { Color3 },
	farPlanets: { { color: Color3, ring: Color3?, size: number } },
	-- lighting
	ambient: Color3,
	sun: Color3,
	brightness: number,
	clock: number,
	-- plain "rock" planets of this galaxy
	rock: Color3,
	rockMantle: Color3,
	rockCore: Color3,
}

Themes.ByZone = {
	{ -- Dawn Belt: warm sandstone station under an orange sun
		ground = rgb(196, 150, 110), groundAlt = rgb(226, 188, 140), rim = rgb(110, 78, 66), under = rgb(86, 62, 60),
		accent = rgb(255, 170, 60), accent2 = rgb(90, 200, 255), prop = "rocks", propColor = rgb(150, 104, 84), propColor2 = rgb(236, 200, 150),
		groundMaterial = Enum.Material.Sand,
		skyTop = rgb(36, 28, 78), skyHorizon = rgb(232, 120, 84), nebula = { rgb(255, 150, 90), rgb(200, 90, 150), rgb(255, 200, 120) },
		farPlanets = { { color = rgb(255, 190, 110), ring = rgb(255, 230, 190), size = 120 }, { color = rgb(190, 110, 200), size = 46 } },
		ambient = rgb(170, 150, 165), sun = rgb(255, 225, 190), brightness = 2.4, clock = 15.2,
		rock = rgb(168, 140, 120), rockMantle = rgb(214, 130, 70), rockCore = rgb(255, 214, 110),
	},
	{ -- Verdant Nebula: mossy teal deck, giant mushrooms
		ground = rgb(74, 150, 112), groundAlt = rgb(136, 206, 140), rim = rgb(40, 84, 80), under = rgb(34, 62, 70),
		accent = rgb(170, 255, 120), accent2 = rgb(255, 120, 200), prop = "mushrooms", propColor = rgb(240, 110, 150), propColor2 = rgb(245, 235, 210),
		groundMaterial = Enum.Material.Grass,
		skyTop = rgb(12, 44, 58), skyHorizon = rgb(70, 190, 150), nebula = { rgb(90, 230, 170), rgb(60, 140, 200), rgb(190, 255, 150) },
		farPlanets = { { color = rgb(120, 220, 160), size = 100 }, { color = rgb(240, 220, 120), ring = rgb(255, 250, 200), size = 56 } },
		ambient = rgb(140, 175, 160), sun = rgb(225, 255, 225), brightness = 2.3, clock = 13.4,
		rock = rgb(104, 150, 110), rockMantle = rgb(70, 190, 150), rockCore = rgb(200, 255, 140),
	},
	{ -- Frost Halo: pale ice deck, crystal spikes
		ground = rgb(190, 222, 245), groundAlt = rgb(236, 248, 255), rim = rgb(84, 120, 170), under = rgb(60, 84, 130),
		accent = rgb(110, 220, 255), accent2 = rgb(200, 160, 255), prop = "ice", propColor = rgb(150, 215, 255), propColor2 = rgb(235, 250, 255),
		groundMaterial = Enum.Material.Snow,
		skyTop = rgb(18, 30, 84), skyHorizon = rgb(130, 190, 255), nebula = { rgb(140, 200, 255), rgb(190, 160, 255), rgb(225, 245, 255) },
		farPlanets = { { color = rgb(200, 235, 255), ring = rgb(160, 200, 255), size = 130 }, { color = rgb(120, 150, 240), size = 50 } },
		ambient = rgb(165, 185, 215), sun = rgb(225, 240, 255), brightness = 2.5, clock = 12.2,
		rock = rgb(170, 205, 235), rockMantle = rgb(110, 165, 235), rockCore = rgb(235, 250, 255),
	},
	{ -- Ember Forge: dark basalt with lava seams
		ground = rgb(74, 58, 62), groundAlt = rgb(255, 120, 50), rim = rgb(40, 30, 36), under = rgb(30, 22, 28),
		accent = rgb(255, 140, 40), accent2 = rgb(255, 220, 90), prop = "vents", propColor = rgb(52, 42, 48), propColor2 = rgb(255, 110, 40),
		groundMaterial = Enum.Material.Basalt,
		skyTop = rgb(44, 10, 22), skyHorizon = rgb(232, 84, 40), nebula = { rgb(255, 100, 50), rgb(200, 40, 60), rgb(255, 190, 80) },
		farPlanets = { { color = rgb(230, 80, 50), size = 140 }, { color = rgb(60, 40, 50), ring = rgb(255, 150, 70), size = 60 } },
		ambient = rgb(170, 130, 125), sun = rgb(255, 200, 160), brightness = 2.2, clock = 17.3,
		rock = rgb(92, 72, 74), rockMantle = rgb(220, 90, 40), rockCore = rgb(255, 225, 120),
	},
	{ -- Storm Reach: violet steel with tesla coils
		ground = rgb(98, 92, 160), groundAlt = rgb(250, 225, 110), rim = rgb(52, 46, 100), under = rgb(38, 34, 78),
		accent = rgb(255, 230, 90), accent2 = rgb(120, 240, 255), prop = "coils", propColor = rgb(70, 66, 120), propColor2 = rgb(255, 235, 110),
		groundMaterial = Enum.Material.Metal,
		skyTop = rgb(24, 16, 64), skyHorizon = rgb(140, 100, 230), nebula = { rgb(150, 110, 255), rgb(90, 200, 255), rgb(255, 230, 120) },
		farPlanets = { { color = rgb(170, 140, 255), ring = rgb(255, 235, 140), size = 150 }, { color = rgb(90, 210, 240), size = 54 } },
		ambient = rgb(150, 145, 200), sun = rgb(235, 225, 255), brightness = 2.3, clock = 19.0,
		rock = rgb(130, 124, 190), rockMantle = rgb(90, 190, 240), rockCore = rgb(255, 240, 130),
	},
	{ -- Void Crown: obsidian with magenta and cyan
		ground = rgb(40, 34, 66), groundAlt = rgb(255, 90, 210), rim = rgb(20, 18, 38), under = rgb(14, 12, 28),
		accent = rgb(60, 240, 225), accent2 = rgb(255, 90, 210), prop = "obelisks", propColor = rgb(28, 24, 50), propColor2 = rgb(60, 240, 225),
		groundMaterial = Enum.Material.Slate,
		skyTop = rgb(8, 6, 22), skyHorizon = rgb(120, 40, 170), nebula = { rgb(255, 80, 210), rgb(60, 230, 230), rgb(140, 80, 255) },
		farPlanets = { { color = rgb(30, 24, 60), ring = rgb(255, 90, 210), size = 160 }, { color = rgb(60, 240, 225), size = 40 } },
		ambient = rgb(140, 130, 190), sun = rgb(225, 215, 255), brightness = 2.1, clock = 0.4,
		rock = rgb(70, 60, 110), rockMantle = rgb(150, 70, 210), rockCore = rgb(90, 250, 235),
	},
} :: { Theme }

-- The arena borrows a neutral steel look.
Themes.Arena = {
	ground = rgb(86, 92, 112), groundAlt = rgb(228, 70, 70), rim = rgb(40, 44, 60), under = rgb(28, 30, 44),
	accent = rgb(255, 80, 80), accent2 = rgb(90, 200, 255), prop = "none", propColor = rgb(60, 64, 84), propColor2 = rgb(255, 200, 60),
	groundMaterial = Enum.Material.Metal,
	skyTop = rgb(14, 14, 40), skyHorizon = rgb(200, 70, 90), nebula = { rgb(255, 90, 90), rgb(255, 170, 80), rgb(120, 120, 255) },
	farPlanets = { { color = rgb(220, 90, 90), ring = rgb(255, 200, 120), size = 130 }, { color = rgb(120, 140, 255), size = 50 } },
	ambient = rgb(160, 155, 180), sun = rgb(255, 230, 225), brightness = 2.3, clock = 16,
	rock = rgb(120, 120, 140), rockMantle = rgb(200, 90, 90), rockCore = rgb(255, 220, 120),
} :: Theme

function Themes.get(zone: number?): Theme
	return if zone then (Themes.ByZone[zone] or Themes.ByZone[1]) else Themes.Arena
end

return Themes
