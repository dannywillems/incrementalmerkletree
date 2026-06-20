/-
Mathlib-dependent frontier root facts (PLAN.md, P2.3).

This establishes the base case of the frontier root theorem: a freshly
constructed (single-leaf) frontier computes the reference Merkle root of the
one-element leaf list. The inductive step over `append` is the remaining work.
-/
import Imt.Frontier
import Mathlib

namespace Imt

/-- The spine-root recurrence: one more level wraps the spine in a combine with
    the empty subtree root on the right. -/
theorem spineRoot_succ {H : Type} [Hashable H] (leaf : H) (d : Nat) :
    spineRoot leaf (d + 1) = Hashable.combine d (spineRoot leaf d) (emptyRoot d) := by
  simp only [spineRoot, List.range_succ, List.foldl_append, List.foldl_cons, List.foldl_nil]

/-- The left spine of a single leaf is exactly the reference Merkle root of the
    one-element leaf list. -/
theorem spineRoot_eq_merkleRoot {H : Type} [Hashable H] (leaf : H) (depth : Nat) :
    spineRoot leaf depth = merkleRoot depth [leaf] := by
  induction depth with
  | zero => simp [spineRoot]
  | succ d ih =>
    have h1 : (1 : Nat) ≤ 2 ^ d := Nat.one_le_two_pow
    rw [spineRoot_succ, ih, merkleRoot,
      List.take_of_length_le (by simpa using h1),
      List.drop_eq_nil_of_le (by simpa using h1), merkleRoot_nil]

/-- P2.3 (base case): a freshly constructed single-leaf frontier computes the
    reference Merkle root of its one-element leaf list. -/
theorem root_new_eq_merkleRoot {H : Type} [Hashable H] (leaf : H) (depth : Nat) :
    (NonEmptyFrontier.new leaf).root depth = merkleRoot depth [leaf] := by
  rw [NonEmptyFrontier.root_new, spineRoot_eq_merkleRoot]

/-- P2.3 (base case), lifted to the depth-bounded `Frontier`: a single-leaf
    frontier computes the reference Merkle root of its one-element leaf list. -/
theorem Frontier.singleton_root_eq_merkleRoot {H : Type} [Hashable H]
    (leaf : H) (depth : Nat) :
    (Frontier.singleton leaf : Frontier H depth).root = merkleRoot depth [leaf] := by
  rw [Frontier.singleton_root, root_new_eq_merkleRoot]

end Imt
