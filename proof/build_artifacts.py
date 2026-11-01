"""Build the scoped arithmetic model and replayable patch without editing upstream."""
from pathlib import Path
import ast
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent
SESSION = "a3627280-2af6-4efe-8492-01f45c278a3c"
INPUTS = HERE.parent / "sessions" / SESSION / "inputs" / "sglang06"
INPUTS.mkdir(parents=True, exist_ok=True)

MODEL = '''# Scoped extraction. Inputs are scalars from the lone unsharded baseline request.
token_capacity = capacity - reserve
max_new_tokens = token_capacity - paged_input - page_size - 1
if requested < max_new_tokens:
    max_new_tokens = requested
if max_new_tokens < 0:
    max_new_tokens = 0
min_free_tokens = capacity - (paged_input + page_size) - max_new_tokens
blocked = min_free_tokens <= reserve
'''
ORIGINAL = MODEL.replace("capacity - reserve", "capacity", 1)
(HERE / "model.py").write_text(MODEL, encoding="utf-8")
(HERE / "original-model.py").write_text(ORIGINAL, encoding="utf-8")

OPS = {ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.LtE: "<=", ast.Lt: "<"}
def emit(node):
    if isinstance(node, ast.Name):
        return f'Name({json.dumps(node.id)})'
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return f"Int({node.value})"
    if isinstance(node, ast.BinOp):
        return f'BinOp("{OPS[type(node.op)]}", {emit(node.left)}, {emit(node.right)})'
    if isinstance(node, ast.Compare) and len(node.ops) == 1:
        return f'Compare({emit(node.left)}, CmpOp("{OPS[type(node.ops[0])]}", {emit(node.comparators[0])}))'
    if isinstance(node, ast.Call):
        args = ", ".join(emit(arg) for arg in node.args)
        return f"Call({emit(node.func)}, ({args}, .Exprs))"
    if isinstance(node, ast.Assign) and len(node.targets) == 1:
        return f"Assign({emit(node.targets[0])}, {emit(node.value)})"
    if isinstance(node, ast.If):
        then = " ".join(emit(item) for item in node.body) + " .Stmts"
        otherwise = " ".join(emit(item) for item in node.orelse) + " .Stmts"
        return f"If({emit(node.test)}, ({then}), ({otherwise}))"
    raise ValueError(ast.dump(node))

def body(source):
    return "\n        ".join(emit(node) for node in ast.parse(source).body) + " .Stmts"

initial = '''"capacity" |-> T "paged_input" |-> I "page_size" |-> P
                  "reserve" |-> R "requested" |-> M'''
final = initial + ''' "token_capacity" |-> (T -Int R)
                  "max_new_tokens" |-> ?N:Int "min_free_tokens" |-> ?F:Int "blocked" |-> false'''

def claim(label, source, before, after, domain, ensures=""):
    return f'''  claim [{label}]:
    <k> {body(source)} => .K </k>
    <env> 0 </env>
    <scopes> (0 |-> scope({before}, parent(-1))) (-1 |-> builtinsScope)
          => (0 |-> scope({after}, parent(-1))) (-1 |-> builtinsScope) </scopes>
    <scopeLoc> 1 </scopeLoc>
    <heap> .Map </heap>
    <heapLoc> 0 </heapLoc>
    <stack> .List </stack>
    <ret> noRet </ret>
    <exc> NoExc </exc>
    <exit-code> 0 </exit-code>
    requires {domain}
    {ensures}
'''

spec = '''requires "semantics.k"
module RUN2-SGLANG06-SPEC
  imports MPY
'''
domain = "I >=Int 0 andBool P >=Int 1 andBool R >=Int 1 andBool M >=Int 0\n         andBool T >=Int I +Int P +Int R +Int 1"
limit = "T -Int R -Int I -Int P -Int 1"
for label, branch, new in (
    ("requested-binds", f"M <=Int ({limit})", "M"),
    ("capacity-binds", f"M >Int ({limit})", f"({limit})"),
):
    result = initial + f''' "token_capacity" |-> (T -Int R)
                  "max_new_tokens" |-> {new} "min_free_tokens" |-> (T -Int I -Int P -Int {new}) "blocked" |-> false'''
    spec += claim(label, MODEL, initial, result, domain + "\n         andBool " + branch)
spec += "endmodule\n"
(HERE / "spec.k").write_text(spec, encoding="utf-8")

before = '"capacity" |-> 600 "paged_input" |-> 560 "page_size" |-> 1 "reserve" |-> 1 "requested" |-> 1000'
after = before + ' "token_capacity" |-> 600 "max_new_tokens" |-> 38 "min_free_tokens" |-> 1 "blocked" |-> false'
mutation = '''requires "semantics.k"
module RUN2-SGLANG06-MUTATION
  imports MPY
'''
mutation += claim("original-must-admit", ORIGINAL, before, after, "true")
mutation += "endmodule\n"
(HERE / "mutation.k").write_text(mutation, encoding="utf-8")

# Preserve source and create a conservative baseline-only production proposal.
original = (HERE / "upstream" / "scheduler.py").read_text(encoding="utf-8")
patched = original.replace(
    "from sglang.srt.managers.schedule_policy import (\n    AddReqResult,",
    "from sglang.srt.managers.schedule_policy import (\n    IGNORE_EOS_RESERVE_TOKENS,\n    AddReqResult,", 1)
needle = "        max_new_tokens = self.token_to_kv_pool_allocator.max_new_tokens_for_memory(\n"
addition = '''        # The fixed-pool ignore_eos path requires free tokens to be strictly
        # greater than its reserve, even for the first request on an empty pool.
        if (
            self.disable_radix_cache
            and req.sampling_params.ignore_eos
            and not self.is_hybrid_swa
            and self.kv_shard_widening == 1
        ):
            token_capacity -= IGNORE_EOS_RESERVE_TOKENS
'''
assert original.count(needle) == 1
patched = patched.replace(needle, addition + needle, 1)
(HERE / "patched-scheduler.py").write_text(patched, encoding="utf-8")
patch = "".join(difflib.unified_diff(original.splitlines(True), patched.splitlines(True),
    fromfile="a/python/sglang/srt/managers/scheduler.py", tofile="b/python/sglang/srt/managers/scheduler.py"))
(HERE / "fix.patch").write_bytes(patch.encode("utf-8"))

for name in ("spec.k", "mutation.k"):
    (INPUTS / name).write_bytes((HERE / name).read_bytes())

manifest = {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest()
            for name in ("model.py", "original-model.py", "spec.k", "mutation.k", "fix.patch", "upstream/scheduler.py", "upstream/base.py", "upstream/schedule_policy.py")}
(HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"session": SESSION, "inputs": str(INPUTS), "sha256": manifest}, indent=2))
