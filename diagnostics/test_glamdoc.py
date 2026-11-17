"""Exercise centered Glam Doc content and edge hints against captured Ink trees."""
import re
from pathlib import Path

from lupa.lua54 import LuaRuntime
from fixture_io import read_ink_dump

SOURCE = Path("cet/UltrawideUIOverhaul/init.lua").read_text(encoding="utf-8")
ROOT = "inkMenuLayer/inkVirtualWindow/Root[0]"
TARGETS = {f"{ROOT}/Root[0]", f"{ROOT}/Root[1]"}
HINTS = f"{ROOT}/Root[0]/button_hints[6]"
BACKGROUND = f"{ROOT}/Root[0]/Background_generic[0]"
FLUFF = f"{ROOT}/Root[0]/Background_Fluff_GRP[9]"
MASK = f"{ROOT}/Root[0]/background_paperdoll_mask[2]"


def check(dump_name, width, height, spread, expected, missing=None):
    dump = read_ink_dump(dump_name)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        events = {}; writes = {}; suppressed = false
        function registerForEvent(name, fn) events[name] = fn end
        CName = {new = function(name) return name end}
        Vector2 = {new = function(value) return value end}
        function UWMapSetBlackBarsSuppressed(value) suppressed = value end
        function GetMod() return nil end
        function makeWidget(n)
            n.childWidgets = {}
            function n:GetWidget(index) return self.childWidgets[index] end
            function n:GetName() return {value = self.name} end
            function n:GetSize() return {X = self.size[1], Y = self.size[2]} end
            function n:SetSize(x, y)
                self.size[1] = x; self.size[2] = y
                writes[#writes + 1] = self.path
            end
            function n:GetMargin()
                return {left=self.margin[1], top=self.margin[2], right=self.margin[3], bottom=self.margin[4]}
            end
            function n:SetMargin(l, t, r, b)
                self.margin = {l, t, r, b}
                writes[#writes + 1] = self.path
            end
            function n:GetScale() return {X=self.scale[1], Y=self.scale[2]} end
            function n:SetScale(v)
                self.scale = {v.X, v.Y}; writes[#writes + 1] = self.path
            end
            function n:GetTranslation() return {X=self.translation[1], Y=self.translation[2]} end
            function n:SetTranslation(v)
                self.translation = {v.X, v.Y}; writes[#writes + 1] = self.path
            end
            function n:FlagForVisualInvalidation() end
            return n
        end
        function setSpread(fn, value, seen)
            seen = seen or {}
            if seen[fn] then return false end
            seen[fn] = true
            for i = 1, 255 do
                local name, upvalue = debug.getupvalue(fn, i)
                if name == nil then break end
                if name == 'UI_SPREAD_PERCENT' then
                    debug.setupvalue(fn, i, value); return true
                end
                if type(upvalue) == 'function' and setSpread(upvalue, value, seen) then
                    return true
                end
            end
            return false
        end
    """)
    widgets = {}
    for node in dump["nodes"]:
        if node["path"] == missing:
            continue
        widgets[node["path"]] = lua.globals().makeWidget(
            lua.table_from(node, recursive=True)
        )
    for path, widget in widgets.items():
        if path == dump["root"]:
            continue
        parent, child = path.rsplit("/", 1)
        if parent in widgets:
            index = int(re.search(r"\[(\d+)\]$", child).group(1))
            widgets[parent].childWidgets[index] = widget
    lua.globals().window = widgets[dump["root"]]
    lua.globals().screenWidth = width
    lua.globals().screenHeight = height
    lua.execute("""
        function GetDisplayResolution() return screenWidth, screenHeight end
        Game = {GetInkSystem = function()
            return {GetLayer = function()
                return {GetVirtualWindow = function() return window end}
            end}
        end}
    """)
    lua.execute(SOURCE)
    apply = lua.globals().UWUI_glamdoc.apply
    assert lua.globals().setSpread(apply, spread)
    success = apply("captured Ink tree test")
    writes = list(lua.globals().writes.values())
    if expected is None:
        assert not success and not writes
        assert not lua.globals().suppressed
    else:
        assert success and set(writes) == TARGETS | {HINTS, BACKGROUND, FLUFF, MASK} and len(writes) == 7
        assert lua.globals().suppressed
        hints_right = 100 - (expected - 3840) / 2
        physical_ink_width = width / height * 2160
        cover_scale = physical_ink_width / 3840
        for node in dump["nodes"]:
            if node["path"] not in widgets:
                continue
            current = widgets[node["path"]]
            expected_x = 3840 if node["path"] in TARGETS else node["size"][0]
            assert abs(current.size[1] - expected_x) < 1e-6
            assert current.size[2] == node["size"][1]
            for index in range(4):
                expected_margin = hints_right if node["path"] == HINTS and index == 2 else node["margin"][index]
                assert current.margin[index + 1] == expected_margin
            expected_scale = cover_scale if node["path"] in {BACKGROUND, FLUFF} else cover_scale * 1.2 if node["path"] == MASK else node["scale"][0]
            expected_translation = physical_ink_width * .1 if node["path"] == MASK else node["translation"][0]
            assert abs(current.scale[1] - expected_scale) < 1e-6
            assert current.scale[2] == node["scale"][1]
            assert abs(current.translation[1] - expected_translation) < 1e-6
            assert current.translation[2] == node["translation"][1]
        for _ in range(3):
            assert apply("repeat")
            assert widgets[HINTS].margin[3] == hints_right
            assert abs(widgets[MASK].scale[1] - cover_scale * 1.2) < 1e-6
            assert abs(widgets[MASK].translation[1] - physical_ink_width * .1) < 1e-6
        # Reload on the same live tree must not accumulate the previous shift.
        lua.execute(SOURCE)
        apply = lua.globals().UWUI_glamdoc.apply
        assert lua.globals().setSpread(apply, spread)
        assert apply("reload")
        assert widgets[HINTS].margin[3] == hints_right
        assert abs(widgets[MASK].scale[1] - cover_scale * 1.2) < 1e-6
        assert abs(widgets[MASK].translation[1] - physical_ink_width * .1) < 1e-6
    print(f"PASS {dump_name}: {width}x{height}, spread={spread}%, expected={expected}")


for dump_name in [
    "ink_tree_dump_20261031-120341_01_inkMenuLayer.json",
    "ink_tree_dump_20261031-120618_02_inkMenuLayer.json",
    "ink_tree_dump_20261116-090607_01_inkMenuLayer.json",
]:
    for width, height, spread, expected in [
        (3440, 1440, 100, 5160),
        (5120, 1440, 100, 7680),
        (2880, 1440, 100, 4320),
        (3440, 1440, 0, 3840),
        (3440, 1440, 50, 4500),
        (1920, 1080, 100, None),
    ]:
        check(dump_name, width, height, spread, expected)
    check(dump_name, 3440, 1440, 100, None, f"{ROOT}/Root[0]/Background_generic[0]")
    check(dump_name, 3440, 1440, 100, None, HINTS)
