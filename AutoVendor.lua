-- AutoVendor: whenever a merchant opens, sells every gray item and every item
-- you marked to sell, then repairs all gear with your own gold if this
-- merchant can repair. Selling goes first so the sale money can help pay for
-- the repair.
--
-- Marking items, in your bags (default bags or Baganator):
--   Alt+left-click   = mark to sell (again to unmark). Gold coin in the corner.
--   Alt+right-click  = protect (again to unprotect). Red outline with an X;
--                      never sold or suggested for deletion.
-- With any other bag addon use /av sell [item] or /av protect [item].
-- Marks are by item type and shared by all your characters. An item is never
-- both: marking it one way clears the other.

local _, ns = ...

local PREFIX = "|cff33ff99AutoVendor|r "
ns.PREFIX = PREFIX
local FIRST_BAG, LAST_BAG = 0, 4
local QUALITY_POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- Sold in small batches because the server can drop a burst of sales.
local SELL_BATCH = 10
local SELL_DELAY = 0.25
local REPAIR_DELAY = 0.4 -- lets the sale money arrive before repairing
local MAX_PASSES = 40 -- stops retrying an item that stays locked

-- Bumped on every open and close, so a pending timer from an earlier visit
-- can tell it's stale and stop.
local session = 0

local function formatMoney(copper)
	local gold = math.floor(copper / 10000)
	local silver = math.floor(copper / 100) % 100
	local remainder = copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. "g" end
	if silver > 0 then parts[#parts + 1] = silver .. "s" end
	if remainder > 0 or #parts == 0 then parts[#parts + 1] = remainder .. "c" end
	return table.concat(parts, " ")
end
ns.formatMoney = formatMoney

local function sellPriceOf(info)
	local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if not getInfo or not info.hyperlink then return 0 end
	local price = select(11, getInfo(info.hyperlink))
	if type(price) ~= "number" then return 0 end
	return price * (info.stackCount or 1)
end

local function isProtected(itemID)
	return itemID ~= nil and AutoVendorDB ~= nil and AutoVendorDB.protected ~= nil
		and AutoVendorDB.protected[itemID] == true
end
ns.isProtected = isProtected

local function isMarkedToSell(itemID)
	return itemID ~= nil and AutoVendorDB ~= nil and AutoVendorDB.sell ~= nil
		and AutoVendorDB.sell[itemID] == true
end
ns.isMarkedToSell = isMarkedToSell

local function shouldSell(info)
	if not info or info.hasNoValue or isProtected(info.itemID) then return false end
	local s = AutoVendorDB.settings
	return (s.sellGrays and info.quality == QUALITY_POOR)
		or (s.sellMarked and isMarkedToSell(info.itemID))
end

-- Returns the repair cost paid, or nil plus the unpaid cost if short on gold.
local function repairAll()
	if not CanMerchantRepair() then return 0 end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return 0 end
	if GetMoney() < cost then return nil, cost end
	RepairAllItems(false) -- false = your own gold, never guild funds
	return cost
end

local function finish(id, state)
	C_Timer.After(REPAIR_DELAY, function()
		if id ~= session then return end

		local repaired, unpaid
		if AutoVendorDB.settings.repair then repaired, unpaid = repairAll() end
		local parts = {}
		if state.count > 0 then
			local noun = state.count == 1 and " item" or " items"
			parts[#parts + 1] = "sold " .. state.count .. noun .. " for " .. formatMoney(state.earned)
		end
		if repaired and repaired > 0 then
			parts[#parts + 1] = "repaired for " .. formatMoney(repaired)
		elseif unpaid then
			parts[#parts + 1] = "not enough gold to repair (" .. formatMoney(unpaid) .. ")"
		end
		if #parts > 0 then
			print(PREFIX .. table.concat(parts, ", ") .. ".")
		end
	end)
end

local function sellPass(id, state)
	if id ~= session then return end
	state.passes = state.passes + 1

	local soldThisPass, moreToDo = 0, false
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local key = bag .. ":" .. slot
			if shouldSell(info) and not state.sent[key] then
				if info.isLocked or soldThisPass >= SELL_BATCH then
					moreToDo = true
				else
					state.sent[key] = true
					state.count = state.count + 1
					state.earned = state.earned + sellPriceOf(info)
					soldThisPass = soldThisPass + 1
					C_Container.UseContainerItem(bag, slot)
				end
			end
		end
	end

	if moreToDo and state.passes < MAX_PASSES then
		C_Timer.After(SELL_DELAY, function() sellPass(id, state) end)
	else
		finish(id, state)
	end
end

-- ---------------------------------------------------------------------------
-- Protecting items (shared by every bag UI) and redrawing markers
-- ---------------------------------------------------------------------------

-- Redraws protection and delete-suggestion markers in whichever bag UIs exist.
function ns.RefreshVisuals()
	if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
		Baganator.API.RequestItemButtonsRefresh()
	end
	if ns.RefreshDefaultBags then ns.RefreshDefaultBags() end
end

local function afterMarkChange()
	-- A modified click can still pick the item up; put it back.
	if GetCursorInfo() == "item" then ClearCursor() end
	-- The change may affect which item is the delete suggestion.
	if ns.RescanBagSpace then ns.RescanBagSpace() end
	ns.RefreshVisuals()
end

local function toggleProtected(itemID, itemLink)
	if not AutoVendorDB then return end
	local label = itemLink or ("item " .. itemID)
	if isProtected(itemID) then
		AutoVendorDB.protected[itemID] = nil
		print(PREFIX .. label .. " is no longer protected.")
	else
		AutoVendorDB.protected[itemID] = true
		AutoVendorDB.sell[itemID] = nil
		print(PREFIX .. label .. " is protected and won't be sold or suggested for deletion.")
	end
	afterMarkChange()
end
ns.ToggleProtected = toggleProtected

local function toggleSell(itemID, itemLink)
	if not AutoVendorDB then return end
	local label = itemLink or ("item " .. itemID)
	if isMarkedToSell(itemID) then
		AutoVendorDB.sell[itemID] = nil
		print(PREFIX .. label .. " is no longer marked to sell.")
	else
		AutoVendorDB.sell[itemID] = true
		AutoVendorDB.protected[itemID] = nil
		print(PREFIX .. label .. " is marked to sell. It will be sold at the next vendor.")
	end
	afterMarkChange()
end
ns.ToggleSell = toggleSell

-- The one place that decides what a modified click on a bag item means, so
-- every bag UI behaves the same. Returns true if the click was ours.
function ns.HandleItemClick(mouseButton, itemID, itemLink)
	if not itemID then return false end
	local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
	if mouseButton == "LeftButton" and alt and not ctrl and not shift then
		toggleSell(itemID, itemLink)
		return true
	elseif mouseButton == "RightButton" and alt and not ctrl and not shift then
		toggleProtected(itemID, itemLink)
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Protection marker in Baganator
-- ---------------------------------------------------------------------------

local OUTLINE_COLOR = { 0.9, 0.1, 0.1 }

-- Built once per Baganator item button. The returned frame is what Baganator
-- shows or hides; the dotted, pulsing outline (Markers.lua) hangs off it so
-- both appear together.
local function createMarker(itemButton)
	local marker = CreateFrame("Frame", nil, itemButton)
	marker:SetSize(16, 16)
	marker.padding = 0

	local x = marker:CreateTexture(nil, "OVERLAY")
	x:SetAllPoints()
	x:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

	ns.CreateOutline(marker, itemButton, OUTLINE_COLOR)

	-- Alt+left-click marks to sell, Alt+right-click protects (ns.HandleItemClick).
	-- Hooked here because this runs once per Baganator item button.
	itemButton:HookScript("OnClick", function(self, mouseButton)
		local details = self.BGR
		if details then ns.HandleItemClick(mouseButton, details.itemID, details.itemLink) end
	end)

	return marker
end

-- Gold coin in the corner of items marked to sell.
local function createSellMarker(itemButton)
	local marker = CreateFrame("Frame", nil, itemButton)
	marker:SetSize(14, 14)
	marker.padding = 0
	local coin = marker:CreateTexture(nil, "OVERLAY")
	coin:SetAllPoints()
	coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	ns.AddPulse(marker)
	return marker
end

local function registerWithBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
	-- First in the top-left corner, so it wins over e.g. the junk coin there.
	-- An item is never both protected and marked, so they can share the corner.
	Baganator.API.RegisterCornerWidget("AutoVendor: protected", "autovendor_protected",
		function(_, details) return isProtected(details.itemID) end,
		createMarker, { corner = "top_left", priority = 1 }, true)
	Baganator.API.RegisterCornerWidget("AutoVendor: marked to sell", "autovendor_sell",
		function(_, details) return isMarkedToSell(details.itemID) end,
		createSellMarker, { corner = "top_left", priority = 2 }, true)
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(self, event, addonName)
	if event == "ADDON_LOADED" then
		if addonName ~= "AutoVendor" then return end
		self:UnregisterEvent("ADDON_LOADED")
		AutoVendorDB = AutoVendorDB or {}
		AutoVendorDB.protected = AutoVendorDB.protected or {}
		AutoVendorDB.sell = AutoVendorDB.sell or {}
		AutoVendorDB.settings = AutoVendorDB.settings or {}
		for key, default in pairs({ sellGrays = true, sellMarked = true, repair = true, bagSpace = true,
			moveToSpecialBags = true, mergeStacks = true, guardSales = true, guardTrades = true }) do
			if AutoVendorDB.settings[key] == nil then AutoVendorDB.settings[key] = default end
		end
		registerWithBaganator()
		return
	end
	session = session + 1
	if event == "MERCHANT_SHOW" then
		-- shouldSell() checks the sell settings, so with both off nothing sells.
		sellPass(session, { sent = {}, count = 0, earned = 0, passes = 0 })
	end
end)
