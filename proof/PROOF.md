# SOUND-BUT-LIMITED

The remote K prover established the admission arithmetic of the explicit SGLANG-06 extraction. It did not verify the complete SGLang patch or service. Same-agent review checked the final artifacts and retained evidence. No independent audit or separate replay was performed.

## Proved property

The two claims in `spec.k` cover all nonnegative requested output lengths. Inputs are integer capacity `T`, page-rounded prompt `I`, page size `P`, and reserve `R`. The permitted domain is `I >= 0`, `P >= 1`, `R >= 1`, and `T >= I + P + R + 1`. The model subtracts `R` from the intake capacity, clips generation, and computes the lone-request strict reserve gate. Both claims finish with `blocked = false`. Their final states fix the clipped output length and remaining free tokens exactly.

This is partial correctness. The theorem excludes scheduler liveness, allocator dispatch, GPU execution, page allocation, concurrent batches, SWA, Mamba, sharded pools, and inputs below the stated capacity. `SCOPE.md` records the connection limits.

## Proof-extension inventory

There are no local operational rules, simplification rules, auxiliary lemmas, summaries, or trusted claims. `spec.k` imports only the immutable bundled `MPY` semantics. `verification.k` is an unused empty inventory module. The executed terms are generated from `model.py`. That model expands integer minimum and maximum into ordinary conditionals. It is a deliberate extraction, with no claim of a machine-checked refinement from the entire production function.

## Commands and actual results

Session `a3627280-2af6-4efe-8492-01f45c278a3c` pins `minipy` at `d4d75049838b`. The service reported K `7.1.337`.

```text
intent-check prove --session a3627280-2af6-4efe-8492-01f45c278a3c --spec inputs/sglang06/spec.k --spec-module RUN2-SGLANG06-SPEC
task: 75db8b39-4050-4364-b256-0f526b591f0c
status: completed
result: proved
error: null
tool: kprove
exitCode: 0
stdout: #Top (KAST)
```

The final positive submission used no depth bound and no claim exclusions or admissions. Both claims were selected. The retained `evidence/patched-proof.json` contains the full server result, stdout, and stderr. The final `spec.k` SHA-256 is `9341b7533204adb51cb728ca146b29955abc57589aaf721a39c175fc717e28a5`.

```text
intent-check prove --session a3627280-2af6-4efe-8492-01f45c278a3c --spec inputs/sglang06/mutation.k --spec-module RUN2-SGLANG06-MUTATION
task: 524a9487-e4ae-440c-812a-ebde572fedf4
status: completed
result: notProved
error: null
tool: kprove
exitCode: 1
```

The mutation executes the original capacity assignment with capacity 600, rounded prompt 560, page size 1, reserve 1, and requested output 1000. It deliberately requires `blocked = false`. The retained residual instead contains `max_new_tokens = 38`, `min_free_tokens = 1`, and `blocked = true`. This is a reachable failing postcondition, not an error or timeout. See `evidence/original-negative-control.json` and the small extracted residual beside it.

Earlier attempts retained in the session used symbolic `min`/`max` directly and left their generic function guards unresolved. They are not used as positive evidence. The final conditional form closed in the same session. Five proof attempts were used, leaving 45 of the configured 50 at final submission. No new session bypassed a limit.

## Review gates

Gate A passes for the model. The submitted terms execute the model body under fixed semantics. All observed locals and control cells are constrained. The precondition is satisfiable, for example at the recorded witness. The mutation changes the body actually submitted and produces the expected failing final state. No added theory supplies the result.

Gate B is limited relative to the full repair request. The claims cover the model's complete stated domain, but the production-to-model connection remains a reviewed extraction with finite tests. They do not establish the original full SCHED-P20 liveness contract. The final status is therefore SOUND-BUT-LIMITED.

Gate C passes for the stated limited result. Exact sources, source hashes, commands, task IDs, full results, and exclusions are retained. Standard integer arithmetic and the pinned MiniPy semantics are trust boundaries. The production extraction assumptions in `SCOPE.md` remain assumptions.

## Empirical evidence and unresolved work

`python tools/verify_capacity.py` applies the real candidate patch and extracts the actual scheduler intake plus allocator clip. It reproduces output 38/free 1 before the patch and output 37/free 2 afterward. It checks 6,345 baseline scalar cases across page sizes 1, 2, 4, 8, and 16. These finite checks preserve the strict admission margin in their tested domain. They do not replace a universal source-refinement proof.

The patch is a candidate against SGLang `fd5c52588ff2399d25d31e49cf2121863cf620e3`. It still needs full project tests and an isolated server run, including zero-output requests, very small capacities, nonbaseline allocators, and surrounding scheduler behavior. A future article can accurately say that the extracted arithmetic was formally verified. It cannot say that the complete generated production patch was formally verified.
