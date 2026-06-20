/-
Layer 2: the Merkle frontier (PLAN.md, P2.*).

Models `NonEmptyFrontier` from `incrementalmerkletree/src/frontier.rs`: the
reduced representation of a Merkle tree as its rightmost leaf plus the stored
left-sibling subtree roots (the ommers). This module sets up the structure and
its well-formedness invariant; the `append`/`root` algorithms and the root
correctness theorem (P2.3) build on this.
-/
import Imt.Basic
import Imt.Hash

namespace Imt

/-- The root of a single leaf padded on the right with empty subtrees up to
    `depth`: fold the leaf up the left spine, combining with `emptyRoot i` at each
    level. This is the root a fresh (no-ommer) frontier computes. -/
def spineRoot {H : Type} [Hashable H] (leaf : H) (depth : Nat) : H :=
  (List.range depth).foldl (fun acc i => Hashable.combine i acc (emptyRoot i)) leaf

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

/-- Rust `NonEmptyFrontier::root` (clean level-fold form): fold the leaf up
    through levels `0 .. depth-1`. At level `i`, a set position bit consumes the
    next ommer as the left sibling; a clear bit pairs the running digest with the
    empty subtree root `emptyRoot i` on the right. -/
def root [Hashable H] (f : NonEmptyFrontier H) (depth : Nat) : H :=
  ((List.range depth).foldl
    (fun (st : H × List H) (i : Nat) =>
      if f.position.val.getLsbD i then
        match st.2 with
        | [] => st
        | o :: rest => (Hashable.combine i o st.1, rest)
      else
        (Hashable.combine i st.1 (emptyRoot i), st.2))
    (f.leaf, f.ommers)).1

/-- The root of a freshly constructed frontier is the left spine of its leaf:
    with no ommers and position 0, every level pairs the digest with an empty
    subtree on the right. -/
theorem root_new [Hashable H] (leaf : H) (depth : Nat) :
    (new leaf).root depth = spineRoot leaf depth := by
  simp only [root, spineRoot, new]
  -- the position is 0, so every bit is clear and the ommer list stays empty
  suffices h : ∀ (L : List Nat) (a : H),
      (L.foldl
        (fun (st : H × List H) (i : Nat) =>
          if (0 : BitVec 64).getLsbD i then
            (match st.2 with
              | [] => st
              | o :: rest => (Hashable.combine i o st.1, rest))
          else (Hashable.combine i st.1 (emptyRoot i), st.2))
        (a, ([] : List H))).1
      = L.foldl (fun acc i => Hashable.combine i acc (emptyRoot i)) a from h _ _
  intro L
  induction L with
  | nil => intro a; rfl
  | cons x xs ih =>
    intro a
    simp only [List.foldl_cons]
    split
    · rename_i h; simp at h
    · exact ih _

end NonEmptyFrontier

end Imt
