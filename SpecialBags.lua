-- SpecialBags: when your normal bags are full, moves anything that belongs in
-- a special bag (ammo into a quiver or ammo pouch, leather into a
-- leatherworking bag, herbs into an herb bag, soul shards into a soul bag...)
-- into a free slot there. That frees normal slots without deleting anything.
--
-- Only moves into EMPTY special-bag slots; it never drops onto a partial
-- stack, where the leftover could end up stuck on your cursor.

local _, ns = ...

local FIRST_BAG, LAST_BAG = 0, 4

local IC = Enum and Enum.ItemClass or {}
local CLASS_CONTAINER = IC.Container or 1
local CLASS_QUIVER = IC.Quiver or 11

local getItemFamily = (C_Item and C_Item.GetItemFamily) or _G.GetItemFamily
local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local band = bit and bit.band

local function enabled()
	return AutoVendorDB and AutoVendorDB.settings and AutoVendorDB.settings.moveToSpecialBags ~= false
end

-- ---------------------------------------------------------------------------
-- Combining partial stacks
-- ---------------------------------------------------------------------------

local getItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function mergeEnabled()
	return AutoVendorDB and AutoVendorDB.settings and AutoVendorDB.settings.mergeStacks ~= false
end

-- Merges a stack in your normal bags into another partial stack of the same
-- item (in any bag, so a quiver's partial stack of arrows counts too), but
-- only when the whole stack fits -- otherwise no slot is freed. Uses an exact
-- split so nothing is ever left on the cursor. One move per item per call;
-- the bag update that follows calls this again if still full. Returns how
-- many stacks it merged.
function ns.MergeStacks()
	if not mergeEnabled() or GetCursorInfo() then return 0 end

	local byItem = {}
	for bag = FIRST_BAG, LAST_BAG do
		local ordinary = bag == 0 or select(2, C_Container.GetContainerNumFreeSlots(bag)) == 0
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isLocked then
				local maxStack = select(8, getItemInfo(info.itemID))
				local count = info.stackCount or 1
				if maxStack and maxStack > 1 and count < maxStack then
					local list = byItem[info.itemID] or {}
					list[#list + 1] = { bag = bag, slot = slot, count = count, room = maxStack - count,
						ordinary = ordinary, link = info.hyperlink }
					byItem[info.itemID] = list
				end
			end
		end
	end

	local merged, names = 0, {}
	for _, stacks in pairs(byItem) do
		if #stacks >= 2 then
			-- Smallest normal-bag stack goes into the stack with the most room.
			table.sort(stacks, function(a, b) return a.count < b.count end)
			local src
			for _, s in ipairs(stacks) do
				if s.ordinary then src = s; break end
			end
			local dest
			for _, d in ipairs(stacks) do
				if d ~= src and d.room >= (src and src.count or math.huge)
					and (not dest or d.room > dest.room) then
					dest = d
				end
			end
			if src and dest then
				C_Container.SplitContainerItem(src.bag, src.slot, src.count)
				C_Container.PickupContainerItem(dest.bag, dest.slot)
				if GetCursorInfo() then ClearCursor() end -- didn't take: put it back
				merged = merged + 1
				names[#names + 1] = src.link or "an item"
			end
		end
	end

	if merged > 0 then
		print(ns.PREFIX .. "Bags full - combined stacks of " .. table.concat(names, ", ") .. ".")
	end
	return merged
end

-- ---------------------------------------------------------------------------
-- Moving into special bags
-- ---------------------------------------------------------------------------

-- Free slots in each special bag, as { bag = , family = , slots = {..} }.
local function specialBagsWithRoom()
	local list = {}
	for bag = 1, LAST_BAG do
		local free, family = C_Container.GetContainerNumFreeSlots(bag)
		if family and family ~= 0 and free and free > 0 then
			local slots = {}
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				if not C_Container.GetContainerItemInfo(bag, slot) then slots[#slots + 1] = slot end
			end
			if #slots > 0 then list[#list + 1] = { bag = bag, family = family, slots = slots } end
		end
	end
	return list
end

local function isOrdinaryBag(bag)
	if bag == 0 then return true end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	return family == 0
end

-- Moves every item it can from the normal bags into special bags. Returns
-- how many stacks it moved.
function ns.MoveToSpecialBags()
	if not (enabled() and getItemFamily and band) then return 0 end
	if GetCursorInfo() then return 0 end -- don't disturb whatever you're holding

	local targets = specialBagsWithRoom()
	if #targets == 0 then return 0 end

	local moved, names = 0, {}
	for bag = FIRST_BAG, LAST_BAG do
		if isOrdinaryBag(bag) then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID and not info.isLocked then
					local _, _, _, _, _, classID = getItemInfoInstant(info.itemID)
					-- Bags and quivers carry their own family; never move those.
					local family = (classID ~= CLASS_CONTAINER and classID ~= CLASS_QUIVER)
						and getItemFamily(info.itemID) or 0
					if family and family ~= 0 then
						for _, t in ipairs(targets) do
							if #t.slots > 0 and band(family, t.family) ~= 0 then
								local destSlot = table.remove(t.slots, 1)
								C_Container.PickupContainerItem(bag, slot)
								C_Container.PickupContainerItem(t.bag, destSlot)
								-- If the drop didn't take, put it back where it was.
								if GetCursorInfo() then ClearCursor() end
								moved = moved + 1
								names[#names + 1] = (info.hyperlink or ("item " .. info.itemID))
									.. ((info.stackCount or 1) > 1 and (" x" .. info.stackCount) or "")
								break
							end
						end
					end
				end
			end
		end
	end

	if moved > 0 then
		print(ns.PREFIX .. "Bags full - moved " .. table.concat(names, ", ") .. " into your special bags.")
	end
	return moved
end

-- Called when the normal bags are full: combine stacks first, and only if
-- that frees nothing, move things into special bags. Returns how many moves
-- it started.
function ns.FreeUpSpace()
	local merged = ns.MergeStacks()
	if merged > 0 then return merged end
	return ns.MoveToSpecialBags()
end
