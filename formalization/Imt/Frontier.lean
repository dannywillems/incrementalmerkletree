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

/-- `spineRoot` is exactly the spine `spineFrom` starting at level 0. -/
theorem spineRoot_eq_spineFrom {H : Type} [Hashable H] (leaf : H) (depth : Nat) :
    spineRoot leaf depth = spineFrom leaf 0 depth := by
  simp only [spineRoot, spineFrom, Nat.zero_add]

/-- The `spineRoot` recurrence: one more level wraps the spine with an empty
    subtree on the right. -/
theorem spineRoot_succ {H : Type} [Hashable H] (leaf : H) (d : Nat) :
    spineRoot leaf (d + 1) = Hashable.combine d (spineRoot leaf d) (emptyRoot d) := by
  rw [spineRoot_eq_spineFrom, spineRoot_eq_spineFrom, spineFrom_succ, Nat.zero_add]

/-- Rust `NonEmptyFrontier`: the most recently appended `leaf` at `position`,
    plus the stored left siblings (`ommers`) needed to witness it, ordered from
    lowest level to highest.

    A frontier keeps only the rightmost path of the tree plus the left siblings
    hanging off it (the ommers), one per set bit of `position`. Example for
    `position = 6` (7 leaves, `6 = 0b110`, so two ommers `o1, o2`):

    ```text
                  *                  leaf = leaf at position 6
                 / \                 o2   = root of leaves 0..3   (left sibling at level 2)
               o2   *                o1   = root of leaves 4,5    (left sibling at level 1)
                   / \               *    = nodes recomputed on demand by `root`
                 o1   *
                     / \
                   leaf  E           (E = empty; right side empty until more leaves arrive)
    ```
-/
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
    empty subtree root `emptyRoot i` on the right.

    ```text
    digest := leaf
    for i = 0 .. depth-1:
      if bit i of position set:   digest := combine i  ommer_i  digest        (left sibling stored)
      else:                       digest := combine i  digest  (emptyRoot i)  (right sibling empty)
    root := digest
    ```
-/
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

/-- The root at depth 0 is just the current leaf (the empty fold). -/
@[simp] theorem root_zero [Hashable H] (f : NonEmptyFrontier H) : f.root 0 = f.leaf := by
  simp [root]

/-- The root of a freshly constructed frontier is the left spine of its leaf:
    with no ommers and position 0, every level pairs the digest with an empty
    subtree on the right. -/
theorem root_new [Hashable H] (leaf : H) (depth : Nat) :
    (new leaf).root depth = spineRoot leaf depth := by
  simp only [root, spineRoot, new]
  exact foldl_clear 0 (List.range depth) leaf [] (fun i _ => by simp)

/-- The carry performed when appending to a frontier whose last leaf is a right
    child: combine the carry digest with successive stored ommers while the old
    position's bit is set, then place the carry at the first cleared level. -/
def appendCarry [Hashable H] (p : BitVec 64) (level : Nat) (carry : H) :
    List H → List H
  | [] => [carry]
  | o :: rest =>
    if p.getLsbD level then
      appendCarry p (level + 1) (Hashable.combine level o carry) rest
    else
      carry :: o :: rest

/-- How many ommers `appendCarry` consumes: the run of consecutive set bits of
    `p` starting at `level`, capped by the number of ommers. -/
def carryRun (p : BitVec 64) (level : Nat) : List H → Nat
  | [] => 0
  | _ :: rest => if p.getLsbD level then carryRun p (level + 1) rest + 1 else 0

/-- The carry consumes `carryRun` ommers and emits one merged ommer, so the
    resulting list has length `ommers.length + 1 - carryRun`. -/
theorem appendCarry_length [Hashable H] (p : BitVec 64) (level : Nat) (carry : H)
    (ommers : List H) :
    (appendCarry p level carry ommers).length
      = ommers.length + 1 - carryRun p level ommers := by
  induction ommers generalizing level carry with
  | nil => simp [appendCarry, carryRun]
  | cons o rest ih =>
    rw [appendCarry, carryRun]
    by_cases hb : p.getLsbD level = true
    · simp only [hb, if_true, List.length_cons]
      rw [ih]; omega
    · simp [hb, List.length_cons]

/-- The carry never consumes more ommers than are present. -/
theorem carryRun_le_length (p : BitVec 64) (level : Nat) (ommers : List H) :
    carryRun p level ommers ≤ ommers.length := by
  induction ommers generalizing level with
  | nil => simp [carryRun]
  | cons o rest ih =>
    rw [carryRun]
    by_cases hb : p.getLsbD level = true
    · simp only [hb, if_true, List.length_cons]
      have h := ih (level + 1); omega
    · simp [hb]

/-- `carryRun` depends only on the length of the ommer list, not its contents:
    the run is a function of the position bits alone. -/
theorem carryRun_length_eq (p : BitVec 64) (level : Nat) (l₁ l₂ : List H)
    (h : l₁.length = l₂.length) : carryRun p level l₁ = carryRun p level l₂ := by
  induction l₁ generalizing level l₂ with
  | nil => cases l₂ <;> simp_all [carryRun]
  | cons a as ih =>
    cases l₂ with
    | nil => simp at h
    | cons b bs =>
      rw [carryRun, carryRun]
      simp only [List.length_cons, Nat.add_right_cancel_iff] at h
      by_cases hb : p.getLsbD level = true
      · simp only [hb, if_true]; rw [ih (level + 1) bs h]
      · simp [hb]

/-- The carry consumes nothing exactly when there are no ommers or the current
    bit is already clear. -/
theorem carryRun_eq_zero_iff (p : BitVec 64) (level : Nat) (ommers : List H) :
    carryRun p level ommers = 0 ↔ ommers = [] ∨ p.getLsbD level = false := by
  cases ommers with
  | nil => simp [carryRun]
  | cons o rest =>
    rw [carryRun]
    by_cases hb : p.getLsbD level = true <;> simp [hb]

/-- `appendCarry` always produces a non-empty ommer list: it emits at least the
    carried value. -/
theorem appendCarry_ne_nil [Hashable H] (p : BitVec 64) (level : Nat) (carry : H)
    (ommers : List H) : appendCarry p level carry ommers ≠ [] := by
  induction ommers generalizing level carry with
  | nil => simp [appendCarry]
  | cons o rest ih =>
    rw [appendCarry]
    by_cases hb : p.getLsbD level = true
    · simp only [hb, if_true]; exact ih _ _
    · simp [hb]

/-- Rust `NonEmptyFrontier::append`: extend the frontier with leaf `v`. If the
    old position is even (new position a right child) the old leaf becomes a
    level-0 ommer; otherwise (old position odd) the old leaf is carried up,
    combining with stored ommers until a cleared level is reached. This is a
    binary increment of `position` where each carry merges two subtrees.

    ```text
    old position even (..0):   leaf is a left child, just store it as a new ommer
        ommers [o0, o1, ..]  ->  [oldleaf, o0, o1, ..]      (no hashing)

    old position odd (..0111): leaf is a right child, carry through the trailing
        ones, merging with each ommer, and drop the carry at the first clear bit:
        carry = combine 2 o2 (combine 1 o1 (combine 0 o0 oldleaf))
        ommers [o0, o1, o2, o3, ..]  ->  [carry, o3, ..]
    ```
-/
def append [Hashable H] (f : NonEmptyFrontier H) (v : H) : NonEmptyFrontier H :=
  if f.position.val.getLsbD 0 then
    { position := ⟨f.position.val + 1⟩, leaf := v,
      ommers := appendCarry f.position.val 0 f.leaf f.ommers }
  else
    { position := ⟨f.position.val + 1⟩, leaf := v,
      ommers := f.leaf :: f.ommers }

@[simp] theorem append_position [Hashable H] (f : NonEmptyFrontier H) (v : H) :
    (f.append v).position = ⟨f.position.val + 1⟩ := by
  unfold append; split <;> rfl

@[simp] theorem append_leaf [Hashable H] (f : NonEmptyFrontier H) (v : H) :
    (f.append v).leaf = v := by
  unfold append; split <;> rfl

/-- Appending always leaves a non-empty ommer list (the even case prepends the
    old leaf; the odd case emits the carry). -/
theorem append_ommers_ne_nil [Hashable H] (f : NonEmptyFrontier H) (v : H) :
    (f.append v).ommers ≠ [] := by
  unfold append
  split
  · exact appendCarry_ne_nil _ _ _ _
  · simp

/-- If the position bit at `depth` is clear, extending the root computation by one
    level just wraps the current root with an empty subtree on the right. The
    frontier analog of the merkleRoot spine recurrence; it removes depth-padding
    from the general root theorem.

    A clear bit at `depth` means the frontier's leaf lies in the left half of the
    level-`(depth+1)` subtree, so the right half is empty:

    ```text
              root (depth+1)                  =  combine depth _ _
             /              \
        root depth        emptyRoot depth     <- right half all empty (bit clear)
         (left half)       (right half)
    ```
-/
theorem root_succ_of_clear [Hashable H] (f : NonEmptyFrontier H) (depth : Nat)
    (h : f.position.val.getLsbD depth = false) :
    f.root (depth + 1) = Hashable.combine depth (f.root depth) (emptyRoot depth) := by
  simp only [NonEmptyFrontier.root, List.range_succ, List.foldl_append, List.foldl_cons,
    List.foldl_nil, h, Bool.false_eq_true, if_false]

/-- P2.1 (even case): appending to a frontier at an even position preserves
    well-formedness. The old leaf becomes a new level-0 ommer (length +1) and the
    population count of the position rises by one (`popcount_succ_of_even`). -/
theorem append_wf_even [Hashable H] (f : NonEmptyFrontier H) (v : H)
    (heven : f.position.val.getLsbD 0 = false) (hwf : f.WF) : (f.append v).WF := by
  unfold WF append at *
  rw [if_neg (by rw [heven]; simp)]
  simp only [List.length_cons]
  rw [popcount_succ_of_even f.position.val heven]
  omega

/-- Appending one leaf to a single-leaf frontier yields position 1, the new leaf,
    and the old leaf as the sole (level-0) ommer. -/
theorem new_append [Hashable H] (a b : H) :
    (new a).append b = { position := ⟨1⟩, leaf := b, ommers := [a] } := by
  simp [append, new]

/-- Appending a third leaf exercises the carry: from `⟨1, b, [a]⟩` (position 1,
    odd) the old leaf `b` combines with ommer `a` and the result is stored as a
    single level-1 ommer. -/
theorem new_append_append [Hashable H] (a b c : H) :
    ((new a).append b).append c
      = { position := ⟨2⟩, leaf := c, ommers := [Hashable.combine 0 a b] } := by
  simp [append, new, appendCarry]

/-- The frontier analog of `merkleRoot_eq_spineFrom`: if every position bit from
    level `k` up to `k+n` is clear, the depth-`(k+n)` root is the depth-`k` root
    wrapped in a spine of `n` empty-sibling levels. This lets a root be computed
    at the position's own root level, then climbed to any larger depth.

    ```text
    root (k+n)  =     combine (k+n-1)
                     /              \
                   ...            emptyRoot (k+n-1)
                  /
              root k                  (the meaningful part; bits k..k+n-1 clear)
    ```
-/
theorem root_eq_spineFrom [Hashable H] (f : NonEmptyFrontier H) (k : Nat) :
    ∀ n, (∀ i, k ≤ i → i < k + n → f.position.val.getLsbD i = false) →
      f.root (k + n) = spineFrom (f.root k) k n := by
  intro n
  induction n with
  | zero => intro _; simp [spineFrom]
  | succ n ih =>
    intro h
    have hk : f.position.val.getLsbD (k + n) = false :=
      h (k + n) (Nat.le_add_right k n) (by omega)
    have ih' := ih (fun i hi hlt => h i hi (by omega))
    rw [show k + (n + 1) = (k + n) + 1 from by omega, root_succ_of_clear f (k + n) hk, ih',
      spineFrom_succ]

/-- The root fold of the two-element frontier `⟨1, b, [a]⟩`: level 0 consumes the
    ommer `a` (giving `combine 0 a b`), then the higher levels form an
    empty-sibling spine. -/
theorem root_two_frontier [Hashable H] (a b : H) (d : Nat) :
    (NonEmptyFrontier.mk ⟨1⟩ b [a]).root (d + 1)
      = spineFrom (Hashable.combine 0 a b) 1 d := by
  simp only [NonEmptyFrontier.root, List.range_succ_eq_map, List.foldl_cons]
  rw [if_pos (show (1 : BitVec 64).getLsbD 0 = true by decide)]
  rw [NonEmptyFrontier.foldl_clear 1 (List.map Nat.succ (List.range d))
    (Hashable.combine 0 a b) []
    (by intro i hi; simp only [List.mem_map, List.mem_range] at hi
        obtain ⟨j, _, rfl⟩ := hi; simp [BitVec.getLsbD_one])]
  rw [List.foldl_map]
  simp only [spineFrom, Nat.add_comm]

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

/-- Rust `Frontier::tree_size`: the number of leaves represented (0 when empty,
    else position + 1). -/
def tree_size (f : Frontier H depth) : Nat :=
  match f.value with
  | none => 0
  | some nf => nf.position.val.toNat + 1

@[simp] theorem empty_tree_size : (empty : Frontier H depth).tree_size = 0 := rfl

@[simp] theorem singleton_tree_size [Hashable H] (v : H) :
    (singleton v : Frontier H depth).tree_size = 1 := rfl

/-- Rust `Frontier::append`: append `v`, returning `true` on success. Fails
    (returns `false` and the unchanged frontier) when the tree is already a
    complete subtree at `depth`, i.e. full. -/
def append [Hashable H] (v : H) (f : Frontier H depth) : Bool × Frontier H depth :=
  match f.value with
  | none => (true, ⟨some (NonEmptyFrontier.new v)⟩)
  | some nf =>
    if nf.position.isCompleteSubtree (BitVec.ofNat 8 depth) then
      (false, f)
    else
      (true, ⟨some (nf.append v)⟩)

/-- Appending to the empty frontier always succeeds and yields the single-leaf
    frontier. -/
@[simp] theorem append_empty [Hashable H] (v : H) :
    append v (empty : Frontier H depth) = (true, singleton v) := rfl

/-- `Frontier.append` always yields a non-empty frontier (even when it reports
    failure it returns the unchanged, already non-empty, full frontier). -/
theorem append_value_isSome [Hashable H] (v : H) (f : Frontier H depth) :
    (append v f).2.value.isSome = true := by
  cases hv : f.value with
  | none => simp [append, hv]
  | some nf =>
    simp only [append, hv]
    by_cases h : nf.position.isCompleteSubtree (BitVec.ofNat 8 depth) <;> simp [h, hv]

end Frontier

end Imt
