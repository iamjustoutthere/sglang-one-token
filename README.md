# One Token Wedge

An SGLang request that fits in memory but never gets admitted. This repo has the bug, a one-line fix, and a K proof that the fixed admission arithmetic works for every integer input.

**Presentation:** [`docs/index.html`](docs/index.html) (open it locally, or enable GitHub Pages on `/docs`). Use the arrow keys to move and `N` for speaker notes.

## The bug in one picture

```
 Pool = 600 tokens, empty. Prompt = 560.

 INTAKE: "how much may this request generate?"
 [ prompt 560 | overhead 1 | output 38 | free 1 ]   = 600   "fits"

 ADMISSION: "is there enough left over?"
   free = 1, rule: free must be MORE than 1
   1 > 1 ?  NO  -> NO_TOKEN, every pass, forever
```

The pool is already empty, so nothing can ever free memory, and retrying computes the same number. The request blocks the head of the FCFS queue, and every request behind it waits. Meanwhile `/health` keeps returning 200.

## Why a shorter prompt doesn't help

```
 G    = T - I - P - 1            intake's output allowance
 free = T - I - P - G            what admission sees
      = T - I - P - (T - I - P - 1)
      = 1                        for every T, I, P
```

When memory is what limits the output, the prompt size cancels out. Intake hands any space you free up straight to generation.

## The fix

```diff
+ if (self.disable_radix_cache and req.sampling_params.ignore_eos
+         and not self.is_hybrid_swa and self.kv_shard_widening == 1):
+     token_capacity -= IGNORE_EOS_RESERVE_TOKENS
  max_new_tokens = self.token_to_kv_pool_allocator.max_new_tokens_for_memory(...)
```

Intake reserves `R` before it clips, so admission sees `R + 1` free. The strict gate `free <= R` stays as it is. Changing the gate to `<` would also make the request run, but it would delete the reserve that guards paged allocation corner cases.

## Evidence

| Level | What | Where |
| --- | --- | --- |
| Observed | Real CPU server stalls 3/3; the output-37 and radix-on controls complete | [`bug/evidence.md`](bug/evidence.md) |
| Tested | 6,345 cases run the **real** patched intake and allocator bodies, page sizes 1 to 16 | [`tools/verify_capacity.py`](tools/verify_capacity.py) |
| Proved | Two K claims cover **every** integer input to the extracted model: `blocked = false`, free = R + 1 | [`proof/PROOF.md`](proof/PROOF.md) |
| Proved again (Lean 4) | Fix admits every input; the original leaves exactly 1 free and is refused for **every** input | [`lean/SglangWedge.lean`](lean/SglangWedge.lean) |
| Negative control | Original line, same claim: `notProved`, residual `max_new_tokens=38, min_free_tokens=1, blocked=true` | [`proof/evidence/`](proof/evidence/) |

Proof receipt: task `75db8b39-4050-4364-b256-0f526b591f0c`, result `proved`, `kprove` exit 0, MiniPy semantics `d4d75049838b`, K 7.1.337. No local rules, lemmas, summaries, trusted claims, or depth bound.

Theorem domain: integers with `I >= 0`, `P >= 1`, `R >= 1`, `M >= 0`, `T >= I + P + R + 1`.

## Scope (read this before quoting)

Status: **SOUND-BUT-LIMITED.**

- **Accurate:** "We formally verified the admission arithmetic of the fix."
- **Not accurate:** "We verified the SGLang patch."
- The theorem covers a hand-extracted model of the arithmetic. The link to production code is a reviewed extraction plus the 6,345 tests. Nothing proves that the model matches SGLang.
- Not covered: scheduler liveness, GPU runs, page sizes above 1 on a real server, concurrency, sharded or SWA pools, and zero-output requests.

## Run it

```bash
python tools/verify_capacity.py    # applies bug/fix.patch, runs real bodies, prints 6345
python proof/inspect_evidence.py   # summarizes the retained prover receipts
bash proof/prove.sh                # needs intent-check and a prover session
lean lean/SglangWedge.lean         # Lean 4.15.0, core only; silent = all theorems checked
```

## Layout

```
bug/      write-up, evidence, fix.patch, pinned upstream scheduler.py
proof/    model.py, spec.k, mutation.k, receipts, PROOF.md, SCOPE.md, upstream sources
tools/    verify_capacity.py: 6,345-case regression on the real patched bodies
lean/     SglangWedge.lean: the same theorem, proved independently in Lean 4
docs/     interactive presentation
```

Upstream SGLang sources are Apache-2.0 and keep their original notices (`bug/baseline/LICENSE`, `proof/upstream/LICENSE`). The pinned upstream commit is `sgl-project/sglang@fd5c52588ff2399d25d31e49cf2121863cf620e3`.
