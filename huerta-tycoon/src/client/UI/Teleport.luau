--!nonstrict
-- Client-side character teleports (garden spawn, seed shop, sell stand).
local Players = game:GetService("Players")

local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local I18n = require(script.Parent.I18n)
local L = I18n.L

local player = Players.LocalPlayer

local Teleport = {}

local function boundsOf(inst: Instance): (CFrame?, Vector3?)
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	elseif inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	return nil, nil
end

local function pivot(cf: CFrame): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 then
		Toasts.show(L("tp.wait"), "error")
		return false
	end
	if hum.Sit then
		hum.Sit = false
	end
	char:PivotTo(cf)
	return true
end

function Teleport.hubPart(name: string): Instance?
	local hub = workspace:FindFirstChild("Hub")
	return hub and hub:FindFirstChild(name)
end

function Teleport.myPlot(): Instance?
	local d = State.data
	if not d or not d.plotIndex then
		return nil
	end
	local plots = workspace:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot_" .. tostring(d.plotIndex))
end

-- Stand in front of a part (along its LookVector), facing it.
function Teleport.near(target: Instance?, distance: number?): boolean
	if not target then
		Toasts.show(L("tp.notFound"), "error")
		return false
	end
	local cf, size = boundsOf(target)
	if not cf or not size then
		return false
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local base = cf.Position - Vector3.new(0, size.Y / 2, 0)
	local pos = base + look * ((distance or 6) + math.max(size.X, size.Z) / 2) + Vector3.new(0, 4, 0)
	return pivot(CFrame.lookAt(pos, Vector3.new(cf.Position.X, pos.Y, cf.Position.Z)))
end

function Teleport.toGarden(): boolean
	local plot = Teleport.myPlot()
	local spawn = plot and plot:FindFirstChild("Spawn")
	if not spawn or not spawn:IsA("BasePart") then
		Toasts.show(L("tp.gardenLoading"), "error")
		return false
	end
	return pivot((spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3.5, 0)) * CFrame.Angles(0, math.pi, 0))
end

function Teleport.toShop(): boolean
	return Teleport.near(Teleport.hubPart("SeedShop"), 7)
end

function Teleport.toSellStand(): boolean
	return Teleport.near(Teleport.hubPart("SellStand"), 5)
end

function Teleport.distanceTo(target: Instance?): number
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not target then
		return math.huge
	end
	local cf = boundsOf(target)
	if not cf then
		return math.huge
	end
	return ((root :: BasePart).Position - cf.Position).Magnitude
end

return Teleport
