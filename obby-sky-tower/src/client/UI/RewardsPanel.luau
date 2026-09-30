--!strict
-- Daily reward, play-time rewards (5/15/30/60 min this session) and codes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Net)
local Kit = require(script.Parent.Kit)
local Toast = require(script.Parent.Toast)

local RewardsPanel = {}

local function say(ok: boolean, msg: string?, _extra: any?)
	if msg then
		Toast.show(msg, if ok then "success" else "error")
	end
end

function RewardsPanel.init()
	local content = Kit.panel("rewards", "@panel.rewards", Kit.C.orange)

	-- daily ------------------------------------------------------------------------------------
	local dailyTitle: TextLabel
	local daily = Kit.frame(content, UDim2.new(0.5, -8, 0, 170), UDim2.fromOffset(0, 0), Kit.C.card)
	Kit.corner(daily, 16)
	Kit.stroke(daily, Color3.fromRGB(220, 210, 235), 3)
	dailyTitle = Kit.text(daily, "@rewards.daily", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 8), Kit.C.ink, nil, 30)
	local dailyInfo = Kit.text(daily, "", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 44), Color3.fromRGB(110, 105, 140), nil, 20)
	local dailyBtn = Kit.button(daily, "@rewards.claim", UDim2.new(1, -20, 0, 56), UDim2.new(0, 10, 1, -66), Kit.C.green, function()
		say(Net.request("ClaimDaily"))
	end)

	-- codes ---------------------------------------------------------------------------------------
	local codes = Kit.frame(content, UDim2.new(0.5, -8, 0, 170), UDim2.new(0.5, 8, 0, 0), Kit.C.card)
	Kit.corner(codes, 16)
	Kit.stroke(codes, Color3.fromRGB(220, 210, 235), 3)
	local codesTitle = Kit.text(codes, "@rewards.codes", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 8), Kit.C.ink, nil, 30)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -20, 0, 48)
	box.Position = UDim2.fromOffset(10, 46)
	box.BackgroundColor3 = Color3.fromRGB(245, 242, 250)
	Kit.setText(box, "rewards.enter_code", nil, "PlaceholderText")
	box.Text = ""
	box.Font = Kit.Font
	box.TextScaled = true
	box.TextColor3 = Kit.C.ink
	box.ClearTextOnFocus = false
	Kit.corner(box, 12)
	Kit.stroke(box, Color3.fromRGB(200, 190, 220), 2)
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 26
	tsc.Parent = box
	box.Parent = codes
	local redeemBtn = Kit.button(codes, "@rewards.redeem", UDim2.new(1, -20, 0, 56), UDim2.new(0, 10, 1, -66), Kit.C.blue, function()
		local ok, msg = Net.request("RedeemCode", { code = box.Text })
		say(ok, msg)
		if ok then
			box.Text = ""
		end
	end)

	-- play time -----------------------------------------------------------------------------------
	local playTitle = Kit.text(content, "@rewards.playtime", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 180), Kit.C.ink, nil, 26)
	local rows: { { btn: TextButton, bar: Frame, label: TextLabel } } = {}
	local cellParts: { { cell: Frame, minutes: TextLabel, reward: TextLabel, track: Frame, label: TextLabel, btn: TextButton, x: number } } = {}
	local n = #Config.PlaytimeRewards
	for i, r in Config.PlaytimeRewards do
		local w = 1 / n
		local cell = Kit.frame(content, UDim2.new(w, -8, 0, 160), UDim2.new(w * (i - 1), 4, 0, 214), Kit.C.card)
		Kit.corner(cell, 14)
		Kit.stroke(cell, Color3.fromRGB(220, 210, 235), 3)
		local minutes = Kit.text(cell, "", UDim2.new(1, -10, 0, 26), UDim2.fromOffset(5, 4), Kit.C.ink, nil, 24)
		Kit.setText(minutes, "rewards.minutes", { n = r.minutes })
		local rewardText = Kit.text(cell, "", UDim2.new(1, -10, 0, 36), UDim2.fromOffset(5, 30), Color3.fromRGB(200, 140, 20), nil, 20)
		if r.freeSkips > 0 then
			Kit.setText(rewardText, "rewards.coins_skips", { coins = r.coins, n = r.freeSkips })
		else
			Kit.setText(rewardText, "rewards.coins", { coins = r.coins })
		end
		local track = Kit.frame(cell, UDim2.new(1, -16, 0, 8), UDim2.fromOffset(8, 70), Color3.fromRGB(230, 225, 240))
		Kit.corner(track, 5)
		local bar = Kit.frame(track, UDim2.fromScale(0, 1), UDim2.new(), Kit.C.green)
		Kit.corner(bar, 5)
		local label = Kit.text(cell, "", UDim2.new(1, -10, 0, 20), UDim2.fromOffset(5, 80), Color3.fromRGB(110, 105, 140), nil, 16)
		local btn = Kit.button(cell, "@rewards.claim", UDim2.new(1, -16, 0, 48), UDim2.new(0, 8, 1, -54), Kit.C.green, function()
			say(Net.request("ClaimPlaytime", { index = i }))
		end, nil, 20)
		rows[i] = { btn = btn, bar = bar, label = label }
		cellParts[i] = { cell = cell, minutes = minutes, reward = rewardText, track = track, label = label, btn = btn, x = w * (i - 1) }
	end

	-- Touch: wide, short panel (Kit.panel) -> shorter blocks, code box and Redeem on one row,
	-- and buttons >= 54 design px tall.
	Kit.onLayout(function(touch)
		local blockH = if touch then 120 else 170
		daily.Size = UDim2.new(0.5, -8, 0, blockH)
		codes.Size = UDim2.new(0.5, -8, 0, blockH)
		if touch then
			dailyTitle.Size = UDim2.new(1, -20, 0, 28)
			dailyTitle.Position = UDim2.fromOffset(10, 2)
			codesTitle.Size = UDim2.new(1, -20, 0, 28)
			codesTitle.Position = UDim2.fromOffset(10, 2)
			dailyInfo.Size = UDim2.new(1, -20, 0, 26)
			dailyInfo.Position = UDim2.fromOffset(10, 31)
			dailyBtn.Size = UDim2.new(1, -20, 0, 56)
			dailyBtn.Position = UDim2.new(0, 10, 1, -60)
			box.Size = UDim2.new(0.5, -14, 0, 56)
			box.Position = UDim2.new(0, 10, 1, -60)
			redeemBtn.Size = UDim2.new(0.5, -14, 0, 56)
			redeemBtn.Position = UDim2.new(0.5, 4, 1, -60)
		else
			dailyTitle.Size = UDim2.new(1, -20, 0, 34)
			dailyTitle.Position = UDim2.fromOffset(10, 8)
			codesTitle.Size = UDim2.new(1, -20, 0, 34)
			codesTitle.Position = UDim2.fromOffset(10, 8)
			dailyInfo.Size = UDim2.new(1, -20, 0, 50)
			dailyInfo.Position = UDim2.fromOffset(10, 44)
			dailyBtn.Size = UDim2.new(1, -20, 0, 56)
			dailyBtn.Position = UDim2.new(0, 10, 1, -66)
			box.Size = UDim2.new(1, -20, 0, 48)
			box.Position = UDim2.fromOffset(10, 46)
			redeemBtn.Size = UDim2.new(1, -20, 0, 56)
			redeemBtn.Position = UDim2.new(0, 10, 1, -66)
		end
		playTitle.Size = UDim2.new(1, 0, 0, if touch then 22 else 30)
		playTitle.Position = UDim2.fromOffset(0, if touch then 124 else 180)
		local w = 1 / #cellParts
		for i, c in cellParts do
			c.cell.Size = UDim2.new(w, -8, 0, if touch then 136 else 160)
			c.cell.Position = UDim2.new(w * (i - 1), 4, 0, if touch then 148 else 214)
			c.minutes.Size = UDim2.new(1, -10, 0, if touch then 24 else 26)
			c.minutes.Position = UDim2.fromOffset(5, if touch then 2 else 4)
			c.reward.Size = UDim2.new(1, -10, 0, if touch then 32 else 36)
			c.reward.Position = UDim2.fromOffset(5, if touch then 26 else 30)
			c.track.Position = UDim2.fromOffset(8, if touch then 57 else 70)
			c.label.Size = UDim2.new(1, -10, 0, if touch then 15 else 20)
			c.label.Position = UDim2.fromOffset(5, if touch then 64 else 80)
			c.btn.Size = UDim2.new(1, -16, 0, if touch then 54 else 48)
			c.btn.Position = UDim2.new(0, 8, 1, if touch then -56 else -54)
		end
	end)

	local function refresh()
		local s = Net.state
		local d = s.daily or {}
		local day = d.day or 1
		local amount = Config.DailyRewards[math.min(day, #Config.DailyRewards)]
		if Net.hasPass("VIP") then
			amount *= 2
		end
		if d.canClaim then
			Kit.setText(dailyInfo, "rewards.day_streak", { day = day, coins = amount })
			Kit.setText(dailyBtn, "rewards.claim_now")
			dailyBtn.BackgroundColor3 = Kit.C.green
		else
			Kit.setText(dailyInfo, "rewards.next_in", { time = Kit.formatTime((d.nextIn or 0) - (os.clock() - Net.stateAt)) })
			Kit.setText(dailyBtn, "rewards.claimed")
			dailyBtn.BackgroundColor3 = Kit.C.grey
		end
		local claimed = {}
		for _, i in (s.playClaimed or {}) :: { number } do
			claimed[i] = true
		end
		local played = Net.playSeconds()
		for i, r in Config.PlaytimeRewards do
			local row = rows[i]
			local need = r.minutes * 60
			local k = math.clamp(played / need, 0, 1)
			row.bar.Size = UDim2.fromScale(k, 1)
			if claimed[i] then
				Kit.setText(row.btn, "rewards.done")
				row.btn.BackgroundColor3 = Kit.C.grey
				Kit.setText(row.label, "rewards.claimed")
			elseif k >= 1 then
				Kit.setText(row.btn, "rewards.claim_now")
				row.btn.BackgroundColor3 = Kit.C.green
				Kit.setText(row.label, "rewards.ready")
			else
				Kit.setText(row.btn, "rewards.wait")
				row.btn.BackgroundColor3 = Kit.C.grey
				Kit.setRaw(row.label, Kit.formatTime(need - played))
			end
		end
	end

	Kit.onOpen("rewards", refresh)
	Net.changed:Connect(function()
		if Kit.current() == "rewards" then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Kit.current() == "rewards" then
				refresh()
			end
		end
	end)
end

return RewardsPanel
