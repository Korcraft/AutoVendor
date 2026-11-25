-- Conflicts: points out, once per addon, other loaded addons that do the same
-- job. They don't know about AutoVendor's protected items, so an auto-seller
-- can sell something you protected. Never disables anything itself.

local _, ns = ...

-- Addon folder name -> what overlaps.
local OVERLAPPING = {
	Scrap = "auto-sells junk",
	Peddler = "auto-sells items",
	Dejunk = "auto-sells junk",
	Vendomatic = "auto-sells junk and repairs",
	AutoSell = "auto-sells junk",
	BetterVendorPrice = "suggests what to delete when your bags are full",
}

local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	if not (isLoaded and AutoVendorDB) then return end
	AutoVendorDB.conflictsNoted = AutoVendorDB.conflictsNoted or {}
	for name, what in pairs(OVERLAPPING) do
		if isLoaded(name) and not AutoVendorDB.conflictsNoted[name] then
			AutoVendorDB.conflictsNoted[name] = true
			print(ns.PREFIX .. name .. " also " .. what .. ". It doesn't know about "
				.. "AutoVendor's protected items, so you may want to turn that part of it off. "
				.. "(You won't see this again.)")
		end
	end
end)
