-- Settings: the same page of switches in two places, built by one function:
--   * its own movable window (/av). Closing it just closes it; it never goes
--     through Blizzard's settings panel, whose close reopens the game menu.
--   * Blizzard's Options > AddOns > AutoVendor.
-- Each page re-reads the settings when shown and after any change, so the two
-- never disagree. Layout idea borrowed from Shady Business (MIT).

local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local ROW_SPACING = 30
local WIDTH = 640
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
			.. "(gold coin, that stack only), along with the grays when you open a vendor, whatever its quality." },
	{ label = "Put bank-listed items in the bank", option = setting("bankMarked"),
		help = "When you open your bank, moves everything on your bank list (Shift+Alt+left-click) and every "
			.. "stack you marked with Shift+Alt+right-click (that stack only) into the bank. "
			.. "Bank-marked items are never sold or suggested for deletion." },
	{ label = "Repair gear at vendors", option = setting("repair"),
		help = "Repairs all your gear with your own gold (never guild funds) when the vendor can repair." },
	{ label = "Suggest what to delete (from the slider below)", option = setting("bagSpace"),
		help = "Names the least valuable item when your bags fill up, and outlines it in pink. Never deletes anything.",
		after = function() if ns.RescanBagSpace then ns.RescanBagSpace() end end },
	{ label = "Suggest deletes and tidy stacks from:", option = setting("suggestAt"),
		help = "How full your normal bags must be (quivers and profession bags don't count) before AutoVendor "
			.. "outlines the cheapest item in pink and shows the Delete button (while your bags are open), and "
			.. "starts combining stacks and moving things into special bags. All the way left = always; all the "
			.. "way right = only when full. Tidying waits until you've stopped moving things, never runs while "
			.. "a vendor, bank, trade or mail window is open or in combat, and leaves alone any item you split "
			.. "by hand in the last 2 minutes.",
		slider = {
			min = 0, max = 100, step = 10, leftText = "Always", rightText = "Only when full",
			describe = function(v)
				if v <= 0 then return "Always" elseif v >= 100 then return "Only when full" end
				return v .. "% full"
			end,
		},
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
	{ label = "Combine partial stacks (from the slider above)", option = setting("mergeStacks"),
		help = "Once your normal bags are as full as the slider says, merges partial stacks of the same item (including into a "
			.. "partial stack in your quiver or a profession bag) when that frees a slot." },
	{ label = "Move items into special bags (from the slider above)", option = setting("moveToSpecialBags"),
		help = "Once your normal bags are as full as the slider says, moves ammo into your quiver or ammo pouch, leather into a "
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

local COLORS_HEIGHT = 120 -- header + three rows of swatches
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
	local cell = #ns.MARKER_COLORS -- the first free cell after the swatches
	reset:SetPoint("TOPLEFT", x + (cell % 3) * columnWidth, y - 22 - math.floor(cell / 3) * 28 - 1)
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
	for _, s in ipairs(page.sliders) do s() end
end

local function syncVisible()
	for _, page in ipairs(pages) do
		if page:IsVisible() then sync(page) end
	end
end

-- Rows an option takes on the page: a slider (label + bar) takes two.
local function rowsOf(o) return o.slider and 2 or 1 end
local function totalRows()
	local n = 0
	for _, o in ipairs(visibleOptions()) do n = n + rowsOf(o) end
	return n
end

local function addTooltip(frame, o)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(o.label, 1, 1, 1)
		GameTooltip:AddLine(o.help, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A plain slider (no template: template availability varies between clients).
local function buildSlider(container, o, x, y, width)
	local spec = o.slider
	local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", x + 6, y - 4)
	label:SetText(o.label)
	local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	valueText:SetPoint("TOPRIGHT", container, "TOPLEFT", x + width, y - 4)

	local slider = CreateFrame("Slider", nil, container)
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("TOPLEFT", x + 10, y - 26)
	slider:SetSize(width - 14, 16)
	slider:SetMinMaxValues(spec.min, spec.max)
	slider:SetValueStep(spec.step)
	slider:SetObeyStepOnDrag(true)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:EnableMouseWheel(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.4, 0.4, 0.4, 0.9)
	local left = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	left:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
	left:SetText(spec.leftText)
	local right = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	right:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
	right:SetText(spec.rightText)

	local syncing = false
	local function syncSlider()
		local value = o.option.get()
		syncing = true
		slider:SetValue(value)
		syncing = false
		valueText:SetText(spec.describe(value))
	end
	slider:SetScript("OnValueChanged", function(_, value)
		if syncing then return end
		value = math.floor(value / spec.step + 0.5) * spec.step
		if value == o.option.get() then return end
		o.option.set(value)
		valueText:SetText(spec.describe(value))
		if o.after then o.after() end
	end)
	slider:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(self:GetValue() + delta * spec.step)
	end)
	addTooltip(slider, o)
	container.sliders[#container.sliders + 1] = syncSlider
end

local function buildPage(container, x, y)
	container.boxes = {}
	container.sliders = {}
	local row = 0
	for _, o in ipairs(visibleOptions()) do
		local rowY = y - row * ROW_SPACING
		if o.slider then
			buildSlider(container, o, x, rowY, LISTS_WIDTH + 6)
		else
			local box = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
			box:SetPoint("TOPLEFT", x, rowY)
			box.Text:SetText(o.label)
			box.Text:SetFontObject("GameFontHighlight")
			box:SetScript("OnClick", function(self)
				o.option.set(self:GetChecked() and true or false)
				if o.after then o.after() end
				syncVisible()
			end)
			addTooltip(box, o)
			container.boxes[o] = box
		end
		row = row + rowsOf(o)
	end
	local colorsY = y - row * ROW_SPACING - 12
	buildColors(container, x + 6, colorsY, LISTS_WIDTH)
	ns.BuildLists(container, x + 6, colorsY - COLORS_HEIGHT, LISTS_WIDTH)
	container:HookScript("OnShow", sync)
	pages[#pages + 1] = container
end

-- Blizzard's standard window style (portrait, title bar, inset).
local function createWindow()
	window = CreateFrame("Frame", "AutoVendorSettings", UIParent, "ButtonFrameTemplate")
	window:SetSize(WIDTH, 120 + totalRows() * ROW_SPACING + COLORS_HEIGHT + ns.LISTS_HEIGHT)
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
