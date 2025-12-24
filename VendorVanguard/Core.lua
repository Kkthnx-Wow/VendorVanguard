--------------------------------------------------------------------------------
-- Core.lua: Namespace, Lifecycle, DB, Slash, & Event Dispatch
--------------------------------------------------------------------------------
local addonName, ns = ...

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

-- Cache globals (perf / style)
local _G = _G
local type = type
local pairs = pairs
local string_lower = string.lower
local string_match = string.match
local string_gsub = string.gsub
local string_format = string.format

local CreateFrame = CreateFrame
local CopyTable = CopyTable
local GetItemInfo = GetItemInfo
local C_Item = C_Item

-- Expose globally for debugging if needed
_G[addonName] = ns

-- Initialize Module Tables (safe if Core loads first)
ns.Modules = ns.Modules or {}
ns.Utils = ns.Utils or {}
ns.Config = ns.Config or {}

-- Default Configuration
local defaults = {
	AutoSell = true,
	AutoRepair = true,
	GuildRepair = true,
	DetailedReport = true,
	CustomJunk = {}, -- [itemID] = true
}

-- Deep-ish defaults apply (handles nested tables safely)
local function ApplyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = CopyTable(v)
			else
				dst[k] = v
			end
		elseif type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			ApplyDefaults(dst[k], v)
		end
	end
end

local function EnsureDBTables(db)
	if type(db.CustomJunk) ~= "table" then
		db.CustomJunk = {}
	end
end

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
			VendorVanguardDB = VendorVanguardDB or {}
			ApplyDefaults(VendorVanguardDB, defaults)
			EnsureDBTables(VendorVanguardDB)

			ns.DB = VendorVanguardDB

			if ns.Utils and ns.Utils.Print then
				ns.Utils.Print(L.MSG_LOADED)
			end

			self:UnregisterEvent("ADDON_LOADED")
		end
		return
	end

	-- Dispatch Events to Modules
	for _, module in pairs(ns.Modules) do
		local handler = module[event]
		if handler then
			handler(module, ...)
		end
	end
end)

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------
SLASH_VENDORVANGUARD1 = "/vv"

local function ToBoolOnOff(val)
	val = val and string_lower(val) or ""
	return (val == "on" or val == "1" or val == "true" or val == "yes")
end

local function PrintUsage()
	ns.Utils.Print(L.CMD_HEADER)
	ns.Utils.Print(L.CMD_OPEN)
	ns.Utils.Print(L.CMD_AUTOSELL)
	ns.Utils.Print(L.CMD_AUTOREPAIR)
	ns.Utils.Print(L.CMD_GUILDREPAIR)
	ns.Utils.Print(L.CMD_REPORT)
	ns.Utils.Print(L.CMD_JUNK_ADD)
	ns.Utils.Print(L.CMD_JUNK_DEL)
	ns.Utils.Print(L.CMD_JUNK_LIST)
end

SlashCmdList["VENDORVANGUARD"] = function(msg)
	msg = msg or ""
	msg = string_gsub(msg, "^%s+", "")
	msg = string_gsub(msg, "%s+$", "")

	if msg == "" then
		if ns.Config and ns.Config.Open then
			ns.Config.Open()
		else
			PrintUsage()
		end
		return
	end

	local a, b, c = string_match(msg, "^(%S+)%s*(%S*)%s*(.*)$")
	a = a and string_lower(a) or ""
	b = b and string_lower(b) or ""

	if not ns.DB then
		PrintUsage()
		return
	end

	-- Simple toggles
	if a == "autosell" then
		ns.DB.AutoSell = ToBoolOnOff(b)
		ns.Utils.Print(string_format(L.MSG_OPT_NOW, L.OPT_AUTOSELL, (ns.DB.AutoSell and "|cff00ff00ON|r" or "|cffff0000OFF|r")))
		return
	elseif a == "autorepair" or a == "repair" then
		ns.DB.AutoRepair = ToBoolOnOff(b)
		ns.Utils.Print(string_format(L.MSG_OPT_NOW, L.OPT_AUTOREPAIR, (ns.DB.AutoRepair and "|cff00ff00ON|r" or "|cffff0000OFF|r")))
		return
	elseif a == "guildrepair" then
		ns.DB.GuildRepair = ToBoolOnOff(b)
		ns.Utils.Print(string_format(L.MSG_OPT_NOW, L.OPT_GUILDREPAIR, (ns.DB.GuildRepair and "|cff00ff00ON|r" or "|cffff0000OFF|r")))
		return
	elseif a == "report" then
		ns.DB.DetailedReport = ToBoolOnOff(b)
		ns.Utils.Print(string_format(L.MSG_OPT_NOW, L.OPT_REPORT, (ns.DB.DetailedReport and "|cff00ff00ON|r" or "|cffff0000OFF|r")))
		return
	end

	-- Junk management
	if a == "junk" then
		local sub = b
		local rest = c

		if type(ns.DB.CustomJunk) ~= "table" then
			ns.DB.CustomJunk = {}
		end

		if sub == "list" then
			local count = 0
			for _ in pairs(ns.DB.CustomJunk) do
				count = count + 1
			end
			ns.Utils.Print(string_format(L.MSG_CUSTOMJUNK_COUNT, count))
			return
		end

		if (sub == "add" or sub == "del" or sub == "remove") and rest and rest ~= "" then
			local itemID = ns.Utils.ParseItemID and ns.Utils.ParseItemID(rest)
			if not itemID then
				ns.Utils.Print(L.ERR_PARSE_ITEMID)
				return
			end

			if sub == "add" then
				-- Block items with no vendor value / unsellable
				if C_Item and C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(itemID)
				end
				local name, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
				if not name then
					ns.Utils.Print(L.ERR_ITEM_LOADING)
					return
				end
				if not sellPrice or sellPrice <= 0 then
					ns.Utils.Print(L.ERR_NO_VENDOR_VALUE)
					return
				end
				ns.DB.CustomJunk[itemID] = true
				ns.Utils.Print(string_format(L.MSG_JUNK_ADDED_ID, itemID))
			else
				ns.DB.CustomJunk[itemID] = nil
				ns.Utils.Print(string_format(L.MSG_JUNK_REMOVED_ID, itemID))
			end

			if ns.Config and ns.Config.Refresh then
				ns.Config.Refresh()
			end
			return
		end
	end

	PrintUsage()
end
