/-
Mathlib-dependent frontier root facts (PLAN.md, P2.3).

This establishes the base case of the frontier root theorem: a freshly
constructed (single-leaf) frontier computes the reference Merkle root of the
one-element leaf list. The inductive step over `append` is the remaining work.
-/
import Imt.Frontier
import ImtMathlib.MerkleRoot
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

/-- P2.3 for two leaves: a frontier built from two appends computes the
    reference Merkle root of the two-element list. -/
theorem root_two_eq_merkleRoot {H : Type} [Hashable H] (a b : H) (d : Nat) :
    ((NonEmptyFrontier.new a).append b).root (d + 1) = merkleRoot (d + 1) [a, b] := by
  rw [NonEmptyFrontier.new_append, NonEmptyFrontier.root_two_frontier]
  have hmr : merkleRoot (d + 1) [a, b] = spineFrom (merkleRoot 1 [a, b]) 1 d := by
    have h := merkleRoot_eq_spineFrom 1 [a, b] (by norm_num) d
    rwa [Nat.add_comm 1 d] at h
  rw [hmr]
  congr 1

namespace NonEmptyFrontier

/-- Build the frontier representing the leaf list `v0 :: vs` by folding `append`
    over `vs` starting from the single-leaf frontier `new v0`. This is the
    abstraction function from a non-empty leaf list to its frontier summary.

    ```text
    ofList v0 [a, b, c] = (((new v0).append a).append b).append c
    represents leaves:     [v0, a, b, c]
    ```
-/
def ofList {H : Type} [Hashable H] (v0 : H) (vs : List H) : NonEmptyFrontier H :=
  vs.foldl (fun f x => f.append x) (new v0)

/-- Each appended leaf advances the position by one. -/
theorem foldl_append_position {H : Type} [Hashable H]
    (f0 : NonEmptyFrontier H) (vs : List H) :
    (vs.foldl (fun f x => f.append x) f0).position.val
      = f0.position.val + (vs.length : BitVec 64) := by
  induction vs generalizing f0 with
  | nil => simp
  | cons x xs ih =>
    simp only [List.foldl_cons, ih, append_position, List.length_cons]
    push_cast
    ring

/-- The current leaf of a fold of appends is the last appended leaf (or the seed
    when nothing was appended). -/
theorem foldl_append_leaf {H : Type} [Hashable H]
    (f0 : NonEmptyFrontier H) (vs : List H) :
    (vs.foldl (fun f x => f.append x) f0).leaf = vs.getLastD f0.leaf := by
  induction vs generalizing f0 with
  | nil => simp
  | cons x xs ih => simp only [List.foldl_cons, ih, append_leaf, List.getLastD_cons]

/-- P2.1 (abstraction): `ofList v0 vs` sits at position `vs.length`, i.e. it
    represents the `vs.length + 1` leaves `v0 :: vs`. -/
@[simp] theorem ofList_position {H : Type} [Hashable H] (v0 : H) (vs : List H) :
    (ofList v0 vs).position.val = (vs.length : BitVec 64) := by
  simp [ofList, foldl_append_position, new]

/-- `ofList v0 vs` carries the last of `v0 :: vs` as its current leaf. -/
@[simp] theorem ofList_leaf {H : Type} [Hashable H] (v0 : H) (vs : List H) :
    (ofList v0 vs).leaf = vs.getLastD v0 := by
  simp [ofList, foldl_append_leaf, new]

end NonEmptyFrontier

end Imt
