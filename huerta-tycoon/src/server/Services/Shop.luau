--!strict
-- Seed shop: global restock every Config.RestockInterval; each player buys from a personal copy of the roll.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Locale = require(ReplicatedStorage.Shared.Locale)
local R = Locale.ref
local Remotes = require(script.Parent.Remotes)
local Session = require(script.Parent.Session)
local Validate = require(script.Parent.Parent.Security.Validate)

local Shop = {}

local rng = Random.new()
Shop.roll = {} :: { [string]: number }
Shop.nextRestockAt = 0

function Shop.rollStock(): { [string]: number }
	local stock = {}
	for _, seed in Config.Seeds do
		if rng:NextNumber() <= seed.stockChance then
			stock[seed.id] = rng:NextInteger(seed.stockMin, seed.stockMax)
		else
			stock[seed.id] = 0
		end
	end
	return stock
end

function Shop.send(s: Session.S)
	Remotes.fire("StockUpdate", s.player, s.stock, Shop.nextRestockAt)
end

function Shop.giveCopy(s: Session.S)
	s.stock = table.clone(Shop.roll)
	Shop.send(s)
end

-- personal reroll (Robux product)
function Shop.personalRestock(s: Session.S)
	local stock = Shop.rollStock()
	-- a paid restock always contains at least one Rare+ seed
	local rare = {}
	for _, seed in Config.Seeds do
		if seed.rarity ~= "Common" and seed.rarity ~= "Uncommon" and seed.rarity ~= "Divine" then
			table.insert(rare, seed)
		end
	end
	local pick = rare[rng:NextInteger(1, #rare)]
	stock[pick.id] = math.max(stock[pick.id], 1)
	s.stock = stock
	Shop.send(s)
end

local function restock()
	Shop.roll = Shop.rollStock()
	Shop.nextRestockAt = os.time() + Config.RestockInterval
	for _, s in Session.sessions do
		Shop.giveCopy(s)
	end
	-- announce rare stock to everyone
	for _, seed in Config.Seeds do
		if (Shop.roll[seed.id] or 0) > 0 and (seed.rarity == "Legendary" or seed.rarity == "Mythic" or seed.rarity == "Divine") then
			Remotes.notifyAll(R("msg.rareStock", { seed = Locale.seedName(seed.id) }), "rare")
		end
	end
end

-- Live event restock: everyone gets a fresh roll with at least one Mythic-or-better seed in stock.
function Shop.rareRestock()
	restock()
	local top = {}
	for _, seed in Config.Seeds do
		if seed.rarity == "Mythic" or seed.rarity == "Divine" then
			table.insert(top, seed)
		end
	end
	if #top == 0 then
		return
	end
	for _, s in Session.sessions do
		local pick = top[rng:NextInteger(1, #top)]
		s.stock[pick.id] = math.max(s.stock[pick.id] or 0, 1)
		Shop.send(s)
	end
end

function Shop.run()
	restock()
	task.spawn(function()
		while true do
			task.wait(1)
			if os.time() >= Shop.nextRestockAt then
				restock()
			end
		end
	end)
end

Remotes.handle("BuySeed", function(player, payload)
	local s = Session.get(player)
	if not s then
		return false, R("err.loading")
	end
	local seedId = payload.seedId
	-- NaN/inf/strings fall back to 1: a NaN amount used to slip past every comparison and made cash NaN
	local amount = Validate.clampAmount(payload.amount, 1, 50, 1)
	local seed = if Validate.key(seedId, Config.SeedById) then Config.SeedById[seedId] else nil
	if not seed then
		return false, R("err.unknownSeed")
	end
	local left = s.stock[seed.id] or 0
	if left <= 0 then
		return false, R("err.outOfStock")
	end
	amount = math.min(amount, left, math.floor(s.profile.cash / seed.price))
	if amount <= 0 then
		return false, R("err.noCash")
	end
	if not Session.trySpend(s, seed.price * amount) then
		return false, R("err.noCash")
	end
	s.stock[seed.id] = left - amount
	s.profile.seeds[seed.id] = (s.profile.seeds[seed.id] or 0) + amount
	Session.markDirty(s)
	Shop.send(s)
	return true, R("msg.bought", { n = amount, seed = Locale.seedName(seed.id) })
end)

return Shop
