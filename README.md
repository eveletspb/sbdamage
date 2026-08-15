# SbDamage

SbDamage is a lightweight outgoing damage text replacement for World of Warcraft 3.3.5a.

> SbDamage was inspired by the NiceDamage addon.

NiceDamage changed the font used by Blizzard's floating combat text. SbDamage keeps the idea of clear, satisfying damage numbers, but renders its own outgoing damage messages. This makes target positioning, spell icons, damage-school colors, pet damage, and critical-hit animations configurable.

## Features

- Damage numbers appear above the target's visible nameplate, with configurable X/Y offsets.
- Each damage cluster has three compact streams: periodic player damage on the left, direct player damage in the center, and pet damage on the right.
- Configurable spacing between streams and numbers, plus a per-stream visible-number limit.
- Configurable movement direction: always upward, always downward, or automatic based on available screen space.
- Configurable animation speed from 50% to 200% and fade-out start, applied immediately to visible numbers.
- Configurable screen position is used as a fallback when the target's nameplate is hidden.
- Every displayed hit remains a separate number, including AoE and DoT damage; hits are never merged into totals.
- Optional spell icon next to the damage number.
- Four icon modes: disabled, every hit, one per target, or one icon per AoE series.
- Configurable icon size and optional desaturation.
- Localized text for misses, dodges, parries, blocks, resists, immunities, absorbs, and related outcomes.
- Pet and owned guardian/totem damage can be enabled or disabled.
- Pet numbers and icons use a separately configurable reduced scale.
- Pet melee hits use the standard pet Attack command icon.
- Critical-hit size scales the whole message, including its icon; animations can be disabled, shaken, pulsed, or combined.
- Multiple bundled fonts and independently configurable text sizes for direct and periodic damage.
- Configurable colors based on the actual damage school.
- Nine focused native WoW settings pages with no Ace3 or other runtime dependencies.
- Preview mode for configuring the addon without entering combat.
- Exact, grouped, or shortened (`k`/`m`) damage-number formatting.
- Independent minimum thresholds for direct and periodic damage.
- Optional autoattack hiding and blacklist/whitelist filtering by spell ID.
- Three built-in appearance presets and optional debug counters.

## Damage colors

SbDamage uses familiar WoW colors by default:

- melee attacks, `Auto Shot`, and `Shoot` — white;
- physical ability damage — yellow;
- Holy — gold;
- Fire — orange-red;
- Nature — green;
- Frost — light blue;
- Shadow — purple;
- Arcane — magenta.

Every color can be changed. School-based coloring can also be disabled in favor of one shared color.

## Settings

The native settings UI is split into nine focused pages instead of one long scrolling form:

- `SbDamage` — master switches, a short layout explanation, preview, navigation, and confirmed reset of all settings;
- `Layout` — target offsets, compact damage columns, exact fallback coordinates, and screen placement mode;
- `Multiple targets` — smart cluster separation, strict nameplate placement, focused grouping, and secondary-target scale;
- `Appearance` — font, animation speed, spell icons, critical-hit animation, and pet number/icon scale;
- `Text size` — separate size controls for direct damage (abilities, auto attacks, and regular misses) and periodic damage;
- `Colors` — either one shared color or the damage-school palette, shown only when relevant.
- `Filters` — direct/periodic thresholds, autoattacks, spell-ID blacklist/whitelist, and debug counters.
- `Format and timing` — number formatting and fade-out start.
- `Presets` — classic defaults, a low-clutter setup, and emphasized critical hits.

Preview is available from every page and also works while combat rendering is disabled. The `Multiple targets` page uses three synthetic nearby targets so separation mode, maximum shift, and secondary-target scale can be checked immediately. Other pages use the current target's visible nameplate when possible, or the configured fallback position otherwise. Ambiguous values are displayed with `px` or `%`, dependent controls are disabled automatically, and layout, appearance, colors, or all settings can be reset independently.

Direct and periodic sizes are base font sizes. Pet damage, secondary targets, and critical hits keep their existing relative scales on top of the selected base size. Periodic pet damage therefore uses the periodic base size together with the configured pet scale.

## AoE behavior

SbDamage does not merge AoE damage. Every displayed hit remains a separate number, preserving the satisfying “damage rain” effect. When a visible limit is reached, the oldest number is recycled rather than combining events into a total.

Damage is grouped into a compact cluster above each visible nameplate. Direct player hits stay in the center, periodic player ticks form a line on the left, and all pet damage forms a smaller line on the right. Numbers only move vertically; there is no global horizontal search that spreads them across the screen.

The recommended `Smart separation` mode compares whole target clusters and moves a colliding cluster vertically by no more than the configured limit. `Strictly above targets` keeps exact nameplate positions even when they overlap. `At the selected target` collects all outgoing hits into one compact cluster above the selected target or at the fallback point. Secondary-target numbers can use a smaller independent scale.

The layout uses the measured size of each number, spell icon, target scale, and critical-hit animation to keep messages separated. Movement can be forced upward, forced downward, or selected automatically from the available screen space. Horizontal screen clamping preserves the stream order and reduces spacing only when required. When a configured stream limit is reached, SbDamage recycles only the oldest number in that target's stream. If an extreme text/icon configuration cannot fit vertically, the oldest number in that target's cluster is recycled until the visible cluster fits. Damage events are never combined into a single total.

When no nameplate can be identified, all unknown targets share the same compact three-stream fallback cluster. This is intentional: the client exposes no reliable position for those units, and guessing separate screen positions would recreate the scattered layout.

The recommended `Shared series` icon mode displays an icon only on the first hit from the same ability within a short time window. `Series per target` applies that short window separately to each affected unit, while `Every hit` is available for maximum detail. Icon filtering never merges damage numbers, and every visible critical hit is still animated independently.

## Installation

1. The addon directory must be named `SbDamage` and contain only `SbDamage.toc`.
2. Copy it to `World of Warcraft/Interface/AddOns/`.
3. Restart the game client or run `/reload`.
4. Open `Interface Options -> AddOns -> SbDamage`.

SbDamage targets WoW 3.3.5a (`Interface 30300`) and AzerothCore/TrinityCore-based servers using the standard client combat-log API.

## Commands

- `/sbd` or `/sbdamage` — open the settings panel.
- `/sbd test` — preview damage numbers, colors, and icons.
- `/sbd move` — enable or disable mouse movement for the fallback screen position.
- `/sbd debug` — print received, displayed, and filtered event counters.
- `/sbd debug reset` — reset debug counters.

## Differences from NiceDamage

| NiceDamage | SbDamage |
|---|---|
| Replaces the global `DAMAGE_TEXT_FONT` | Renders its own outgoing damage messages |
| Font selection requires renaming a file | Font selection is available in game |
| Position is controlled by the client | Target nameplate positioning, X/Y offsets, and screen fallback |
| No spell icons | Player and pet ability icons |
| Standard number styling | Configurable damage-school colors |
| Standard critical-hit behavior | Configurable critical-hit animations |
| No settings panel | Native settings panel and preview mode |

## Limitations

- WoW 3.3.5a does not expose screen coordinates for arbitrary 3D models to addons. Target positioning therefore requires a visible nameplate. Press `V` to show enemy nameplates; otherwise, SbDamage uses its configured screen fallback.
- When several visible units have the same name, the client does not expose the GUID associated with each nameplate. SbDamage assigns new GUIDs to matching nameplates in sequence and can identify the currently selected target more accurately through its highlighted nameplate.
- Smart separation moves whole colliding clusters vertically up to the configured maximum. Overlap can remain when that limited area has insufficient room; strict mode intentionally preserves exact nameplate positions.
- Guardian and totem ownership detection depends on correct combat-log flags from the server core.
- While enabled, SbDamage temporarily disables Blizzard's outgoing player damage, periodic damage, and pet melee text to prevent duplicates. Previous CVar values are restored when SbDamage is disabled.
- The original NiceDamage repository did not specify licenses for its bundled fonts. Before publishing a release archive, verify redistribution rights for every `.ttf` file or replace them with fonts carrying clear licenses.

## Credits

- Montyburns — author of NiceDamage, which inspired this project.
- The xCT+ and MikScrollingBattleText developers — for established combat-text UX and performance ideas.
