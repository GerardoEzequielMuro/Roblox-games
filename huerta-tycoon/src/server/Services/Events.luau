--!strict
-- Scheduled global live events (weekly Harvest Festival, recurring Lucky Hour) + cross-server admin trigger.
--   * every second: compute the current event (Shared.LiveEvents); on start force its weather, restock with a
--     guaranteed Mythic+ seed when configured, and announce it; on end restore the random weather cycle.
--   * /event <id> <minutes> (TextChatCommand, admins only) -> MessagingService "CK_LiveEvent" -> every server
--     sets the same override.
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local LiveEvents = require(ReplicatedStorage.Shared.LiveEvents)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Weather = require(script.Parent.Weather)
local Shop = require(script.Parent.Shop)

local Events = {}

local TOPIC = "CK_LiveEvent"
Events.override = nil :: { id: string, endsAt: number }?
Events.active = nil :: LiveEvents.Current?
Events.clock = function(): number
	return os.time()
end

local function def(): any
	local a = Events.active
	return if a then Config.LiveEventDefs[a.id] else nil
end

function Events.mutationMult(): number
	local d = def()
	return if d and d.mutationMult then d.mutationMult else 1
end

function Events.growthMult(): number
	local d = def()
	return if d and d.growthMult then d.growthMult else 1
end

function Events.id(): string?
	return if Events.active then Events.active.id else nil
end

function Events.payload(): (any, any)
	local now = Events.clock()
	return Events.active, LiveEvents.nextStart(now, Config.LiveEvents)
end

function Events.send(player: Player)
	local cur, nxt = Events.payload()
	Remotes.fire("LiveEventUpdate", player, cur, nxt)
end

local function broadcast()
	local cur, nxt = Events.payload()
	Remotes.fireAll("LiveEventUpdate", cur, nxt)
end

local function started(cur: LiveEvents.Current)
	local d = Config.LiveEventDefs[cur.id]
	if d and d.weather then
		Weather.force(d.weather, cur.endsAt)
	end
	if d and d.guaranteedRareRestock then
		Shop.rareRestock()
	end
	Remotes.notifyAll(R("event.started", { name = R("event." .. cur.id .. ".name") }), "rare")
end

local function ended(prev: LiveEvents.Current)
	local d = Config.LiveEventDefs[prev.id]
	if d and d.weather then
		Weather.unforce()
	end
end

-- Recompute now; returns the current event (used by the loop and by tests).
function Events.update(): LiveEvents.Current?
	local now = Events.clock()
	local cur = LiveEvents.current(now, Config.LiveEvents, Events.override)
	if cur and not Config.LiveEventDefs[cur.id] then
		cur = nil
	end
	local prev = Events.active
	local changed = (prev == nil) ~= (cur == nil) or (prev and cur and (prev.id ~= cur.id or prev.endsAt ~= cur.endsAt))
	if changed then
		Events.active = cur
		if prev and (not cur or cur.id ~= prev.id) then
			ended(prev)
		end
		if cur and (not prev or prev.id ~= cur.id) then
			started(cur)
		elseif cur then
			local d = Config.LiveEventDefs[cur.id]
			if d and d.weather then
				Weather.force(d.weather, cur.endsAt) -- same event, new end time
			end
		end
		broadcast()
	end
	return cur
end

-- Sets (or clears with nil) the admin override on this server.
function Events.setOverride(o: { id: string, endsAt: number }?)
	Events.override = o
	Events.update()
end

-- Validates an admin request; returns the override or nil.
function Events.parseCommand(text: string): { id: string, endsAt: number }?
	local id, minutes = string.match(text, "^%s*/event%s+(%w+)%s+(%d+)%s*$")
	local m = tonumber(minutes)
	if not id or not m or not Config.LiveEventDefs[id] or m < 1 or m > Config.LiveEventMaxMinutes then
		return nil
	end
	return { id = id, endsAt = Events.clock() + m * 60 }
end

local function isAdmin(userId: number): boolean
	return table.find(Config.AdminUserIds, userId) ~= nil
end

local function setupAdmin()
	if game.PlaceId ~= 0 then
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(msg)
				local data = msg.Data
				if type(data) == "table" and type(data.id) == "string" and Config.LiveEventDefs[data.id] and type(data.endsAt) == "number" then
					Events.setOverride({ id = data.id, endsAt = data.endsAt })
				end
			end)
		end)
	end
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "CK_EventCommand"
	cmd.PrimaryAlias = "/event"
	cmd.AutocompleteVisible = false
	cmd.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player or not isAdmin(source.UserId) then
			return
		end
		local o = Events.parseCommand(text)
		if not o then
			Remotes.notify(player, R("event.adminUsage"), "error")
			return
		end
		Events.setOverride(o)
		if game.PlaceId ~= 0 then
			pcall(function()
				MessagingService:PublishAsync(TOPIC, { id = o.id, endsAt = o.endsAt })
			end)
		end
	end)
	cmd.Parent = TextChatService
end

function Events.run()
	setupAdmin()
	task.spawn(function()
		while true do
			pcall(Events.update)
			task.wait(1)
		end
	end)
end

return Events
