--------------------------------------------------------------------------------
-- Modules\Repair.lua: Auto Repair & Gossip Handling
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
ns.Modules.Repair = M

-- Localize APIs
local CanMerchantRepair = CanMerchantRepair
local GetRepairAllCost = GetRepairAllCost
local GetGuildBankWithdrawMoney = GetGuildBankWithdrawMoney
local RepairAllItems = RepairAllItems
local IsInGuild = IsInGuild
local CanGuildBankRepair = CanGuildBankRepair
local GetMoney = GetMoney
local IsShiftKeyDown = IsShiftKeyDown
local C_GossipInfo = C_GossipInfo
local ipairs = ipairs

local REPAIR_GOSSIP_IDS = {
	[37005] = true, -- Jeeves
	[44982] = true, -- Reaves
}

function M:MERCHANT_SHOW()
	if not ns.DB.AutoRepair or IsShiftKeyDown() then
		return
	end
	if not CanMerchantRepair() then
		return
	end

	local repairCost, canRepair = GetRepairAllCost()
	if canRepair and repairCost > 0 then
		self:AttemptRepair(repairCost)
	end
end

function M:AttemptRepair(cost)
	-- 1. Try Guild Bank
	if ns.DB.GuildRepair and IsInGuild() and CanGuildBankRepair() then
		local guildFunds = GetGuildBankWithdrawMoney()
		if guildFunds == -1 or guildFunds >= cost then
			RepairAllItems(true) -- true = useGuild
			ns.Utils.Print(string.format(L.MSG_GUILD_REPAIRED, ns.Utils.FormatMoney(cost)))
			return
		end
	end

	-- 2. Fallback to Player Money
	if GetMoney() >= cost then
		RepairAllItems()
		ns.Utils.Print(string.format(L.MSG_SELF_REPAIRED, ns.Utils.FormatMoney(cost)))
	else
		ns.Utils.Print(L.ERR_REPAIR_FUNDS)
	end
end

function M:GOSSIP_SHOW()
	if IsShiftKeyDown() then
		return
	end

	-- Automate Jeeves/Reaves
	local options = C_GossipInfo.GetOptions()
	if not options then
		return
	end

	for _, option in ipairs(options) do
		if REPAIR_GOSSIP_IDS[option.gossipOptionID] then
			C_GossipInfo.SelectOption(option.gossipOptionID)
			return
		end
	end
end
