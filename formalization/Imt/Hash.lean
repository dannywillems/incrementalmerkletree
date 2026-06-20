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

end Imt
