--!strict
-- Overhead name tag (P0-5): display name, "Stage N · 🏆 W" and a title earned by wins.
-- The two localized lines carry LocKey / LocArgs attributes, so each client renders them in its own
-- language (client/World/WorldText.luau). Updated from Session.push (stage / win / rebirth).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local Session = require(script.Parent.Session)
local StageGenerator = require(script.Parent.StageGenerator)

local Nametags = {}

local GOLD = Color3.fromRGB(255, 215, 80)

function Nametags.titleIndex(wins: number): number
	local idx = 1
	for i, t in Config.Titles do
		if wins >= t.wins then
			idx = i
		end
	end
	return idx
end

local function line(parent: Instance, name: string, y: number, h: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, h)
	l.Position = UDim2.fromScale(0, y)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.TextStrokeColor3 = Color3.fromRGB(25, 25, 45)
	l.Parent = parent
	return l
end

local function ensure(player: Player): BillboardGui?
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not char or not head then
		return nil
	end
	local bb = head:FindFirstChild("SkyTag") :: BillboardGui?
	if bb then
		return bb
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local g = Instance.new("BillboardGui")
	g.Name = "SkyTag"
	g.Size = UDim2.fromScale(6, 1.6)
	g.StudsOffset = Vector3.new(0, 2.6, 0)
	g.MaxDistance = 80
	g.AlwaysOnTop = false
	g.LightInfluence = 0
	line(g, "NameLine", 0, 0.42, Color3.new(1, 1, 1))
	line(g, "StageLine", 0.42, 0.3, Color3.fromRGB(200, 235, 255))
	line(g, "TitleLine", 0.72, 0.28, Config.RebirthColors[1])
	g.Adornee = head
	g.Parent = head
	return g
end

function Nametags.update(player: Player)
	local p = Data.get(player)
	local g = ensure(player)
	if not p or not g then
		return
	end
	local vip = Session.hasPass(player, "VIP")
	local nameLine = g:FindFirstChild("NameLine") :: TextLabel
	nameLine.Text = if vip then "[VIP] " .. player.DisplayName else player.DisplayName
	nameLine.TextColor3 = if vip then GOLD else Color3.new(1, 1, 1)
	local s = Session.get(player)
	local stage = math.max(if s then s.at else 0, p.stage)
	local stageLine = g:FindFirstChild("StageLine") :: TextLabel
	if stageLine:GetAttribute("S") ~= stage or stageLine:GetAttribute("W") ~= p.wins then
		stageLine:SetAttribute("S", stage)
		stageLine:SetAttribute("W", p.wins)
		StageGenerator.loc(stageLine, "tag.stage", { n = stage, w = p.wins })
	end
	-- title: the tower gifts (stage 1000, stage 500) outrank the titles earned by wins
	local idx = Nametags.titleIndex(p.wins)
	local key, color = "title." .. idx, Config.RebirthColors[((idx - 1) % #Config.RebirthColors) + 1]
	if p.gifts["10"] then
		key, color = "title.conqueror", GOLD
	elseif p.gifts["5"] then
		key, color = "title.legend", GOLD
	end
	local titleLine = g:FindFirstChild("TitleLine") :: TextLabel
	if titleLine:GetAttribute("K") ~= key then
		titleLine:SetAttribute("K", key)
		titleLine.TextColor3 = color
		StageGenerator.loc(titleLine, key)
	end
end

function Nametags.init()
	Session.onPush(Nametags.update)
end

return Nametags
