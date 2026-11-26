# AutoVendor

A small World of Warcraft addon (WoW Forever client).

- **Sells gray items** (and everything on your blacklist) automatically whenever you open a vendor, then **repairs** your gear with your own gold.
- **One-time marks (Alt+click in your bags):** Alt+left-click = sell this stack at the next vendor (gold dotted outline + coin); Alt+right-click = protect this stack (red dotted outline). Again to unmark. Only the stack you clicked is marked: other stacks of the same item are left alone (8 arrows in your bag can be sold while the full quiver stays). The mark follows the stack if you move it, and AutoVendor won't merge a marked stack or move it into a special bag. Once the stack is sold, deleted or gone, the mark is gone too.
- **Permanent lists (Ctrl+Alt+click in your bags):** Ctrl+Alt+left-click = **blacklist** (always sold, whatever its quality); Ctrl+Alt+right-click = **whitelist** (never sold or suggested for deletion) - every time the item is in your bags. Again to take it off. Saved by item type, for all your characters.
  - Both lists are also in the settings window (`/av`): see everything on them, remove items with the X, and add items you aren't carrying by typing an item ID or name, Shift+clicking an item link, or dropping an item on the list. (`/av sell [item]` and `/av protect [item]` also add/remove.)
- **Markers:** protect once = red dotted outline + X; whitelist = red solid outline + X; sell once = gold dotted outline + coin; blacklist = gold solid outline + coin; delete suggestion = hot pink dotted outline. The tooltip says which, too.
- **Colours:** every outline colour (whitelist, protect once, delete suggestion, blacklist, sell once) can be changed on its own in /av: click a swatch to pick a colour, right-click it to put it back. "Reset colours" restores all five.
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
  - a **Delete** button sits beside your open bags while something is outlined: each click deletes the pink item, then the next one lights up, so keep clicking until you have room. One item per click; rare or better asks first. Turn it off in /av
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
