--------------------------------------------------------------------------------
-- Core.lua: Namespace, Lifecycle & Event Dispatch
--------------------------------------------------------------------------------
local addonName, ns = ...
_G[addonName] = ns -- Expose globally for debugging if needed

-- Initialize Module Tables
ns.Modules = {}
ns.Utils = {}

-- Localize Global APIs
local CopyTable = CopyTable
local print = print

-- Default Configuration
local defaults = {
	AutoSell = true,
	AutoRepair = true,
	GuildRepair = true,
	DetailedReport = true,
	CustomJunk = {}, -- [itemID] = true
}

-- Event Frame
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("GOSSIP_SHOW")
f:RegisterEvent("UI_ERROR_MESSAGE")

f:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == addonName then
			-- Initialize Database
			VendorVanguardDB = VendorVanguardDB or CopyTable(defaults)
			for k, v in pairs(defaults) do
				if VendorVanguardDB[k] == nil then
					VendorVanguardDB[k] = v
				end
			end
			ns.DB = VendorVanguardDB

			ns.Utils.Print("Loaded. /vv for options.")
			self:UnregisterEvent("ADDON_LOADED")
		end
		return
	end

	-- Dispatch Events to Modules
	-- Each module can define OnMerchantShow, OnMerchantClosed, etc.
	for name, module in pairs(ns.Modules) do
		if module[event] then
			module[event](module, ...)
		end
	end
end)

-- Slash Commands
SLASH_VENDORVANGUARD1 = "/vv"
SlashCmdList["VENDORVANGUARD"] = function(msg)
	local key, val = msg:match("(%w+)%s+(%w+)")
	if key == "autosell" then
		ns.DB.AutoSell = (val == "on")
		ns.Utils.Print("AutoSell is now " .. (ns.DB.AutoSell and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	elseif key == "repair" then
		ns.DB.AutoRepair = (val == "on")
		ns.Utils.Print("AutoRepair is now " .. (ns.DB.AutoRepair and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	else
		ns.Utils.Print("Usage: /vv autosell [on/off] | /vv repair [on/off]")
	end
end
