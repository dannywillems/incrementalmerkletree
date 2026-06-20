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

/-- Bits at or beyond the width are clear. -/
theorem getLsbD_ge (p : BitVec 64) (i : Nat) (h : 64 ≤ i) : p.getLsbD i = false := by
  rw [getLsbD_eq_testBit]
  exact Nat.testBit_lt_two_pow
    (Nat.lt_of_lt_of_le p.isLt (Nat.pow_le_pow_right (by norm_num) h))

/-- A 64-bit vector has zero population count iff it is the zero vector. -/
theorem popcount_eq_zero_iff (p : BitVec 64) : popcount p = 0 ↔ p = 0 := by
  rw [popcount_eq_countP_testBit, List.countP_eq_zero]
  constructor
  · intro h
    have hz : p.toNat = 0 := by
      apply Nat.eq_of_testBit_eq
      intro i
      rw [Nat.zero_testBit]
      by_cases hi : i < 64
      · simpa using h i (by simp [List.mem_range, hi])
      · exact Nat.testBit_lt_two_pow
          (Nat.lt_of_lt_of_le p.isLt (Nat.pow_le_pow_right (by norm_num) (by omega)))
    exact BitVec.eq_of_toNat_eq (by simp [hz])
  · rintro rfl i _; simp

end Imt
