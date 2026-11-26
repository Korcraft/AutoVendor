-- Lists: the whitelist and blacklist panels on the settings page.
--   Whitelist (AutoVendorDB.protected) = never sold, never suggested for
--     deletion, bought back / pulled out of trades if sold or traded by hand.
--   Blacklist (AutoVendorDB.sell)      = sold at every vendor, gray or not.
-- Permanent: saved by item type, for all your characters, until you take an
-- item off. Ctrl+Alt+click in your bags changes them too. (Plain Alt+click is a separate one-time mark.) Add an item
-- by typing its ID or name, Shift+clicking an item link, or dropping an item
-- on the panel.

local _, ns = ...

local ROW_HEIGHT = 18
local LIST_HEIGHT = 140
ns.LISTS_HEIGHT = 64 + LIST_HEIGHT -- total height a column takes on the page

local getItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

local LISTS = {
	{ key = "protected", title = "Whitelist - never sell", color = { 0.9, 0.1, 0.1 },
		hint = "Or Ctrl+Alt+right-click it in your bags." },
	{ key = "sell", title = "Blacklist - always sell", color = { 1, 0.82, 0 },
		hint = "Or Ctrl+Alt+left-click it in your bags." },
}

local columns = {}   -- every list column built, on every page
local addBoxes = {}  -- their input boxes, for Shift+click links

-- Turns typed text into an item ID: an item link, a number, or the name of an
-- item the game already knows about.
local function parseItem(text)
	text = (text or ""):match("^%s*(.-)%s*$")
	if text == "" then return nil end
	local id = tonumber(text:match("item:(%d+)") or text)
	if not id and getItemInfo then
		local link = select(2, getItemInfo(text))
		id = link and tonumber(link:match("item:(%d+)"))
	end
	if id and getItemInfoInstant and getItemInfoInstant(id) then return id end
	return nil
end

local function nameOf(id)
	local name, _, quality = getItemInfo(id)
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		return "item " .. id .. " (loading...)", 1, 1, 1
	end
	local r, g, b = 1, 1, 1
	if GetItemQualityColor and quality then r, g, b = GetItemQualityColor(quality) end
	return name, r, g, b
end

local function add(column, text)
	local id = parseItem(text)
	if not id then
		print(ns.PREFIX .. "Couldn't find that item. Use an item ID, Shift+click an item link, "
			.. "or drop an item here.")
		return
	end
	ns.SetListed(id, column.key)
end

-- Adds whatever item is on the cursor (dragged from your bags).
local function addFromCursor(column)
	local kind, id = GetCursorInfo()
	if kind ~= "item" or not id then return end
	ClearCursor()
	ns.SetListed(id, column.key)
end

local function getRow(column, i)
	local row = column.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, column.child)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", column.child, "RIGHT")
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	row.icon:SetPoint("LEFT", 2, 0)

	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(14, 14)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	row.remove:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
	row.remove:SetScript("OnClick", function() ns.SetListed(row.itemID, nil) end)
	row.remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Remove from list")
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.label:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(self.itemID)
		else
			GameTooltip:SetHyperlink("item:" .. self.itemID)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- Dropping an item on a row adds it too.
	row:SetScript("OnReceiveDrag", function() addFromCursor(column) end)

	column.rows[i] = row
	return row
end

local function refreshColumn(column)
	local items = {}
	for id in pairs(AutoVendorDB[column.key] or {}) do
		local name, r, g, b = nameOf(id)
		items[#items + 1] = { id = id, name = name, r = r, g = g, b = b }
	end
	table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)

	for i, item in ipairs(items) do
		local row = getRow(column, i)
		row.itemID = item.id
		row.icon:SetTexture(select(5, getItemInfoInstant(item.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.label:SetText(item.name)
		row.label:SetTextColor(item.r, item.g, item.b)
		row:Show()
	end
	for i = #items + 1, #column.rows do column.rows[i]:Hide() end
	column.child:SetHeight(math.max(1, #items * ROW_HEIGHT))
	column.empty:SetShown(#items == 0)
	column.count:SetText("(" .. #items .. ")")
end

function ns.RefreshLists()
	if not AutoVendorDB then return end
	for _, column in ipairs(columns) do
		if column.frame:IsVisible() then refreshColumn(column) end
	end
end

local function buildColumn(container, spec, x, y, width)
	local column = { key = spec.key, rows = {} }
	local frame = CreateFrame("Frame", nil, container)
	frame:SetPoint("TOPLEFT", x, y)
	frame:SetSize(width, ns.LISTS_HEIGHT)
	column.frame = frame

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 2, 0)
	title:SetText(spec.title)
	title:SetTextColor(spec.color[1], spec.color[2], spec.color[3])
	column.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	column.count:SetPoint("LEFT", title, "RIGHT", 4, 0)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	hint:SetText(spec.hint)

	-- Input: type an ID or name and press Enter / Add, or Shift+click a link.
	local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	box:SetSize(width - 62, 20)
	box:SetPoint("TOPLEFT", 6, -34)
	box:SetAutoFocus(false)
	box.column = column
	local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	placeholder:SetPoint("LEFT", 2, 0)
	placeholder:SetText("Item ID, name or Shift+click")
	local function updatePlaceholder()
		placeholder:SetShown(box:GetText() == "" and not box:HasFocus())
	end
	box:SetScript("OnEditFocusGained", updatePlaceholder)
	box:SetScript("OnEditFocusLost", updatePlaceholder)
	box:SetScript("OnTextChanged", updatePlaceholder)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self)
		add(column, self:GetText())
		self:SetText("")
	end)
	box:SetScript("OnReceiveDrag", function() addFromCursor(column) end)
	box:HookScript("OnMouseDown", function() addFromCursor(column) end)
	addBoxes[#addBoxes + 1] = box

	local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	addButton:SetSize(50, 22)
	addButton:SetPoint("LEFT", box, "RIGHT", 6, 0)
	addButton:SetText("Add")
	addButton:SetScript("OnClick", function()
		if GetCursorInfo() == "item" then
			addFromCursor(column)
		else
			add(column, box:GetText())
			box:SetText("")
			box:ClearFocus()
		end
	end)

	-- The list itself, scrolling.
	local area = CreateFrame("Frame", nil, frame)
	area:SetPoint("TOPLEFT", 0, -60)
	area:SetSize(width, LIST_HEIGHT)
	area:EnableMouse(true)
	area:SetScript("OnReceiveDrag", function() addFromCursor(column) end)
	area:SetScript("OnMouseUp", function() addFromCursor(column) end)
	local bg = area:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.35)

	local scroll = CreateFrame("ScrollFrame", nil, area, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -24, 4)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width - 28, 1)
	scroll:SetScrollChild(child)
	column.child = child

	column.empty = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	column.empty:SetPoint("CENTER")
	column.empty:SetText("Empty. Drop an item here to add it.")

	frame:SetScript("OnShow", function() refreshColumn(column) end)
	columns[#columns + 1] = column
	return column
end

-- Builds both lists side by side at x, y in `container`, `width` wide in all.
function ns.BuildLists(container, x, y, width)
	local gap = 16
	local colWidth = math.floor((width - gap) / 2)
	for i, spec in ipairs(LISTS) do
		buildColumn(container, spec, x + (i - 1) * (colWidth + gap), y, colWidth)
	end
end

-- Shift+clicking an item while one of our input boxes has focus adds it.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if type(ChatEdit_InsertLink) == "function" then
			hooksecurefunc("ChatEdit_InsertLink", function(link)
				for _, box in ipairs(addBoxes) do
					if box:IsVisible() and box:HasFocus() and type(link) == "string" then
						add(box.column, link)
						box:SetText("")
						return
					end
				end
			end)
		end
		return
	end
	-- Item names arriving from the server: redraw once they've settled.
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		ns.RefreshLists()
	end)
end)
