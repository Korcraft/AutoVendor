# AutoVendor

A small World of Warcraft addon (WoW Forever client).

- **Sells gray items** automatically whenever you open a vendor, then **repairs** your gear with your own gold.
- **Protect items:** Alt+click an item in your bags to protect it (again to unprotect). Works in the default bags and in [Baganator](https://www.curseforge.com/wow/addons/baganator); with any other bag addon type `/av protect` and Shift+click the item. Protected items are never sold or suggested for deletion, get a red outline, and say so in their tooltip.
- **Bags full?** AutoVendor tells you the least valuable item to delete:
  - never suggests protected items, profession/gathering tools (skinning knife, mining pick, fishing poles...), quest items, keys, or items with no vendor price
  - food, drink, potions, reagents and ammo are only suggested as a last resort
  - if two partial stacks can be merged, it tells you that first
  - the suggestion gets a bright blue outline (default bags and Baganator) and a tooltip line
  - it never deletes anything itself

## Settings

Type `/av` (or open AutoVendor in the game's AddOns options) for on/off switches:
sell gray items, repair gear, bags-full delete suggestions, and - if you also run
Huntard - buying ammo at vendors.

## Commands

- `/av space` (or `/autovendor space`) - show the full delete order and what's being skipped, in a copyable window.
- `/av protect [item]` - protect or unprotect an item (type `/av protect`, then Shift+click the item).

## Install

Download the zip from [Releases](../../releases) and extract the `AutoVendor` folder into your `Interface/AddOns` folder.

Inspired by [BetterVendorPrice](https://github.com/mooreatv/BetterVendorPrice)'s bags-full helper.
