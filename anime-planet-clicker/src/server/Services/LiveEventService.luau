--!strict
-- Live events: the UTC schedule (Meteor Shower, Lucky Nebula, Crystal Weekend) plus an admin override
-- (/event <id> <minutes>) shared across servers with MessagingService. Pushes the effects into
-- State.eventEffects (Stardust / luck / Crystal multipliers) and tells clients through LiveEventUpdate.
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local LiveEvents = require(ReplicatedStorage.Shared.LiveEvents)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Locale = require(ReplicatedStorage.Shared.Locale)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local M = Locale.m

local LiveEventService = {}

local TOPIC = "PC_LiveEvent"
local override: LiveEvents.Override? = nil
local lastKey = ""

local function payload(): { [string]: any }
	local now = os.time()
	local active = LiveEvents.active(now, override)
	local nextAt, nextId = LiveEvents.nextStart(now)
	local anomalyOn, _, anomalyEdge = Formulas.anomaly(now)
	return { active = active, current = active[1], nextAt = nextAt, nextId = nextId, serverTime = now, anomalyOn = anomalyOn, anomalyEdge = anomalyEdge }
end

local function isAdmin(userId: number): boolean
	return table.find(Config.AdminUserIds, userId) ~= nil
end

-- Recomputes the active events; on change updates luck for everyone and notifies clients.
function LiveEventService.refresh(force: boolean?)
	local now = os.time()
	local active = LiveEvents.active(now, override)
	local parts = {}
	for _, a in active do
		table.insert(parts, a.id .. "@" .. a.endsAt)
	end
	local anomalyOn = Formulas.anomaly(now)
	table.insert(parts, if anomalyOn then "anomaly" else "quiet")
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
	State.eventEffects = LiveEvents.effects(active)
	State.invalidateAll()
	for _, player in Players:GetPlayers() do
		State.dirty(player)
	end
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

-- "/event LuckyHour 15" from an admin. Returns ok, message.
function LiveEventService.command(userId: number, text: string): (boolean, Locale.Message)
	if not isAdmin(userId) then
		return false, M("msg.admin_only")
	end
	local id, minutesText = text:match("^%s*/event%s+(%w+)%s+(%d+)%s*$")
	local minutes = tonumber(minutesText)
	if not id or not Config.LiveEventDefs[id] or not minutes or minutes < 1 or minutes > Config.LiveEventMaxMinutes then
		return false, M("msg.event_usage", { max = Config.LiveEventMaxMinutes })
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
	State.eventEffects = LiveEvents.effects(LiveEvents.active(os.time(), nil))

	if game.PlaceId ~= 0 then
		task.spawn(function()
			pcall(function()
				MessagingService:SubscribeAsync(TOPIC, function(message)
					local d = message.Data
					if type(d) == "table" and type(d.id) == "string" and Config.LiveEventDefs[d.id] and type(d.endsAt) == "number" then
						override = { id = d.id, endsAt = math.min(d.endsAt, os.time() + Config.LiveEventMaxMinutes * 60) }
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
