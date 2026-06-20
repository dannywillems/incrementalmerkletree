/-
Layer 0: addressing arithmetic for incrementalmerkletree.

This is the scaffold for milestone M0/M1 of the formalization (see PLAN.md).
It models the Rust types `Level`, `Position`, and `Address` from
`incrementalmerkletree/src/lib.rs` using `BitVec`, faithful to the wrapping
`u8` / `u64` semantics.

The universal theorems (P0.1 .. P0.10 in PLAN.md) are the work to come; here
we establish the definitions plus ground "oracle" checks that mirror the Rust
unit tests, every one closed by `decide` over the computable model. A failing
check breaks the build, so CI exercises the model rather than just typechecking
signatures.
-/

import Std.Tactic.BVDecide

namespace Imt

/-- A tree level. Rust `u8`. Level 0 is a leaf. -/
abbrev Level := BitVec 8

/-- The 0-based index of a leaf at level 0. Rust `Position(u64)`. -/
structure Position where
  val : BitVec 64
  deriving DecidableEq, Repr

/-- The address of any node: a level plus a level-relative index. Rust `Address`. -/
structure Address where
  level : Level
  index : BitVec 64
  deriving DecidableEq, Repr

/-- Population count: the number of set bits. Used by `pastOmmerCount`. -/
def popcount {w : Nat} (x : BitVec w) : Nat :=
  (List.range w).foldl (fun acc i => acc + (if x.getLsbD i then 1 else 0)) 0

namespace Address

/-- Rust `Address::parent`: `(level + 1, index >> 1)`. -/
def parent (a : Address) : Address :=
  { level := a.level + 1, index := a.index >>> (1 : Nat) }

/-- Rust `Address::sibling`: `(level, index ^ 1)`. -/
def sibling (a : Address) : Address :=
  { level := a.level, index := a.index ^^^ 1 }

/-- Rust `Address::is_right_child`: `index & 1 == 1`. -/
def isRightChild (a : Address) : Bool := (a.index &&& 1) == 1

/-- Rust `Address::is_left_child`: `index & 1 == 0`. -/
def isLeftChild (a : Address) : Bool := (a.index &&& 1) == 0

/-- Rust `Address::above_position`: `(level, position >> level)`. -/
def abovePosition (l : Level) (p : Position) : Address :=
  { level := l, index := p.val >>> l.toNat }

end Address

namespace Position

/-- Rust `Position::root_level`: `64 - leading_zeros`, i.e. one above the
    highest set bit (and 0 for position 0). Computed by scanning bits so it
    reduces under `decide` without well-founded recursion. -/
def rootLevel (p : Position) : Level :=
  BitVec.ofNat 8 <|
    (List.range 64).foldl (fun acc i => if p.val.getLsbD i then i + 1 else acc) 0

/-- Rust `Position::past_ommer_count`. Bits above the root level are zero, so
    this equals the full population count of the position. -/
def pastOmmerCount (p : Position) : Nat := popcount p.val

end Position

/-! ## Layer 0 theorems (milestone M1)

Universal versions of the navigation identities from PLAN.md, proved for all
inputs over the BitVec model rather than only on the ground oracle values
below. -/

namespace Address

/-- P0.1: `sibling` is an involution (`tests::*` navigation identities). -/
@[simp] theorem sibling_sibling (a : Address) : a.sibling.sibling = a := by
  obtain ⟨level, index⟩ := a
  have h : (index ^^^ 1) ^^^ 1 = index := by bv_decide
  simp only [sibling, h]

/-- `parent` raises the level by one. -/
@[simp] theorem parent_level (a : Address) : a.parent.level = a.level + 1 := rfl

/-- `sibling` preserves the level. -/
@[simp] theorem sibling_level (a : Address) : a.sibling.level = a.level := rfl

/-- P0.1: a node is a right child iff it is not a left child. -/
theorem isRightChild_eq_not_isLeftChild (a : Address) :
    a.isRightChild = !a.isLeftChild := by
  simp only [isRightChild, isLeftChild]
  bv_decide

/-- P0.2: `above_position` shifts the position right by the level
    (`tests::addr_above_position`). -/
theorem abovePosition_index (l : Level) (p : Position) :
    (abovePosition l p).index = p.val >>> l.toNat := rfl

end Address

/-! ## Oracle checks (mirror the Rust unit tests)

These ground facts are proved by `decide` over the computable model. They are
the same values asserted in the Rust test modules, so they pin the definitions
to the upstream behavior. -/

section Oracles
open Address Position

-- P0.1 (instance): sibling is an involution. `tests::*` navigation identities.
example : sibling (sibling { level := 7, index := 5 }) = { level := 7, index := 5 } := by decide
example : (sibling { level := 0, index := 2 }).index = 3 := by decide
example : (sibling { level := 0, index := 3 }).index = 2 := by decide

-- P0.1 (instance): parent of leaf 8 is (1, 4). Figure 3.4a.
example : parent { level := 0, index := 8 } = { level := 1, index := 4 } := by decide

-- P0.2 (instance): above_position. `tests::addr_above_position`.
example : abovePosition 3 { val := 9 } = { level := 3, index := 1 } := by decide

-- P0.3: root_level. `tests::position_root_level`.
example : Position.rootLevel { val := 0 } = 0 := by decide
example : Position.rootLevel { val := 1 } = 1 := by decide
example : Position.rootLevel { val := 2 } = 2 := by decide
example : Position.rootLevel { val := 3 } = 2 := by decide
example : Position.rootLevel { val := 4 } = 3 := by decide
example : Position.rootLevel { val := 7 } = 3 := by decide
example : Position.rootLevel { val := 8 } = 4 := by decide

-- P0.4: past_ommer_count = popcount. `tests::position_past_ommer_count`.
example : Position.pastOmmerCount { val := 0 } = 0 := by decide
example : Position.pastOmmerCount { val := 1 } = 1 := by decide
example : Position.pastOmmerCount { val := 2 } = 1 := by decide
example : Position.pastOmmerCount { val := 3 } = 2 := by decide
example : Position.pastOmmerCount { val := 4 } = 1 := by decide
example : Position.pastOmmerCount { val := 7 } = 3 := by decide
example : Position.pastOmmerCount { val := 8 } = 1 := by decide

end Oracles

end Imt
