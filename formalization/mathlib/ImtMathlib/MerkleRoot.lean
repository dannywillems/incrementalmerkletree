/-
Mathlib-dependent structural lemmas about the `merkleRoot` reference model
(PLAN.md, support for the frontier root theorem P2.3).
-/
import Imt.Hash
import Mathlib

namespace Imt

/-- The reference Merkle root depends only on the first `2^d` leaves: padding the
    leaf list beyond the tree width does not change the root. This is the key
    structural fact behind the frontier root theorem (a frontier represents a
    prefix of the leaves, and the root pads the rest with empty subtrees). -/
theorem merkleRoot_take [Hashable H] (d : Nat) (leaves : List H) :
    merkleRoot d leaves = merkleRoot d (leaves.take (2 ^ d)) := by
  induction d generalizing leaves with
  | zero => cases leaves <;> rfl
  | succ d ih =>
    have hpow : (2 : Nat) ^ d ≤ 2 ^ (d + 1) :=
      Nat.pow_le_pow_right (by norm_num) (Nat.le_succ d)
    have hsub : (2 : Nat) ^ (d + 1) - 2 ^ d = 2 ^ d := by
      rw [pow_succ]; omega
    rw [merkleRoot, merkleRoot, List.take_take, Nat.min_eq_left hpow]
    rw [ih (leaves.drop (2 ^ d)), ih ((leaves.take (2 ^ (d + 1))).drop (2 ^ d))]
    simp only [List.drop_take, List.take_take, hsub, Nat.min_self]

/-- Once the first `2^d` leaves are present, appending more does not change the
    depth-`d` root. The frontier-padding corollary of `merkleRoot_take`. -/
theorem merkleRoot_append_of_full [Hashable H] (d : Nat) (leaves extra : List H)
    (h : 2 ^ d ≤ leaves.length) :
    merkleRoot d (leaves ++ extra) = merkleRoot d leaves := by
  rw [merkleRoot_take d (leaves ++ extra), merkleRoot_take d leaves,
    List.take_append_of_le_length h]

end Imt
