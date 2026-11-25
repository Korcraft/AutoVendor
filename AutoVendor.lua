-- AutoVendor: whenever a merchant opens, sells every gray item in your bags,
-- then repairs all gear with your own gold if this merchant can repair.
-- Selling goes first so the sale money can help pay for the repair.
--
-- Protected items: Alt+left-click an item in your Baganator bags to protect
-- it (again to unprotect). Protected items are never auto-sold and get a red
-- outline with an X, as a reminder not to sell them by hand either.
-- Protection is by item type, shared by all your characters.

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
	return itemID ~= nil and AutoVendorDB ~= nil and AutoVendorDB.protected[itemID] == true
end
ns.isProtected = isProtected

local function isSellableGray(info)
	return info and info.quality == QUALITY_POOR and not info.hasNoValue
		and not isProtected(info.itemID)
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

		local repaired, unpaid = repairAll()
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
			if isSellableGray(info) and not state.sent[key] then
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
-- Protection marker in Baganator
-- ---------------------------------------------------------------------------

local OUTLINE_COLOR = { 0.9, 0.1, 0.1, 1 }
local OUTLINE_THICKNESS = 2

local function toggleProtected(itemID, itemLink)
	local label = itemLink or ("item " .. itemID)
	if isProtected(itemID) then
		AutoVendorDB.protected[itemID] = nil
		print(PREFIX .. label .. " is no longer protected.")
	else
		AutoVendorDB.protected[itemID] = true
		print(PREFIX .. label .. " is protected and won't be sold.")
	end
	-- An Alt+left-click can still pick the item up; put it back.
	if GetCursorInfo() == "item" then ClearCursor() end
	-- A newly protected item may have been the delete suggestion; pick again.
	if ns.RescanBagSpace then ns.RescanBagSpace() end
	Baganator.API.RequestItemButtonsRefresh()
end

-- Built once per Baganator item button. The returned frame is what Baganator
-- shows or hides; the outline hangs off it so both appear together.
local function createMarker(itemButton)
	local marker = CreateFrame("Frame", nil, itemButton)
	marker:SetSize(16, 16)
	marker.padding = 0

	local x = marker:CreateTexture(nil, "OVERLAY")
	x:SetAllPoints()
	x:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

	local function edge()
		local t = marker:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3], OUTLINE_COLOR[4])
		return t
	end
	local top, bottom, left, right = edge(), edge(), edge(), edge()
	top:SetPoint("TOPLEFT", itemButton, "TOPLEFT")
	top:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT")
	top:SetHeight(OUTLINE_THICKNESS)
	bottom:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT")
	bottom:SetHeight(OUTLINE_THICKNESS)
	left:SetPoint("TOPLEFT", itemButton, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT")
	left:SetWidth(OUTLINE_THICKNESS)
	right:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT")
	right:SetWidth(OUTLINE_THICKNESS)

	-- Baganator's own Alt+click (highlight matching items) also runs; harmless.
	itemButton:HookScript("OnClick", function(self, mouseButton)
		if mouseButton ~= "LeftButton" or not IsAltKeyDown()
			or IsShiftKeyDown() or IsControlKeyDown() then
			return
		end
		local details = self.BGR
		if details and details.itemID then toggleProtected(details.itemID, details.itemLink) end
	end)

	return marker
end

local function registerWithBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
	-- First in the top-left corner, so it wins over e.g. the junk coin there.
	Baganator.API.RegisterCornerWidget("AutoVendor: protected", "autovendor_protected",
		function(_, details) return isProtected(details.itemID) end,
		createMarker, { corner = "top_left", priority = 1 }, true)
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
		registerWithBaganator()
		return
	end
	session = session + 1
	if event == "MERCHANT_SHOW" then
		sellPass(session, { sent = {}, count = 0, earned = 0, passes = 0 })
	end
end)
