#!/usr/bin/env python3
"""Create a source-only ZIP without build products, credentials or caches."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root=Path(__file__).resolve().parents[1]
excluded={'.build','build','dist','.git','xcuserdata','__pycache__'}
excluded_files={'.DS_Store','task_plan.md','findings.md','progress.md'}
output=root/'dist/CodexQuotaRing-source.zip'
output.parent.mkdir(exist_ok=True)
with ZipFile(output,'w',ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        relative=path.relative_to(root)
        if path.is_file() and not excluded.intersection(relative.parts) and path.name not in excluded_files:
            archive.write(path,Path(root.name)/relative)
print(output)
