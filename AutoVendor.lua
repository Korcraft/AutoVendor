-- AutoVendor: whenever a merchant opens, sells every gray item and every item
-- you marked to sell, then repairs all gear with your own gold if this
-- merchant can repair. Selling goes first so the sale money can help pay for
-- the repair. When the bank opens, puts everything marked for the bank in it.
--
-- Two kinds of marks, in your bags (default bags or Baganator):
--   * One-time, on the one stack you click (other stacks are left alone):
--       Alt+left-click        = sell this stack (gold dotted outline + coin)
--       Alt+right-click       = protect this stack (red dotted outline + X)
--       Shift+Alt+right-click = bank this stack (blue dotted outline + bank icon)
--     Again to unmark. Once the stack is gone (sold, deleted, banked...), the
--     mark is gone too.
--   * Permanent lists, by item type, for all your characters, until you take
--     it off (also in the lists in /av (Lists.lua), or /av sell|protect [item]):
--       Ctrl+Alt+left-click   = blacklist (AutoVendorDB.sell): always sold
--       Ctrl+Alt+right-click  = whitelist (AutoVendorDB.protected): never sold
--       Shift+Alt+left-click  = bank list (AutoVendorDB.bank): always banked
-- An item only ever has one mark: setting one clears the others.

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

-- ---------------------------------------------------------------------------
-- Marks. The whitelist and blacklist are by item type (every copy, always).
-- One-time marks (Alt+click) belong to the one stack you clicked: other
-- stacks of the same item are left alone. They're saved per character in
-- AutoVendorCharDB.once, keyed by the stack's item GUID, so the mark follows
-- the stack if you drag it to another slot. (Without GUIDs on a client, the
-- key falls back to the bag slot.)
-- ---------------------------------------------------------------------------

local function onceKey(bag, slot)
	if not (bag and slot) then return nil end
	if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
		local ok, guid = pcall(function()
			local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
			return C_Item.GetItemGUID(loc)
		end)
		if ok and guid then return guid end
	end
	return "slot:" .. bag .. ":" .. slot
end

-- The one-time mark ({ kind = "sell"|"protected", itemID }) on a bag slot, or nil.
local function onceMarkAt(bag, slot, itemID)
	if not (AutoVendorCharDB and AutoVendorCharDB.once) then return nil end
	local key = onceKey(bag, slot)
	local m = key and AutoVendorCharDB.once[key]
	if m and (itemID == nil or m.itemID == itemID) then return m, key end
	return nil
end
function ns.HasOnceMark(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	return info ~= nil and onceMarkAt(bag, slot, info.itemID) ~= nil
end

-- How an item is marked: "whitelist", "blacklist", "protectOnce", "sellOnce"
-- or nil. The permanent lists win over a one-time mark. Without `bag` and
-- `slot` only the lists are checked.
local function markOf(itemID, bag, slot)
	local db = AutoVendorDB
	if not (itemID and db) then return nil end
	if db.protected[itemID] then return "whitelist" end
	if db.sell[itemID] then return "blacklist" end
	if db.bank and db.bank[itemID] then return "bankList" end
	local m = onceMarkAt(bag, slot, itemID)
	if m then
		return (m.kind == "sell" and "sellOnce") or (m.kind == "bank" and "bankOnce") or "protectOnce"
	end
	return nil
end
ns.MarkOf = markOf

-- Bank list or one-time bank: put in the bank when you open it, and never
-- sold or suggested for deletion meanwhile.
local function isBankMarked(itemID, bag, slot)
	local m = markOf(itemID, bag, slot)
	return m == "bankList" or m == "bankOnce"
end
ns.isBankMarked = isBankMarked

local function isProtected(itemID, bag, slot)
	local m = markOf(itemID, bag, slot)
	return m == "whitelist" or m == "protectOnce"
end
ns.isProtected = isProtected

local function isMarkedToSell(itemID, bag, slot)
	local m = markOf(itemID, bag, slot)
	return m == "blacklist" or m == "sellOnce"
end
ns.isMarkedToSell = isMarkedToSell

-- Every one-time-marked stack still in your bags: key -> { bag, slot, info }.
local function carriedOnceMarks()
	local found = {}
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local m, key = onceMarkAt(bag, slot, info.itemID)
				if m then found[key] = { bag = bag, slot = slot, info = info } end
			end
		end
	end
	return found
end

-- For Guard.lua: a protected-once stack of this item that's gone from your
-- bags (you sold it by hand). Takes the mark off it and remembers to put it
-- back on the stack once it's bought back. True if there was one.
local reprotect = {} -- itemID -> { n = stacks to mark again, before = keys in your bags at the sale }
local function allKeysOf(itemID)
	local keys = {}
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then keys[onceKey(bag, slot)] = true end
		end
	end
	return keys
end
function ns.TakeSoldOnceProtect(itemID)
	if not (itemID and AutoVendorCharDB and AutoVendorCharDB.once) then return false end
	local carried = carriedOnceMarks()
	for key, m in pairs(AutoVendorCharDB.once) do
		if m.kind == "protected" and m.itemID == itemID and not carried[key] then
			AutoVendorCharDB.once[key] = nil
			local r = reprotect[itemID] or { n = 0, before = allKeysOf(itemID) }
			r.n = r.n + 1
			reprotect[itemID] = r
			return true
		end
	end
	return false
end

-- For Guard.lua: is a protected-once stack of this item locked in your bags
-- (items in the trade window stay in the bag, locked)?
function ns.IsOnceProtectedInTrade(itemID)
	for _, c in pairs(carriedOnceMarks()) do
		if c.info.itemID == itemID and c.info.isLocked
			and AutoVendorCharDB.once[onceKey(c.bag, c.slot)].kind == "protected" then
			return true
		end
	end
	return false
end

-- Bought-back stacks come back as new items, so put their mark back on the
-- stack of that item that wasn't in your bags when it was sold.
local function applyReprotect()
	for itemID, r in pairs(reprotect) do
		for bag = FIRST_BAG, LAST_BAG do
			for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				local key = info and info.itemID == itemID and onceKey(bag, slot)
				if key and r.n > 0 and not r.before[key] and not AutoVendorCharDB.once[key] then
					AutoVendorCharDB.once[key] = { kind = "protected", itemID = itemID }
					r.before[key] = true
					r.n = r.n - 1
					ns.RefreshVisuals()
				end
			end
		end
		if r.n <= 0 then reprotect[itemID] = nil end
	end
end
-- Forgets bought-back stacks that never came back (vendor closed).
local function clearReprotect() reprotect = {} end

local function shouldSell(info, bag, slot)
	if not info or info.hasNoValue or isProtected(info.itemID, bag, slot) then return false end
	if isBankMarked(info.itemID, bag, slot) then return false end
	local s = AutoVendorDB.settings
	return (s.sellGrays and info.quality == QUALITY_POOR)
		or (s.sellMarked and isMarkedToSell(info.itemID, bag, slot))
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
			if shouldSell(info, bag, slot) and not state.sent[key] then
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

local LIST_NAMES = { whitelist = "whitelist", blacklist = "blacklist", bankList = "bank list" }
local LIST_CLICKS = {
	whitelist = "Ctrl+Alt+right-click", blacklist = "Ctrl+Alt+left-click", bankList = "Shift+Alt+left-click",
}
local ONCE_ON = {
	sell = " (this stack) will be sold at the next vendor. Ctrl+Alt+left-click to always sell every one.",
	protected = " (this stack) is protected. Ctrl+Alt+right-click to always keep every one.",
	bank = " (this stack) goes in the bank next time you open it. Shift+Alt+left-click to always bank every one.",
}
local ONCE_OFF = {
	sell = " is no longer marked to sell.",
	protected = " is no longer protected.",
	bank = " is no longer marked for the bank.",
}

-- One-time marks on the one stack in `bag`/`slot`. `kind` is "sell",
-- "protected" or "bank".
local function toggleOnce(kind, itemID, itemLink, bag, slot)
	if not AutoVendorDB then return end
	local label = labelOf(itemID, itemLink)
	local m = markOf(itemID)
	-- A permanent list entry is changed with its own click or in /av, not with a one-time click.
	if LIST_NAMES[m] then
		print(PREFIX .. label .. " is on your " .. LIST_NAMES[m] .. ". " .. LIST_CLICKS[m]
			.. " it (or use /av) to take it off first.")
		afterMarkChange()
		return
	end
	local key = onceKey(bag, slot)
	if not key then
		print(PREFIX .. "Couldn't tell which bag slot that was. One-time marks only work on items in your bags.")
		afterMarkChange()
		return
	end
	local current = onceMarkAt(bag, slot, itemID)
	if current and current.kind == kind then
		AutoVendorCharDB.once[key] = nil
		print(PREFIX .. label .. ONCE_OFF[kind])
	else
		AutoVendorCharDB.once[key] = { kind = kind, itemID = itemID }
		print(PREFIX .. label .. ONCE_ON[kind])
	end
	afterMarkChange()
end

-- Permanent lists: puts an item on the whitelist, blacklist or bank list, or
-- off it if it's already there. Used by the clicks and /av protect|sell [item].
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
-- blacklist, "bank" = bank list), or takes it off all of them when `list` is
-- nil. Used by the list panels. Any one-time marks on stacks of it go too:
-- the list decides for all of them now.
function ns.SetListed(itemID, list, itemLink)
	if not (AutoVendorDB and itemID) then return end
	local label = labelOf(itemID, itemLink)
	for key, m in pairs(AutoVendorCharDB.once) do
		if m.itemID == itemID then AutoVendorCharDB.once[key] = nil end
	end
	AutoVendorDB.protected[itemID] = nil
	AutoVendorDB.sell[itemID] = nil
	AutoVendorDB.bank[itemID] = nil
	if list == "protected" then
		AutoVendorDB.protected[itemID] = true
		print(PREFIX .. label .. " is on your whitelist: never sold or suggested for deletion.")
	elseif list == "sell" then
		AutoVendorDB.sell[itemID] = true
		print(PREFIX .. label .. " is on your blacklist: sold at every vendor.")
	elseif list == "bank" then
		AutoVendorDB.bank[itemID] = true
		print(PREFIX .. label .. " is on your bank list: put in the bank whenever you open it, "
			.. "never sold or suggested for deletion.")
	else
		print(PREFIX .. label .. " is off your lists.")
	end
	afterMarkChange()
end

-- Drops one-time marks for stacks you no longer carry (sold, deleted, merged
-- away). Waits while a vendor or trade window is open: a protected stack sold
-- or traded by hand is gone from your bags until Guard.lua gets it back, and
-- must stay protected.
local function pruneOnceMarks()
	if not (AutoVendorDB and AutoVendorCharDB and AutoVendorCharDB.once) then return end
	if (MerchantFrame and MerchantFrame:IsShown()) or (TradeFrame and TradeFrame:IsShown()) then return end
	clearReprotect()
	if not next(AutoVendorCharDB.once) then return end
	local slots = 0
	for bag = FIRST_BAG, LAST_BAG do slots = slots + (C_Container.GetContainerNumSlots(bag) or 0) end
	if slots == 0 then return end -- bag data not loaded yet (login, loading screen)
	-- A stack on the cursor is still in its slot (locked) until it's dropped.
	local carried = carriedOnceMarks()
	local changed = false
	for key in pairs(AutoVendorCharDB.once) do
		if not carried[key] then
			AutoVendorCharDB.once[key] = nil
			changed = true
		end
	end
	if changed then ns.RefreshVisuals() end
end

-- The one place that decides what a modified click on a bag item means, so
-- every bag UI behaves the same. Returns true if the click was ours. `bag`
-- and `slot` say which stack a one-time mark goes on.
-- Ctrl+click on an item opens the dressing room and Shift+click on a stack
-- opens the split-stack box, and the game does that before our click hook
-- runs. So each of those windows notes when it opened, and our modified
-- clicks close one that opened on that same click. (One you already had open
-- stays open.)
local dressUpShownAt = {}
local function watchDressUp()
	for _, name in ipairs({ "DressUpFrame", "SideDressUpFrame", "StackSplitFrame" }) do
		local f = _G[name]
		if f and not dressUpShownAt[f] then
			-- Hooked only now and already open: it loaded on this very click.
			dressUpShownAt[f] = f:IsShown() and GetTime() or -1
			f:HookScript("OnShow", function(self) dressUpShownAt[self] = GetTime() end)
		end
	end
end
local function closeDressUpFromThisClick()
	watchDressUp() -- in case a dressing room frame loads late
	for f, shownAt in pairs(dressUpShownAt) do
		if shownAt == GetTime() and f:IsShown() then
			if HideUIPanel then HideUIPanel(f) end
			if f:IsShown() then f:Hide() end
		end
	end
end

function ns.HandleItemClick(mouseButton, itemID, itemLink, bag, slot)
	if not itemID then return false end
	local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
	if not alt or (shift and ctrl) then return false end
	if ctrl or shift then closeDressUpFromThisClick() end
	-- Alt = one-time mark; Ctrl+Alt = permanent list; Shift+Alt = bank.
	if shift then
		if mouseButton == "LeftButton" then
			togglePermanent("bank", itemID, itemLink)
			return true
		elseif mouseButton == "RightButton" then
			toggleOnce("bank", itemID, itemLink, bag, slot)
			return true
		end
		return false
	end
	if mouseButton == "LeftButton" then
		if ctrl then togglePermanent("sell", itemID, itemLink) else toggleOnce("sell", itemID, itemLink, bag, slot) end
		return true
	elseif mouseButton == "RightButton" then
		if ctrl then togglePermanent("protected", itemID, itemLink) else toggleOnce("protected", itemID, itemLink, bag, slot) end
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
		if not details then return end
		local loc = details.itemLocation
		ns.HandleItemClick(mouseButton, details.itemID, details.itemLink, loc and loc.bagID, loc and loc.slotIndex)
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
			function(_, details)
				local loc = details.itemLocation
				return markOf(details.itemID, loc and loc.bagID, loc and loc.slotIndex) == kind
			end,
			markerMaker(create, solid), { corner = "top_left", priority = priority }, true)
	end
	add("AutoVendor: whitelist", "autovendor_whitelist", "whitelist", ns.CreateProtectMarker, true, 1)
	add("AutoVendor: protected (once)", "autovendor_protected", "protectOnce", ns.CreateProtectMarker, false, 2)
	add("AutoVendor: blacklist", "autovendor_blacklist", "blacklist", ns.CreateSellMarker, true, 3)
	add("AutoVendor: sell (once)", "autovendor_sell", "sellOnce", ns.CreateSellMarker, false, 4)
	add("AutoVendor: bank list", "autovendor_banklist", "bankList", ns.CreateBankMarker, true, 5)
	add("AutoVendor: bank (once)", "autovendor_bank", "bankOnce", ns.CreateBankMarker, false, 6)
end

-- ---------------------------------------------------------------------------
-- Bank: when it opens, everything on the bank list and every stack marked
-- for the bank once goes in, a few at a time like selling. Right-clicking a
-- bag item while the bank is open moves it to the bank -- but would use it
-- (eat, equip...) if the bank weren't open, so every move checks that first.
-- ---------------------------------------------------------------------------

local bankOpen = false
local bankSession = 0

local function bankMarkedLeft()
	local n = 0
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and isBankMarked(info.itemID, bag, slot) then n = n + 1 end
		end
	end
	return n
end

local function bankPass(id, state)
	if id ~= bankSession or not bankOpen then return end
	state.passes = state.passes + 1
	local movedThisPass, moreToDo = 0, false
	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local key = bag .. ":" .. slot
			if info and info.itemID and not state.sent[key] and isBankMarked(info.itemID, bag, slot) then
				if info.isLocked or movedThisPass >= SELL_BATCH then
					moreToDo = true
				elseif bankOpen then
					state.sent[key] = true
					state.count = state.count + 1
					movedThisPass = movedThisPass + 1
					C_Container.UseContainerItem(bag, slot)
				end
			end
		end
	end
	if moreToDo and state.passes < MAX_PASSES then
		C_Timer.After(SELL_DELAY, function() bankPass(id, state) end)
		return
	end
	C_Timer.After(REPAIR_DELAY, function()
		if id ~= bankSession or state.count == 0 then return end
		local left = bankMarkedLeft()
		local moved = math.max(0, state.count - left)
		local line = PREFIX .. "put " .. moved .. (moved == 1 and " stack" or " stacks") .. " in the bank"
		if left > 0 then line = line .. "; " .. left .. " didn't fit (bank full?)" end
		print(line .. ".")
	end)
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("TRADE_CLOSED")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:SetScript("OnEvent", function(self, event, addonName)
	if event == "BANKFRAME_OPENED" then
		bankOpen = true
		bankSession = bankSession + 1
		if AutoVendorDB.settings.bankMarked then
			local id = bankSession
			-- A moment for the bank's contents to arrive first.
			C_Timer.After(0.3, function() bankPass(id, { sent = {}, count = 0, passes = 0 }) end)
		end
		return
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
		bankSession = bankSession + 1
		return
	end
	if event == "ADDON_LOADED" then
		if addonName ~= "AutoVendor" then return end
		self:UnregisterEvent("ADDON_LOADED")
		AutoVendorDB = AutoVendorDB or {}
		AutoVendorDB.protected = AutoVendorDB.protected or {}
		AutoVendorDB.sell = AutoVendorDB.sell or {}
		AutoVendorDB.bank = AutoVendorDB.bank or {}
		AutoVendorDB.settings = AutoVendorDB.settings or {}
		-- One-time marks are about the stacks this character carries, so per
		-- character. (Before 1.4 they were by item type in .sell/.protected.)
		AutoVendorCharDB = AutoVendorCharDB or {}
		AutoVendorCharDB.once = AutoVendorCharDB.once or {}
		AutoVendorCharDB.sell, AutoVendorCharDB.protected = nil, nil
		for key, default in pairs({ sellGrays = true, sellMarked = true, repair = true, bagSpace = true, deleteButton = true, suggestAt = 100,
			moveToSpecialBags = true, mergeStacks = true, guardSales = true, guardTrades = true, bankMarked = true }) do
			if AutoVendorDB.settings[key] == nil then AutoVendorDB.settings[key] = default end
		end
		-- 1.5.0's "always show" switch became the slider's far left.
		if AutoVendorDB.settings.alwaysSuggest then AutoVendorDB.settings.suggestAt = 0 end
		AutoVendorDB.settings.alwaysSuggest = nil
		registerWithBaganator()
		watchDressUp()
		return
	end
	if event == "BAG_UPDATE_DELAYED" then
		applyReprotect()
		pruneOnceMarks()
		return
	end
	if event == "TRADE_CLOSED" then C_Timer.After(1, pruneOnceMarks) return end
	session = session + 1
	if event == "MERCHANT_SHOW" then
		-- shouldSell() checks the sell settings, so with both off nothing sells.
		sellPass(session, { sent = {}, count = 0, earned = 0, passes = 0 })
	else -- MERCHANT_CLOSED: the last sales and buybacks have landed by then
		C_Timer.After(1, pruneOnceMarks)
	end
end)
