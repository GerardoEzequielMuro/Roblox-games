--!strict
-- Non-blocking offers: a slim strip at the top centre, right under the run timer: one line of
-- title and the buttons side by side. It never covers the route, and it goes away by itself.
-- Used by the "Stuck on stage N?" skip offer (P0-1) and the notification opt-in (P0-8).
local Kit = require(script.Parent.Kit)

local Cards = {}

export type CardButton = { name: string, text: string, color: Color3, onClick: () -> () }

local WIDTH = 620
local BTN_H = 48
local GAP = 8
local TITLE_H = 26
local HEIGHT = TITLE_H + BTN_H + 14

local region: Frame? = nil
local token = 0

local function ensure(): Frame
	if region then
		return region
	end
	local r = Kit.region("Card", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 90), Vector2.new(WIDTH, HEIGHT))
	r.ZIndex = 15
	r.Visible = false
	Kit.onLayout(function(touch, area, scale)
		-- between the Roblox buttons (left) and the progress bar / action column (right)
		local s = math.min(scale, area.X * (if touch then 0.46 else 0.6) / WIDTH)
		r.Position = UDim2.new(0.5, 0, 0, Kit.hudTop + 4)
		Kit.setScale(r, s)
		Kit.cardInset = if r.Visible then math.floor(HEIGHT * s) + 6 else 0
	end)
	region = r
	return r
end

function Cards.hide(name: string?)
	local r = region
	if r and r.Visible and (name == nil or r:GetAttribute("Card") == name) then
		r.Visible = false
		token += 1
		Kit.relayout()
	end
end

function Cards.current(): string?
	local r = region
	if r and r.Visible then
		return r:GetAttribute("Card") :: string?
	end
	return nil
end

-- title: already-translated text. Returns the card frame.
function Cards.show(name: string, title: string, buttons: { CardButton }, seconds: number?): Frame
	local r = ensure()
	for _, c in r:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	token += 1
	local my = token
	r:SetAttribute("Card", name)
	local body = Kit.frame(r, UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(24, 28, 44))
	body.Name = "Body"
	body.BackgroundTransparency = 0.25
	Kit.corner(body, 16)
	local outline = Kit.stroke(body, Color3.new(1, 1, 1), 1.5)
	outline.Transparency = 0.55
	local t = Kit.bold(body, title, UDim2.new(1, -60, 0, TITLE_H), UDim2.fromOffset(12, 4), Kit.C.yellow, nil, 22)
	t.Name = "Title"
	t.TextXAlignment = Enum.TextXAlignment.Left
	Kit.button(body, "X", UDim2.fromOffset(30, 26), UDim2.new(1, -6, 0, 4), Kit.C.red, function()
		Cards.hide(name)
	end, Vector2.new(1, 0), 18).Name = "Close"
	local n = math.max(1, #buttons)
	local w = (WIDTH - 16 - (n - 1) * GAP) / n
	for i, b in buttons do
		local btn = Kit.button(body, b.text, UDim2.fromOffset(w, BTN_H), UDim2.fromOffset(8 + (i - 1) * (w + GAP), TITLE_H + 8), b.color, function()
			Cards.hide(name)
			b.onClick()
		end, nil, 22)
		btn.Name = b.name
	end
	r.Visible = true
	Kit.relayout()
	Kit.pop(body, 0.6)
	if seconds then
		task.delay(seconds, function()
			if token == my then
				Cards.hide(name)
			end
		end)
	end
	return body
end

return Cards
