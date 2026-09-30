--!nonstrict
-- Colors, fonts and emoji used across the client UI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontAlt = Enum.Font.GothamBold

Theme.C = {
	Green = Color3.fromRGB(76, 204, 82),
	GreenDark = Color3.fromRGB(34, 120, 44),
	Lime = Color3.fromRGB(140, 230, 70),
	Yellow = Color3.fromRGB(255, 208, 54),
	Orange = Color3.fromRGB(255, 146, 38),
	Red = Color3.fromRGB(238, 68, 68),
	Blue = Color3.fromRGB(64, 156, 255),
	Teal = Color3.fromRGB(40, 196, 190),
	Purple = Color3.fromRGB(156, 92, 255),
	Pink = Color3.fromRGB(255, 96, 170),
	Gold = Color3.fromRGB(255, 196, 40),
	Grey = Color3.fromRGB(150, 150, 160),
	Panel = Color3.fromRGB(255, 248, 230),
	PanelEdge = Color3.fromRGB(94, 60, 30),
	Card = Color3.fromRGB(255, 255, 255),
	Ink = Color3.fromRGB(58, 40, 26),
	InkSoft = Color3.fromRGB(120, 96, 74),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
	Stroke = Color3.fromRGB(30, 26, 22),
	Dark = Color3.fromRGB(34, 38, 50),
	Cash = Color3.fromRGB(120, 255, 110),
}

Theme.ToastColors = {
	info = Theme.C.Blue,
	success = Theme.C.Green,
	error = Theme.C.Red,
	rare = Theme.C.Purple,
}

Theme.SeedEmoji = {
	carrot = "🥕",
	tomato = "🍅",
	corn = "🌽",
	blueberry = "🍇",
	pumpkin = "🎃",
	watermelon = "🍉",
	apple = "🍎",
	dragonfruit = "🐲",
	mango = "🥭",
	starfruit = "🌟",
	moonmelon = "🌕",
	cosmiclotus = "🌸",
}

Theme.WeatherEmoji = {
	Rain = "🌧️",
	Snow = "❄️",
	Thunderstorm = "⛈️",
	GoldenHour = "🌅",
}

Theme.WeatherColor = {
	Rain = Color3.fromRGB(70, 120, 200),
	Snow = Color3.fromRGB(120, 180, 230),
	Thunderstorm = Color3.fromRGB(80, 60, 140),
	GoldenHour = Color3.fromRGB(230, 150, 40),
	Clear = Color3.fromRGB(70, 170, 240),
}

Theme.MutationEmoji = {
	Normal = "🌱",
	Rainbow = "🌈",
	Shocked = "⚡",
	Golden = "⭐",
	Frozen = "❄️",
	Wet = "💧",
}

Theme.UpgradeEmoji = {
	GrowSpeed = "🧪",
	CropValue = "💲",
	Luck = "🍀",
	Backpack = "🎒",
	Farmhand = "🤖",
}

Theme.ProductEmoji = {
	DoubleCash = "💰",
	AutoHarvest = "🤖",
	SellAnywhere = "📦",
	VIP = "👑",
	SuperLuck = "🍀",
	BigBasket = "🧺",
	CashSmall = "💵",
	CashLarge = "💰",
	InstantGrow = "⚡",
	Restock = "🔄",
	LuckyPack = "🎲",
}

function Theme.seedEmoji(id: string?): string
	return (id and Theme.SeedEmoji[id]) or "🌱"
end

function Theme.rarityColor(rarity: string?): Color3
	return (rarity and Config.Rarities[rarity]) or Theme.C.Grey
end

function Theme.darken(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

function Theme.lighten(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), f)
end

return Theme
