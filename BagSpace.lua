-- BagSpace: when your bags fill up, names the item you'd lose the least by
-- deleting. It never deletes anything itself.
--
-- Open your bags while they're full and the cheapest item gets a pink
-- outline. Delete it and the next cheapest lights up, and so on, until you
-- close your bags. Next time they're full and you open them, it starts again.
--
-- How it picks:
--   * Items marked to sell (Alt+left-click or blacklist) come first: you already said
--     they're junk.
--   * Never suggested: protected or whitelisted items, gathering and
--     profession tools (skinning knife, mining pick, fishing poles...), quest
--     items, keys, items with no vendor price (hearthstone and the like), and
--     anything in a profession bag, quiver or ammo pouch.
--   * Ordinary items come first, cheapest whole stack (vendor price x count)
--     first. Ties go to the lower quality.
--   * Food, drink, potions, reagents and ammo are only suggested when nothing
--     ordinary is left, since you're probably carrying those on purpose.
--   * If two partial stacks of the same item could be merged, it says so
--     first: merging frees a slot without losing anything.
--
-- /autovendor space (or /av space) opens a window listing the full ranking.

local _, ns = ...

local FIRST_BAG, LAST_BAG = 0, 4
local FULL_ERROR_THROTTLE = 30 -- seconds between "Inventory is full" reminders

-- Item class IDs (Enum.ItemClass), with plain numbers as a fallback.
local IC = Enum and Enum.ItemClass or {}
local CLASS_CONSUMABLE = IC.Consumable or 0
local CLASS_REAGENT = IC.Reagent or 5
local CLASS_PROJECTILE = IC.Projectile or 6
local CLASS_QUIVER = IC.Quiver or 11
local CLASS_QUEST = IC.Questitem or 12
local CLASS_KEY = IC.Key or 13

-- Items you carry to use, not to sell. Suggested only as a last resort.
local KEEP_LAST = {
	[CLASS_CONSUMABLE] = "consumable",
	[CLASS_REAGENT] = "reagent",
	[CLASS_PROJECTILE] = "ammo",
	[CLASS_QUIVER] = "quiver",
}

-- Profession and gathering tools. They're cheap at a vendor, which is exactly
-- why a price-only pick keeps suggesting them.
local TOOLS = {
	[7005] = true,  -- Skinning Knife
	[12709] = true, -- Finkle's Skinner
	[2901] = true,  -- Mining Pick
	[5956] = true,  -- Blacksmith Hammer
	[6219] = true,  -- Arclight Spanner
	[10498] = true, -- Gyromatic Micro-Adjustor
	[6218] = true,  -- Runed Copper Rod
	[6339] = true,  -- Runed Silver Rod
	[11130] = true, -- Runed Golden Rod
	[11145] = true, -- Runed Truesilver Rod
	[16207] = true, -- Runed Arcanite Rod
	[6256] = true,  -- Fishing Pole
	[6365] = true,  -- Strong Fishing Pole
	[6366] = true,  -- Darkwood Fishing Pole
	[6367] = true,  -- Big Iron Fishing Pole
	[12225] = true, -- Blump Family Fishing Pole
	[19022] = true, -- Nat Pagle's Extreme Angler FC-5000
	[19970] = true, -- Arcanite Fishing Pole
	[4471] = true,  -- Flint and Tinder
	[5060] = true,  -- Thieves' Tools
	[9149] = true,  -- Philosopher's Stone
	[6948] = true,  -- Hearthstone
}

local getItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

local candidate          -- best slot to delete, or nil
local freeSlots          -- free slots in ordinary bags at the last scan
local lastFullWarning = 0

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

local function isOrdinaryBag(bag)
	if bag == 0 then return true end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	return family == 0
end

local lastOrdinaryFree -- free normal slots at the last bag update (nil before the first)

local function ordinaryFreeSlots()
	local free = 0
	for bag = FIRST_BAG, LAST_BAG do
		if isOrdinaryBag(bag) then free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
	end
	return free
end

local function isQuestItem(bag, slot, classID)
	if classID == CLASS_QUEST then return true end
	if C_Container.GetContainerItemQuestInfo then
		local q = C_Container.GetContainerItemQuestInfo(bag, slot)
		if q and (q.isQuestItem or q.questID) then return true end
	end
	return false
end

-- Returns an entry describing the slot, with .skip set to a reason when the
-- slot must never be suggested.
local function describe(bag, slot, info)
	local e = {
		bag = bag, slot = slot,
		itemID = info.itemID, link = info.hyperlink,
		count = info.stackCount or 1, quality = info.quality or 1,
	}
	local _, _, _, _, _, classID = getItemInfoInstant(info.itemID)
	local _, _, _, _, _, _, _, maxStack, _, _, unitPrice = getItemInfo(info.hyperlink or info.itemID)
	e.maxStack = maxStack or 1

	if ns.isProtected(info.itemID, bag, slot) then e.skip = "protected / whitelist"
	elseif ns.isBankMarked(info.itemID, bag, slot) then e.skip = "going to the bank"
	elseif TOOLS[info.itemID] then e.skip = "tool"
	elseif isQuestItem(bag, slot, classID) then e.skip = "quest item"
	elseif classID == CLASS_KEY then e.skip = "key"
	elseif info.isLocked then e.skip = "in use"
	elseif unitPrice == nil then
		e.skip = "item data still loading"
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(info.itemID)
		end
	elseif info.hasNoValue or unitPrice <= 0 then e.skip = "no vendor price"
	else
		e.value = unitPrice * e.count
		e.marked = ns.isMarkedToSell(info.itemID, bag, slot)
		if not e.marked then e.lastResort = KEEP_LAST[classID] end
	end
	return e
end

-- Lower sorts first: marked-to-sell, then ordinary, then last-resort; within
-- each, cheaper first, then lower quality, then fewer items.
local function better(a, b)
	if a.marked ~= b.marked then return a.marked end
	if (a.lastResort ~= nil) ~= (b.lastResort ~= nil) then return a.lastResort == nil end
	if a.value ~= b.value then return a.value < b.value end
	if a.quality ~= b.quality then return a.quality < b.quality end
	return a.count < b.count
end

-- Finds an item that sits in two or more partial stacks, so merging them
-- frees a slot for free.
local function findMergeable(entries)
	local partials = {}
	for _, e in ipairs(entries) do
		if e.maxStack > 1 and e.count < e.maxStack then
			local list = partials[e.itemID] or {}
			list[#list + 1] = e
			partials[e.itemID] = list
		end
	end
	for _, list in pairs(partials) do
		if #list >= 2 then
			local total = 0
			for _, e in ipairs(list) do total = total + e.count end
			-- Merging saves a slot only if fewer stacks would hold it all.
			if math.ceil(total / list[1].maxStack) < #list then return list[1] end
		end
	end
end

local function scan()
	local entries, ranked, skipped = {}, {}, {}
	local free = 0
	for bag = FIRST_BAG, LAST_BAG do
		if isOrdinaryBag(bag) then
			free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID then
					local e = describe(bag, slot, info)
					entries[#entries + 1] = e
					if e.skip then skipped[#skipped + 1] = e else ranked[#ranked + 1] = e end
				end
			end
		end
	end
	table.sort(ranked, better)
	return ranked, skipped, free, findMergeable(entries)
end

-- ---------------------------------------------------------------------------
-- Telling the player
-- ---------------------------------------------------------------------------

local function describeChoice(e)
	local text = e.link or ("item " .. e.itemID)
	if e.count > 1 then text = text .. " x" .. e.count end
	return text .. " (" .. ns.formatMoney(e.value) .. ")"
end

local function announce()
	local ranked, _, _, mergeable = scan()
	if mergeable then
		print(ns.PREFIX .. "Bags full, but you have partial stacks of "
			.. (mergeable.link or "an item") .. " that can be merged to free a slot.")
		return
	end
	local best = ranked[1]
	if not best then
		print(ns.PREFIX .. "Bags full, and nothing in them is safe to suggest deleting.")
		return
	end
	local line = ns.PREFIX .. "Bags full. Least valuable: " .. describeChoice(best) .. "."
	if best.lastResort then
		line = line .. " (Only " .. best.lastResort .. "s left to suggest.)"
	end
	print(line)
end

function ns.BagSpaceEnabled()
	return AutoVendorDB == nil or AutoVendorDB.settings == nil or AutoVendorDB.settings.bagSpace ~= false
end

local function keyOf(e)
	return e and (e.bag .. ":" .. e.slot .. ":" .. e.itemID) or nil
end

-- ---------------------------------------------------------------------------
-- Delete mode: starts when your bags are full and a bag window is open. It
-- then keeps pointing at the next cheapest item after each delete -- even
-- once there's free space -- until you close your bags.
-- ---------------------------------------------------------------------------

local bagOpen = false
local deleteMode = false

-- Baganator's backpack windows are named after its skin ("frame group"), so
-- they're found by name prefix. Looked up again if none are found yet.
local baganatorBackpacks = {}
local lastBaganatorSearch = -math.huge
local function findBaganatorBackpacks()
	-- Walking all globals isn't free, so at most once every 5 seconds.
	if GetTime() - lastBaganatorSearch < 5 then return end
	lastBaganatorSearch = GetTime()
	local found = {}
	pcall(function()
		for name, value in pairs(_G) do
			if type(name) == "string" and type(value) == "table"
				and (name:find("^Baganator_SingleViewBackpackViewFrame")
					or name:find("^Baganator_CategoryViewBackpackViewFrame"))
				and type(value.IsShown) == "function" then
				found[#found + 1] = value
			end
		end
	end)
	baganatorBackpacks = found
end

-- IsVisible, not IsShown: bag addons often hide the game's own bag windows by
-- moving them under a hidden frame, which leaves IsShown() true forever.
-- Returns the open bag window (Baganator's first, then the game's combined
-- bag, then the backpack, then any other bag), or nil when none is open.
local function openBagFrame()
	if Baganator then
		if #baganatorBackpacks == 0 then findBaganatorBackpacks() end
		for _, f in ipairs(baganatorBackpacks) do
			if f:IsVisible() then return f end
		end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsVisible() then return ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f and f:IsVisible() then return f end
	end
	return nil
end

local function isAnyBagOpen()
	return openBagFrame() ~= nil
end

-- Total slots in normal bags. 0 means the bag data hasn't loaded yet (right
-- after login or a loading screen), when every bag also reports 0 free --
-- which must not count as "full".
local function ordinaryTotalSlots()
	local total = 0
	for bag = FIRST_BAG, LAST_BAG do
		if isOrdinaryBag(bag) then total = total + (C_Container.GetContainerNumSlots(bag) or 0) end
	end
	return total
end

local function rescan()
	local ranked, _, free = scan()
	local old = keyOf(candidate)
	if not bagOpen then
		deleteMode = false
	elseif free == 0 and ordinaryTotalSlots() > 0 and not (ns.IsTidying and ns.IsTidying()) then
		-- Only starts while the bags are really full, after tidying couldn't
		-- free anything. Once on, it stays on until the bags close.
		deleteMode = true
	end
	-- "Always show" (off by default): a suggestion whenever your bags are open, full or not.
	local always = bagOpen and AutoVendorDB and AutoVendorDB.settings and AutoVendorDB.settings.alwaysSuggest
	candidate = ((deleteMode or always) and ns.BagSpaceEnabled()) and ranked[1] or nil
	local wasFree = freeSlots
	freeSlots = free
	if keyOf(candidate) ~= old then ns.RefreshVisuals() end
	return wasFree
end
ns.RescanBagSpace = rescan

-- ---------------------------------------------------------------------------
-- Delete button: sits beside the open bag window while there's a pink
-- suggestion. Each click deletes the suggested item; the next cheapest then
-- lights up, so clicking again deletes that one, until you close your bags.
-- The game only lets an addon delete from a real click, so it's always one
-- item per click -- never several at once, never on its own.
-- ---------------------------------------------------------------------------

local RARE = 3
local deleteButton
local deletedKey -- the slot just deleted, so a fast double click can't hit it twice

function ns.DeleteButtonEnabled()
	return AutoVendorDB == nil or AutoVendorDB.settings == nil or AutoVendorDB.settings.deleteButton ~= false
end

-- Deletes `e` if that slot still holds exactly that item and it's still allowed.
local function deleteEntry(e)
	if not e or keyOf(e) ~= keyOf(candidate) then return end
	if GetCursorInfo() then
		print(ns.PREFIX .. "Put down what's on your cursor first.")
		return
	end
	local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
	if not (info and info.itemID == e.itemID) or info.isLocked or ns.isProtected(e.itemID, e.bag, e.slot)
		or ns.isBankMarked(e.itemID, e.bag, e.slot) then
		rescan()
		return
	end
	C_Container.PickupContainerItem(e.bag, e.slot)
	local kind, cursorID = GetCursorInfo()
	if kind ~= "item" or cursorID ~= e.itemID then
		ClearCursor()
		return
	end
	DeleteCursorItem()
	if GetCursorInfo() then
		-- Still holding it: the game didn't allow the delete. Put it back.
		ClearCursor()
		print(ns.PREFIX .. "The game didn't let AutoVendor delete that. Drag it out of your bag to delete it by hand.")
		return
	end
	deletedKey = keyOf(e)
	print(ns.PREFIX .. "Deleted " .. describeChoice(e) .. ".")
end

-- Rare or better: asks first (the game asks too when you delete those by hand).
StaticPopupDialogs["AUTOVENDOR_CONFIRM_DELETE"] = {
	text = "AutoVendor: delete %s?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(_, e) deleteEntry(e) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function onDeleteClick()
	local e = candidate
	if not e or keyOf(e) == deletedKey then return end
	if (e.quality or 1) >= RARE then
		StaticPopup_Show("AUTOVENDOR_CONFIRM_DELETE", describeChoice(e), nil, e)
	else
		deleteEntry(e)
	end
end

local function createDeleteButton()
	local b = CreateFrame("Button", "AutoVendorDeleteButton", UIParent, "UIPanelButtonTemplate")
	b:SetSize(110, 24)
	b:SetFrameStrata("HIGH")
	b:SetText("Delete")
	-- The item's icon, outlined like its slot in the bag (same colour setting).
	local iconFrame = CreateFrame("Frame", nil, b)
	iconFrame:SetSize(32, 32)
	iconFrame:SetPoint("RIGHT", b, "LEFT", -10, 0)
	b.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	ns.CreateOutline(iconFrame, iconFrame, "suggest")
	b:SetScript("OnClick", onDeleteClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Delete the pink-outlined item", 1, 1, 1)
		if candidate then
			GameTooltip:AddLine(describeChoice(candidate), nil, nil, nil, true)
		end
		GameTooltip:AddLine("Deletes it for good. The next cheapest item then lights up; "
			.. "click again to delete that one too. Closes with your bags.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Hide()
	return b
end

local function updateDeleteButton()
	local bagFrame = candidate and ns.DeleteButtonEnabled() and openBagFrame()
	if not bagFrame then
		if deleteButton then deleteButton:Hide() end
		return
	end
	deleteButton = deleteButton or createDeleteButton()
	deleteButton:ClearAllPoints()
	-- Left of the bag window's top-left corner; the icon sits left of the button.
	deleteButton:SetPoint("TOPRIGHT", bagFrame, "TOPLEFT", -4, -24)
	deleteButton.icon:SetTexture(C_Container.GetContainerItemInfo(candidate.bag, candidate.slot)
		and C_Container.GetContainerItemInfo(candidate.bag, candidate.slot).iconFileID or nil)
	if deletedKey and keyOf(candidate) ~= deletedKey then deletedKey = nil end
	deleteButton:SetEnabled(keyOf(candidate) ~= deletedKey)
	deleteButton:Show()
end

-- Watches for bag windows opening and closing (any bag UI).
local function watchBags()
	C_Timer.NewTicker(0.2, function()
		local open = isAnyBagOpen()
		if open ~= bagOpen then
			bagOpen = open
			if not open then deletedKey = nil end
			rescan()
		end
		updateDeleteButton()
	end)
end

-- The slot currently suggested for deletion (only in delete mode).
function ns.GetDeleteSuggestion()
	return candidate
end

local function merchantOpen()
	return MerchantFrame and MerchantFrame:IsShown()
end

-- ---------------------------------------------------------------------------
-- Copyable report window (/autovendor space)
-- ---------------------------------------------------------------------------

local reportWindow

local function showCopyableText(title, text)
	if not reportWindow then
		local f = CreateFrame("Frame", "AutoVendorReportWindow", UIParent)
		f:SetSize(560, 440)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)

		local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOP", 0, -10)
		f.label = label

		local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("TOP", label, "BOTTOM", 0, -4)
		hint:SetText("Click inside, then Ctrl+A, Ctrl+C to copy")

		local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		closeBtn:SetSize(80, 22)
		closeBtn:SetPoint("BOTTOM", 0, 10)
		closeBtn:SetText("Close")
		closeBtn:SetScript("OnClick", function() f:Hide() end)

		local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -44)
		scroll:SetPoint("BOTTOMRIGHT", -32, 40)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(500)
		edit:SetAutoFocus(false)
		edit:SetTextInsets(4, 4, 4, 4)
		edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scroll:SetScrollChild(edit)
		f.edit = edit

		f:Hide()
		reportWindow = f
	end
	reportWindow.label:SetText(title)
	reportWindow.edit:SetText(text)
	reportWindow.edit:HighlightText()
	reportWindow.edit:SetFocus()
	reportWindow:Show()
end

-- Plain item name for the report; links don't copy out cleanly.
local function nameOf(e)
	local name = e.link and e.link:match("%[(.-)%]") or ("item " .. e.itemID)
	if e.count > 1 then name = name .. " x" .. e.count end
	return name
end

ns.ShowCopyableText = showCopyableText

local function showReport()
	local ranked, skipped, free, mergeable = scan()
	local lines = {
		"Free slots in ordinary bags: " .. free .. " of " .. ordinaryTotalSlots(),
		"Bag window open: " .. (isAnyBagOpen() and "yes" or "no")
			.. "   Delete mode: " .. (deleteMode and "on" or "off")
			.. "   Suggesting: " .. (candidate and nameOf(candidate) or "nothing"),
		"",
	}
	if mergeable then
		lines[#lines + 1] = "Partial stacks of " .. nameOf(mergeable) .. " can be merged to free a slot."
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = "Delete order (first = least valuable):"
	for i, e in ipairs(ranked) do
		local tag = e.marked and "  [marked to sell]"
			or e.lastResort and ("  [last resort: " .. e.lastResort .. "]") or ""
		lines[#lines + 1] = string.format("%2d. %s - %s%s", i, nameOf(e), ns.formatMoney(e.value), tag)
	end
	if #ranked == 0 then lines[#lines + 1] = "  (nothing)" end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Never suggested:"
	for _, e in ipairs(skipped) do
		lines[#lines + 1] = "  " .. nameOf(e) .. " - " .. e.skip
	end
	if #skipped == 0 then lines[#lines + 1] = "  (nothing)" end
	showCopyableText("AutoVendor: bag space", table.concat(lines, "\n"))
end

-- ---------------------------------------------------------------------------
-- Baganator marker on the suggested item (hot pink by default, dotted, with a glow)
-- ---------------------------------------------------------------------------

local function createSuggestionMarker(itemButton)
	local marker = CreateFrame("Frame", nil, itemButton)
	marker:SetSize(1, 1)
	marker.padding = 0
	ns.CreateOutline(marker, itemButton, "suggest")
	return marker
end

local function registerWithBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
	Baganator.API.RegisterCornerWidget("AutoVendor: delete suggestion", "autovendor_delete_suggestion",
		function(_, details)
			-- By slot, so other stacks of the same item don't light up too.
			local loc = details.itemLocation
			return candidate ~= nil and loc ~= nil
				and loc.bagID == candidate.bag and loc.slotIndex == candidate.slot
		end,
		createSuggestionMarker, { corner = "bottom_left", priority = 1 }, true)
end

-- ---------------------------------------------------------------------------

-- Called by SpecialBags.lua when tidying is finished. If the bags are still
-- full after combining and moving everything it could, now it's time to
-- suggest a delete.
function ns.OnTidyDone()
	lastOrdinaryFree = ordinaryFreeSlots()
	rescan()
	if freeSlots == 0 and not merchantOpen() and ns.BagSpaceEnabled() then
		lastFullWarning = GetTime()
		announce()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, _, message)
	if event == "PLAYER_LOGIN" then
		registerWithBaganator()
		rescan()
		watchBags()
	elseif event == "BAG_UPDATE_DELAYED" then
		-- While tidying (SpecialBags.lua), each bag update runs its next pass;
		-- everything else waits until it's finished (ns.OnTidyDone below).
		if ns.IsTidying and ns.IsTidying() then
			ns.TidyStep()
			return
		end
		-- The moment the normal bags fill up: tidy first (combine stacks, move
		-- things into special bags) and only then decide about deleting.
		local free = ordinaryFreeSlots()
		if free == 0 and lastOrdinaryFree ~= 0 and ns.StartTidy then
			lastOrdinaryFree = 0
			ns.StartTidy()
			return
		end
		lastOrdinaryFree = free
		rescan()
	elseif event == "UI_ERROR_MESSAGE" then
		if message == ERR_INV_FULL and ns.StartTidy and not ns.IsTidying()
			and GetTime() - lastFullWarning > FULL_ERROR_THROTTLE then
			lastFullWarning = GetTime()
			ns.StartTidy()
		end
	end
end)

SLASH_AUTOVENDOR1 = "/autovendor"
SLASH_AUTOVENDOR2 = "/av"
SlashCmdList.AUTOVENDOR = function(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$")
	local command, rest = msg:match("^(%S*)%s*(.-)$")
	command = command:lower()
	if command == "" or command == "settings" or command == "config" then
		ns.ShowSettings()
	elseif command == "guardtest" then
		ns.GuardTest()
	elseif command == "space" then
		showReport()
	elseif command == "protect" or command == "sell" then
		-- Works with any bag addon: type the command, then Shift+click the item.
		local itemID = tonumber(rest:match("item:(%d+)") or rest)
		local toggle = command == "protect" and ns.ToggleProtected or ns.ToggleSell
		if itemID then
			toggle(itemID, rest:match("|c.-|r"))
		else
			print(ns.PREFIX .. "Type /av " .. command .. " and then Shift+click an item.")
		end
	else
		print(ns.PREFIX .. "/av - open settings.")
		print(ns.PREFIX .. "/av space - show what to delete when your bags are full.")
		print(ns.PREFIX .. "/av sell [item] - add to or remove from your blacklist (always sold).")
		print(ns.PREFIX .. "/av protect [item] - add to or remove from your whitelist (never sold).")
		print(ns.PREFIX .. "In your bags: Alt+left/right-click = sell/protect that stack only; Ctrl+Alt+left/right-click = blacklist/whitelist; Shift+Alt+left/right-click = bank list/bank that stack once.")
	end
end
