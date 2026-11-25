-- Settings: the same page of switches in two places, built by one function:
--   * its own movable window (/av). Closing it just closes it; it never goes
--     through Blizzard's settings panel, whose close reopens the game menu.
--   * Blizzard's Options > AddOns > AutoVendor.
-- Each page re-reads the settings when shown and after any change, so the two
-- never disagree. Layout idea borrowed from Shady Business (MIT).

local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local ROW_SPACING = 30
local WIDTH = 340

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
		help = "Sells every gray item when you open a vendor. Protected items (Alt+right-click) are never sold." },
	{ label = "Sell items I marked (Alt+left-click)", option = setting("sellMarked"),
		help = "Alt+left-click an item in your bags to mark it to sell (gold coin). Marked items are sold "
			.. "along with the grays when you open a vendor." },
	{ label = "Repair gear at vendors", option = setting("repair"),
		help = "Repairs all your gear with your own gold (never guild funds) when the vendor can repair." },
	{ label = "Suggest what to delete when bags are full", option = setting("bagSpace"),
		help = "Names the least valuable item when your bags fill up, and outlines it in pink. Never deletes anything.",
		after = function() if ns.RescanBagSpace then ns.RescanBagSpace() end end },
	{ label = "Buy back protected items sold by mistake", option = setting("guardSales"),
		help = "If you sell a protected item to a vendor by hand, it's bought straight back. "
			.. "Unprotect it first (Alt+right-click) to sell it on purpose." },
	{ label = "Take protected items out of trades", option = setting("guardTrades"),
		help = "If you put a protected item in the trade window, it's taken straight back out. "
			.. "Unprotect it first (Alt+right-click) to trade it on purpose." },
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
	for i, o in ipairs(visibleOptions()) do
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
	container:HookScript("OnShow", sync)
	pages[#pages + 1] = container
end

-- Blizzard's standard window style (portrait, title bar, inset).
local function createWindow()
	window = CreateFrame("Frame", "AutoVendorSettings", UIParent, "ButtonFrameTemplate")
	window:SetSize(WIDTH, 110 + #visibleOptions() * ROW_SPACING)
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
