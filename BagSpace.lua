-- BagSpace: when your bags fill up, names the item you'd lose the least by
-- deleting. It never deletes anything itself.
--
-- How it picks:
--   * Never suggested: items you protected with Alt+click, gathering and
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

	if ns.isProtected(info.itemID) then e.skip = "protected (Alt+click)"
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
		e.lastResort = KEEP_LAST[classID]
	end
	return e
end

-- Lower sorts first: ordinary before last-resort, then cheaper, then lower
-- quality, then fewer items.
local function better(a, b)
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

local function rescan()
	local ranked, _, free = scan()
	local old = keyOf(candidate)
	candidate = (free == 0 and ns.BagSpaceEnabled()) and ranked[1] or nil
	local wasFree = freeSlots
	freeSlots = free
	if keyOf(candidate) ~= old then ns.RefreshVisuals() end
	return wasFree
end
ns.RescanBagSpace = rescan

-- The slot currently suggested for deletion (only while bags are full).
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

local function showReport()
	local ranked, skipped, free, mergeable = scan()
	local lines = { "Free slots in ordinary bags: " .. free, "" }
	if mergeable then
		lines[#lines + 1] = "Partial stacks of " .. nameOf(mergeable) .. " can be merged to free a slot."
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = "Delete order (first = least valuable):"
	for i, e in ipairs(ranked) do
		local tag = e.lastResort and ("  [last resort: " .. e.lastResort .. "]") or ""
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
-- Baganator marker on the suggested item (purple outline)
-- ---------------------------------------------------------------------------

local function createSuggestionMarker(itemButton)
	local marker = CreateFrame("Frame", nil, itemButton)
	marker:SetSize(1, 1)
	marker.padding = 0
	local function edge()
		local t = marker:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0.8, 0.3, 1, 1)
		return t
	end
	local top, bottom, left, right = edge(), edge(), edge(), edge()
	top:SetPoint("TOPLEFT", itemButton, "TOPLEFT")
	top:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT")
	top:SetHeight(2)
	bottom:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT")
	bottom:SetHeight(2)
	left:SetPoint("TOPLEFT", itemButton, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", itemButton, "BOTTOMLEFT")
	left:SetWidth(2)
	right:SetPoint("TOPRIGHT", itemButton, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", itemButton, "BOTTOMRIGHT")
	right:SetWidth(2)
	return marker
end

local function registerWithBaganator()
	if not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then return end
	Baganator.API.RegisterCornerWidget("AutoVendor: delete suggestion", "autovendor_delete_suggestion",
		function(_, details)
			return candidate ~= nil and details.itemID == candidate.itemID
		end,
		createSuggestionMarker, { corner = "bottom_left", priority = 1 }, true)
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, _, message)
	if event == "PLAYER_LOGIN" then
		registerWithBaganator()
		rescan()
	elseif event == "BAG_UPDATE_DELAYED" then
		local wasFree = rescan()
		-- Announce only the moment the bags fill, not on every later change.
		if freeSlots == 0 and wasFree and wasFree > 0 and not merchantOpen() and ns.BagSpaceEnabled() then
			lastFullWarning = GetTime()
			announce()
		end
	elseif event == "UI_ERROR_MESSAGE" then
		if message == ERR_INV_FULL and ns.BagSpaceEnabled()
			and GetTime() - lastFullWarning > FULL_ERROR_THROTTLE then
			lastFullWarning = GetTime()
			announce()
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
	elseif command == "space" then
		showReport()
	elseif command == "protect" then
		-- Works with any bag addon: type /av protect, then Shift+click the item.
		local itemID = tonumber(rest:match("item:(%d+)") or rest)
		if itemID then
			ns.ToggleProtected(itemID, rest:match("|c.-|r"))
		else
			print(ns.PREFIX .. "Type /av protect and then Shift+click an item to protect or unprotect it.")
		end
	else
		print(ns.PREFIX .. "/av - open settings.")
		print(ns.PREFIX .. "/av space - show what to delete when your bags are full.")
		print(ns.PREFIX .. "/av protect [item] - protect or unprotect an item (or Alt+click it in your bags).")
	end
end
