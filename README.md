# BuffLedger

A standalone buff bar for vanilla WoW 1.12 (Turtle-based servers) that sorts your buffs by something meaningful - which class gave you a buff, not the raw order the client happens to report auras in - instead of Blizzard's default row. Class buffs, weapon enchants, consumables, world buffs, and racials each get their own color-coded cluster. A separate debuff bar (own Options tab, no sorting/grouping) shows what's on you the same way. Replaces pfUI's own buff and debuff display too, if pfUI is loaded.

![Buff icons grouped and color-coded by category, with gaps between clusters](screenshots/main.png)

## Requires

**[ClassicAPI](https://github.com/brues-code/ClassicAPI)** - a client-side mod that exposes `C_UnitAuras`, the modern-shaped aura API this addon reads buffs through. It's not a regular addon and can't be installed by copying a folder into `Interface/AddOns/` - see that repo for install instructions. Without it, BuffLedger loads but does nothing (no bar, `/bl` doesn't respond) and prints a message saying so on login. pfUI's own buff module needs the same API, so if pfUI's buffs already work on your setup, ClassicAPI is already present and you don't need to do anything extra.

## Install

1. Copy the `BuffLedger` folder into `Interface/AddOns/`
2. Enable BuffLedger at the character select addon list

Looks like pfUI by default - the flat near-black border, drop shadow, and Expressway font are bundled straight from pfUI's own files, so it looks right whether or not pfUI is actually installed. Everything is still fully configurable from its own Options window regardless (see below) - it never reads pfUI's live settings, so pfUI being installed doesn't override anything you set here.

## Usage

Drag either bar to reposition it (both start unlocked). `/bl options` opens a full settings window with a tab for each bar - icon size, spacing, columns, font, text size, border thickness, scale, growth direction, and a background panel toggle for both; the buff bar's tab also has a category gap slider, since it's the only one that groups icons into clusters.

- `/bl` or `/buffledger` - full command list
- `/bl options` (or `/bl opt`, `/bl config`) - settings window (buff bar and debuff bar tabs)
- `/bl lock` / `/bl unlock` - lock the buff bar in place, or free it to drag again (the debuff bar's lock is in its Options tab)
- `/bl reset` - reset buff bar position (the debuff bar has its own Reset Position button in its Options tab)
- `/bl scan` - scans your current raid/party and reports any buffs it doesn't recognize yet, with a guess at which class they belong to
- `/bl test [0-1 | % | off]` - preview a shuffled sample of every buff this addon knows about, without needing a raid to actually hold them all at once
- `/bl toggle <class|weapon|consumable|world|racial|other>` - show/hide one category

## How it works

The client's aura API has no concept of "who gave you this buff" - it's just a name, icon, and duration. BuffLedger keeps its own lookup table (`Data.lua`) mapping buff names to a source: a specific class, a world buff, a consumable, a racial, or "other" for anything unrecognized. Weapon enchants (sharpening stones, wizard oils, ...) aren't auras at all on this client, so those are read separately via `GetWeaponEnchantInfo()` and shown as their own category.

- **Grouped, not just sorted** - buffs from the same source sit together as one visual cluster, with a configurable gap between clusters. A cluster never splits across rows just because one ran out of horizontal room; it moves to the next row as a whole.
- **Color-coded borders** - class buffs take that class's actual class color; every other category gets its own fixed color (gold for world buffs, green for consumables, etc).
- **Sorted by time remaining within each cluster** - the buff closest to falling off is the most visually prominent one, not buried by alphabetical accident.
- **`/bl scan`** turns "is this buff in the lookup table yet" from a one-at-a-time guessing game into a single command - point it at a full raid and it'll tell you exactly which buffs it doesn't recognize, and which class it thinks each one belongs to.

## Known limitations

- Blizzard's own default buff icons may still show alongside this addon's bar. They used to get hidden automatically, but that was found to also hide your actual debuffs on this client (the player's debuffs render through that same stock frame here, not a separate one) - not a trade worth making, so it was reverted. If that stock display bothers you, pfUI's own buff module (if you run pfUI) hides it safely on its own without this issue.
- The name-to-class table is hand-maintained. Most standard buffs are already in it, but a private server's custom content can always add something new - if a buff lands in the generic "Other" bucket, that's what happened. `/bl scan` is the fastest way to find and fix these.
- A few consumables display under a short generic effect name in-game rather than the item's own name (e.g. Cerebral Cortex Compound's actual buff is "Infallible Mind") - most of these are already accounted for, but this is a real limitation of matching by aura name at all, not a bug.
- `/bl scan`'s raid-wide read assumes `C_UnitAuras.GetAuraDataByIndex` works against non-player unit tokens (`raid1`, `raid2`, ...) the same way it does for `"player"`. Every confirmed use elsewhere on this client only ever calls it with `"player"`, so this hasn't been independently verified.

## Credits

Built to match the look of [CombatLedger](https://github.com/kobeniiiiii/CombatLedger), [LootLedger](https://github.com/kobeniiiiii/LootLedger), and [CleanRolls](https://github.com/kobeniiiiii/CleanRolls) - the Expressway font and flat backdrop skin are bundled from [pfUI](https://github.com/shagu/pfUI) by Eric Mauser (Shagu), MIT-licensed.
