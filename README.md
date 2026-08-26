# Ultrawide UI Overhaul

RED4ext plugin (`BlackPillarsRemover`) that prevents Cyberpunk 2077's fullscreen compositor from
adding 16:9 side pillars when an ultrawide menu or background is intentionally
laid out across a 21:9 display.

The plugin does not move widgets and does not alter menu layout by itself.
Widget placement is handled separately by the CET script in
`cet/UltrawideUIOverhaul/init.lua`. The native coordinator is in
`cet/BlackPillarsCoordinator/init.lua`. The native plugin registers
`UWMapSetBlackBarsSuppressed(Bool)`:

- `false`: keep the game's stock fullscreen fit and side pillars;
- `true`: preserve the physical ultrawide rectangle for qualifying fullscreen
  compositions.

## Compatibility

The hook is version-locked to Cyberpunk 2077 2.31. It checks the expected bytes
at the target RVA and refuses to install on an unknown executable. A game update
may require a new RVA/signature before the plugin can be used safely.

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

Copy the CET coordinator to:

`Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/UltrawideUIOverhaul/init.lua`

Copy the coordinator to:

`Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/BlackPillarsCoordinator/init.lua`

The CET coordinator is optional for the native plugin itself, but is required
to switch pillars at the correct menu/loading lifecycle points.

## License

The native source is released under the MIT License. `RED4ext.SDK` remains under
its own license and is intentionally not vendored in this repository.
