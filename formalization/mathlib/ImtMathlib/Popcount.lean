/-
Mathlib-dependent Layer 0 facts about `popcount` (PLAN.md, P0.4 support).

These need induction / the `Nat` and `List` libraries, so they live on the
Mathlib track rather than the core stable+beta track.
-/
import Imt.Basic
import Mathlib

namespace Imt

/-- The population count of a `w`-bit vector is at most `w`. -/
theorem popcount_le {w : Nat} (x : BitVec w) : popcount x ≤ w := by
  calc popcount x
      = (List.range w).countP (fun i => x.getLsbD i) := rfl
    _ ≤ (List.range w).length := List.countP_le_length
    _ = w := List.length_range

/-- The all-zero vector has population count zero. -/
theorem popcount_zero {w : Nat} : popcount (0 : BitVec w) = 0 := by
  simp [popcount]

end Imt
