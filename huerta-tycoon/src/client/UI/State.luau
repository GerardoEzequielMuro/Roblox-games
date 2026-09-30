--!nonstrict
-- Tiny client store: latest server snapshot + stock + weather + local selection, with a change signal.
local State = {}

State.data = nil :: any -- server State (see DESIGN.md); nil until Hello/StateUpdate arrives
State.stock = {} :: { [string]: number }
State.nextRestockAt = 0
State.weather = { id = nil :: string?, endsAt = 0, nextAt = 0 }
State.selectedSeed = nil :: string?
State.liveEvent = { current = nil :: any, next = nil :: any }

type Listener = (kind: string) -> ()
local listeners: { Listener } = {}

-- kind is one of "state" | "stock" | "weather" | "selected"
function State.onChanged(fn: Listener): () -> ()
	table.insert(listeners, fn)
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end

local function fire(kind: string)
	for _, fn in table.clone(listeners) do
		task.spawn(fn, kind)
	end
end

-- Re-run every listener (used after a language switch so computed texts are rebuilt).
function State.refreshAll()
	for _, kind in { "state", "stock", "weather", "selected", "event" } do
		fire(kind)
	end
end

function State.now(): number
	return workspace:GetServerTimeNow()
end

function State.setState(s: any)
	if type(s) ~= "table" then
		return
	end
	-- a reply that was built before the snapshot we already have must not overwrite it
	local cur = State.data
	if cur and type(cur.rev) == "number" and type(s.rev) == "number" and s.rev < cur.rev then
		return
	end
	State.data = s
	fire("state")
end

function State.setStock(stock: any, nextRestockAt: any)
	if type(stock) == "table" then
		State.stock = stock
	end
	if type(nextRestockAt) == "number" then
		State.nextRestockAt = nextRestockAt
	end
	fire("stock")
end

function State.setWeather(id: any, endsAt: any, nextAt: any)
	State.weather = {
		id = if type(id) == "string" then id else nil,
		endsAt = tonumber(endsAt) or 0,
		nextAt = tonumber(nextAt) or 0,
	}
	fire("weather")
end

function State.setLiveEvent(current: any, nxt: any)
	State.liveEvent = {
		current = if type(current) == "table" and type(current.id) == "string" then current else nil,
		next = if type(nxt) == "table" and type(nxt.id) == "string" then nxt else nil,
	}
	fire("event")
end

function State.setSelected(seedId: string?)
	if State.selectedSeed == seedId then
		return
	end
	State.selectedSeed = seedId
	fire("selected")
end

function State.seedCount(seedId: string?): number
	local d = State.data
	if not d or not seedId or type(d.seeds) ~= "table" then
		return 0
	end
	return d.seeds[seedId] or 0
end

function State.totalSeeds(): number
	local d = State.data
	local n = 0
	if d and type(d.seeds) == "table" then
		for _, c in d.seeds do
			n += c
		end
	end
	return n
end

function State.hasPass(key: string): boolean
	local d = State.data
	return d ~= nil and type(d.passes) == "table" and d.passes[key] == true
end

function State.cash(): number
	local d = State.data
	return if d then d.cash or 0 else 0
end

return State
