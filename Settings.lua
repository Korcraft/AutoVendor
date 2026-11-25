-- Settings: a small window of on/off switches, opened with /av or from WoW's
-- AddOns options. Built from plain widgets, like Huntard's settings window,
-- because template availability varies between clients.

local _, ns = ...

local WIDTH, PAD = 360, 20

local frame
local syncers = {}

local function syncAll()
	for _, sync in ipairs(syncers) do sync() end
end

local function makeCheckbox(parent, y, text, get, set)
	local check = CreateFrame("CheckButton", nil, parent)
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", PAD, y)
	check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

	local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	label:SetText(text)
	check:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0)

	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		syncAll()
	end)
	table.insert(syncers, function() check:SetChecked(get() and true or false) end)
end

-- Huntard owns ammo buying; this switch just flips Huntard's own setting.
local function huntardAmmo()
	local H = _G.Huntard
	return H and H.db and H.db.ammoRestock
end

local function buildWindow()
	frame = CreateFrame("Frame", "AutoVendorSettingsFrame", UIParent)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	table.insert(UISpecialFrames, "AutoVendorSettingsFrame") -- Esc closes it

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("AutoVendor Settings")

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(26, 22)
	close:SetPoint("TOPRIGHT", -8, -8)
	close:SetText("X")
	close:SetScript("OnClick", function() frame:Hide() end)

	local s = AutoVendorDB.settings
	local y = -50
	makeCheckbox(frame, y, "Sell gray items at vendors",
		function() return s.sellGrays end,
		function(on) s.sellGrays = on end)
	y = y - 30
	makeCheckbox(frame, y, "Repair gear at vendors",
		function() return s.repair end,
		function(on) s.repair = on end)
	y = y - 30
	makeCheckbox(frame, y, "Suggest what to delete when bags are full",
		function() return s.bagSpace end,
		function(on)
			s.bagSpace = on
			if ns.RescanBagSpace then ns.RescanBagSpace() end
		end)
	y = y - 30
	if huntardAmmo() then
		makeCheckbox(frame, y, "Buy ammo at vendors (Huntard)",
			function() return huntardAmmo().enabled end,
			function(on) huntardAmmo().enabled = on end)
		y = y - 30
	end

	frame:SetSize(WIDTH, -y + 20)
	frame:SetScript("OnShow", syncAll)
end

function ns.ShowSettings()
	if not AutoVendorDB then return end
	if not frame then buildWindow() end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- An AutoVendor entry in WoW's AddOns options with a button to open the window.
local function registerOptionsPanel()
	local panel = CreateFrame("Frame")
	panel.name = "AutoVendor"

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("AutoVendor")

	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(200, 26)
	open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	open:SetText("Open AutoVendor Settings")
	open:SetScript("OnClick", function()
		if _G.SettingsPanel and _G.SettingsPanel:IsShown() then
			pcall(HideUIPanel, _G.SettingsPanel)
		end
		if not (frame and frame:IsShown()) then ns.ShowSettings() end
	end)

	if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
		pcall(function()
			local category = _G.Settings.RegisterCanvasLayoutCategory(panel, "AutoVendor")
			_G.Settings.RegisterAddOnCategory(category)
		end)
	elseif _G.InterfaceOptions_AddCategory then
		pcall(_G.InterfaceOptions_AddCategory, panel)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", registerOptionsPanel)
