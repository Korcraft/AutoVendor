-- SpecialBags: the moment your normal bags fill up, tidies them to free as
-- many slots as possible, without deleting anything:
--   1. combines partial stacks of the same item (also into a partial stack in
--      a quiver or profession bag), and
--   2. moves anything that belongs in a special bag (ammo into a quiver or
--      ammo pouch, leather into a leatherworking bag, herbs into an herb bag,
--      soul shards into a soul bag...) into a free slot there.
-- It repeats both until neither finds anything more to do, then reports it
-- all in one chat line. Moves into special bags go to EMPTY slots only.

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

-- Combines partial stacks of the same item until each item is in as few
-- stacks as possible (five single potions in five slots end up as one stack
-- of five). Each move takes the smallest partial stack in your normal bags
-- and tops up another partial stack -- one in a special bag first (so loose
-- arrows go into the quiver's stack), otherwise the fullest one. Every move
-- either empties the source slot or fills the target, so it always finishes.
-- Uses an exact split so nothing is ever left on the cursor. One move per
-- item per call (moved stacks stay locked until the server confirms); the
-- tidy loop calls it again. Adds what it combined to `names`; returns the
-- number of moves.
local function mergeStacks(names, tried)
	if not mergeEnabled() then return 0 end

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

	local merged = 0
	for _, stacks in pairs(byItem) do
		if #stacks >= 2 then
			table.sort(stacks, function(a, b) return a.count < b.count end)
			local src
			for _, s in ipairs(stacks) do
				if s.ordinary then src = s; break end
			end
			local dest
			if src then
				for _, d in ipairs(stacks) do
					if d ~= src then
						local better = not dest
							or (not d.ordinary and dest.ordinary)
							or (d.ordinary == dest.ordinary and d.count > dest.count)
						if better then dest = d end
					end
				end
			end
			local key = src and dest and (src.bag .. ":" .. src.slot .. ">" .. dest.bag .. ":" .. dest.slot
				.. ":" .. src.count .. ":" .. dest.count)
			if key and not tried[key] then
				tried[key] = true
				C_Container.SplitContainerItem(src.bag, src.slot, math.min(src.count, dest.room))
				C_Container.PickupContainerItem(dest.bag, dest.slot)
				if GetCursorInfo() then ClearCursor() end -- didn't take: put it back
				merged = merged + 1
				local name = src.link or "an item"
				if not tContains(names, name) then names[#names + 1] = name end
			end
		end
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

-- Moves every item it can from the normal bags into empty special-bag slots.
-- Adds what it moved to `names`; returns the count.
local function moveToSpecialBags(names, tried)
	if not (enabled() and getItemFamily and band) then return 0 end

	local targets = specialBagsWithRoom()
	if #targets == 0 then return 0 end

	local moved = 0
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
							if #t.slots > 0 and band(family, t.family) ~= 0 and not tried[bag .. ":" .. slot] then
								tried[bag .. ":" .. slot] = true
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

	return moved
end

-- ---------------------------------------------------------------------------
-- The tidy loop
-- ---------------------------------------------------------------------------

local MAX_PASSES = 40
local FALLBACK_DELAY = 1.5 -- next pass if no bag update arrives (a move that didn't take)

local tidy -- nil when idle

local function finish()
	local t = tidy
	tidy = nil
	local parts = {}
	if #t.merged > 0 then parts[#parts + 1] = "combined stacks of " .. table.concat(t.merged, ", ") end
	if #t.moved > 0 then parts[#parts + 1] = "moved " .. table.concat(t.moved, ", ") .. " into your special bags" end
	if #parts > 0 then
		print(ns.PREFIX .. "Bags full - " .. table.concat(parts, "; ") .. ".")
	end
	if ns.OnTidyDone then ns.OnTidyDone() end
end

-- One pass: combine stacks; if there was nothing to combine, move into
-- special bags; if neither had anything to do, the tidy is finished. Called
-- again on the next bag update (or after FALLBACK_DELAY).
function ns.TidyStep()
	if not tidy then return end
	tidy.passes = tidy.passes + 1
	local pass = tidy.passes

	if GetCursorInfo() then
		-- You're holding something; don't disturb it, try again shortly.
		if pass < MAX_PASSES then
			C_Timer.After(FALLBACK_DELAY, function() if tidy and tidy.passes == pass then ns.TidyStep() end end)
		else
			finish()
		end
		return
	end

	local started = mergeStacks(tidy.merged, tidy.tried)
	if started == 0 then started = moveToSpecialBags(tidy.moved, tidy.tried) end
	if started == 0 or pass >= MAX_PASSES then
		finish()
		return
	end
	C_Timer.After(FALLBACK_DELAY, function() if tidy and tidy.passes == pass then ns.TidyStep() end end)
end

function ns.IsTidying()
	return tidy ~= nil
end

-- Starts tidying; BagSpace calls this the moment the normal bags fill up.
function ns.StartTidy()
	if tidy then return end
	tidy = { passes = 0, merged = {}, moved = {}, tried = {} } -- tried: never retry the same move
	ns.TidyStep()
end
