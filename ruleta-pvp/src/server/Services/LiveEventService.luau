--!strict
-- Live events: the UTC schedule (Double XP every 3 h, Chaos Weekend) plus an admin override
-- (/event <id> <minutes>) shared across servers with MessagingService. The match runner
-- asks for the active multipliers when it pays a match.
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local LiveEvents = require(ReplicatedStorage.Shared.LiveEvents)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Remotes = require(script.Parent.Remotes)
local M = Locale.m

local LiveEventService = {}

local TOPIC = "SpinShowdown_LiveEvent"
local MAX_MINUTES = 180
local override: LiveEvents.Override? = nil
local lastKey = ""

local function payload(): { [string]: any }
	local now = os.time()
	local active = LiveEvents.active(now, override)
	local nextAt, nextId = LiveEvents.nextStart(now)
	return { active = active, current = active[1], nextAt = nextAt, nextId = nextId, serverTime = now }
end

local function isAdmin(userId: number): boolean
	return table.find(Config.AdminUserIds, userId) ~= nil
end

-- Multipliers for a match in `modeId` right now.
function LiveEventService.effects(modeId: string): { coinMult: number, xpMult: number }
	return LiveEvents.effects(LiveEvents.active(os.time(), override), modeId)
end

function LiveEventService.refresh(force: boolean?)
	local now = os.time()
	local active = LiveEvents.active(now, override)
	local parts = {}
	for _, a in active do
		table.insert(parts, a.id .. "@" .. a.endsAt)
	end
	local key = table.concat(parts, ",")
	if key == lastKey and not force then
		return
	end
	local started = {}
	for _, a in active do
		if not lastKey:find(a.id .. "@", 1, true) then
			table.insert(started, a.id)
		end
	end
	lastKey = key
	local data = payload()
	data.started = started
	Remotes.fireAll("LiveEventUpdate", data)
end

function LiveEventService.sendTo(player: Player)
	Remotes.fire("LiveEventUpdate", player, payload())
end

function LiveEventService.setOverride(id: string, endsAt: number)
	override = { id = id, endsAt = endsAt }
	LiveEventService.refresh()
end

function LiveEventService.clearOverride()
	override = nil
	LiveEventService.refresh()
end

-- "/event DoubleXP 15" from an admin. Returns ok, message.
function LiveEventService.command(userId: number, text: string): (boolean, Locale.Message)
	if not isAdmin(userId) then
		return false, M("msg.admin_only")
	end
	local id, minutesText = text:match("^%s*/event%s+(%w+)%s+(%d+)%s*$")
	local minutes = tonumber(minutesText)
	if not id or not Config.LiveEventDefs[id] or not minutes or minutes < 1 or minutes > MAX_MINUTES then
		return false, M("msg.event_usage", { max = MAX_MINUTES })
	end
	local endsAt = os.time() + minutes * 60
	LiveEventService.setOverride(id, endsAt)
	if game.PlaceId ~= 0 then
		task.spawn(pcall, function()
			MessagingService:PublishAsync(TOPIC, { id = id, endsAt = endsAt })
		end)
	end
	return true, M("msg.event_started", { event = M("event." .. id), minutes = minutes })
end

function LiveEventService.init()
	if game.PlaceId ~= 0 then
		task.spawn(function()
			pcall(function()
				MessagingService:SubscribeAsync(TOPIC, function(message)
					local d = message.Data
					if type(d) == "table" and type(d.id) == "string" and Config.LiveEventDefs[d.id] and type(d.endsAt) == "number" then
						override = { id = d.id, endsAt = math.min(d.endsAt, os.time() + MAX_MINUTES * 60) }
						LiveEventService.refresh()
					end
				end)
			end)
		end)
	end

	-- admin chat command
	task.spawn(function()
		local ok, err = pcall(function()
			local cmd = Instance.new("TextChatCommand")
			cmd.Name = "LiveEventCommand"
			cmd.PrimaryAlias = "/event"
			cmd.Triggered:Connect(function(source: TextSource, text: string)
				local player = Players:GetPlayerByUserId(source.UserId)
				if not player then
					return
				end
				local _, message = LiveEventService.command(source.UserId, text)
				Remotes.notify(player, message, "info")
			end)
			cmd.Parent = TextChatService:WaitForChild("TextChatCommands", 10) or TextChatService
		end)
		if not ok then
			warn("[LiveEvents] chat command unavailable:", err)
		end
	end)

	task.spawn(function()
		while true do
			LiveEventService.refresh()
			task.wait(1)
		end
	end)
end

return LiveEventService
