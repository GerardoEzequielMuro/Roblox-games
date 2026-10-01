--!strict
-- Live events (P0-6): 2x Coins Weekend and Skip Sale Hour on a UTC schedule (Shared/LiveEvents),
-- plus an admin override (/event <id> <minutes>) broadcast to every server with MessagingService.
-- Effects live where coins / receipts are handled (Session.bonusMult, Monetization.saleBonus).
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local LiveEvents = require(ReplicatedStorage.Shared.LiveEvents)
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)

local Events = {}

local TOPIC = "STO_LiveEvent"
local lastKey = ""

local function validId(id: any): boolean
	for _, def in Config.LiveEvents do
		if def.id == id then
			return true
		end
	end
	return false
end

-- current = { id, endsAt }?, upcoming = { id, startsAt }?
function Events.snapshot(): (LiveEvents.Active?, LiveEvents.Upcoming?)
	local now = os.time()
	return LiveEvents.current(now, Config.LiveEvents :: any, Session.eventOverride), LiveEvents.nextStart(now, Config.LiveEvents :: any)
end

function Events.sendTo(player: Player)
	local cur, nxt = Events.snapshot()
	Remotes.fire("LiveEventUpdate", player, cur, nxt)
end

local function broadcastIfChanged(force: boolean?)
	local cur, nxt = Events.snapshot()
	local key = (cur and (cur.id .. cur.endsAt) or "-") .. "|" .. (nxt and (nxt.id .. nxt.startsAt) or "-")
	if force or key ~= lastKey then
		lastKey = key
		Remotes.fireAll("LiveEventUpdate", cur, nxt)
	end
end

-- Admin / test hook: run `id` until `endsAt` (os.time); endsAt <= now clears the override.
function Events.setOverride(id: string, endsAt: number)
	if endsAt <= os.time() then
		Session.eventOverride = nil
	else
		Session.eventOverride = { id = id, endsAt = endsAt }
	end
	broadcastIfChanged(true)
end

local function isAdmin(userId: number): boolean
	return table.find(Config.AdminUserIds, userId) ~= nil
end

function Events.init()
	task.spawn(function() -- SubscribeAsync yields (and fails in unpublished places)
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local d = message.Data
				if type(d) == "table" and validId(d.id) and type(d.endsAt) == "number" and d.endsAt == d.endsAt and d.endsAt < os.time() + 86400 * 2 then
					Events.setOverride(d.id, d.endsAt)
				end
			end)
		end)
	end)

	-- /event <id> <minutes>   (Config.AdminUserIds only)
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "LiveEventCommand"
	cmd.PrimaryAlias = "/event"
	cmd.Triggered:Connect(function(source: TextSource, text: string)
		if not isAdmin(source.UserId) then
			return
		end
		local id, minutes = string.match(text, "^/event%s+(%S+)%s+(%d+)")
		if not id or not validId(id) then
			return
		end
		local mins = math.clamp(tonumber(minutes) or 0, 0, 24 * 60) -- at most a day
		local endsAt = os.time() + mins * 60
		Events.setOverride(id :: string, endsAt)
		pcall(function()
			MessagingService:PublishAsync(TOPIC, { id = id, endsAt = endsAt })
		end)
	end)
	cmd.Parent = TextChatService

	Players.PlayerAdded:Connect(function(player)
		task.defer(Events.sendTo, player)
	end)
	task.spawn(function()
		while true do
			broadcastIfChanged(false)
			task.wait(5)
		end
	end)
end

return Events
