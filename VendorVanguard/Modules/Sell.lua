--------------------------------------------------------------------------------
-- Modules\Sell.lua: Auto Junk Selling
--------------------------------------------------------------------------------
local _, ns = ...
local M = {}
ns.Modules.Sell = M

-- Localize APIs
local C_Container = C_Container
local C_Timer = C_Timer
local GetMoney = GetMoney
local IsShiftKeyDown = IsShiftKeyDown
local wipe = table.wipe

local BAG_START, BAG_END = 0, 5
local SELL_THROTTLE = 0.15

-- Module State
M.cache = {}
M.stop = false
M.startMoney = 0

function M:MERCHANT_SHOW()
	if not ns.DB.AutoSell or IsShiftKeyDown() then
		return
	end

	self.stop = false
	wipe(self.cache)
	self.startMoney = GetMoney()

	self:ProcessBagLoop()
end

function M:MERCHANT_CLOSED()
	self.stop = true
	-- Report Profit
	local profit = GetMoney() - self.startMoney
	if profit > 0 and ns.DB.DetailedReport then
		-- REVERTED: Removed color code. Defaults to white text + money icons.
		ns.Utils.Print(string.format("Junk sold for %s", ns.Utils.FormatMoney(profit)))
	end
end

function M:UI_ERROR_MESSAGE(errorType, msg)
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

			-- Only check slots we haven't touched this session
			if not self.cache[cacheKey] then
				local info = C_Container.GetContainerItemInfo(bag, slot)

				if self:ShouldSell(info) then
					-- Mark as handled so we don't retry immediately
					self.cache[cacheKey] = true

					C_Container.UseContainerItem(bag, slot)

					-- Throttle: Wait before checking next item
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
	if not info or not info.hyperlink or info.hasNoValue then
		return false
	end

	local isGrey = (info.quality == 0)
	local isCustomJunk = ns.DB.CustomJunk[info.itemID]

	if isGrey or isCustomJunk then
		-- Shared Logic Check: Don't sell uncollected transmog!
		if ns.Utils.IsUnknownTransmog(info.hyperlink) then
			return false
		end
		return true
	end

	return false
end
