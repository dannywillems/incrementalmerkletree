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

/-- If every level in `L` has a clear position bit, the root fold over `L`
    ignores the ommers and reduces to the plain empty-sibling spine fold. The
    reusable "clear-bit spine" core of the root computation (used both for a
    fresh frontier and, in the inductive step, for the cleared high bits above
    the complete left part). -/
theorem foldl_clear [Hashable H] (pos : BitVec 64) :
    ∀ (L : List Nat) (a : H) (oms : List H), (∀ i ∈ L, pos.getLsbD i = false) →
      (L.foldl
        (fun (st : H × List H) (i : Nat) =>
          if pos.getLsbD i then
            (match st.2 with
              | [] => st
              | o :: rest => (Hashable.combine i o st.1, rest))
          else (Hashable.combine i st.1 (emptyRoot i), st.2))
        (a, oms)).1
      = L.foldl (fun acc i => Hashable.combine i acc (emptyRoot i)) a := by
  intro L
  induction L with
  | nil => intro a oms _; rfl
  | cons x xs ih =>
    intro a oms h
    simp only [List.foldl_cons]
    have hx : pos.getLsbD x = false := h x (by simp)
    split
    · rename_i hcond; rw [hx] at hcond; simp at hcond
    · exact ih (Hashable.combine x a (emptyRoot x)) oms
        (fun i hi => h i (List.mem_cons_of_mem _ hi))

/-- The root of a freshly constructed frontier is the left spine of its leaf:
    with no ommers and position 0, every level pairs the digest with an empty
    subtree on the right. -/
theorem root_new [Hashable H] (leaf : H) (depth : Nat) :
    (new leaf).root depth = spineRoot leaf depth := by
  simp only [root, spineRoot, new]
  exact foldl_clear 0 (List.range depth) leaf [] (fun i _ => by simp)

end NonEmptyFrontier

/-- Rust `Frontier<H, DEPTH>`: a possibly-empty frontier. The static depth bound
    is carried as a parameter. -/
structure Frontier (H : Type) (depth : Nat) where
  value : Option (NonEmptyFrontier H)

namespace Frontier

variable {H : Type} {depth : Nat}

/-- The empty frontier. -/
def empty : Frontier H depth := ⟨none⟩

/-- A single-leaf frontier. -/
def singleton (leaf : H) : Frontier H depth := ⟨some (NonEmptyFrontier.new leaf)⟩

/-- Rust `Frontier::root`: the empty root when empty, else the inner frontier's
    root computed up to `depth`. -/
def root [Hashable H] (f : Frontier H depth) : H :=
  match f.value with
  | none => emptyRoot depth
  | some nf => nf.root depth

/-- P2.5 (empty case): the empty frontier's root is the empty root. -/
@[simp] theorem empty_root [Hashable H] :
    (empty : Frontier H depth).root = emptyRoot depth := rfl

/-- The root of a single-leaf frontier is the inner frontier's root. -/
@[simp] theorem singleton_root [Hashable H] (leaf : H) :
    (singleton leaf : Frontier H depth).root = (NonEmptyFrontier.new leaf).root depth := rfl

end Frontier

end Imt
