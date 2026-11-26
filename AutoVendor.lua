-- AutoVendor: whenever a merchant opens, sells every gray item and every item
-- you marked to sell, then repairs all gear with your own gold if this
-- merchant can repair. Selling goes first so the sale money can help pay for
-- the repair.
--
-- Two kinds of marks:
--   * One-time, with Alt+click in your bags (default bags or Baganator):
--       Alt+left-click  = sell this (gold coin). Again to unmark.
--       Alt+right-click = protect this (red dotted outline + X). Again to unmark.
--     It covers the copies of that item you're carrying now. Once you no
--     longer have any (sold, deleted, banked...), the mark is gone, and the
--     next one you pick up is treated normally.
--   * Permanent lists, Ctrl+Alt+left/right-click in your bags, the lists in /av (Lists.lua), or /av sell|protect [item]:
--       blacklist (AutoVendorDB.sell)      = always sold, every time you have it
--       whitelist (AutoVendorDB.protected) = never sold, every time you have it
--     By item type, for all your characters, until you take it off.
-- An item is never both sold and protected: marking it one way clears the other.

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

-- How an item is marked: "whitelist", "blacklist", "protectOnce", "sellOnce"
-- or nil. The permanent lists win over a one-time mark.
local function markOf(itemID)
	local db = AutoVendorDB
	if not (itemID and db and AutoVendorCharDB) then return nil end
	if db.protected[itemID] then return "whitelist" end
	if db.sell[itemID] then return "blacklist" end
	if AutoVendorCharDB.protected[itemID] then return "protectOnce" end
	if AutoVendorCharDB.sell[itemID] then return "sellOnce" end
	return nil
end
ns.MarkOf = markOf

local function isProtected(itemID)
	local m = markOf(itemID)
	return m == "whitelist" or m == "protectOnce"
end
ns.isProtected = isProtected

local function isMarkedToSell(itemID)
	local m = markOf(itemID)
	return m == "blacklist" or m == "sellOnce"
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
	if ns.RefreshLists then ns.RefreshLists() end
end

local function afterMarkChange()
	-- A modified click can still pick the item up; put it back.
	if GetCursorInfo() == "item" then ClearCursor() end
	-- The change may affect which item is the delete suggestion.
	if ns.RescanBagSpace then ns.RescanBagSpace() end
	ns.RefreshVisuals()
end

local function labelOf(itemID, itemLink)
	if itemLink then return itemLink end
	local getInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	return (getInfo and select(2, getInfo(itemID))) or ("item " .. itemID)
end

-- One-time marks (Alt+click). `kind` is "sell" or "protected".
local function toggleOnce(kind, itemID, itemLink)
	if not AutoVendorDB then return end
	local label = labelOf(itemID, itemLink)
	local m = markOf(itemID)
	-- A permanent list entry is changed with Ctrl+Alt+click or in /av, not with a one-time click.
	if m == "whitelist" or m == "blacklist" then
		print(PREFIX .. label .. " is on your " .. m .. ". Ctrl+Alt+click it (or use /av) to take it off first.")
		afterMarkChange()
		return
	end
	local once = AutoVendorCharDB
	local other = kind == "sell" and "protected" or "sell"
	if once[kind][itemID] then
		once[kind][itemID] = nil
		print(PREFIX .. label .. (kind == "sell" and " is no longer marked to sell." or " is no longer protected."))
	else
		once[kind][itemID] = true
		once[other][itemID] = nil
		print(PREFIX .. label .. (kind == "sell"
			and " will be sold at the next vendor (this time only - Ctrl+Alt+left-click to always sell it)."
			or " is protected while you carry it (this time only - Ctrl+Alt+right-click to always keep it)."))
	end
	afterMarkChange()
end

-- Permanent lists: puts an item on the whitelist or blacklist, or off it if
-- it's already there. Used by /av protect|sell [item].
local function togglePermanent(list, itemID, itemLink)
	if not AutoVendorDB then return end
	if AutoVendorDB[list][itemID] then
		ns.SetListed(itemID, nil, itemLink)
	else
		ns.SetListed(itemID, list, itemLink)
	end
end
ns.ToggleProtected = function(itemID, itemLink) togglePermanent("protected", itemID, itemLink) end
ns.ToggleSell = function(itemID, itemLink) togglePermanent("sell", itemID, itemLink) end

-- Puts an item on one permanent list ("protected" = whitelist, "sell" =
-- blacklist), or takes it off both when `list` is nil. Used by the list panels.
function ns.SetListed(itemID, list, itemLink)
	if not (AutoVendorDB and itemID) then return end
	local label = labelOf(itemID, itemLink)
	AutoVendorCharDB.protected[itemID] = nil
	AutoVendorCharDB.sell[itemID] = nil
	AutoVendorDB.protected[itemID] = nil
	AutoVendorDB.sell[itemID] = nil
	if list == "protected" then
		AutoVendorDB.protected[itemID] = true
		print(PREFIX .. label .. " is on your whitelist: never sold or suggested for deletion.")
	elseif list == "sell" then
		AutoVendorDB.sell[itemID] = true
		print(PREFIX .. label .. " is on your blacklist: sold at every vendor.")
	else
		print(PREFIX .. label .. " is off your lists.")
	end
	afterMarkChange()
end

-- Drops one-time marks for items you no longer carry. Waits while a vendor
-- or trade window is open: a protected item sold or traded by hand is gone
-- from your bags until Guard.lua gets it back, and must stay protected.
local function pruneOnceMarks()
	local db = AutoVendorDB
	if not (db and AutoVendorCharDB) then return end
	if (MerchantFrame and MerchantFrame:IsShown()) or (TradeFrame and TradeFrame:IsShown()) then return end
	if not (next(AutoVendorCharDB.sell) or next(AutoVendorCharDB.protected)) then return end
	local carried, slots = {}, 0
	for bag = FIRST_BAG, LAST_BAG do
		local n = C_Container.GetContainerNumSlots(bag) or 0
		slots = slots + n
		for slot = 1, n do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then carried[info.itemID] = true end
		end
	end
	if slots == 0 then return end -- bag data not loaded yet (login, loading screen)
	if GetCursorInfo() == "item" then
		local _, cursorID = GetCursorInfo()
		if cursorID then carried[cursorID] = true end -- being moved, still yours
	end
	local changed = false
	for _, marks in pairs({ AutoVendorCharDB.sell, AutoVendorCharDB.protected }) do
		for itemID in pairs(marks) do
			if not carried[itemID] then
				marks[itemID] = nil
				changed = true
			end
		end
	end
	if changed then ns.RefreshVisuals() end
end

-- The one place that decides what a modified click on a bag item means, so
-- every bag UI behaves the same. Returns true if the click was ours.
function ns.HandleItemClick(mouseButton, itemID, itemLink)
	if not itemID then return false end
	local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
	if not alt or shift then return false end
	-- Alt = one-time mark; Ctrl+Alt = permanent list.
	if mouseButton == "LeftButton" then
		if ctrl then togglePermanent("sell", itemID, itemLink) else toggleOnce("sell", itemID, itemLink) end
		return true
	elseif mouseButton == "RightButton" then
		if ctrl then togglePermanent("protected", itemID, itemLink) else toggleOnce("protected", itemID, itemLink) end
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Markers in Baganator (the look is in Markers.lua)
-- ---------------------------------------------------------------------------

-- Alt / Ctrl+Alt clicks on a Baganator item (ns.HandleItemClick). Hooked from
-- every marker's setup, which Baganator runs once per item button, so the
-- clicks work as long as any of our markers is switched on in Baganator.
local function hookClicks(itemButton)
	if itemButton.AutoVendorClicks then return end
	itemButton.AutoVendorClicks = true
	itemButton:HookScript("OnClick", function(self, mouseButton)
		local details = self.BGR
		if details then ns.HandleItemClick(mouseButton, details.itemID, details.itemLink) end
	end)
end

local function markerMaker(create, solid)
	return function(itemButton)
		hookClicks(itemButton)
		local marker = create(itemButton, itemButton, solid)
		marker.padding = 0
		return marker
	end
end

local function registerWithBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
	-- First in the top-left corner, so they win over e.g. the junk coin there.
	-- An item only ever has one of these marks, so they can share the corner.
	local function add(label, id, kind, create, solid, priority)
		Baganator.API.RegisterCornerWidget(label, id,
			function(_, details) return markOf(details.itemID) == kind end,
			markerMaker(create, solid), { corner = "top_left", priority = priority }, true)
	end
	add("AutoVendor: whitelist", "autovendor_whitelist", "whitelist", ns.CreateProtectMarker, true, 1)
	add("AutoVendor: protected (once)", "autovendor_protected", "protectOnce", ns.CreateProtectMarker, false, 2)
	add("AutoVendor: blacklist", "autovendor_blacklist", "blacklist", ns.CreateSellMarker, true, 3)
	add("AutoVendor: sell (once)", "autovendor_sell", "sellOnce", ns.CreateSellMarker, false, 4)
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("TRADE_CLOSED")
events:SetScript("OnEvent", function(self, event, addonName)
	if event == "ADDON_LOADED" then
		if addonName ~= "AutoVendor" then return end
		self:UnregisterEvent("ADDON_LOADED")
		AutoVendorDB = AutoVendorDB or {}
		AutoVendorDB.protected = AutoVendorDB.protected or {}
		AutoVendorDB.sell = AutoVendorDB.sell or {}
		AutoVendorDB.settings = AutoVendorDB.settings or {}
		-- One-time marks are about what this character carries, so per character.
		AutoVendorCharDB = AutoVendorCharDB or {}
		AutoVendorCharDB.sell = AutoVendorCharDB.sell or {}
		AutoVendorCharDB.protected = AutoVendorCharDB.protected or {}
		for key, default in pairs({ sellGrays = true, sellMarked = true, repair = true, bagSpace = true,
			moveToSpecialBags = true, mergeStacks = true, guardSales = true, guardTrades = true }) do
			if AutoVendorDB.settings[key] == nil then AutoVendorDB.settings[key] = default end
		end
		registerWithBaganator()
		return
	end
	if event == "BAG_UPDATE_DELAYED" then pruneOnceMarks() return end
	if event == "TRADE_CLOSED" then C_Timer.After(1, pruneOnceMarks) return end
	session = session + 1
	if event == "MERCHANT_SHOW" then
		-- shouldSell() checks the sell settings, so with both off nothing sells.
		sellPass(session, { sent = {}, count = 0, earned = 0, passes = 0 })
	else -- MERCHANT_CLOSED: the last sales and buybacks have landed by then
		C_Timer.After(1, pruneOnceMarks)
	end
end)
