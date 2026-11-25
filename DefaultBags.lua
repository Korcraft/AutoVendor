-- DefaultBags: the same markers and clicks as in Baganator, but for the
-- game's own bag windows, plus tooltip lines that show up in any bag UI that
-- uses the standard bag tooltip.
--   red outline + X   = protected (Alt+right-click)
--   gold coin         = marked to sell (Alt+left-click)
--   hot pink outline  = suggested to delete while your bags are full

local _, ns = ...

local THICKNESS = 2
local RED = { 0.9, 0.1, 0.1 }
local GOLD = { 1, 0.82, 0 }
local PINK = { 1, 0.2, 0.6 } -- no item quality or quest border uses pink

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

local function makeOutline(button, color)
	local edges = {}
	for i = 1, 4 do
		local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(color[1], color[2], color[3], 1)
		t:Hide()
		edges[i] = t
	end
	local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(THICKNESS)
	bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(THICKNESS)
	left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(THICKNESS)
	right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(THICKNESS)
	return edges
end

local function showAll(textures, shown)
	for _, t in ipairs(textures) do
		if shown then t:Show() else t:Hide() end
	end
end

local function onClick(self, mouseButton)
	if not IsAltKeyDown() then return end
	local bag, slot = slotOf(self)
	if not bag then return end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info then ns.HandleItemClick(mouseButton, info.itemID, info.hyperlink) end
end

-- Built the first time we see a button: markers plus the click hook.
local function setUp(button)
	local m = {}
	m.protectOutline = makeOutline(button, RED)
	local x = button:CreateTexture(nil, "OVERLAY", nil, 7)
	x:SetSize(16, 16)
	x:SetPoint("TOPLEFT")
	x:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	x:Hide()
	m.protectX = x
	local coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
	coin:SetSize(14, 14)
	coin:SetPoint("TOPLEFT", 1, -1)
	coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	coin:Hide()
	m.sellCoin = coin
	m.suggestOutline = makeOutline(button, PINK)
	button.AutoVendorMarkers = m
	button:HookScript("OnClick", onClick)
	return m
end

local function updateButton(button)
	local m = button.AutoVendorMarkers or setUp(button)
	local protected, marked, suggested = false, false, false
	if button:IsShown() then
		local bag, slot = slotOf(button)
		local info = bag and C_Container.GetContainerItemInfo(bag, slot)
		if info and info.itemID then
			protected = ns.isProtected(info.itemID)
			marked = ns.isMarkedToSell(info.itemID)
			local s = ns.GetDeleteSuggestion and ns.GetDeleteSuggestion()
			suggested = s ~= nil and s.bag == bag and s.slot == slot
		end
	end
	showAll(m.protectOutline, protected)
	if protected then m.protectX:Show() else m.protectX:Hide() end
	if marked then m.sellCoin:Show() else m.sellCoin:Hide() end
	showAll(m.suggestOutline, suggested)
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
	if ns.isProtected(info.itemID) then
		tooltip:AddLine("AutoVendor: protected", RED[1], RED[2], RED[3])
		added = true
	elseif ns.isMarkedToSell(info.itemID) then
		tooltip:AddLine("AutoVendor: marked to sell", GOLD[1], GOLD[2], GOLD[3])
		added = true
	end
	local s = ns.GetDeleteSuggestion and ns.GetDeleteSuggestion()
	if s and s.bag == bag and s.slot == slot then
		tooltip:AddLine("AutoVendor: least valuable item - suggested to delete", PINK[1], PINK[2], PINK[3])
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
