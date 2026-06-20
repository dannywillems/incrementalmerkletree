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
  (List.range w).countP (fun i => x.getLsbD i)

/-- Incrementing an even value sets bit 0 and leaves the higher bits unchanged,
    so the population count goes up by exactly one. The base case of the
    popcount-under-increment reasoning the frontier well-formedness needs. -/
theorem popcount_succ_of_even (p : BitVec 64) (h : p.getLsbD 0 = false) :
    popcount (p + 1) = popcount p + 1 := by
  have hp1 : p + 1 = p ||| 1 := by bv_decide
  have hfun : (fun i => (p ||| 1).getLsbD i) ∘ Nat.succ
      = (fun i => p.getLsbD i) ∘ Nat.succ := by
    funext j; simp [BitVec.getLsbD_or, BitVec.getLsbD_one]
  have h0 : (p ||| 1).getLsbD 0 = true := by simp
  rw [hp1, popcount, popcount, List.range_succ_eq_map]
  simp only [List.countP_cons, List.countP_map, hfun, h0, h]
  simp

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

/-- Rust `Address::children`: `None` at level 0, otherwise the two
    level-(level-1) nodes at indices `2*index` and `2*index + 1`. -/
def children (a : Address) : Option (Address × Address) :=
  if a.level = 0 then
    none
  else
    some
      ( { level := a.level - 1, index := a.index <<< (1 : Nat) },
        { level := a.level - 1, index := (a.index <<< (1 : Nat)) + 1 } )

/-- Rust `Address::is_ancestor_of`: `self` is strictly higher than `addr` and
    `addr`'s index, shifted down by the level gap, lands on `self`'s index.

    ```text
    self = (l_s, i_s) is an ancestor of addr = (l_a, i_a)  iff
        l_a < l_s   AND   (i_a >> (l_s - l_a)) == i_s
    i.e. addr sits in the subtree rooted at self.
    ```
-/
def isAncestorOf (self addr : Address) : Bool :=
  decide (addr.level.toNat < self.level.toNat) &&
    (addr.index >>> (self.level.toNat - addr.level.toNat) == self.index)

/-- Rust `Address::contains`: ancestor-or-equal (the reflexive closure). -/
def contains (self addr : Address) : Bool :=
  self == addr || self.isAncestorOf addr

end Address

namespace Position

/-- Rust `Position::is_complete_subtree`: the tree whose rightmost leaf is at
    this position contains a perfect subtree rooted at `root_level` iff the low
    `root_level` bits of the position are all set. -/
def isCompleteSubtree (p : Position) (l : Level) : Bool :=
  (List.range l.toNat).all (fun i => p.val.getLsbD i)

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

/-- `above_position` lands at the requested level. -/
@[simp] theorem abovePosition_level (l : Level) (p : Position) :
    (abovePosition l p).level = l := rfl

/-- At level 0 `above_position` is the leaf address itself (index = position). -/
@[simp] theorem abovePosition_zero_index (p : Position) :
    (abovePosition 0 p).index = p.val := by
  simp [abovePosition]

/-- `parent` shifts the index right by one. -/
theorem parent_index (a : Address) : a.parent.index = a.index >>> (1 : Nat) := rfl

/-- P0.1: every node is a left child or a right child. -/
theorem isLeftChild_or_isRightChild (a : Address) :
    a.isLeftChild || a.isRightChild := by
  simp only [isLeftChild, isRightChild]
  bv_decide

/-- P0.1: `sibling` flips child parity. -/
theorem sibling_isRightChild (a : Address) :
    a.sibling.isRightChild = a.isLeftChild := by
  simp only [sibling, isRightChild, isLeftChild]
  bv_decide

/-- Being a right child is exactly bit 0 of the index being set. -/
theorem isRightChild_eq_getLsbD (a : Address) :
    a.isRightChild = a.index.getLsbD 0 := by
  simp only [isRightChild]
  bv_decide

/-- Being a left child is the negation of bit 0 of the index. -/
theorem isLeftChild_eq_not_getLsbD (a : Address) :
    a.isLeftChild = !a.index.getLsbD 0 := by
  simp only [isLeftChild]
  bv_decide

/-- An address has children exactly when it is above the leaf level. -/
theorem children_isSome (a : Address) : a.children.isSome = true ↔ a.level ≠ 0 := by
  unfold children
  by_cases h : a.level = 0 <;> simp [h]

end Address

namespace Position

/-- P0.5: a position has a complete subtree rooted at `l` iff all the bits below
    level `l` are set. -/
theorem isCompleteSubtree_iff (p : Position) (l : Level) :
    p.isCompleteSubtree l = true ↔ ∀ i, i < l.toNat → p.val.getLsbD i = true := by
  simp [isCompleteSubtree, List.all_eq_true, List.mem_range]

end Position

namespace Address

/-- P0.6: `contains` is reflexive (every address contains itself). -/
@[simp] theorem contains_refl (a : Address) : a.contains a = true := by
  simp [contains]

/-- P0.6: `is_ancestor_of` is transitive: ancestry composes by adding the level
    gaps and the index shifts. -/
theorem isAncestorOf_trans {a b c : Address}
    (hab : a.isAncestorOf b = true) (hbc : b.isAncestorOf c = true) :
    a.isAncestorOf c = true := by
  simp only [isAncestorOf, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hab hbc ⊢
  obtain ⟨hlab, hiab⟩ := hab
  obtain ⟨hlbc, hibc⟩ := hbc
  refine ⟨by omega, ?_⟩
  rw [show a.level.toNat - c.level.toNat
        = (b.level.toNat - c.level.toNat) + (a.level.toNat - b.level.toNat) from by omega,
    BitVec.shiftRight_add, hibc, hiab]

/-- An address is never a strict ancestor of itself (the level must strictly
    decrease). -/
theorem not_isAncestorOf_self (a : Address) : a.isAncestorOf a = false := by
  simp [isAncestorOf]

/-- P0.6: `contains` is transitive (with reflexivity, a preorder; with
    `not_isAncestorOf_self`, a partial order). -/
theorem contains_trans {a b c : Address}
    (hab : a.contains b = true) (hbc : b.contains c = true) : a.contains c = true := by
  simp only [contains, Bool.or_eq_true, beq_iff_eq] at hab hbc ⊢
  rcases hab with rfl | hab
  · exact hbc
  · rcases hbc with rfl | hbc
    · exact Or.inr hab
    · exact Or.inr (isAncestorOf_trans hab hbc)

/-- P0.6: `contains` is antisymmetric, so it is a partial order: two addresses
    that each contain the other are equal (mutual strict ancestry is impossible
    because the level would have to both increase and decrease). -/
theorem contains_antisymm {a b : Address}
    (hab : a.contains b = true) (hba : b.contains a = true) : a = b := by
  simp only [contains, Bool.or_eq_true, beq_iff_eq] at hab hba
  rcases hab with rfl | hab
  · rfl
  · rcases hba with rfl | hba
    · rfl
    · simp only [isAncestorOf, Bool.and_eq_true, decide_eq_true_eq] at hab hba
      obtain ⟨hab, _⟩ := hab
      obtain ⟨hba, _⟩ := hba
      omega

/-- The address above a position contains that position's leaf: the level-`l`
    subtree root over `p` is an ancestor (or, at level 0, equal).

    ```text
        abovePosition l p = (l, p >> l)
                  | contains
        leaf addr        = (0, p)
    ```
-/
theorem abovePosition_contains_leaf (l : Level) (p : Position) :
    (abovePosition l p).contains (abovePosition 0 p) = true := by
  simp only [contains, abovePosition, isAncestorOf, Bool.or_eq_true, beq_iff_eq,
    Bool.and_eq_true, decide_eq_true_eq]
  by_cases h : l.toNat = 0
  · left
    have hl : l = 0 := by apply BitVec.eq_of_toNat_eq; simp [h]
    subst hl; simp
  · right
    have h0 : (0 : Level).toNat = 0 := rfl
    exact ⟨by omega, by simp⟩

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

-- children. `tests::addr_children`.
example : children { level := 0, index := 1 } = none := by decide
example : children { level := 3, index := 1 }
    = some ({ level := 2, index := 2 }, { level := 2, index := 3 }) := by decide

-- is_complete_subtree. `tests::position_is_complete_subtree`.
example : Position.isCompleteSubtree { val := 0 } 0 = true := by decide
example : Position.isCompleteSubtree { val := 1 } 1 = true := by decide
example : Position.isCompleteSubtree { val := 2 } 1 = false := by decide
example : Position.isCompleteSubtree { val := 3 } 2 = true := by decide
example : Position.isCompleteSubtree { val := 4 } 2 = false := by decide
example : Position.isCompleteSubtree { val := 7 } 3 = true := by decide

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
