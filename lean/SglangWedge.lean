/-
  SGLang one-token admission wedge: the fix, verified in Lean 4.

  Scope: this is the same scalar extraction the K proof uses
  (proof/model.py), taken from SGLang fd5c525:
    * intake:    Scheduler.init_req_max_new_tokens + allocator
                 max_new_tokens_for_memory (output clip)
    * admission: PrefillAdder.add_one_req_ignore_eos, lone request on an
                 empty baseline pool (strict gate: reject if free <= R)

  It proves the arithmetic of the fix for every integer input. It does NOT
  prove that this extraction matches the production Python, or that the
  scheduler later runs the request (liveness). Core Lean only, no Mathlib.

  Names follow the write-up:
    T  token capacity of the pool        P  page size (= per-request overhead)
    I  prompt length, already page-rounded R  admission reserve
    M  requested output length
-/

structure Inputs where
  T : Int
  I : Int
  P : Int
  R : Int
  M : Int

/-- Allocator output clip, as in proof/model.py:
    `g := cap - I - P - 1; if M < g then g := M; if g < 0 then g := 0`.
    Written with the clamp pushed into both branches, which computes the same
    value. `cap` is the capacity intake passes to the allocator. -/
def clip (cap I P M : Int) : Int :=
  if M < cap - I - P - 1 then
    (if M < 0 then 0 else M)
  else
    (if cap - I - P - 1 < 0 then 0 else cap - I - P - 1)

/-- Free tokens the lone-request admission gate sees after charging the
    prompt, one page of overhead and the full output allowance `g`. -/
def freeAfter (T I P g : Int) : Int := T - (I + P) - g

/-- Original intake: clips against the full capacity. -/
def originalGrant (x : Inputs) : Int := clip x.T x.I x.P x.M
def originalFree  (x : Inputs) : Int := freeAfter x.T x.I x.P (originalGrant x)

/-- Patched intake: subtracts the reserve before clipping
    (`token_capacity -= IGNORE_EOS_RESERVE_TOKENS`). -/
def patchedGrant (x : Inputs) : Int := clip (x.T - x.R) x.I x.P x.M
def patchedFree  (x : Inputs) : Int := freeAfter x.T x.I x.P (patchedGrant x)

/-- Admission's strict gate admits only when free > R. -/
def Admitted (x : Inputs) (free : Int) : Prop := x.R < free

/-- The theorem's domain, identical to the K claims' preconditions. -/
def Domain (x : Inputs) : Prop :=
  0 ≤ x.I ∧ 1 ≤ x.P ∧ 1 ≤ x.R ∧ 0 ≤ x.M ∧ x.I + x.P + x.R + 1 ≤ x.T

/-! ## The fix -/

/-- Main theorem: after the fix, the gate admits every request in the domain. -/
theorem patched_admits (x : Inputs) (h : Domain x) :
    Admitted x (patchedFree x) := by
  obtain ⟨hI, hP, hR, hM, hT⟩ := h
  unfold Admitted patchedFree freeAfter patchedGrant clip
  split <;> split <;> omega

/-- The output allowance is never negative. -/
theorem patched_grant_nonneg (x : Inputs) (h : Domain x) :
    0 ≤ patchedGrant x := by
  obtain ⟨hI, hP, hR, hM, hT⟩ := h
  unfold patchedGrant clip
  split <;> split <;> omega

/-- K claim `requested-binds`: small requests keep exactly what they asked for. -/
theorem patched_requested_binds (x : Inputs) (h : Domain x)
    (hsmall : x.M ≤ x.T - x.R - x.I - x.P - 1) :
    patchedGrant x = x.M := by
  obtain ⟨hI, hP, hR, hM, hT⟩ := h
  unfold patchedGrant clip
  split <;> split <;> omega

/-- K claim `capacity-binds`: when memory limits the output, exactly R + 1
    tokens stay free, one more than the strict gate requires. -/
theorem patched_capacity_binds (x : Inputs) (h : Domain x)
    (hlarge : x.T - x.R - x.I - x.P - 1 < x.M) :
    patchedFree x = x.R + 1 := by
  obtain ⟨hI, hP, hR, hM, hT⟩ := h
  unfold patchedFree freeAfter patchedGrant clip
  split <;> split <;> omega

/-! ## The bug, for every input (stronger than a single negative control) -/

/-- Before the fix, whenever memory limits the output, exactly one token is
    left free, whatever the capacity, prompt length or page size. -/
theorem original_free_eq_one (x : Inputs)
    (hT : x.I + x.P + 1 ≤ x.T) (hbind : x.T - x.I - x.P - 1 ≤ x.M) :
    originalFree x = 1 := by
  unfold originalFree freeAfter originalGrant clip
  split <;> split <;> omega

/-- So with any reserve R ≥ 1, the original code is refused, for every such input. -/
theorem original_blocked (x : Inputs)
    (hT : x.I + x.P + 1 ≤ x.T) (hbind : x.T - x.I - x.P - 1 ≤ x.M)
    (hR : 1 ≤ x.R) :
    ¬ Admitted x (originalFree x) := by
  unfold Admitted
  rw [original_free_eq_one x hT hbind]
  omega

/-! ## The recorded witness: T = 600, I = 560, P = 1, R = 1, M = 1000 -/

def witness : Inputs := ⟨600, 560, 1, 1, 1000⟩

example : originalGrant witness = 38 := by decide
example : originalFree witness = 1 := by decide
example : ¬ Admitted witness (originalFree witness) :=
  original_blocked witness (by decide) (by decide) (by decide)

example : patchedGrant witness = 37 := by decide
example : patchedFree witness = 2 := by decide
example : Admitted witness (patchedFree witness) :=
  patched_admits witness ⟨by decide, by decide, by decide, by decide, by decide⟩
