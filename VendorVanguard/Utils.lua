--------------------------------------------------------------------------------
-- Utils.lua: Shared Helper Functions
--------------------------------------------------------------------------------
local _, ns = ...

-- Localize APIs
local C_TransmogCollection = C_TransmogCollection
local GetMoneyString = GetMoneyString
local format = string.format
local print = print

-- Print Helper
function ns.Utils.Print(msg)
	print(format("|cff00ccffVendorVanguard|r: %s", msg))
end

-- Formatted Money String
function ns.Utils.FormatMoney(amount)
	return GetMoneyString(amount, true)
end

-- Check if item appearance is uncollected (Fixed Logic)
-- Returns true if the item offers a transmog appearance we do NOT have yet.
function ns.Utils.IsUnknownTransmog(itemLink)
	if not itemLink then
		return false
	end

	-- 1. Get the item's appearance ID (visual ID) and modified ID (specific source)
	-- API: C_TransmogCollection.GetItemInfo(itemLink)
	-- Returns: appearanceID, sourceID
	local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)

	-- If no sourceID is returned, the item is not transmoggable (e.g. trinket, ring, neck, or trash)
	if not sourceID then
		return false
	end

	-- 2. Check if we have collected this specific source
	-- API: C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
	local isCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)

	return not isCollected
end
