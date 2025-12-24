--------------------------------------------------------------------------------
-- Config.lua: Options Panel + Custom Junk List (icons + remove X)
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

ns.Config = ns.Config or {}

-- Cache globals / APIs
local _G = _G
local type = type
local pairs = pairs
local tostring = tostring

local table_sort = table.sort

local string_format = string.format

local CreateFrame = CreateFrame
local Settings = Settings
local InterfaceOptions_AddCategory = InterfaceOptions_AddCategory
local InterfaceOptionsFrame_OpenToCategory = InterfaceOptionsFrame_OpenToCategory

local FauxScrollFrame_Update = FauxScrollFrame_Update
local FauxScrollFrame_GetOffset = FauxScrollFrame_GetOffset
local FauxScrollFrame_OnVerticalScroll = FauxScrollFrame_OnVerticalScroll

local C_Item = C_Item
local GetItemInfoInstant = GetItemInfoInstant
local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor

-- Constants
local ROW_HEIGHT = 22
local NUM_ROWS = 10

local panel
local categoryID
local isRegistered = false

local countText
local inputBox
local scrollFrame
local rows = {}
local sortedIDs = {}

local function GetDB()
	return ns.DB
end

local function EnsureDB()
	local db = GetDB()
	if not db then
		return nil
	end
	if type(db.CustomJunk) ~= "table" then
		db.CustomJunk = {}
	end
	return db
end

local function GetItemNameIconQuality(itemID)
	-- Return name, icon, quality (best-effort). Item info may not be cached yet.
	local name, icon, quality

	-- Full item info (preferred)
	if GetItemInfo then
		local n, _, q, _, _, _, _, _, _, texture = GetItemInfo(itemID)
		name, quality, icon = n, q, texture
	end

	-- C_Item (Retail) helpers can fill gaps
	if (not name) and C_Item and C_Item.GetItemNameByID then
		name = C_Item.GetItemNameByID(itemID)
	end
	if (not icon) and C_Item and C_Item.GetItemIconByID then
		icon = C_Item.GetItemIconByID(itemID)
	end

	-- Instant info fallback (icon)
	if (not icon) and GetItemInfoInstant then
		local _, _, _, _, texture = GetItemInfoInstant(itemID)
		icon = texture
	end

	return name, icon, quality
end

local function RebuildSortedIDs()
	local db = EnsureDB()
	if not db then
		return
	end

	for i = 1, #sortedIDs do
		sortedIDs[i] = nil
	end

	for itemID in pairs(db.CustomJunk) do
		sortedIDs[#sortedIDs + 1] = itemID
	end

	table_sort(sortedIDs)
end

local function RefreshList()
	if not panel or not panel:IsShown() then
		return
	end

	local db = EnsureDB()
	if not db then
		return
	end

	RebuildSortedIDs()

	local total = #sortedIDs
	if countText then
		countText:SetText(string_format(L.UI_JUNK_COUNT, total))
	end

	if scrollFrame and FauxScrollFrame_Update then
		FauxScrollFrame_Update(scrollFrame, total, NUM_ROWS, ROW_HEIGHT)
	end

	local offset = (scrollFrame and FauxScrollFrame_GetOffset) and FauxScrollFrame_GetOffset(scrollFrame) or 0

	for i = 1, NUM_ROWS do
		local row = rows[i]
		local index = i + offset

		if index <= total then
			local itemID = sortedIDs[index]
			row.itemID = itemID

			local name, icon, quality = GetItemNameIconQuality(itemID)
			if not name then
				name = string_format(L.UI_ROW_LOADING, itemID)
				-- Request load so it resolves later (Retail)
				if C_Item and C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(itemID)
				end
			end

			row.text:SetText(name .. " (" .. tostring(itemID) .. ")")

			-- Quality color
			if quality and GetItemQualityColor then
				local r, g, b = GetItemQualityColor(quality)
				row.text:SetTextColor(r, g, b)
			else
				row.text:SetTextColor(1, 1, 1)
			end

			if icon then
				row.icon:SetTexture(icon)
			else
				row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			end

			row:Show()
		else
			row.itemID = nil
			row:Hide()
		end
	end
end

local function ParseFromInput()
	if not inputBox then
		return nil
	end
	local text = inputBox:GetText() or ""
	return ns.Utils.ParseItemID and ns.Utils.ParseItemID(text) or nil
end

local function AddItem()
	local db = EnsureDB()
	if not db then
		return
	end

	local itemID = ParseFromInput()
	if not itemID then
		ns.Utils.Print(L.UI_ERR_PASTE_ITEM)
		return
	end

	-- Ensure item data is requested (may not be immediately available)
	if C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID)
	end

	local name, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
	if not name then
		ns.Utils.Print(L.ERR_ITEM_LOADING)
		return
	end

	-- Block items with no vendor value / unsellable
	if not sellPrice or sellPrice <= 0 then
		ns.Utils.Print(L.ERR_NO_VENDOR_VALUE)
		return
	end

	if db.CustomJunk[itemID] then
		ns.Utils.Print(string_format(L.MSG_JUNK_ALREADY, name, itemID))
	else
		db.CustomJunk[itemID] = true
		ns.Utils.Print(string_format(L.MSG_JUNK_ADDED, name, itemID))
	end

	if inputBox then
		inputBox:SetText("")
		inputBox:ClearFocus()
	end

	RefreshList()
end

local function RemoveItem(itemID)
	local db = EnsureDB()
	if not db then
		return
	end

	if itemID then
		db.CustomJunk[itemID] = nil
		ns.Utils.Print(string_format(L.MSG_JUNK_REMOVED_ID, itemID))
	end

	RefreshList()
end

local function CreateCheckbox(parent, x, y, label, tooltip, getter, setter)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

	if cb.Text then
		cb.Text:SetText(label)
	else
		local t = _G[cb:GetName() .. "Text"]
		if t then
			t:SetText(label)
		end
	end

	cb.tooltipText = label
	cb.tooltipRequirement = tooltip

	cb:SetScript("OnShow", function(self)
		local db = GetDB()
		if not db then
			return
		end
		self:SetChecked(getter(db))
	end)

	cb:SetScript("OnClick", function(self)
		local db = EnsureDB()
		if not db then
			return
		end
		setter(db, self:GetChecked() and true or false)
	end)

	return cb
end

local function CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(360, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("LEFT", row, "LEFT", 4, 0)

	local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	text:SetPoint("RIGHT", row, "RIGHT", -32, 0)
	text:SetJustifyH("LEFT")

	local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	btn:SetSize(22, 18)
	btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	btn:SetText("|cffff3333X|r")
	btn:SetScript("OnClick", function(self)
		local r = self:GetParent()
		RemoveItem(r.itemID)
	end)

	row.icon = icon
	row.text = text
	row.remove = btn
	row:Hide()
	return row
end

local function CreatePanel()
	if panel then
		return
	end

	panel = CreateFrame("Frame")
	panel.name = L.UI_TITLE

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L.UI_TITLE)

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	sub:SetText(L.UI_SUBTITLE)

	-- Checkboxes
	CreateCheckbox(panel, 16, -60, L.UI_CB_AUTOSELL, L.UI_CB_AUTOSELL_TT, function(db)
		return db.AutoSell
	end, function(db, v)
		db.AutoSell = v
	end)
	CreateCheckbox(panel, 16, -85, L.UI_CB_AUTOREPAIR, L.UI_CB_AUTOREPAIR_TT, function(db)
		return db.AutoRepair
	end, function(db, v)
		db.AutoRepair = v
	end)
	CreateCheckbox(panel, 16, -110, L.UI_CB_GUILDREPAIR, L.UI_CB_GUILDREPAIR_TT, function(db)
		return db.GuildRepair
	end, function(db, v)
		db.GuildRepair = v
	end)
	CreateCheckbox(panel, 16, -135, L.UI_CB_REPORT, L.UI_CB_REPORT_TT, function(db)
		return db.DetailedReport
	end, function(db, v)
		db.DetailedReport = v
	end)

	-- Custom Junk header
	local junkTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	junkTitle:SetPoint("TOPLEFT", 16, -175)
	junkTitle:SetText(L.UI_JUNK_TITLE)

	countText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	countText:SetPoint("TOPLEFT", junkTitle, "BOTTOMLEFT", 0, -4)
	countText:SetText(string_format(L.UI_JUNK_COUNT, 0))

	-- Input
	inputBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	inputBox:SetSize(260, 24)
	inputBox:SetPoint("TOPLEFT", countText, "BOTTOMLEFT", 4, -10)
	inputBox:SetAutoFocus(false)
	inputBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	inputBox:SetScript("OnEnterPressed", function(self)
		AddItem()
	end)

	local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("LEFT", inputBox, "RIGHT", 10, 0)
	hint:SetText(L.UI_INPUT_HINT)

	local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	addBtn:SetSize(90, 22)
	addBtn:SetPoint("TOPLEFT", inputBox, "BOTTOMLEFT", -6, -8)
	addBtn:SetText(L.BTN_ADD)
	addBtn:SetScript("OnClick", AddItem)

	-- Faux scroll list
	scrollFrame = CreateFrame("ScrollFrame", nil, panel, "FauxScrollFrameTemplate")
	scrollFrame:SetSize(380, (NUM_ROWS * ROW_HEIGHT) + 6)
	scrollFrame:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", -2, -10)
	scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RefreshList)
	end)

	-- Rows anchored to the panel (not inside scrollFrame)
	local listAnchor = CreateFrame("Frame", nil, panel)
	listAnchor:SetSize(380, NUM_ROWS * ROW_HEIGHT)
	listAnchor:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 8, -2)

	for i = 1, NUM_ROWS do
		rows[i] = CreateRow(listAnchor, i)
	end

	-- Refresh when item info becomes available
	panel:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	panel:SetScript("OnEvent", function()
		if panel:IsShown() then
			RefreshList()
		end
	end)

	panel:SetScript("OnShow", RefreshList)
end

local function RegisterPanel()
	if isRegistered then
		return
	end
	isRegistered = true

	CreatePanel()

	-- Modern Settings UI
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
		categoryID = category.GetID and category:GetID() or category.ID
		return
	end

	-- Fallback: Interface Options
	if InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function ns.Config.Refresh()
	RefreshList()
end

function ns.Config.Open()
	RegisterPanel()

	-- Open modern Settings, else Interface Options
	if Settings and Settings.OpenToCategory and categoryID then
		Settings.OpenToCategory(categoryID)
		return
	end

	if InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel) -- Blizzard quirk
	end
end

-- Register early
RegisterPanel()
