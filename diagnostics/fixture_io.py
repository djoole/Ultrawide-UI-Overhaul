"""Read retained Ink captures without depending on the game installation path."""
import json
import os
from pathlib import Path
from zipfile import ZipFile


def read_ink_dump(name):
    external = os.environ.get('UWUI_INK_DUMP_DIR')
    if external:
        return json.loads((Path(external) / name).read_text(encoding='utf-8'))
    archive = Path(__file__).resolve().parents[1] / 'maintenance/ink-test-fixtures.zip'
    if not archive.is_file():
        raise FileNotFoundError('Restore maintenance/ink-test-fixtures.zip or set UWUI_INK_DUMP_DIR')
    with ZipFile(archive) as captures:
        return json.loads(captures.read(name).decode('utf-8'))
