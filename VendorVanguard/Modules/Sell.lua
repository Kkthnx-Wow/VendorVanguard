--------------------------------------------------------------------------------
-- Modules\Sell.lua: Auto Junk Selling
--------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local setmetatable = setmetatable

if not L then
	L = setmetatable({}, {
		__index = function(_, k)
			return k
		end,
	})
	ns.L = L
end
local M = {}
ns.Modules.Sell = M

-- Cache globals / APIs
local _G = _G
local type = type
local string_format = string.format

local table_wipe = table.wipe
local C_Container = C_Container
local C_Timer = C_Timer
local GetMoney = GetMoney
local IsShiftKeyDown = IsShiftKeyDown

local BAG_START, BAG_END = 0, 5
local SELL_THROTTLE = 0.15

-- Also sell these (pet trash "currencies" / items)
local petTrashCurrenies = {
	[3300] = true,
	[3670] = true,
	[6150] = true,
	[11406] = true,
	[11944] = true,
	[25402] = true,
	[36812] = true,
	[62072] = true,
	[67410] = true,
}

-- Module State
M.cache = M.cache or {}
M.stop = false
M.startMoney = 0

function M:MERCHANT_SHOW()
	if not ns.DB or not ns.DB.AutoSell or IsShiftKeyDown() then
		return
	end

	-- Ensure table exists
	if type(ns.DB.CustomJunk) ~= "table" then
		ns.DB.CustomJunk = {}
	end

	self.stop = false
	table_wipe(self.cache)
	self.startMoney = GetMoney()

	self:ProcessBagLoop()
end

function M:MERCHANT_CLOSED()
	self.stop = true

	-- Report Profit
	local profit = GetMoney() - (self.startMoney or 0)
	if profit > 0 and ns.DB and ns.DB.DetailedReport then
		-- Defaults to white text + money icons.
		ns.Utils.Print(string_format(L.MSG_JUNK_SOLD, ns.Utils.FormatMoney(profit)))
	end
end

function M:UI_ERROR_MESSAGE(_, msg)
	-- Stop if vendor refuses to buy (e.g., wrong vendor type or disconnect)
	if msg == _G.ERR_VENDOR_DOESNT_BUY then
		self.stop = true
	end
end

function M:ProcessBagLoop()
	if self.stop then
		return
	end

	for bag = BAG_START, BAG_END do
		local numSlots = C_Container.GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			if self.stop then
				return
			end

			local cacheKey = (bag * 100) + slot
			if not self.cache[cacheKey] then
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if self:ShouldSell(info) then
					self.cache[cacheKey] = true
					C_Container.UseContainerItem(bag, slot)

					-- Throttle to avoid disconnect / spam
					C_Timer.After(SELL_THROTTLE, function()
						self:ProcessBagLoop()
					end)
					return
				end
			end
		end
	end
end

function M:ShouldSell(info)
	if not info or not info.hyperlink then
		return false
	end

	-- Some items are flagged as no-value; those cannot be sold.
	if info.hasNoValue then
		return false
	end

	local itemID = info.itemID
	if not itemID then
		return false
	end

	local isGrey = (info.quality == 0)
	local isCustomJunk = (ns.DB and ns.DB.CustomJunk and ns.DB.CustomJunk[itemID]) and true or false
	local isPetTrash = petTrashCurrenies[itemID] and true or false

	if not (isGrey or isCustomJunk or isPetTrash) then
		return false
	end

	-- Shared Logic Check: Don't sell uncollected transmog!
	if ns.Utils.IsUnknownTransmog(info.hyperlink) then
		return false
	end

	return true
end
