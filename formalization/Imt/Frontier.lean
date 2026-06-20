/-
Layer 2: the Merkle frontier (PLAN.md, P2.*).

Models `NonEmptyFrontier` from `incrementalmerkletree/src/frontier.rs`: the
reduced representation of a Merkle tree as its rightmost leaf plus the stored
left-sibling subtree roots (the ommers). This module sets up the structure and
its well-formedness invariant; the `append`/`root` algorithms and the root
correctness theorem (P2.3) build on this.
-/
import Imt.Basic

namespace Imt

/-- Rust `NonEmptyFrontier`: the most recently appended `leaf` at `position`,
    plus the stored left siblings (`ommers`) needed to witness it, ordered from
    lowest level to highest. -/
structure NonEmptyFrontier (H : Type) where
  position : Position
  leaf : H
  ommers : List H

namespace NonEmptyFrontier

variable {H : Type}

/-- Well-formedness (P2.1): a frontier stores exactly `popcount(position)` ommers
    (Lemma 3.7 / `from_parts`). -/
def WF (f : NonEmptyFrontier H) : Prop :=
  f.ommers.length = popcount f.position.val

/-- Rust `NonEmptyFrontier::new`: a single leaf at position 0 with no ommers. -/
def new (leaf : H) : NonEmptyFrontier H :=
  { position := ⟨0⟩, leaf := leaf, ommers := [] }

@[simp] theorem new_position (leaf : H) : (new leaf).position = ⟨0⟩ := rfl

@[simp] theorem new_leaf (leaf : H) : (new leaf).leaf = leaf := rfl

@[simp] theorem new_ommers (leaf : H) : (new leaf).ommers = ([] : List H) := rfl

/-- A freshly constructed single-leaf frontier is well-formed. -/
theorem new_wf (leaf : H) : (new leaf).WF := by
  show (0 : Nat) = popcount (0 : BitVec 64)
  decide

end NonEmptyFrontier

end Imt
