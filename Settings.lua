-- Settings: the same page of switches in two places, built by one function:
--   * its own movable window (/av). Closing it just closes it; it never goes
--     through Blizzard's settings panel, whose close reopens the game menu.
--   * Blizzard's Options > AddOns > AutoVendor.
-- Each page re-reads the settings when shown and after any change, so the two
-- never disagree. Layout idea borrowed from Shady Business (MIT).

local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local ROW_SPACING = 30
local WIDTH = 520
local LISTS_WIDTH = WIDTH - 40

-- Huntard owns ammo buying; this switch just flips Huntard's own setting.
-- Only on a hunter: Huntard switches itself off on other classes.
local function huntardAmmo()
	local H = _G.Huntard
	return H and H.active and H.db and H.db.ammoRestock
end

local function setting(key)
	return {
		get = function() return AutoVendorDB.settings[key] end,
		set = function(on) AutoVendorDB.settings[key] = on end,
	}
end

local OPTIONS = {
	{ label = "Sell gray items at vendors", option = setting("sellGrays"),
		help = "Sells every gray item when you open a vendor. Whitelisted items are never sold." },
	{ label = "Sell blacklisted and Alt+clicked items", option = setting("sellMarked"),
		help = "Sells everything on your blacklist (below), and anything you Alt+left-clicked in your bags "
			.. "(gold coin, this time only), along with the grays when you open a vendor, whatever its quality." },
	{ label = "Repair gear at vendors", option = setting("repair"),
		help = "Repairs all your gear with your own gold (never guild funds) when the vendor can repair." },
	{ label = "Suggest what to delete when bags are full", option = setting("bagSpace"),
		help = "Names the least valuable item when your bags fill up, and outlines it in pink. Never deletes anything.",
		after = function() if ns.RescanBagSpace then ns.RescanBagSpace() end end },
	{ label = "Show a Delete button beside your bags", option = setting("deleteButton"),
		help = "While an item is outlined in pink, a Delete button sits beside your open bags. Each click deletes "
			.. "the pink item and the next cheapest lights up, so you can keep clicking until you have the space. "
			.. "Rare and better items ask first. Gone with your bags." },
	{ label = "Buy back whitelisted items sold by mistake", option = setting("guardSales"),
		help = "If you sell a whitelisted item to a vendor by hand, it's bought straight back. "
			.. "Take it off the whitelist first to sell it on purpose." },
	{ label = "Take whitelisted items out of trades", option = setting("guardTrades"),
		help = "If you put a whitelisted item in the trade window, it's taken straight back out. "
			.. "Take it off the whitelist first to trade it on purpose." },
	{ label = "Combine partial stacks when bags are full", option = setting("mergeStacks"),
		help = "When your normal bags fill up, merges partial stacks of the same item (including into a "
			.. "partial stack in your quiver or a profession bag) when that frees a slot." },
	{ label = "Move items into special bags when bags are full", option = setting("moveToSpecialBags"),
		help = "When your normal bags fill up, moves ammo into your quiver or ammo pouch, leather into a "
			.. "leatherworking bag, herbs into an herb bag and so on, if there's a free slot there." },
	{ label = "Buy ammo at vendors (Huntard)",
		option = {
			get = function() return huntardAmmo().enabled end,
			set = function(on) huntardAmmo().enabled = on end,
		},
		help = "Huntard's ammo refill. The same switch as in Huntard's own settings.",
		shown = function() return huntardAmmo() ~= nil end },
}

-- ---------------------------------------------------------------------------
-- Marker colours: a swatch per marker kind (click to pick a colour) and a
-- button that puts them all back. See Markers.lua.
-- ---------------------------------------------------------------------------

local COLORS_HEIGHT = 92 -- header + two rows of swatches
local swatches = {}

local function syncSwatches()
	for _, s in ipairs(swatches) do s.fill:SetColorTexture(unpack(ns.MarkerColor(s.key))) end
end

-- Blizzard's colour picker: the newer call where there is one, else the old fields.
local function pickColor(key)
	local start = ns.MarkerColor(key)
	local r0, g0, b0 = start[1], start[2], start[3]
	local function apply()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		ns.SetMarkerColor(key, r, g, b)
		syncSwatches()
	end
	local function cancel()
		ns.SetMarkerColor(key, r0, g0, b0)
		syncSwatches()
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r0, g = g0, b = b0, hasOpacity = false,
			swatchFunc = apply, cancelFunc = cancel,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = apply
		ColorPickerFrame.cancelFunc = cancel
		ColorPickerFrame.previousValues = { r0, g0, b0 }
		ColorPickerFrame:SetColorRGB(r0, g0, b0)
		ColorPickerFrame:Hide() -- re-show so it picks up the new values
		ShowUIPanel(ColorPickerFrame)
	end
end

local function buildColors(container, x, y, width)
	local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetPoint("TOPLEFT", x, y)
	header:SetText("Highlight colours")
	local sub = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("LEFT", header, "RIGHT", 6, 0)
	sub:SetText("click a swatch to change it")

	local columnWidth = math.floor(width / 3)
	for i, c in ipairs(ns.MARKER_COLORS) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local b = CreateFrame("Button", nil, container)
		b:SetSize(20, 20)
		b:SetPoint("TOPLEFT", x + col * columnWidth, y - 22 - row * 28)
		local border = b:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		border:SetColorTexture(0.8, 0.8, 0.8, 1)
		b.fill = b:CreateTexture(nil, "ARTWORK")
		b.fill:SetPoint("TOPLEFT", 2, -2)
		b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
		b.key = c.key
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", b, "RIGHT", 6, 0)
		label:SetText(c.label)
		b:SetHitRectInsets(0, -(label:GetStringWidth() + 6), 0, 0)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(c.label .. " colour", 1, 1, 1)
			GameTooltip:AddLine("Click to choose the outline and glow colour for this marker. "
				.. "Right-click to put it back to the default.", nil, nil, nil, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, mouseButton)
			if mouseButton == "RightButton" then
				ns.SetMarkerColor(c.key, nil)
				syncSwatches()
			else
				pickColor(c.key)
			end
		end)
		swatches[#swatches + 1] = b
	end

	local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
	reset:SetSize(120, 22)
	reset:SetPoint("TOPLEFT", x + 2 * columnWidth, y - 22 - 28 - 1)
	reset:SetText("Reset colours")
	reset:SetScript("OnClick", function()
		for _, c in ipairs(ns.MARKER_COLORS) do ns.SetMarkerColor(c.key, nil) end
		syncSwatches()
	end)
	container:HookScript("OnShow", syncSwatches)
	syncSwatches()
end

local pages = {}
local window

local function visibleOptions()
	local list = {}
	for _, o in ipairs(OPTIONS) do
		if not o.shown or o.shown() then list[#list + 1] = o end
	end
	return list
end

local function sync(page)
	for o, box in pairs(page.boxes) do box:SetChecked(o.option.get() and true or false) end
end

local function syncVisible()
	for _, page in ipairs(pages) do
		if page:IsVisible() then sync(page) end
	end
end

local function buildPage(container, x, y)
	container.boxes = {}
	local options = visibleOptions()
	for i, o in ipairs(options) do
		local box = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
		box:SetPoint("TOPLEFT", x, y - (i - 1) * ROW_SPACING)
		box.Text:SetText(o.label)
		box.Text:SetFontObject("GameFontHighlight")
		box:SetScript("OnClick", function(self)
			o.option.set(self:GetChecked() and true or false)
			if o.after then o.after() end
			syncVisible()
		end)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(o.label, 1, 1, 1)
			GameTooltip:AddLine(o.help, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		container.boxes[o] = box
	end
	local colorsY = y - #options * ROW_SPACING - 12
	buildColors(container, x + 6, colorsY, LISTS_WIDTH)
	ns.BuildLists(container, x + 6, colorsY - COLORS_HEIGHT, LISTS_WIDTH)
	container:HookScript("OnShow", sync)
	pages[#pages + 1] = container
end

-- Blizzard's standard window style (portrait, title bar, inset).
local function createWindow()
	window = CreateFrame("Frame", "AutoVendorSettings", UIParent, "ButtonFrameTemplate")
	window:SetSize(WIDTH, 120 + #visibleOptions() * ROW_SPACING + COLORS_HEIGHT + ns.LISTS_HEIGHT)
	window:SetTitle("AutoVendor")
	window:SetPortraitToAsset(ICON)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	table.insert(UISpecialFrames, "AutoVendorSettings") -- Escape closes it
	window:Hide()
	local page = CreateFrame("Frame", nil, window.Inset)
	page:SetAllPoints()
	buildPage(page, 8, -8)
	local version = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", 12, 8)
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	version:SetText("AutoVendor " .. (getMeta and getMeta("AutoVendor", "Version") or ""))
end

function ns.ShowSettings()
	if not AutoVendorDB then return end
	if not window then createWindow() end
	window:SetShown(not window:IsShown())
end

-- The page in Blizzard's Options > AddOns. Blizzard sizes and shows the canvas.
local function registerBlizzardPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local canvas = CreateFrame("Frame", nil, UIParent)
	canvas:Hide()
	local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("AutoVendor")
	buildPage(canvas, 12, -52)
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(canvas, "AutoVendor"))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", registerBlizzardPage)
