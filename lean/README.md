# Lean 4 proof

A second, independent proof of the fix's arithmetic, in core Lean 4 (no Mathlib).

```bash
lean SglangWedge.lean     # Lean 4.15.0; silent output = every theorem checked
```

| Theorem | Says |
| --- | --- |
| `patched_admits` | After the fix, the gate admits every request in the domain |
| `patched_capacity_binds` | When memory limits the output, exactly R + 1 tokens stay free |
| `patched_requested_binds` | Small requests keep exactly the length they asked for |
| `patched_grant_nonneg` | The output allowance is never negative |
| `original_free_eq_one` | Before the fix, exactly 1 token stays free, for every T, I, P |
| `original_blocked` | So the original code is refused for every such input |

Domain (same as the K claims): `I >= 0, P >= 1, R >= 1, M >= 0, T >= I + P + R + 1`.

The `example`s at the end check the recorded witness: 600 / 560 / 1 / 1 / 1000 gives 38 output, 1 free, refused before the fix, and 37 output, 2 free, admitted after.

Checks we ran:
- `#print axioms` on the main theorems lists only `propext` and `Quot.sound`: no `sorry` and no `native_decide`.
- Control: claiming that the original code admits every request fails, and `omega` prints a counterexample.
- `clip` here was compared with `proof/model.py` on 220,320 inputs (both versions, including negative values), with zero mismatches.

Scope is the same as the K proof. This is the hand-extracted arithmetic, not the production Python, and it does not cover scheduler liveness. What Lean adds is the bug's side, proved for every input: the K run checked one negative-control witness.
