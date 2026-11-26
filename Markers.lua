-- Markers: the look shared by every AutoVendor marker on a bag slot -- an
-- outline (dotted = one-time, solid = permanent list) plus a soft, steady
-- glow, and the corner icons. Used by the default bags (DefaultBags.lua) and
-- Baganator (AutoVendor.lua, BagSpace.lua).
--   protect once (Alt+right-click)       red dotted outline + X
--   whitelist   (Ctrl+Alt+right-click)   red solid outline + X
--   sell once   (Alt+left-click)         gold coin
--   blacklist   (Ctrl+Alt+left-click)    gold coin + gold solid outline
--   delete suggestion                    hot pink dotted outline

local _, ns = ...

local DASH, GAP, THICKNESS = 4, 3, 2
local GLOW_SCALE = 1.75 -- the glow texture's bright ring sits well inside its edges

-- Lays dashes along one edge of `box`, reusing textures from `pool`. A solid
-- edge is one dash the whole length.
local function layoutEdge(box, pool, used, color, horizontal, length, anchor, solid)
	local dash = solid and length or DASH
	local count = solid and 1 or math.max(1, math.floor((length + GAP) / (DASH + GAP)))
	local span = count * dash + (count - 1) * GAP
	local start = math.floor((length - span) / 2)
	for i = 0, count - 1 do
		used = used + 1
		local t = pool[used]
		if not t then
			t = box:CreateTexture(nil, "OVERLAY", nil, 7)
			pool[used] = t
		end
		t:SetColorTexture(color[1], color[2], color[3], 1)
		t:ClearAllPoints()
		local offset = start + i * (dash + GAP)
		if horizontal then
			t:SetSize(dash, THICKNESS)
			t:SetPoint(anchor, box, anchor, offset, 0)
		else
			t:SetSize(THICKNESS, dash)
			t:SetPoint(anchor, box, anchor, 0, -offset)
		end
		t:Show()
	end
	return used
end

-- Returns a frame (show/hide it as a whole) holding an outline around
-- `anchorTo` and a glow behind it: dotted for one-time marks and the delete
-- suggestion, solid (`solid` = true) for the permanent lists. `parent` owns
-- it, so if a parent is hidden (e.g. a Baganator corner widget), the marker
-- hides with it.
function ns.CreateOutline(parent, anchorTo, color, solid)
	local box = CreateFrame("Frame", nil, parent)
	box:SetAllPoints(anchorTo)
	box:SetFrameLevel(anchorTo:GetFrameLevel() + 2)

	local glow = box:CreateTexture(nil, "OVERLAY", nil, 6)
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(color[1], color[2], color[3], 0.9)
	glow:SetPoint("CENTER", box, "CENTER")

	local pool = {}
	local function layout()
		local w, h = box:GetSize()
		if not w or w <= 0 or not h or h <= 0 then return end
		glow:SetSize(w * GLOW_SCALE, h * GLOW_SCALE)
		local used = 0
		used = layoutEdge(box, pool, used, color, true, w, "TOPLEFT", solid)
		used = layoutEdge(box, pool, used, color, true, w, "BOTTOMLEFT", solid)
		used = layoutEdge(box, pool, used, color, false, h, "TOPLEFT", solid)
		used = layoutEdge(box, pool, used, color, false, h, "TOPRIGHT", solid)
		for i = used + 1, #pool do pool[i]:Hide() end
	end
	box:SetScript("OnSizeChanged", layout)
	layout()

	return box
end

local RED = { 0.9, 0.1, 0.1 }
local GOLD = { 1, 0.82, 0 }

-- Both corner markers return the small corner frame (which Baganator places
-- as a corner widget); the outline hangs off it but covers the whole slot.

-- Protect marker: an X in the corner plus a red outline (solid = whitelist).
function ns.CreateProtectMarker(parent, anchorTo, solid)
	local xFrame = CreateFrame("Frame", nil, parent)
	xFrame:SetSize(16, 16)
	xFrame:SetPoint("TOPLEFT", anchorTo, "TOPLEFT")
	xFrame:SetFrameLevel(anchorTo:GetFrameLevel() + 3)
	local x = xFrame:CreateTexture(nil, "OVERLAY", nil, 7)
	x:SetAllPoints()
	x:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	ns.CreateOutline(xFrame, anchorTo, RED, solid)
	return xFrame
end

-- Sell marker: a gold coin in the corner, plus a solid gold outline for the
-- blacklist.
function ns.CreateSellMarker(parent, anchorTo, solid)
	local coinFrame = CreateFrame("Frame", nil, parent)
	coinFrame:SetSize(14, 14)
	coinFrame:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 1, -1)
	coinFrame:SetFrameLevel(anchorTo:GetFrameLevel() + 3)
	local coin = coinFrame:CreateTexture(nil, "OVERLAY", nil, 7)
	coin:SetAllPoints()
	coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	if solid then ns.CreateOutline(coinFrame, anchorTo, GOLD, true) end
	return coinFrame
end
