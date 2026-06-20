/-
Layer 1: the abstract hash and the Merkle path (PLAN.md, P1.*).

Models `Hashable`, `empty_root`, and `MerklePath` from
`incrementalmerkletree/src/lib.rs`. The hash `combine` is an unconstrained
abstract function (no algebraic axioms), so every theorem here holds for any
hash. The level argument to `combine` is modeled as a `Nat` (a plain height
index) rather than a `BitVec`, which avoids the wraparound side-conditions a
`BitVec 8` level would introduce in the empty-root recurrence.
-/
import Imt.Basic

namespace Imt

/-- A type usable as a node value in a Merkle tree (Rust `Hashable`).
    `combine level a b` is the parent of `a` and `b`, both at `level`. -/
class Hashable (H : Type) where
  emptyLeaf : H
  combine : Nat → H → H → H

variable {H : Type}

/-- Root of an all-empty subtree of the given height (Rust `Hashable::empty_root`).
    `emptyRoot 0 = emptyLeaf` and each level combines the level below with itself. -/
def emptyRoot [Hashable H] : Nat → H
  | 0 => Hashable.emptyLeaf
  | (n + 1) => Hashable.combine n (emptyRoot n) (emptyRoot n)

/-- P1.1: the empty-root recurrence. -/
@[simp] theorem emptyRoot_succ [Hashable H] (n : Nat) :
    (emptyRoot (n + 1) : H) = Hashable.combine n (emptyRoot n) (emptyRoot n) := rfl

@[simp] theorem emptyRoot_zero [Hashable H] :
    (emptyRoot 0 : H) = Hashable.emptyLeaf := rfl

/-- The reference Merkle root (PLAN.md, P1.2): the root of the perfect depth-`d`
    tree whose leaves are `leaves`, padded on the right with `emptyLeaf`. The
    left subtree takes the first `2^d` leaves, the right subtree the rest. This
    is the naive, obviously-correct model that the efficient representations
    (frontier, witness, shard tree) are proved to compute. -/
def merkleRoot [Hashable H] : Nat → List H → H
  | 0, leaves => leaves.headD Hashable.emptyLeaf
  | (d + 1), leaves =>
      Hashable.combine d
        (merkleRoot d (leaves.take (2 ^ d)))
        (merkleRoot d (leaves.drop (2 ^ d)))

/-- At depth 0 the root is the single (first) leaf, or `emptyLeaf` if absent. -/
@[simp] theorem merkleRoot_zero [Hashable H] (leaves : List H) :
    merkleRoot 0 leaves = leaves.headD Hashable.emptyLeaf := rfl

/-- The reference root of an empty leaf list is the empty root: an all-empty
    tree hashes to `emptyRoot d`. -/
@[simp] theorem merkleRoot_nil [Hashable H] (d : Nat) :
    merkleRoot d ([] : List H) = emptyRoot d := by
  induction d with
  | zero => rfl
  | succ d ih => simp [merkleRoot, ih]

/-- Wrap `digest` (the root of a complete subtree rooted at level `start`) with
    empty subtree roots at levels `start, start+1, ..., start+count-1`. This is
    the spine a frontier climbs once its complete left part is reduced to a
    single root: every higher level pairs the running digest with an empty
    subtree on the right. -/
def spineFrom [Hashable H] (digest : H) (start count : Nat) : H :=
  (List.range count).foldl
    (fun acc j => Hashable.combine (start + j) acc (emptyRoot (start + j))) digest

/-- A path from a leaf to a root (Rust `MerklePath<H, DEPTH>`). The length
    invariant (`pathElems.length = depth`) is enforced by `fromParts`. -/
structure MerklePath (H : Type) (depth : Nat) where
  pathElems : List H
  position : Position

/-- Rust `MerklePath::from_parts`: succeeds only when the path has exactly
    `depth` elements. -/
def MerklePath.fromParts (elems : List H) (pos : Position) (depth : Nat) :
    Option (MerklePath H depth) :=
  if elems.length = depth then some ⟨elems, pos⟩ else none

/-- P1.4: a constructed `MerklePath` always has length equal to its depth. -/
theorem MerklePath.fromParts_length {depth : Nat} (elems : List H) (pos : Position)
    (h : (MerklePath.fromParts elems pos depth).isSome) : elems.length = depth := by
  unfold MerklePath.fromParts at h
  by_cases hlen : elems.length = depth
  · exact hlen
  · simp [hlen] at h

/-- Rust `MerklePath::root`: fold the leaf up through the sibling path, with the
    bit of the position at each level selecting whether the running digest is the
    left or right argument to `combine`. -/
def MerklePath.root [Hashable H] {depth : Nat} (p : MerklePath H depth) (leaf : H) : H :=
  p.pathElems.zipIdx.foldl
    (fun root hi =>
      let (h, i) := hi
      if ((p.position.val >>> i) &&& 1) == 0 then
        Hashable.combine i root h
      else
        Hashable.combine i h root)
    leaf

/-- An empty path leaves the leaf unchanged (the depth-0 base case of P1.3). -/
@[simp] theorem MerklePath.root_nil [Hashable H] (pos : Position) (leaf : H) :
    MerklePath.root (⟨[], pos⟩ : MerklePath H 0) leaf = leaf := by
  simp [MerklePath.root]

end Imt
