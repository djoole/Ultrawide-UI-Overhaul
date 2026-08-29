# Ultrawide UI Overhaul

## Short description

Extends Cyberpunk 2077’s menus, working areas and fullscreen backgrounds across ultrawide displays from 2:1 through 32:9 while coordinating the stock side pillars during startup and loading.

## Description

Ultrawide UI Overhaul adapts Cyberpunk 2077’s interface for 2:1, 21:9, intermediate ultrawide and 32:9 displays. Major inventory and content views use the extra horizontal workspace instead of remaining confined to the central 16:9 area. The mod coordinates the game’s black side pillars so startup and loading screens remain clean.

## Features

- Dynamic layout support from 2:1 through 32:9 for the main menu, pause menu and in-game menus.
- Full-width world map background with synchronized markers and widgets.
- Expanded Backpack, Stash and Crafting grids with more visible items and recipes.
- Expanded Gallery pages and Shards reading area.
- Coverage for inventory, cyberware, character, journal, database, settings, mod settings, stats, gallery, shards, save/load, Breach Protocol and related popup views.
- Black pillars are restored during startup and loading, then removed at the appropriate menu and world states.
- Optional compatibility for Cleaner Main Menu and Pause Menu, Preem Menu, StealthRunner and Revised Backpack.

## Requirements

- Cyberpunk 2077 version 2.31 (the native hook is version-locked).
- RED4ext.
- Cyber Engine Tweaks (CET).
- A supported ultrawide display from 2:1 through 32:9.

## Installation with Vortex

1. Download the archive and install it through Vortex as a Cyberpunk 2077 mod.
2. Enable the mod and deploy it.
3. Start the game. No in-game configuration is required.

The archive contains the required `red4ext` and `bin/x64/plugins/cyber_engine_tweaks` paths, so Vortex can deploy it directly.

## Compatibility and troubleshooting

The CET-based layout layer modifies live Ink widgets and is generally less conflict-prone than replacing entire game UI resources. Compatibility cannot be guaranteed when another mod restructures the same widget trees, but optional integrations are isolated and safely skipped when those mods are absent.

Do not install older copies of the same mod alongside this release. If the game has been updated, disable the native DLL until a compatible build is available.

## Source

Source code: https://github.com/djoole/Ultrawide-UI-Overhaul

The repository contains the C++ source, build script and CET scripts. The native plugin is released under the MIT License.
