# 2.5.9b1 — controller cursor candidate fix

Based on official 2.5.9. This build changes the native fullscreen hook's
register preservation, not the menu layouts or pillar-release rules.
The plugin reports `2.5.9-beta.1` in RED4ext; the package name uses `2.5.9b1`.

## Install

Close Cyberpunk 2077 fully, then replace the installed mod with this test
package. With MO2, enable this package instead of the official version, or
make sure it wins all three file conflicts. Restart the game: CET Reload All
does not reload the native DLL. Existing UI Spread and logging settings remain.

## Test

1. Start normally and wait at least 20 seconds at the startup Continue prompt.
   Enter the Main Menu. Check the full-width background and absence of side bars.
2. Move the cursor with the left stick in different directions. Check small
   movements, sustained movements, all screen edges, and D-pad navigation.
   Check the mouse can also reach both ultrawide edges.
3. Load a save. Check Inventory and an access-point Breach Protocol screen:
   stick cursor movement, selecting a cell, and reaching the necessary controls.
4. If using Load Begone direct-save loading, also verify the loading screen
   and game entry retain the normal pillar behavior.
5. For the reported interaction, restart and compare the same controller/menu
   tests with Ultrawide Scanner HUD enabled and disabled. Change one mod at a time.

## Report

Include the resolution, controller, Steam Input/profile or emulation setup,
which screen fails, and whether disabling Scanner HUD changes the result.
Attach the latest `red4ext/logs/red4ext-*.log` and
`red4ext/logs/blackpillarsremover-*.log` from that session. The native log must
contain `2.5.9b1: register-preserving fullscreen hook installed`; this confirms
the intended DLL actually loaded. A short video is useful for cursor jumps.

## Roll back

Close the game and reinstall official 2.5.9 (or re-enable it in MO2). No save
migration or settings reset is needed.

## Automated validation

Run `native/tests/run.ps1` from the repository with Visual Studio C++ tools
and the configured RED4ext SDK. It tests the actual assembly boundary against
an adjustment that destroys every volatile register, Windows stack unwinding,
and the production geometry adjustment at 16:9, 2:1, 21:9 and 32:9, including
the reporter's 5120x2160 and the local 3440x1440 resolutions. These checks do
not replace controller testing in the game or confirm the reporter's fix.
