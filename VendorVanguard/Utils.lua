--------------------------------------------------------------------------------
-- Utils.lua: Shared Helper Functions
--------------------------------------------------------------------------------
local _, ns = ...

ns.Utils = ns.Utils or {}

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
-- Cache globals / APIs
local print = print
local tonumber = tonumber
local string_format = string.format
local string_match = string.match

local GetMoneyString = GetMoneyString
local C_TransmogCollection = C_TransmogCollection

-- Print Helper
function ns.Utils.Print(msg)
	print(string_format("|cff00ccff%s|r: %s", (L and L.ADDON_NAME) or "VendorVanguard", msg))
end

-- Formatted Money String
function ns.Utils.FormatMoney(amount)
	return GetMoneyString(amount, true)
end

-- Parse itemID from: itemLink, "item:####", or plain number
function ns.Utils.ParseItemID(input)
	if not input or input == "" then
		return nil
	end

	local id = string_match(input, "item:(%d+)")
	if id then
		return tonumber(id)
	end

	id = string_match(input, "(%d+)")
	return id and tonumber(id) or nil
end

-- Returns true if the item offers a transmog appearance we do NOT have yet.
function ns.Utils.IsUnknownTransmog(itemLink)
	if not itemLink then
		return false
	end

	local _, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
	if not sourceID then
		return false
	end

	local isCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
	return not isCollected
end
