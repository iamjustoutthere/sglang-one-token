# The SGLang request that fit at intake and could never enter the pool

Consider a scalar example of the final intake calculation. An empty token pool has capacity 600, page size one, and an admission reserve of one. The rounded prompt occupies 560 tokens, and the calculation receives an output limit of 1,000. For an `ignore_eos` request on the path examined here, intake clips the allowance to 38. The prompt, generation, and accounting overhead fit within capacity. Yet admission refuses the request because it leaves exactly one token free, and that stage requires more than one.

The example isolates the arithmetic retained for SGLang issue SGLANG-06, after earlier production limits. The historical server reproduction used an omitted output limit, which reaches the same clip. With the radix cache disabled, that request remained incomplete after 30 seconds. An ordinary request queued afterward also waited. The server still answered its health check. Aborting the first request let the ordinary request complete. The frozen report records the failure and two successful controls in three runs. [SGLANG-06 report](https://github.com/nlp-research-rosu/bug-catalog/blob/c6eb64fbcbb0ade8b6fc22867ef7106acb35665b/reports/sglang06.md)

The disagreement sits between two promises. Intake chooses an output budget intended to fit an otherwise empty pool. Admission then decides whether current resources can support that budget. Waiting is useful when other work can release memory. For this request, the pool is already empty and admission still says no. Nothing needs to finish before it can start, so there is no ordinary completion that will make the same calculation succeed.

The candidate repair reduces the intake allowance by one more token while preserving admission's strict reserve gate. The corrected example permits 37 output tokens and leaves two free. Retained tests check the actual intake and allocator bodies in 6,345 finite cases. A later K proof establishes the corresponding integer property for an explicit extraction. That theorem covers the extracted arithmetic, with source and scheduler assumptions described below. The original discovery remains attributed to property screening.

## What intake is promising

An inference server needs space for a prompt's key/value cache and for the tokens it may generate. SGLang bounds `max_new_tokens` before placing the request into the scheduling workflow. The relevant intake function first applies configured and context-related limits, then asks the selected allocator to clip generation against the empty-pool memory budget. An omitted output limit starts with a large internal value and passes through these same clamps.

The code explicitly connects this calculation to scheduling: “Keep this bound consistent with PrefillAdder's admission budget.” This comment matters because a locally valid upper bound is insufficient. The bound must also produce a request that the downstream admission calculation can accept when all the capacity assumed at intake is available. [Pinned intake source](https://github.com/sgl-project/sglang/blob/fd5c52588ff2399d25d31e49cf2121863cf620e3/python/sglang/srt/managers/scheduler.py#L2688-L2735)

There are two page-related charges to distinguish. First, the prompt occupies whole pages. If its raw length is not a multiple of the page size, the allocator rounds that length upward. Second, admission charges an additional page of per-request overhead on the unsharded baseline path. A prompt that occupies 35 pages therefore consumes those 35 pages before the extra overhead page enters the budget. Treating the overhead as part of prompt rounding would hide an independent term.

The base allocator's memory bound subtracts both the rounded prompt and one page, then subtracts one further token. It takes the minimum with the already limited requested output and clamps the result to zero. The production source thus handles more than the one failing example: a small explicit output limit can survive unchanged, while a large one is reduced to the memory ceiling. [Pinned allocator source](https://github.com/sgl-project/sglang/blob/fd5c52588ff2399d25d31e49cf2121863cf620e3/python/sglang/srt/mem_cache/allocator/base.py#L88-L105)

The defect requires this memory ceiling to determine the final allowance. If an earlier context limit or an explicit small output limit wins, extra space may remain at admission. The historical configuration used a 600-token pool below the model's context length. That made the pool budget decisive. This condition explains why the same server can complete short requests while a request with an omitted or sufficiently large output limit obstructs its queue.

The request also needs the specialized path. In the pinned code, `ignore_eos` together with a disabled tree cache dispatches to `add_one_req_ignore_eos`. EOS is the model's end-of-sequence condition. On this path, ignoring EOS makes the budget account for the full remaining output allowance, using a ratio of 1.0 rather than an estimate of earlier completion. Enabling the radix cache selects other admission logic, which is why the cache-on control is informative. [Pinned dispatch](https://github.com/sgl-project/sglang/blob/fd5c52588ff2399d25d31e49cf2121863cf620e3/python/sglang/srt/managers/schedule_policy.py#L1395-L1402)

## Following the one-token disagreement

Use five quantities for the baseline calculation:

| Symbol | Meaning |
| --- | --- |
| `T` | Configured token capacity used at intake |
| `I` | Prompt size after rounding upward to whole pages |
| `P` | Page size, also the baseline per-request overhead |
| `R` | Admission reserve, one token in the pinned source |
| `M` | Nonnegative output limit supplied to the scalar clipping calculation |

Let `G` be the output allowance produced by the allocator. Before the patch, the calculation is:

```text
G = max(0, min(M, T - I - P - 1))
```

For the scalar witness, `T = 600`, `I = 560`, `P = 1`, `R = 1`, and `M = 1000`. The memory ceiling is `600 - 560 - 1 - 1 = 38`. The requested 1,000 exceeds that ceiling, so `G = 38`. Earlier production clamps can reduce a client's 1,000 before the allocator call. Any value reaching this call at or above 38 gives the same old allowance. The scalar witness isolates that final clipping relationship rather than modeling the preceding limits.

Now follow the request into admission. Its uncached prompt requires 560 tokens. Its extra page costs one. With no running work, no admitted candidates, and no output yet generated, the remaining capacity before projected generation is `600 - 560 - 1 = 39`. The budget then charges the full allowance of 38, leaving one token.

The admission loop evaluates a minimum-free budget as requests reach their projected completion points. For the lone request, there is only one entry. The batch size is one, and no earlier completion contributes freed tokens. Its comparison reduces to:

```text
min_free_tokens = 39 - 38 = 1
reject if min_free_tokens <= R * 1
reject because 1 <= 1
```

The equality is the defect's boundary. The allocator's extra token produces a remainder of one, while the downstream gate admits only a remainder strictly greater than the reserve. Both sides reserve space, but their acceptance boundaries disagree. The constant and strict comparison are visible in the retained admission source. [Pinned reserve loop](https://github.com/sgl-project/sglang/blob/fd5c52588ff2399d25d31e49cf2121863cf620e3/python/sglang/srt/managers/schedule_policy.py#L1241-L1303)

The historical output-37 control changes only the generation allowance at this point. Prompt and overhead still consume 561 tokens, leaving 39 before generation. Subtracting 37 leaves two, and `2 <= 1` is false. The request completed. This adjacent successful case matters because it moves across exactly the disputed inequality. A much smaller request could also complete, but it would locate the boundary less precisely.

The radix-on control answers a separate question. It keeps the troublesome request while selecting another admission path, and that request also completed. Taken together, the controls locate the failure in the interaction between this clip and this specialized gate. They do not show that every allocator or cache configuration follows the same formula. The report's three repeated runs concern this CPU configuration and its controls, rather than a sweep across deployment layouts.

The same calculation explains more than the chosen numbers. Let `A` be the available token count reported for the empty pool. When the old memory ceiling binds and remains nonnegative:

```text
G        = T - I - P - 1
min_free = A - I - P - G
         = A - I - P - (T - I - P - 1)
         = A - T + 1
```

The rounded prompt and the overhead page cancel. Under the baseline assumption `A = T`, the result is always one. A shorter prompt can therefore fail to help: if the memory ceiling still binds, intake grants the recovered space to generation. Increasing capacity can have the same effect. Either change must alter the binding limit or the accounting relationship to create additional margin.

Page size one makes the witness easy to inspect, but it does not create the algebraic disagreement. For an illustrative page-size-16 calculation, a raw prompt of 553 tokens rounds to `I = 560`. At capacity 600, the old ceiling becomes `600 - 560 - 16 - 1 = 23`. Admission starts with `600 - 560 - 16 = 24` and again leaves one. This is an arithmetic illustration, not a recorded GPU or paged-server run. The historical server reproduction used page size one.

The source history recorded in the report helps explain how the disagreement appeared. A change added the per-request page overhead to this specialized admission path. Before that charge, the old intake ceiling left an additional page of slack at the gate. Charging the page exposed the mismatch between the remaining single token and the strict reserve. The repair therefore needs to preserve the new overhead while restoring agreement about the margin.

The multi-request calculation explains why the admission code is more elaborate than this subtraction. It collects remaining generation amounts, orders projected completion points, and checks the minimum free space before adding capacity released by completed requests. At each point, `bs` counts requests still contributing generation demand. For the lone positive-output request, that machinery reduces to one iteration: `tokens_left = G`, `bs = 1`, and `tokens_freed = 0`. No projected release enters before the failing check. The simplification follows from the starting state, rather than an assumption that other requests generally have no cost.

## Why one unadmittable request affects later work

The first request has not filled the pool. It has not begun generation at all. The failure is a decision made against projected usage, before the request enters execution. This distinguishes the case from a workload that starts successfully and later exhausts memory.

In the retained first-come, first-served waiting loop, a non-`CONTINUE` result stops examination of later candidates during that pass. The head returns `NO_TOKEN`, so the short request behind it does not get an independent opportunity to fit. This ordering makes the head's admission result relevant to the availability of otherwise manageable work. [Pinned waiting loop](https://github.com/sgl-project/sglang/blob/fd5c52588ff2399d25d31e49cf2121863cf620e3/python/sglang/srt/managers/scheduler.py#L4274-L4295)

The empty case is retried. The pinned loop sets `batch_is_full` on `NO_TOKEN` only when there is admitted or running work, and the scheduler also clears that flag when the running batch is empty. Resetting the flag cannot correct this particular failure. A new pass obtains the same empty capacity, reads the same clipped allowance, and returns the same rejection. The gate itself supplies the persistent obstruction.

This is the significance of analyzing a lone request. With concurrent requests, refusal can be temporary because a completion changes available capacity. With an empty baseline pool, available capacity already equals the capacity used to size the request. Under unchanged inputs, a retry cannot discover the extra token it needs. The source argument establishes that repeated evaluation of this gate keeps rejecting the request. It is not a theorem about every scheduler transition, cancellation policy, or possible external intervention.

The historical abort supplies a concrete intervention. The test used the blocked request's ID to remove it, then observed the ordinary request complete with HTTP 200. A timeout alone would leave several explanations open, including slow execution or a disconnected client. Removal of the named queue head followed by restored progress ties the later request's delay to that head.

The successful health response measures another behavior. The process can service a health route while generation scheduling repeatedly refuses the same request. The evidence supports a local, reproducible obstruction under a narrow configuration. It does not measure a production outage, affected customers, or a general throughput collapse.

The catalog's SCHED-P20 property expresses the larger obligation: with no running request, no chunk in flight, and an unpaused engine, a validated head should become admitted within a bounded number of steps. Its more specific case addresses this radix-off, `ignore_eos`, empty-pool boundary. The intake comment supplies the consistency promise, and the worked calculation exposes a necessary condition that the original code violates. [SCHED-P20](https://github.com/nlp-research-rosu/bug-catalog/blob/c6eb64fbcbb0ade8b6fc22867ef7106acb35665b/properties/sglang/SCHED-P20.md)

## Reserving the same margin at intake

One apparent repair changes the admission comparison from `<=` to `<`. The old request then passes because one is not less than one. That changes the resource guarantee, however. The reserve is intended for corner cases in allocation accounting, and the property explicitly rejects removing it to make the request run. A successful response alone would not show that a repair preserves this margin.

The distinction matters on paged pools because budgeted token counts and physical allocation increments need not advance together. Extending a sequence can require a whole page even when the immediate token demand is smaller. SCHED-P20 uses that concern to reject weakening the reserve as a repair. Preserving the strict gate keeps the existing safety obligation intact while intake becomes more conservative. It does not establish that the complete page allocator is safe for every layout.

The candidate instead subtracts `IGNORE_EOS_RESERVE_TOKENS` from the capacity passed to the allocator. The allocator still performs its existing prompt rounding, page charge, extra-token subtraction, and output minimum. Admission retains its original comparison. The change is scoped to disabled radix cache, `ignore_eos`, a non-SWA configuration, and shard widening equal to one. [Candidate patch](fix.patch)

Writing the adjusted capacity as `T - R` makes the relationship clear:

```text
B = T - R - I - P - 1
G = max(0, min(M, B))
F = T - I - P - G
```

Here `B` is the corrected memory ceiling and `F` is the lone-request free amount at the gate. When memory determines the allowance, `G = B`, giving:

```text
F = T - I - P - (T - R - I - P - 1)
  = R + 1
```

The extra one remains necessary because admission requires strict inequality. Reserving exactly `R` free tokens would still reach the rejecting boundary. Subtracting `R` before the allocator's existing extra-token charge produces `R + 1`, which passes without changing that boundary.

In the 600-token example, the adjusted capacity is 599. The allocator returns `599 - 560 - 1 - 1 = 37`. The real pool still holds 600 tokens, so admission computes `600 - 560 - 1 - 37 = 2`. The patch changes what intake promises, not the pool's physical capacity. Passing a smaller capacity into the clip deliberately leaves the downstream margin available.

The other clipping regime matters too. If `M <= B`, the request keeps its smaller output allowance. Then `F = T - I - P - M`, which is at least `R + 1` because `M <= B`. The repair therefore preserves requests below the corrected ceiling. A request between the old and new ceilings may receive a smaller allowance, which is the intended correction to an allowance that the baseline gate could not honor.

The placement also preserves surrounding intake behavior. Earlier configured and context limits still run before the allocator call. Afterward, intake still restores `min_new_tokens <= max_new_tokens` if clipping reduced the maximum. The diff leaves cache-enabled requests, requests without `ignore_eos`, hybrid-SWA configurations, and wider shards outside the new adjustment. These preservation claims follow from the patch's condition and unchanged statements. The finite validation exercises the selected baseline path and does not test all those other configurations.

Using the admission constant also preserves the relationship if the reserve changes. A fixed ceiling ending in `- P - 2` would fix the current `R = 1` example while leaving a future mismatch possible. With `R = 2`, its fixed remainder of two would again fail the strict gate. Deriving the intake adjustment from `R` keeps the margin one above the downstream reserve.

The capacity domain needs an explicit boundary. The following proof assumes `T >= I + P + R + 1`, so `B >= 0`. At equality, the corrected ceiling is zero and the scalar calculation still leaves `R + 1`. Below that domain, clamping generation to zero cannot guarantee sufficient space for the prompt and margins. Those inputs need rejection or a separate admission analysis. The arithmetic result does not settle the production lifecycle of zero-output requests.

Zero also exposes a concrete difference between the scalar program and the full reserve loop. Production's helper omits a request state when its remaining output is nonpositive. A lone zero-output request therefore need not execute the loop iteration used for the positive-output witness. The extraction still computes a free amount and a rejection flag at zero. That extension is useful for a total integer claim, but it does not prove that a zero-output request follows the same production transitions. Runtime coverage must address that behavior directly.

## What the retained checks actually execute

The local validation first applies the candidate diff to a temporary copy of the pinned source. It then extracts the real `init_req_max_new_tokens` and base allocator `max_new_tokens_for_memory` bodies. Small test objects provide request fields and allocator dispatch, while an independent calculation checks the resulting lone-request free amount. The retained result records output 38/free 1 before the change and output 37/free 2 afterward. [Validation record](validation.json)

The broader finite check samples page sizes 1, 2, 4, 8, and 16, several capacities, prompt lengths, and output limits including omission, zero, small values, and a large value. It filters cases to those with enough capacity for the rounded prompt and required margins. All 6,345 retained cases keep output nonnegative and leave more than one token free after the patch. These checks connect the proposal to actual function bodies and exercise real prompt rounding.

They do not execute `PrefillAdder` as a complete object, allocate physical cache pages, or run the scheduler. Request objects and dispatch are supplied by the harness, and the gate's arithmetic is checked independently. The historical model-server reproduction and these tests answer different questions. The first shows the queue symptom on the original system. The second checks the candidate's intake calculation across finite source-extracted cases.

## A theorem about the extracted decision

The later proof package makes the arithmetic boundary explicit. Its inputs are integers `T`, `I`, `P`, `R`, and `M`, under precisely these conditions:

```text
I >= 0
P >= 1
R >= 1
M >= 0
T >= I + P + R + 1
```

`I` is already page-rounded. The theorem does not prove a rounding function or require `I` to be a multiple of `P`. It establishes the integer decision for all nonnegative `I` in that domain. Connecting a particular production prompt to that scalar remains a source-refinement obligation.

The submitted program is an explicit scalar extraction from the allocator clip and the lone-request reserve calculation. It assigns `token_capacity = capacity - reserve`, computes the ceiling, and implements minimum and maximum through ordinary conditionals. It finally computes `min_free_tokens` and assigns its local `blocked` observable from the `<= reserve` comparison. This model variable is separate from production's `batch_is_full` flag. The corresponding AST in the K specification is generated from the extraction, which does not execute the complete production Python methods. [Model and scope](../proof/SCOPE.md)

Expanding minimum and maximum makes the executed choice visible. The program starts with the memory ceiling, replaces it with `M` if `M` is smaller, and replaces a negative result with zero. These integer conditionals select the same value as the allocator formula. Under the theorem's capacity precondition, the ceiling is already nonnegative, so the zero clamp cannot create an unexpected third output regime. That is why the two claims can cover the domain completely without omitting the lower boundary.

The two symbolic claims match the two clipping regimes. `requested-binds` assumes `M <= T - R - I - P - 1` and fixes the final allowance to `M`. `capacity-binds` assumes the strict opposite and fixes it to the corrected memory ceiling. Their union covers every nonnegative requested output in the stated capacity domain, including equality in the first claim. Both constrain the final free amount exactly and finish with `blocked = false`. The derivation above explains why those postconditions follow.

The remote task `75db8b39-4050-4364-b256-0f526b591f0c` completed with result `proved` and K prover exit code zero. It used the immutable bundled MiniPy semantics at `d4d75049838b`. Both claims were selected, without a final depth bound or admitted claims. There are no local operational rules, simplification rules, auxiliary lemmas, or summaries supplying the result. The evidence report retains the exact specification, source hashes, commands, and task response. [Proof report](../proof/PROOF.md)

The original-body control tests whether the submitted computation distinguishes the bug. It restores the original capacity assignment and requires `blocked = false` for `600/560/1/1/1000`. Task `524a9487-e4ae-440c-812a-ebde572fedf4` returned `notProved`, with exit code one. Its final residual contains allowance 38, minimum free one, and `blocked = true`. The body reaches a state inconsistent with the requested postcondition. This retained witness gives more information than a bare failed proof status.

The proof covers every input in its symbolic integer domain. The finite checks provide a different connection: real patched source functions participate in them. The production connection consists of the reviewed mapping to the extraction and those 6,345 finite cases. Neither establishes a universal refinement from production SGLang to the scalar program. In particular, the production reserve loop uses request state and a floating-point ratio, while the extraction receives the corresponding whole-number allowance directly.

The production connection assumes the baseline allocator, an empty pool reporting the configured capacity, no cached prefix, no previously generated output, one page of overhead, and no additional Mamba or request-slot reserve. It also assumes the selected unsharded, non-SWA path. The proof omits the earlier memory-budget gate, later admission gates, concurrency, GPU execution, and physical page allocation. A passing reserve calculation alone does not establish eventual selection or completion by the scheduler.

For that reason the retained result is `SOUND-BUT-LIMITED` relative to verification of the complete production repair. The arithmetic theorem succeeded. Full project tests, an isolated patched-server run, broader allocator review, and a source-refinement argument remain outside it. The catalog's SCHED-P20 liveness sketches are useful specifications for those obligations, but they are not claims discharged by this K run.

The useful regression boundary now follows directly from the failure: obtain the largest allowance from real intake, then check it against real admission on an empty baseline pool while preserving the strict reserve. A short output test alone can miss the disagreement. The recorded one-token-lower and cache-on controls explain why. They move away from the failing boundary or select a different path, while the candidate corrects the promise that created the unadmittable head.
