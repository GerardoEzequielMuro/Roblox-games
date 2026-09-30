--!strict
-- Server-wide weather events on a timer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local Weather = {}

Weather.current = nil :: Config.Weather?
Weather.endsAt = 0
Weather.nextAt = os.time() + 120 -- first event soon after server start
local rng = Random.new()
local changed = Instance.new("BindableEvent")
Weather.Changed = changed.Event

local function pick(): Config.Weather
	local total = 0
	for _, w in Config.Weathers do
		total += w.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, w in Config.Weathers do
		roll -= w.weight
		if roll <= 0 then
			return w
		end
	end
	return Config.Weathers[1]
end

function Weather.growthMult(): number
	return if Weather.current then Weather.current.growthMultiplier else 1
end

function Weather.goldenMult(): number
	return if Weather.current then Weather.current.goldenChanceMultiplier else 1
end

function Weather.id(): string?
	return if Weather.current then Weather.current.id else nil
end

function Weather.broadcast(player: Player?)
	local id = Weather.id()
	if player then
		Remotes.fire("WeatherUpdate", player, id, Weather.endsAt, Weather.nextAt)
	else
		Remotes.fireAll("WeatherUpdate", id, Weather.endsAt, Weather.nextAt)
	end
end

function Weather.start(weatherId: string?, duration: number?)
	local w = if weatherId then Config.WeatherById[weatherId] else pick()
	if not w then
		return
	end
	local now = os.time()
	Weather.current = w
	Weather.endsAt = now + (duration or rng:NextInteger(Config.WeatherDurationMin, Config.WeatherDurationMax))
	Weather.nextAt = Weather.endsAt + rng:NextInteger(Config.WeatherGapMin, Config.WeatherGapMax)
	Weather.broadcast()
	changed:Fire(w.id)
end

-- Live events force their weather: it preempts the random cycle until unforce() (the cycle then resumes).
Weather.forced = false
local savedNextAt = 0

function Weather.force(weatherId: string, endsAt: number)
	local w = Config.WeatherById[weatherId]
	if not w then
		return
	end
	if not Weather.forced then
		savedNextAt = Weather.nextAt
	end
	Weather.forced = true
	local changedId = Weather.current ~= w
	Weather.current = w
	Weather.endsAt = endsAt
	Weather.nextAt = math.max(savedNextAt, endsAt + Config.WeatherGapMin // 2)
	Weather.broadcast()
	if changedId then
		changed:Fire(w.id)
	end
end

function Weather.unforce()
	if not Weather.forced then
		return
	end
	Weather.forced = false
	local now = os.time()
	Weather.current = nil
	Weather.endsAt = now
	Weather.nextAt = math.max(savedNextAt, now + Config.WeatherGapMin // 2)
	Weather.broadcast()
	changed:Fire(nil)
end

function Weather.run()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			if Weather.forced then
				continue
			end
			if Weather.current and now >= Weather.endsAt then
				Weather.current = nil
				Weather.broadcast()
				changed:Fire(nil)
			elseif not Weather.current and now >= Weather.nextAt then
				Weather.start()
			end
		end
	end)
end

return Weather
