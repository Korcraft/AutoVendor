# AutoVendor

A small World of Warcraft addon (WoW Forever client).

- **Sells gray items** (and items you marked) automatically whenever you open a vendor, then **repairs** your gear with your own gold.
- **Mark items to sell:** Alt+left-click an item in your bags (again to unmark). It gets a gold coin and is sold along with the grays at the next vendor.
- **Protect items:** Alt+right-click an item in your bags (again to unprotect). Protected items are never sold or suggested for deletion, get a red outline, and say so in their tooltip.
  - Sell one to a vendor by hand anyway and it's bought straight back; put one in a trade window and it's taken straight back out - with a raid-warning-style popup and sound (only you see it). (The game doesn't let addons block a sale or trade, so this is an instant undo.)
- Both work in the default bags and in [Baganator](https://www.curseforge.com/wow/addons/baganator); with any other bag addon type `/av sell` or `/av protect` and Shift+click the item. Marks are per item type and shared by all your characters.
- **Combine stacks:** when your normal bags fill up, partial stacks of the same item are merged first (including into a partial stack in your quiver or a profession bag), if that frees a slot.
- **Special bags:** when your normal bags fill up, items that belong in a special bag (ammo in a quiver or ammo pouch, leather in a leatherworking bag, herbs in an herb bag...) are moved there automatically if it has a free slot.
- **Bags full?** AutoVendor tells you the least valuable item to delete. Only your normal bags count - special bags are ignored:
  - items you marked to sell come first
  - never suggests protected items, profession/gathering tools (skinning knife, mining pick, fishing poles...), quest items, keys, or items with no vendor price
  - food, drink, potions, reagents and ammo are only suggested as a last resort
  - if two partial stacks can be merged, it tells you that first
  - open your bags while they're full and the cheapest item gets a hot pink outline (default bags and Baganator) and a tooltip line; delete it and the next cheapest lights up, and so on until you close your bags
  - it never deletes anything itself

## Settings

Type `/av` (or open AutoVendor in the game's AddOns options) for on/off switches:
sell gray items, repair gear, bags-full delete suggestions, and - if you also run
Huntard - buying ammo at vendors.

## Commands

- `/av space` (or `/autovendor space`) - show the full delete order and what's being skipped, in a copyable window.
- `/av sell [item]` - mark or unmark an item to sell (type `/av sell`, then Shift+click the item).
- `/av protect [item]` - protect or unprotect an item (type `/av protect`, then Shift+click the item).

## Install

Download the zip from [Releases](../../releases) and extract the `AutoVendor` folder into your `Interface/AddOns` folder.

Inspired by [BetterVendorPrice](https://github.com/mooreatv/BetterVendorPrice)'s bags-full helper.
