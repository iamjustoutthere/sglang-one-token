"""Apply the SGLang wedge patch and run the real intake + allocator bodies on 6,345 cases.

No SGLang server, model, GPU, network endpoint, or shared service is started.
"""
from pathlib import Path
from types import SimpleNamespace as NS
import ast
import asyncio
import copy
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPORT = {}

def extract(path, name, env):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    node = copy.deepcopy(next(node for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name))
    node.decorator_list = []
    node.returns = None
    for arg in (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs):
        arg.annotation = None
    exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])), str(path), "exec"), env)
    return env[name]

def applied(here, target):
    shutil.copytree(here / "baseline", target)
    subprocess.run(["git", "apply", "--check", str(here / "fix.patch")], cwd=target, check=True, capture_output=True)
    subprocess.run(["git", "apply", str(here / "fix.patch")], cwd=target, check=True, capture_output=True)


def capacity(here, patched):
    source = ROOT / "proof"
    base = source / "upstream/base.py"
    env = {}
    memory = extract(base, "max_new_tokens_for_memory", env)
    old = extract(here / "baseline/python/sglang/srt/managers/scheduler.py", "init_req_max_new_tokens", {"logger": NS(warning=lambda *a: None)})
    new = extract(patched / "python/sglang/srt/managers/scheduler.py", "init_req_max_new_tokens", {"logger": NS(warning=lambda *a: None), "IGNORE_EOS_RESERVE_TOKENS": 1})
    def invoke(fn, total, prompt, page, requested):
        allocator = NS(page_size=page)
        allocator.max_new_tokens_for_memory = lambda *a, **k: memory(allocator, *a, **k)
        owner = NS(max_new_tokens_limit=None,max_req_len=total-1,max_total_num_tokens=total,kv_shard_widening=1,page_size=page,token_to_kv_pool_allocator=allocator,sliding_window_size=None,chunked_prefill_size=None,disable_radix_cache=True,is_hybrid_swa=False)
        request = NS(origin_input_ids=[0]*prompt,sampling_params=NS(max_new_tokens=requested,min_new_tokens=0,ignore_eos=True))
        fn(owner,request)
        output = request.sampling_params.max_new_tokens
        free = total - (-(-prompt//page)*page + page) - output
        return output, free
    assert invoke(old,600,560,1,None)==(38,1)
    assert invoke(new,600,560,1,None)==(37,2)
    count = 0
    for page in (1,2,4,8,16):
        for total in (64,128,600,1024):
            for prompt in range(1,total-page-2,7):
                rounded=-(-prompt//page)*page
                if total < rounded + page + 2:
                    continue
                for requested in (None,0,1,7,10000):
                    output,free=invoke(new,total,prompt,page,requested)
                    assert free>1 and output>=0
                    count+=1
    return {"recorded_witness_before": {"output":38,"free":1},"recorded_witness_after":{"output":37,"free":2},"source_extracted_cases":count,"boundary":"actual scheduler intake and allocator clip; request objects and allocator dispatch stubbed; admission arithmetic checked independently"}


if __name__ == "__main__":
    here = ROOT / "bug"
    with tempfile.TemporaryDirectory() as directory:
        patched = Path(directory) / "patched"
        applied(here, patched)
        REPORT = {"patch_application": "passed", **capacity(here, patched)}
    print(json.dumps(REPORT, indent=2))
