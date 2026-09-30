--!strict
-- Tiny in-process event bus so gameplay services can report what happened (hatched, taps,
-- crafted, gems spent, rebirth) without requiring the services that react to it
-- (quests, announcements, notification prompts). Avoids require cycles.
local Hooks = {}

local listeners: { [string]: { (...any) -> () } } = {}

function Hooks.on(name: string, fn: (...any) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
end

function Hooks.fire(name: string, ...: any)
	local list = listeners[name]
	if not list then
		return
	end
	for _, fn in list do
		local ok, err = pcall(fn :: any, ...)
		if not ok then
			warn("[Hooks]", name, err)
		end
	end
end

return Hooks
