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

/-- A value below `2^k` has every bit clear at or above level `k`. Generalizes
    `getLsbD_ge`. Used by: applying `NonEmptyFrontier.root_merkleRoot_lift` to
    `ofList`, whose position `L.length - 1` is below `2^k` once `L.length <= 2^k`,
    which discharges that lemma's `hbits` hypothesis. -/
theorem getLsbD_eq_false_of_lt (p : BitVec 64) (k i : Nat)
    (hp : p.toNat < 2 ^ k) (hik : k ≤ i) : p.getLsbD i = false := by
  rw [getLsbD_eq_testBit]
  exact Nat.testBit_lt_two_pow
    (Nat.lt_of_lt_of_le hp (Nat.pow_le_pow_right (by norm_num) hik))

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

/-- A 64-bit vector has positive population count iff it is nonzero. -/
theorem popcount_pos_iff (p : BitVec 64) : 0 < popcount p ↔ p ≠ 0 := by
  rw [Nat.pos_iff_ne_zero, ne_eq, popcount_eq_zero_iff]

/-- Inclusion-exclusion for `List.countP` over two Bool predicates. -/
theorem countP_or_and {α : Type} (l : List α) (p q : α → Bool) :
    l.countP p + l.countP q
      = l.countP (fun x => p x || q x) + l.countP (fun x => p x && q x) := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    simp only [List.countP_cons]
    cases hp : p x <;> cases hq : q x <;> simp_all <;> omega

/-- Inclusion-exclusion for `popcount`: `|a| + |b| = |a ||| b| + |a &&& b|`. -/
theorem popcount_or_add_and (a b : BitVec 64) :
    popcount a + popcount b = popcount (a ||| b) + popcount (a &&& b) := by
  simp only [popcount]
  rw [countP_or_and]
  congr 1 <;>
    (apply List.countP_congr; intro i _; simp [BitVec.getLsbD_or, BitVec.getLsbD_and])

/-- Population count is monotone under `&&&` (a bitwise-and can only clear bits). -/
theorem popcount_and_le_left (a b : BitVec 64) : popcount (a &&& b) ≤ popcount a := by
  simp only [popcount]
  apply List.countP_mono_left
  intro i _ h
  rw [BitVec.getLsbD_and] at h
  simp_all

/-- Population count is monotone under `|||` (a bitwise-or can only set bits). -/
theorem popcount_le_or (a b : BitVec 64) : popcount a ≤ popcount (a ||| b) := by
  simp only [popcount]
  apply List.countP_mono_left
  intro i _ h
  rw [BitVec.getLsbD_or]
  simp_all

/-- Population count is monotone under `&&&` on the right too. -/
theorem popcount_and_le_right (a b : BitVec 64) : popcount (a &&& b) ≤ popcount b := by
  simp only [popcount]
  apply List.countP_mono_left
  intro i _ h
  rw [BitVec.getLsbD_and] at h
  simp_all

/-- For disjoint vectors, `popcount` of the union is additive. -/
theorem popcount_or_of_and_eq_zero (a b : BitVec 64) (h : a &&& b = 0) :
    popcount (a ||| b) = popcount a + popcount b := by
  have hpe := popcount_or_add_and a b
  rw [h, popcount_zero] at hpe
  omega

end Imt
