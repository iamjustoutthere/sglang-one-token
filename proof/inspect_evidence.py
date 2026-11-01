from pathlib import Path
import hashlib
import json
import sys

sys.setrecursionlimit(100000)
here = Path(__file__).resolve().parent
negative = json.loads((here / "evidence/original-negative-control.json").read_text())
stack = [json.loads(negative["stdout"])]
found = {}
while stack:
    item = stack.pop()
    if isinstance(item, dict):
        if item.get("label", {}).get("name") == "_|->_" and len(item.get("args", [])) == 2:
            key = item["args"][0].get("token")
            if key in ('"blocked"', '"max_new_tokens"', '"min_free_tokens"'):
                found[key] = item["args"][1]
        stack.extend(item.values())
    elif isinstance(item, list):
        stack.extend(item)
(here / "evidence/negative-control-residual.json").write_text(json.dumps(found, indent=2) + "\n")
for name in ("patched-proof", "original-negative-control"):
    data = json.loads((here / f"evidence/{name}.json").read_text())
    for stream in ("stdout", "stderr"):
        (here / f"evidence/{name}.{stream}").write_text(data.get(stream, ""), encoding="utf-8")
files = [path for path in here.rglob("*") if path.is_file() and path.name != "bundle-sha256.json" and "__pycache__" not in path.parts]
hashes = {str(path.relative_to(here)).replace("\\", "/"): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(files)}
(here / "bundle-sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
print(json.dumps(found, indent=2))
