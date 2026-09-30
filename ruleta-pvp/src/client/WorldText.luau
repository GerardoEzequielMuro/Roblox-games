--!strict
-- Localizes the world text the server builds (table banners, the core sign, proximity
-- prompts) and draws the three ranking boards in the lobby. Re-rendered when the language
-- changes.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)

local WorldText = {}
WorldText.boardRows = 0

local function render(obj: Instance)
	local key = obj:GetAttribute("LocKey")
	if type(key) ~= "string" then
		return
	end
	if obj:IsA("TextLabel") then
		local icon = obj:GetAttribute("LocIcon")
		obj.Text = (if type(icon) == "string" then icon .. " " else "") .. Lang.upper(Lang.t(key))
	elseif obj:IsA("ProximityPrompt") then
		obj.ActionText = Lang.t(key)
	end
end

local boards: { [string]: { title: TextLabel, list: Frame } } = {}
local lastRows: { [string]: any } = {}

local function buildBoard(part: BasePart)
	local kind = part:GetAttribute("Kind")
	if type(kind) ~= "string" or boards[kind] then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.94, 0.14)
	title.Position = UDim2.fromScale(0.03, 0.02)
	title.Font = Enum.Font.LuckiestGuy
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 215, 80)
	title.Parent = gui
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(0.92, 0.8)
	list.Position = UDim2.fromScale(0.04, 0.18)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	gui.Parent = part
	boards[kind] = { title = title, list = list }
end

local function drawBoards()
	local medals = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(220, 225, 235), Color3.fromRGB(230, 150, 90) }
	for kind, b in boards do
		b.title.Text = "🏆 " .. Lang.upper(Lang.t("rank." .. kind))
		for _, c in b.list:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local rows = lastRows[kind] or {}
		if #rows == 0 then
			rows = { { name = Lang.t("rank.empty"), value = -1 } }
		end
		for i, row in rows do
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, 0, 0.1, 0)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextColor3 = medals[i] or Color3.new(1, 1, 1)
			t.Text = if row.value < 0 then row.name else string.format("#%d  %s  —  %s", i, row.name, Format.commas(row.value))
			t.LayoutOrder = i
			t.Parent = b.list
			WorldText.boardRows += 1
		end
	end
end

function WorldText.refreshBoards()
	local ok, data = Net.request("GetBoards")
	if ok and type(data) == "table" and type(data.rows) == "table" then
		lastRows = data.rows
		drawBoards()
	end
end

function WorldText.init()
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		task.wait(1)
		local function all()
			for _, tag in { "LocText", "LocPrompt" } do
				for _, obj in CollectionService:GetTagged(tag) do
					render(obj)
				end
			end
			drawBoards()
		end
		for _, part in CollectionService:GetTagged("Board") do
			if part:IsA("BasePart") then
				buildBoard(part)
			end
		end
		all()
		for _, tag in { "LocText", "LocPrompt" } do
			CollectionService:GetInstanceAddedSignal(tag):Connect(function(obj)
				task.defer(render, obj)
			end)
		end
		Lang.Changed:Connect(all)
		while true do
			WorldText.refreshBoards()
			task.wait(60)
		end
	end)
end

return WorldText
