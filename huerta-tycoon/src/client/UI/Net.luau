--!nonstrict
-- pcall-safe wrapper around the Request RemoteFunction. Shows the server's message as a toast.
local Toasts = require(script.Parent.Toasts)
local I18n = require(script.Parent.I18n)

local Net = {}

local remotes: Instance? = nil
local busy: { [string]: boolean } = {}

function Net.init(r: Instance)
	remotes = r
end

export type Opts = {
	quiet: boolean?, -- don't toast failures
	silentOk: boolean?, -- don't toast the success message
}

-- Returns ok, message, data (3rd return of the server handler).
function Net.request(action: string, payload: { [string]: any }?, opts: Opts?): (boolean, string?, any)
	local o: Opts = opts or {}
	local req = remotes and remotes:FindFirstChild("Request")
	if not req or not req:IsA("RemoteFunction") then
		if not o.quiet then
			Toasts.show(I18n.t("net.connecting"), "error")
		end
		return false, I18n.t("net.notConnected")
	end

	local key = action
	if payload then
		key ..= ":" .. tostring(payload.tile or payload.seedId or payload.id or "")
	end
	if busy[key] then
		return false, nil
	end
	busy[key] = true
	local callOk, ok, msg, data = pcall(function()
		return (req :: RemoteFunction):InvokeServer(action, payload)
	end)
	busy[key] = nil

	if not callOk then
		warn("[CropKingdom] Request", action, "failed:", ok)
		if not o.quiet then
			Toasts.show(I18n.t("net.hiccup"), "error")
		end
		return false, I18n.t("net.error")
	end
	local message = if type(msg) == "string" and msg ~= "" then msg else nil
	if ok ~= true then
		if not o.quiet then
			Toasts.show(message or I18n.t("net.cant"), "error")
		end
		return false, message, data
	end
	if message and not o.silentOk then
		Toasts.show(message, "success")
	end
	return true, message, data
end

return Net
