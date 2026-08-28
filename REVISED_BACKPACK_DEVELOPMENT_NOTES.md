# Revised Backpack ultrawide development notes

## Files and workflow

The source of truth is:

`C:\Modding\Codex\Modding Divers\CP2077-Ultrawide-World-Map\cet\UltrawideUIOverhaul\init.lua`

The copy loaded by Cyber Engine Tweaks is:

`C:\Games\Steam\steamapps\common\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\UltrawideUIOverhaul\init.lua`

When editing manually, either edit the game copy for a quick experiment and
port the validated change back to the repository, or edit the repository copy
and copy it to the game directory. A CET **Reload All Mods** reloads the Lua.

Do not edit or restore an older complete `init.lua`: this file also contains
all vanilla menu support, main-menu timing, pillar coordination, Backpack v2,
Crafting v2, 21:9/32:9/intermediate-ratio support, and compatibility fixes.

## Optional-mod isolation

Revised Backpack declares this REDscript module and classes:

- `RevisedBackpack.RevisedBackpackController`
- `RevisedBackpack.RevisedBackpackItemController`

The Lua registers their observers inside `pcall`. If Revised Backpack is not
installed, the class lookup fails safely and the rest of Ultrawide UI Overhaul
continues normally. Do not apply Revised Backpack changes from the vanilla
`BackpackMainGameController` path.

## Main Revised Backpack layout

Function: `applyRevisedBackpackLayout(controller, reason)`

The controller root corresponds to the Ink Inspector path:

`Root/Root`

It is resized to `geometry.contentWidth` by `2160`. This means:

- 5160 wide at the legacy 21:9 reference geometry;
- a dynamically calculated width for 32:9 and intermediate ultrawide ratios.

The layout runs once from `OnInitialize` and once through `pendingLayouts`
after 0.75 seconds. The delayed pass protects against late Ink initialization.

## Header widths

The header widgets are direct children of the Revised Backpack controller root:

- `Root/Root/nameContainer`: vanilla 772, ultrawide 1272
- `Root/Root/typeContainer`: vanilla 418, ultrawide 718

They are found recursively because the controller root is above the library
root at runtime. For `nameContainer`, candidates whose direct parent is named
`item` are excluded; those belong to virtual rows. `typeContainer` exists only
on the header.

## Virtual item rows

The inventory list is:

`Root/Root/scrollWrapper/scrollArea/virtualList`

Its rows are virtualized: only a pool of visible row widgets exists. Rows can
be created or recycled after the main screen has initialized. Therefore, a
single recursive scan of `virtualList` is not reliable.

Every row is handled by:

`resizeRevisedBackpackItemRow(controller)`

called from:

`RevisedBackpack.RevisedBackpackItemController.OnInitialize`

Important difference between headers and row cells (confirmed from the mod's
REDscript source):

- header name: `nameContainer`
- row name cell: `item/nameContainer`
- header type: `typeContainer`
- row type cell: `item/type` (not `typeContainer`)

Current row widths:

- `item/nameContainer`: 1242 (the item row has a 30-unit template inset
  relative to the header)
- `item/type`: 718

The visible text widgets have independent layout bounds:

- `item/nameContainer/name`: size/wrapping width 1110, wrapping disabled
- `item/type`: wrapping width 718, wrapping disabled
- `Root/shadow`: size `5200 x 80`, margin `(-1000, 0, 0, 0)`, opacity `0.03`
- `Root/selection`: size `2988 x 80`

Changing only the parent cell size leaves the vanilla name wrapping and Type
ellipsis boundaries cached.

The list viewport is `Root/Root/scrollWrapper/scrollArea`. It is 3088 wide at
the 21:9 reference geometry (vanilla 2188), calculated proportionally for other
supported aspect ratios.

`selectedItemsCount` uses margin `(0, 440, 1980, 0)`.

Garment preview path `Root/Root/previewGarment/Root/wrapper/preview` uses size
`1995 x 1995` and margin `(0, 0, 0, 0)` at all four levels:
`previewGarment`, `root`, `wrapper` and `preview`.

Item preview path `Root/Root/previewItem/Root/wrapper/preview` uses size
`1995 x 1330` at all four levels. `previewItem` uses margin
`(0, 400, 0, 0)`; `root`, `wrapper` and `preview` use zero margins.

The helper searches only four levels below the row root. This is sufficient for
the template paths while avoiding unrelated widgets.

## Why the first implementation failed

The first implementation recursively scanned all current `nameContainer` and
`typeContainer` widgets from the screen controller after a delay. This caused:

1. only rows present in the virtual-list pool at that instant to be resized;
2. later/recycled rows to retain vanilla widths;
3. the Type cells never to resize, because item rows call that widget `type`;
4. following columns to become visually misaligned and appear missing.

Do not return to a delayed recursive scan for virtual list rows. Modify them in
their item-controller lifecycle instead.

## Useful Revised Backpack source

Installed REDscript source:

`C:\Games\Steam\steamapps\common\Cyberpunk 2077\r6\scripts\RevisedBackpack\RevisedBackpack.reds`

Relevant areas:

- main controller: `RevisedBackpackController`
- virtual-list setup: `SetupVirtualList`
- item controller: `RevisedBackpackItemController`
- item widget paths: its `OnInitialize` method

## Testing checklist

After each change:

1. Run CET **Reload All Mods**.
2. Open Revised Backpack.
3. Check the headers immediately and again after the delayed layout pass.
4. Scroll far enough to force virtual rows to recycle.
5. Change categories and filters to rebuild the displayed data.
6. Verify every column still shows its values: name, type, tier, price, weight,
   DPS, damage per shot, range, quest and junk.
7. Reopen vanilla Backpack and confirm it is unchanged.
8. Before release, test at least 21:9 and 32:9.

## Development cleanup before a final release

- Remove the temporary `Revised Backpack controller observed` console print.
- Set temporary tree/controller diagnostic switches to `false`.
- Keep `MAIN_MENU_DIAGNOSTICS` enabled during development as requested, then
  set it to `false` for the final packaged release.
- Package only after the exact installed Lua has been validated in game.
