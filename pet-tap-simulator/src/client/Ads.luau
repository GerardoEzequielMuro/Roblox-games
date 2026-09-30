--!strict
-- Rewarded video ads (client side). A placement's button only shows when its developer
-- product is set (Config.AdProducts), today's cap isn't used up and AdService says a video is
-- available right now. The reward is granted by the server's ProcessReceipt.
local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Lang = require(script.Parent.Lang)

local Ads = {}

local available = false
local checkedAt = -math.huge
local checking = false

local function anyPlacementLive(): boolean
	for _, id in Config.AdProducts :: { [string]: number } do
		if id ~= 0 then
			return true
		end
	end
	return false
end

-- Asks AdService at most once a minute, only when a placement could be shown.
local function refreshAvailability()
	if checking or os.clock() - checkedAt < 60 or not anyPlacementLive() then
		return
	end
	checking = true
	task.spawn(function()
		local ok, result = pcall(function()
			return (AdService :: any):GetAdAvailabilityNowAsync((Enum :: any).AdFormat.RewardedVideo)
		end)
		available = ok and result ~= nil and (result :: any).AdAvailabilityResult == (Enum :: any).AdAvailabilityResult.IsAvailable
		checkedAt = os.clock()
		checking = false
	end)
end

function Ads.canShow(placement: string): boolean
	local id = (Config.AdProducts :: any)[placement]
	local s = Net.state
	if type(id) ~= "number" or id == 0 or not s or not s.ads or s.ads.left <= 0 then
		return false
	end
	refreshAvailability()
	return available
end

local notify: (string, string?) -> () = function() end
function Ads.setNotifier(fn: (string, string?) -> ())
	notify = fn
end

function Ads.watch(placement: string)
	local ok, res = Net.request("WatchAd", { placement = placement })
	if not ok then
		notify(Lang.msg(res), "error")
	end
	checkedAt = -math.huge -- re-check availability after a video
end

return Ads
