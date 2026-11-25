-- Markers: the look shared by every AutoVendor marker on a bag slot -- a
-- dotted outline plus a soft glow, both slowly pulsing. Used by the default
-- bags (DefaultBags.lua) and Baganator (AutoVendor.lua, BagSpace.lua).

local _, ns = ...

local DASH, GAP, THICKNESS = 4, 3, 2
local GLOW_SCALE = 1.75 -- the glow texture's bright ring sits well inside its edges
local PULSE_LOW, PULSE_TIME = 0.35, 0.8

-- Fades `frame` between full and PULSE_LOW alpha, forever, while it's shown.
function ns.AddPulse(frame)
	local group = frame:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(PULSE_LOW)
	fade:SetDuration(PULSE_TIME)
	fade:SetSmoothing("IN_OUT")
	frame:HookScript("OnShow", function() group:Play() end)
	frame:HookScript("OnHide", function() group:Stop() end)
	if frame:IsVisible() then group:Play() end
	return group
end

-- Lays dashes along one edge of `box`, reusing textures from `pool`.
local function layoutEdge(box, pool, used, color, horizontal, length, anchor)
	local count = math.max(1, math.floor((length + GAP) / (DASH + GAP)))
	local span = count * DASH + (count - 1) * GAP
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
		local offset = start + i * (DASH + GAP)
		if horizontal then
			t:SetSize(DASH, THICKNESS)
			t:SetPoint(anchor, box, anchor, offset, 0)
		else
			t:SetSize(THICKNESS, DASH)
			t:SetPoint(anchor, box, anchor, 0, -offset)
		end
		t:Show()
	end
	return used
end

-- Returns a frame (show/hide it as a whole) holding a dotted outline around
-- `anchorTo` and a glow behind it, pulsing. `parent` owns it, so if a parent
-- is hidden (e.g. a Baganator corner widget), the marker hides with it.
function ns.CreateOutline(parent, anchorTo, color)
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
		used = layoutEdge(box, pool, used, color, true, w, "TOPLEFT")
		used = layoutEdge(box, pool, used, color, true, w, "BOTTOMLEFT")
		used = layoutEdge(box, pool, used, color, false, h, "TOPLEFT")
		used = layoutEdge(box, pool, used, color, false, h, "TOPRIGHT")
		for i = used + 1, #pool do pool[i]:Hide() end
	end
	box:SetScript("OnSizeChanged", layout)
	layout()

	ns.AddPulse(box)
	return box
end
