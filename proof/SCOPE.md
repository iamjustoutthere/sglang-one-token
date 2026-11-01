# SGLANG-06 arithmetic extraction

## Property in plain language

The model receives an empty pool capacity, an already rounded prompt size, a page size, a reserve, and a requested output length. These are whole numbers. The page size and reserve are positive. The capacity can hold the rounded prompt, one page, the reserve, and one further token.

The patched model reduces the intake capacity by the reserve. It clips the output length, then executes the lone-request admission calculation. For every permitted input, that calculation leaves more tokens free than the reserve and does not reject the request at this gate. The two claims cover requested lengths on both sides of the clipping limit. They establish partial correctness. They do not prove scheduler progress or service termination.

## Program boundary

`model.py` is an explicit scalar extraction from the pinned SGLang allocator clip and the first iteration of `add_one_req_ignore_eos`. It is not a verbatim complete upstream function. `paged_input` is the page-rounded prompt before the admission page overhead. The unsharded, non-SWA, baseline allocator, disabled-radix-cache path is assumed. The model starts after these path conditions and input values are established.

The proposed production patch changes `scheduler.py` at intake. It subtracts `IGNORE_EOS_RESERVE_TOKENS` from the capacity passed to the allocator for that baseline path. This proof does not execute the production scheduler, allocator dispatch, request objects, the memory budget's earlier gate, or any GPU code. It therefore supports the candidate patch's arithmetic, not a claim that the whole patch is formally verified.

## Input domain and observations

Capacity, rounded prompt, page size, reserve, and requested output are integers. The prompt and requested output are nonnegative. Page size and reserve are at least one. Capacity is at least prompt plus page plus reserve plus one. Cases below this capacity are outside this claim and still need request rejection or another admission analysis.

The observable results are adjusted capacity, clipped output length, remaining free tokens, and the blocked flag. The claims preserve input bindings, heap, stack, return state, exception state, exit code, environment, and allocation counters. No output, allocation, exception, retry, or concurrent task is modeled.

## Contract reading and connection limits

The bug contract is that a request accepted at intake must be schedulable on an otherwise empty pool. The theorem checks only the strict reserve gate for a lone baseline request. It assumes the allocator reports the configured capacity, prompt prefix length is zero, per-request overhead is one page, and no Mamba or request-slot reserve applies. These assumptions come from the recorded baseline reproduction and must be checked for any new deployment.

The AST in `spec.k` is generated directly from `model.py` by `build_artifacts.py`. The source's integer `max(0, min(requested, bound))` is expanded into two ordinary conditionals in the model. For integer inputs these select the same value by the definition of minimum and maximum. No local operational rules, trusted claims, summaries, or execution bridges are added. MiniPy provides the integer arithmetic, comparisons, assignments, and conditionals. Production Python and MiniPy differ in many other features, which this extraction does not use. Finite source-extraction regression checks are separate evidence and do not prove a universal refinement from SGLang to this model.
