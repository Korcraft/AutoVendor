-- Guard: an undo for protected items, since the game doesn't let addons
-- block a sale or a trade.
--   * Sold a protected item to a vendor (right-click or drag)? It's bought
--     straight back from the vendor's buyback tab.
--   * Put a protected item in the trade window? It's taken straight back
--     out (items in a trade never leave your bag, they're only locked).
-- To sell or trade a protected item on purpose, unprotect it first
-- (Alt+right-click, or Ctrl+Alt+right-click to take it off the whitelist).
--
-- /av guardtest opens a copyable window showing whether the game functions
-- this relies on exist on this client, plus the current buyback list.

local _, ns = ...

local function setting(key)
	return AutoVendorDB and AutoVendorDB.settings and AutoVendorDB.settings[key] ~= false
end

local function itemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)"))
end

-- A raid-warning-style message in the middle of your screen, with the raid
-- warning sound. Local only: nothing is sent to your group.
local function warn(text)
	if RaidNotice_AddMessage and RaidWarningFrame then
		local color = (ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.28, b = 0 }
		RaidNotice_AddMessage(RaidWarningFrame, text, color)
	end
	if PlaySound then
		local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING
		pcall(PlaySound, kit or 8959)
	end
end

-- ---------------------------------------------------------------------------
-- Vendor buyback
-- ---------------------------------------------------------------------------

-- Every buyback entry already there when the window opened (or after our
-- last check), counted by link. Anything beyond these counts is newly sold.
local known = {}
local merchantOpen = false

local function buybackCounts()
	local counts = {}
	for i = 1, (GetNumBuybackItems and GetNumBuybackItems() or 0) do
		local link = GetBuybackItemLink(i)
		if link then counts[link] = (counts[link] or 0) + 1 end
	end
	return counts
end

local function checkBuyback()
	if not (merchantOpen and setting("guardSales") and GetNumBuybackItems and GetBuybackItemLink and BuybackItem) then
		return
	end
	local seen = {}
	-- Newest sales go at the end of the list, so look from the end.
	for i = GetNumBuybackItems(), 1, -1 do
		local link = GetBuybackItemLink(i)
		if link then
			seen[link] = (seen[link] or 0) + 1
			local isNew = seen[link] > (known[link] or 0)
			local itemID = itemIDFromLink(link)
			-- Whitelisted, or a protected-once stack that just left your bags.
			if isNew and (ns.isProtected(itemID) or ns.TakeSoldOnceProtect(itemID)) then
				BuybackItem(i)
				warn("PROTECTED ITEM SOLD - " .. link .. " bought back")
				print(ns.PREFIX .. link .. " is protected - bought it back. "
					.. "To sell it on purpose, Alt+right-click it, or Ctrl+Alt+right-click if it is whitelisted.")
				-- One per update: indexes shift; the next MERCHANT_UPDATE continues.
				-- The entry counts as known now, so a buyback that didn't go
				-- through is never retried (or repeated on a shifted index).
				known = buybackCounts()
				return
			end
		end
	end
	known = buybackCounts()
end

-- ---------------------------------------------------------------------------
-- Trade window
-- ---------------------------------------------------------------------------

local function checkTradeSlot(slot)
	if not (setting("guardTrades") and GetTradePlayerItemLink and ClickTradeButton) then return end
	local link = GetTradePlayerItemLink(slot)
	local itemID = itemIDFromLink(link)
	if not (link and (ns.isProtected(itemID) or ns.IsOnceProtectedInTrade(itemID))) then return end
	if GetCursorInfo() then return end -- don't drop something you're holding
	ClickTradeButton(slot)            -- picks it back up out of the trade slot...
	if GetCursorInfo() then ClearCursor() end -- ...and returns it to its bag slot
	warn("PROTECTED ITEM - " .. link .. " taken out of the trade")
	print(ns.PREFIX .. link .. " is protected - took it out of the trade. "
		.. "To trade it on purpose, Alt+right-click it, or Ctrl+Alt+right-click if it is whitelisted.")
end

-- ---------------------------------------------------------------------------
-- /av guardtest
-- ---------------------------------------------------------------------------

function ns.GuardTest()
	local function has(name, value) return name .. ": " .. (value ~= nil and "yes" or "MISSING") end
	local lines = {
		"AutoVendor guard test",
		"",
		"Vendor buyback functions:",
		"  " .. has("GetNumBuybackItems", GetNumBuybackItems),
		"  " .. has("GetBuybackItemLink", GetBuybackItemLink),
		"  " .. has("GetBuybackItemInfo", GetBuybackItemInfo),
		"  " .. has("BuybackItem", BuybackItem),
		"",
		"Trade functions:",
		"  " .. has("GetTradePlayerItemLink", GetTradePlayerItemLink),
		"  " .. has("ClickTradeButton", ClickTradeButton),
		"",
		"Warning popup:",
		"  " .. has("RaidNotice_AddMessage", RaidNotice_AddMessage),
		"  " .. has("RaidWarningFrame", RaidWarningFrame),
		"  " .. has("SOUNDKIT.RAID_WARNING", SOUNDKIT and SOUNDKIT.RAID_WARNING),
		"",
		"Vendor window open: " .. tostring(merchantOpen),
	}
	if merchantOpen and GetNumBuybackItems and GetBuybackItemLink then
		lines[#lines + 1] = "Buyback list (oldest first):"
		local n = GetNumBuybackItems()
		for i = 1, n do
			local link = GetBuybackItemLink(i)
			local name = link and link:match("%[(.-)%]") or "?"
			local mark = ns.isProtected(itemIDFromLink(link)) and "  [protected]" or ""
			lines[#lines + 1] = string.format("  %d. %s%s", i, name, mark)
		end
		if n == 0 then lines[#lines + 1] = "  (empty)" end
	else
		lines[#lines + 1] = "(Open a vendor and run this again to see the buyback list.)"
	end
	ns.ShowCopyableText("AutoVendor: guard test", table.concat(lines, "\n"))
	warn("AutoVendor guard test - this is what the warning looks like")
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "MERCHANT_SHOW" then
		merchantOpen = true
		known = buybackCounts()
	elseif event == "MERCHANT_CLOSED" then
		merchantOpen = false
	elseif event == "MERCHANT_UPDATE" then
		checkBuyback()
	elseif event == "TRADE_PLAYER_ITEM_CHANGED" then
		checkTradeSlot(arg1)
	end
end)
