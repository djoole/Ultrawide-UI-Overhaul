# Ultrawide UI Overhaul

Current release: **2.5.7**

Ultrawide UI Overhaul redesigns Cyberpunk 2077's menus, loading screens and
fullscreen backgrounds for displays from 2:1 through 32:9. Content-heavy menus
gain additional usable space instead of merely stretching their backgrounds,
and the optional UI Spread setting lets users choose how far the interface
extends while backgrounds remain full-width.

Widget placement is handled by the CET script in
`cet/UltrawideUIOverhaul/init.lua`. The CET pillar coordinator is in
`cet/BlackPillarsCoordinator/init.lua`. The RED4ext plugin prevents the
fullscreen compositor from adding 16:9 side pillars when an ultrawide menu or
background is intentionally laid out across the display. It registers
`UWMapSetBlackBarsSuppressed(Bool)`:

- `false`: keep the game's stock fullscreen fit and side pillars;
- `true`: preserve the physical ultrawide rectangle for qualifying fullscreen
  compositions.

## Features

- Full-width 21:9 and 32:9 world map with synchronized map geometry, markers,
  district outlines and GPS path;
- expanded Backpack, Stash, Crafting, Gallery and Shards layouts that use the added
  horizontal workspace instead of merely extending their backgrounds;
- ultrawide backgrounds and repositioned edge widgets across the vanilla
  fullscreen menus, loading screens, popup views and Breach Protocol;
- configurable UI Spread from a centered 16:9 content area to the full
  ultrawide width, independently from full-width backgrounds;
- coordinated stock pillars during startup, loading screens, the main menu and
  gameplay;
- ratio-aware support covering 2:1, 21:9, intermediate ultrawide and 32:9
  modes, including 2880x1440, 1920x816, 2560x1000, 2560x1080, 3440x1440
  and 3200x900 tests;
- optional UI compatibility for Cleaner Main Menu and Pause Menu, Preem Menu
  StealthRunner, Revised Backpack and Vehicle Selector Frontend.

## Requirements

- Cyberpunk 2077 2.5;
- [RED4ext](https://github.com/WopsS/RED4ext);
- [Cyber Engine Tweaks](https://github.com/maximegmd/CyberEngineTweaks);
- [Codeware](https://github.com/psiberx/cp2077-codeware);
- Native Settings UI is optional and exposes UI Spread and debug-log settings.

## Compatibility

The hook is version-locked to Cyberpunk 2077 2.5 (runtime 3.0.88.46235). It checks the expected bytes
at the target RVA and refuses to install on an unknown executable. A game update
may require a new RVA/signature before the plugin can be used safely.

## Version 2.5.7

- Fixed the mouse cursor being confined to the central 16:9 area on Cyberpunk
  2077 2.5 while preserving gamepad pointer movement.
- Fixed black side bars remaining on loading screens when Load Begone or
  another auto-load mod skips the Main Menu and loads a save directly.

## Version 2.5.6

- Updated the native RED4ext plugin for Cyberpunk 2077 2.5 and the current
  RED4ext SDK/runtime.
- Relocated the fullscreen-composition hook and the controller-pointer caller
  exception while retaining the existing ultrawide layouts and behavior.

## Version 2.5.5

- Fixed UI rendering glitches beyond 4096 pixels on the Perks screen by
  introducing an automatic compatibility mode for wider resolutions.

## Version 2.5.4

- Added proper fullscreen arcade-minigame support by temporarily restoring the
  native black pillars around their authored aspect-ratio content.
- Fixed checkpoint reload and quickload screens exposing the streaming game
  world at the ultrawide edges.

## Version 2.5.3

- Fixed Initial Loading Screen, Fast Travel Loading Screen and World Map refits
  on systems where controller root widgets did not expose their parent.

## Version 2.5.2

- Fixed debug logging being forced on by default.

## Version 2.5.1

- Made initial loading-screen ultrawide coverage generic across different
  scenes.
- Improved optional Mod Settings and Revised Backpack detection.
- Improved World Map readiness handling so camera adjustments wait for the Ink
  layout.

## Version 2.5.0

- Added full ultrawide support for loading screens.

## Version 2.4.2

- Added Vehicle Selector Frontend compatibility, including correct ultrawide
  placement of vehicle preview images in the Mods menu.

## Version 2.4.1

- Added full ultrawide support for the Buy/Sell Vendor screen and Item/Wardrobe
  Preview.
- Made the player inventory default to All Items when opening a Vendor.

## Version 2.4.0

- Added UI Spread in the Mods settings, with continuous interpolation between
  a centered 16:9 content area and the full ultrawide width.
- Kept fullscreen backgrounds full-width independently from UI Spread.
- Added an Activate Debug Logs setting.
- Fixed the Native Settings description panel being placed too far right.

## Version 2.3.0

- Rewrote the layout system around exact widget paths instead of broad
  recursive scans.
- Removed heavy retries and repeated layout passes, substantially reducing
  menu-opening frame-time spikes and stutter.
- Fixed timing issues involving widgets created or animated after menu
  initialization.
- Improved Main Menu handling, startup pillar removal and optional diagnostics.

## Version 2.2.2

- Kept SmartFrame picture-picker pagination independent from the expanded main
  Gallery, restoring access to every photo in its fixed nine-image pages.

## Version 2.2.1

- Prevented repeated Backpack layout mutations while its virtualized inventory
  was being initialized, resolving opening crashes reported by affected users.
- Applied Backpack grid geometry once before controller initialization, while
  keeping Search placement in a separate post-initialization pass.

## Version 2.2.0

- Added proportional 2:1 layout support, validated at 2880x1440 and suitable
  for equivalent modes such as 3840x1920.
- Interpolated narrow-ultrawide margins, work areas and item-grid geometry
  between the vanilla 16:9 canvas and the established 21:9 layouts.
- Added ratio-aware Revised Backpack columns and preview sizing below 21:9,
  while preserving its validated 21:9 composition on wider displays.

## Version 2.1.0

- Added a full ultrawide Stash overhaul with ratio-aware player and storage
  grids, expanded filters, optional Stash Search placement and dynamic sorting
  dropdown positioning.
- Isolated the Flatline screen from shared ultrawide Pause Menu and Gallery
  transformations so its animated layout remains vanilla.

## Version 2.0.0

- Turned the project into a full ultrawide UI overhaul rather than a
  background-only extension.
- Expanded the vanilla Backpack item grid and repositioned its filters,
  search, sorting and dropdown controls across the available width.
- Expanded the Crafting recipe grid with ratio-aware columns and corrected
  its scrolling and button-hint boundaries.
- Added optional Revised Backpack support, including expanded list columns,
  corrected text wrapping, full-row selection effects and larger item and
  garment previews.
- Expanded Gallery to use the available width and dynamically show 14 images
  per page at 21:9 and 20 at 32:9.
- Expanded the Shards reader and its text wrapping across the remaining
  screen space.
- Added ultrawide treatment for Breach Protocol and its tutorial overlay.
- Added coverage for Reset Attributes, Gallery viewer, Journal detail and
  Database popup views.
- Added configured-resolution detection to the native plugin for low-height
  ultrawide modes such as 1920x816, with a live game-window fallback.
- Preserved controller-stick pointer input while removing fullscreen pillars.
- Kept all diagnostic and development probes disabled in the release build.

## Version 1.2.2

- Prevented main-menu discovery retries from spilling into the first in-game
  menu when Skip Main Menu or a similar startup mod is used.
- Improved pillar-state recovery and menu lifecycle reliability.

## Version 1.2.1

- Fixed controller-stick pointer input being blocked by the native fullscreen
  composition hook.

## Version 1.2.0

- Added full 32:9 support across all covered menus and the world map.
- Added ratio-aware placement for edge widgets, button hints and decorative
  elements.
- Generalized SAVE / LOAD layout corrections for both 21:9 and 32:9.
- Improved MODS and MOD SETTINGS list positioning on ultrawide displays.
- Added support for the 3200x900 custom 32:9 test resolution.
- Preserved the validated 21:9 layouts without regressions.

## Version 1.1.0

- Added Preem Menu compatibility.
- Added dynamic main-menu scene detection for alternate backgrounds.
- Added Skip Time ultrawide coverage.
- Preserved the correct pillar state across CET Reload All Mods.
- Improved main-menu timing and lifecycle reliability.
- Added and validated 2560x1080 support.

## Build

Requirements:

- Windows x64;
- Visual Studio 2019 or newer with the C++ desktop workload;
- a local checkout of [RED4ext.SDK](https://github.com/WopsS/RED4ext.SDK).

The build script expects the SDK at `native/deps/RED4ext.SDK` by default and
accepts an alternative path:

```powershell
git clone https://github.com/WopsS/RED4ext.SDK native/deps/RED4ext.SDK
.\native\build.ps1
```

To use another SDK location:

```powershell
.\native\build.ps1 -SdkPath D:\deps\RED4ext.SDK
```

The DLL is written to `native/build/BlackPillarsRemover.dll`.

## Installation

Copy the resulting DLL to:

`Cyberpunk 2077/red4ext/plugins/BlackPillarsRemover/BlackPillarsRemover.dll`

Copy the CET layout script to:

`Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/UltrawideUIOverhaul/init.lua`

Copy the coordinator to:

`Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/BlackPillarsCoordinator/init.lua`

The CET coordinator is optional for the native plugin itself, but is required
to switch pillars at the correct menu/loading lifecycle points.

## License

The native source is released under the MIT License. `RED4ext.SDK` remains under
its own license and is intentionally not vendored in this repository.
