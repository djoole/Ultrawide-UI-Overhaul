"""Run the retained Lua layout regressions from any working directory."""
import os
import subprocess
import sys
from pathlib import Path
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
os.chdir(root)
for name in ['test_glamdoc.py', 'test_crafting_spread.py', 'test_cyberware_tooltips.py', 'test_revised_backpack.py']:
    subprocess.run([sys.executable, str(root / 'diagnostics' / name)], check=True)
for name in ['test_loading_startup.lua', 'test_startup_menu_after_loading.lua']:
    LuaRuntime(unpack_returned_tuples=True).execute((root / 'diagnostics' / name).read_text(encoding='utf-8'))
print('PASS all retained Lua layout regressions')
