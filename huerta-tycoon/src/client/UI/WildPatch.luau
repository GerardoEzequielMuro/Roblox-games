--!nonstrict
-- Wild Patch, client side: the plants you already picked this hour disappear for you only (other players still
-- see theirs), and the sign on the patch shows the countdown to the next regrow.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local I18n = require(script.Parent.I18n)
local State = require(script.Parent.State)

local WildPatch = {}

-- { nextAt, left, claimed = {index, ...} } from the last server snapshot.
function WildPatch.info(): any
	local d = State.data
	local w = d and d.wild
	if type(w) ~= "table" then
		return { nextAt = 0, left = 0, claimed = {} }
	end
	return w
end

-- One line for the HUD pill.
function WildPatch.hudText(): string
	local w = WildPatch.info()
	if (w.left or 0) > 0 then
		return I18n.t("wild.hudLeft", { n = w.left })
	end
	return I18n.t("wild.hudNext", { time = Format.time(math.max(0, (w.nextAt or 0) - State.now())) })
end

local function apply()
	local folder = workspace:FindFirstChild("WildPatch")
	if not folder then
		return
	end
	local claimed: { [number]: boolean } = {}
	for _, i in WildPatch.info().claimed or {} do
		claimed[i] = true
	end
	for _, node in folder:GetChildren() do
		local index = node:GetAttribute("Index")
		if type(index) ~= "number" then
			continue
		end
		local gone = claimed[index] == true
		local prompt = node:FindFirstChild("Prompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = not gone
		end
		local crop = node:FindFirstChild("Crop")
		if crop then
			for _, d in crop:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = if gone then 1 else 0
				elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
					d.Enabled = not gone
				end
			end
		end
	end
end

function WildPatch.init()
	State.onChanged(function(kind)
		if kind == "state" then
			apply()
		end
	end)
	local pending = false
	local function later()
		if not pending then
			pending = true
			task.delay(0.3, function()
				pending = false
				apply()
			end)
		end
	end
	task.spawn(function()
		local folder = workspace:WaitForChild("WildPatch")
		folder.DescendantAdded:Connect(later) -- regrow, or the patch streaming in
		apply()
		while true do
			local clock = folder:FindFirstChild("Clock", true)
			if clock and clock:IsA("TextLabel") then
				local w = WildPatch.info()
				clock.Text = I18n.t("wild.hudNext", { time = Format.time(math.max(0, (w.nextAt or 0) - State.now())) })
			end
			task.wait(1)
		end
	end)
end

return WildPatch
