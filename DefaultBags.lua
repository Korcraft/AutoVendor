-- DefaultBags: the same markers and clicks as in Baganator, but for the
-- game's own bag windows, plus tooltip lines that show up in any bag UI that
-- uses the standard bag tooltip.
-- What each marker means is listed at the top of Markers.lua.

local _, ns = ...

-- ---------------------------------------------------------------------------
-- Finding the default bag buttons
-- ---------------------------------------------------------------------------

local function containerFrames()
	local frames = {}
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f then frames[#frames + 1] = f end
	end
	-- Newer clients can show all bags in one combined window.
	if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
	return frames
end

local function eachButton(frame, fn)
	if type(frame.Items) == "table" then -- newer clients keep a list
		for _, button in ipairs(frame.Items) do fn(button) end
		return
	end
	local name = frame:GetName() -- older clients name them ContainerFrameNItemM
	if not name then return end
	local i = 1
	while _G[name .. "Item" .. i] do
		fn(_G[name .. "Item" .. i])
		i = i + 1
	end
end

local function slotOf(button)
	local bag
	if button.GetBagID then
		bag = button:GetBagID()
	elseif button:GetParent() then
		bag = button:GetParent():GetID()
	end
	return bag, button:GetID()
end

-- ---------------------------------------------------------------------------
-- Markers
-- ---------------------------------------------------------------------------

local function setShown(frame, shown)
	if shown then frame:Show() else frame:Hide() end
end

local function onClick(self, mouseButton)
	if not IsAltKeyDown() then return end
	local bag, slot = slotOf(self)
	if not bag then return end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info then ns.HandleItemClick(mouseButton, info.itemID, info.hyperlink, bag, slot) end
end

-- Built the first time we see a button: markers (dotted outline and glow -- see
-- Markers.lua) plus the click hook.
local function setUp(button)
	local m = {
		protectOnce = ns.CreateProtectMarker(button, button, false),
		whitelist = ns.CreateProtectMarker(button, button, true),
		sellOnce = ns.CreateSellMarker(button, button, false),
		blacklist = ns.CreateSellMarker(button, button, true),
		bankOnce = ns.CreateBankMarker(button, button, false),
		bankList = ns.CreateBankMarker(button, button, true),
	}
	m.protectOnce:Hide()
	m.whitelist:Hide()
	m.sellOnce:Hide()
	m.blacklist:Hide()
	m.bankOnce:Hide()
	m.bankList:Hide()

	m.suggest = ns.CreateOutline(button, button, "suggest")
	m.suggest:Hide()

	button.AutoVendorMarkers = m
	button:HookScript("OnClick", onClick)
	return m
end

local function updateButton(button)
	local m = button.AutoVendorMarkers or setUp(button)
	local mark, suggested = nil, false
	if button:IsShown() then
		local bag, slot = slotOf(button)
		local info = bag and C_Container.GetContainerItemInfo(bag, slot)
		if info and info.itemID then
			mark = ns.MarkOf(info.itemID, bag, slot)
			local s = ns.GetDeleteSuggestion and ns.GetDeleteSuggestion()
			suggested = s ~= nil and s.bag == bag and s.slot == slot
		end
	end
	for _, kind in ipairs({ "protectOnce", "whitelist", "sellOnce", "blacklist", "bankOnce", "bankList" }) do
		setShown(m[kind], mark == kind)
	end
	setShown(m.suggest, suggested)
end

function ns.RefreshDefaultBags()
	for _, frame in ipairs(containerFrames()) do
		if frame:IsShown() then eachButton(frame, updateButton) end
	end
end

-- Runs one frame later, after the game has finished redrawing its bags.
local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0, function()
		pending = false
		ns.RefreshDefaultBags()
	end)
end

-- ---------------------------------------------------------------------------
-- Tooltip lines (default bags, Baganator and most other bag addons)
-- ---------------------------------------------------------------------------

local function addTooltipLines(tooltip, bag, slot)
	if not (bag and slot) then return end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not (info and info.itemID) then return end
	local added = false
	local mark = ns.MarkOf(info.itemID, bag, slot)
	local text = ({
		whitelist = "AutoVendor: whitelist - never sold",
		protectOnce = "AutoVendor: protected (this stack)",
		blacklist = "AutoVendor: blacklist - always sold",
		sellOnce = "AutoVendor: will be sold (this stack)",
		bankList = "AutoVendor: bank list - always banked",
		bankOnce = "AutoVendor: goes in the bank (this stack)",
	})[mark]
	if text then
		local c = ns.MarkerColor(mark)
		tooltip:AddLine(text, c[1], c[2], c[3])
		added = true
	end
	local s = ns.GetDeleteSuggestion and ns.GetDeleteSuggestion()
	if s and s.bag == bag and s.slot == slot then
		tooltip:AddLine("AutoVendor: least valuable item - suggested to delete", unpack(ns.MarkerColor("suggest")))
		added = true
	end
	if added then tooltip:Show() end
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		for _, frame in ipairs(containerFrames()) do
			frame:HookScript("OnShow", refreshSoon)
		end
		if type(ContainerFrame_Update) == "function" then
			hooksecurefunc("ContainerFrame_Update", refreshSoon)
		end
		if GameTooltip and GameTooltip.SetBagItem then
			hooksecurefunc(GameTooltip, "SetBagItem", addTooltipLines)
		end
	end
	refreshSoon()
end)
