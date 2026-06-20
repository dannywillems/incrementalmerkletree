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

/-- `merkleRoot` depends only on the first `2^d` leaves: lists agreeing on that
    prefix have the same depth-`d` root. -/
theorem merkleRoot_take_congr [Hashable H] (d : Nat) (l₁ l₂ : List H)
    (h : l₁.take (2 ^ d) = l₂.take (2 ^ d)) : merkleRoot d l₁ = merkleRoot d l₂ := by
  rw [merkleRoot_take d l₁, merkleRoot_take d l₂, h]

/-- Truncating to the first `2^d` leaves leaves the depth-`d` root unchanged. -/
theorem merkleRoot_take_self [Hashable H] (d : Nat) (l : List H) :
    merkleRoot d (l.take (2 ^ d)) = merkleRoot d l := (merkleRoot_take d l).symm

/-- A leaf list of all `emptyLeaf` (any length) hashes to the empty root. -/
theorem merkleRoot_replicate [Hashable H] (d n : Nat) :
    merkleRoot d (List.replicate n (Hashable.emptyLeaf : H)) = emptyRoot d := by
  induction d generalizing n with
  | zero => cases n <;> simp [merkleRoot, List.replicate_succ]
  | succ d ih =>
    rw [merkleRoot, List.take_replicate, List.drop_replicate, ih, ih, emptyRoot_succ]

/-- Once the first `2^d` leaves are present, appending more does not change the
    depth-`d` root. The frontier-padding corollary of `merkleRoot_take`. -/
theorem merkleRoot_append_of_full [Hashable H] (d : Nat) (leaves extra : List H)
    (h : 2 ^ d ≤ leaves.length) :
    merkleRoot d (leaves ++ extra) = merkleRoot d leaves := by
  rw [merkleRoot_take d (leaves ++ extra), merkleRoot_take d leaves,
    List.take_append_of_le_length h]

/-- Spine-extension of `merkleRoot`: when the leaves fit in a complete subtree at
    level `k`, the full depth-`(k+n)` root is the level-`k` root wrapped in a
    spine of empty subtree roots over the `n` higher levels. This is the
    "climb to the top with empty siblings" half of the frontier root theorem. -/
theorem merkleRoot_eq_spineFrom [Hashable H] (k : Nat) (leaves : List H)
    (hlen : leaves.length ≤ 2 ^ k) (n : Nat) :
    merkleRoot (k + n) leaves = spineFrom (merkleRoot k leaves) k n := by
  induction n with
  | zero => simp [spineFrom]
  | succ n ih =>
    have hle : leaves.length ≤ 2 ^ (k + n) :=
      le_trans hlen (Nat.pow_le_pow_right (by norm_num) (Nat.le_add_right k n))
    rw [show k + (n + 1) = (k + n) + 1 from by omega, merkleRoot,
      List.take_of_length_le hle, List.drop_eq_nil_of_le hle, merkleRoot_nil, ih,
      spineFrom_succ]

end Imt
