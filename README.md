# AutoVendor

A small World of Warcraft addon (WoW Forever client).

- **Sells gray items** automatically whenever you open a vendor, then **repairs** your gear with your own gold.
- **Protect items:** Alt+click an item in [Baganator](https://www.curseforge.com/wow/addons/baganator) to protect it (again to unprotect). Protected items are never sold or suggested for deletion and get a red outline.
- **Bags full?** AutoVendor tells you the least valuable item to delete:
  - never suggests protected items, profession/gathering tools (skinning knife, mining pick, fishing poles...), quest items, keys, or items with no vendor price
  - food, drink, potions, reagents and ammo are only suggested as a last resort
  - if two partial stacks can be merged, it tells you that first
  - the suggestion gets a yellow outline in Baganator
  - it never deletes anything itself

## Commands

- `/av space` (or `/autovendor space`) - show the full delete order and what's being skipped, in a copyable window.

## Install

Download the zip from [Releases](../../releases) and extract the `AutoVendor` folder into your `Interface/AddOns` folder.

Inspired by [BetterVendorPrice](https://github.com/mooreatv/BetterVendorPrice)'s bags-full helper.
