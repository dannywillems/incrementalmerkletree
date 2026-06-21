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

/-! ### Arithmetic foundations for the P2.3 ommer characterization

`baseIndex m j` is the start index of the level-`j` subtree containing leaf `m`
(`m` rounded down to a multiple of `2 ^ j`); its recurrence drives the level
induction of the characterization. -/

/-- Peeling the next power-of-two modulus: bit `j` contributes `2 ^ j` exactly
    when it is set. The arithmetic backbone of `baseIndex_succ`. Used by: the
    P2.3 ommer characterization. -/
theorem mod_two_pow_succ (m j : Nat) :
    m % 2 ^ (j + 1) = m % 2 ^ j + 2 ^ j * (m / 2 ^ j % 2) := by
  rw [pow_succ, Nat.mod_mul]

/-- A position bit as a `0/1` value equals `toNat / 2 ^ j % 2`, bridging the
    fold's `getLsbD` test to the base-index arithmetic. Used by: the P2.3 ommer
    characterization. -/
theorem ite_getLsbD_eq_div_mod (p : BitVec 64) (j : Nat) :
    (if p.getLsbD j then (1 : Nat) else 0) = p.toNat / 2 ^ j % 2 := by
  rw [getLsbD_eq_testBit]
  rcases Nat.mod_two_eq_zero_or_one (p.toNat / 2 ^ j) with h | h <;>
    simp [Nat.testBit, Nat.shiftRight_eq_div_pow, h]

/-- Start index of the level-`j` subtree containing leaf `m`: `m` rounded down to
    a multiple of `2 ^ j`. Used by: the P2.3 ommer characterization invariant
    (the current subtree is `L.drop (baseIndex (n-1) j)`). -/
def baseIndex (m j : Nat) : Nat := m - m % 2 ^ j

/-- The level-0 subtree starts at the leaf itself. -/
theorem baseIndex_zero (m : Nat) : baseIndex m 0 = m := by
  simp [baseIndex, Nat.mod_one]

/-- Going up one level moves the subtree start down by `2 ^ j` exactly when bit
    `j` is set (the complete left sibling joins). Used by: the inductive step of
    the ommer characterization. -/
theorem baseIndex_succ (m j : Nat) :
    baseIndex m (j + 1) = baseIndex m j - 2 ^ j * (m / 2 ^ j % 2) := by
  unfold baseIndex
  have h2 : m % 2 ^ (j + 1) ≤ m := Nat.mod_le _ _
  have h1 : m % 2 ^ j ≤ m := Nat.mod_le _ _
  rw [mod_two_pow_succ]
  omega

/-- The subtree start never exceeds the leaf index. Used by: the ommer
    characterization (drop offsets stay in range). -/
theorem baseIndex_le (m j : Nat) : baseIndex m j ≤ m := by
  unfold baseIndex; exact Nat.sub_le _ _

/-- The level-`j` subtree containing the last leaf has length `(n-1) % 2^j + 1`.
    Used by: the ommer characterization (the current subtree is `L.drop baseIndex`
    and the merkleRoot split needs its length). -/
theorem length_drop_baseIndex {H : Type} (L : List H) (j : Nat) (hL : 1 ≤ L.length) :
    (L.drop (baseIndex (L.length - 1) j)).length = (L.length - 1) % 2 ^ j + 1 := by
  rw [List.length_drop, baseIndex]
  have h1 : (L.length - 1) % 2 ^ j ≤ L.length - 1 := Nat.mod_le _ _
  omega

/-- The current level-`j` subtree fits within `2^j` leaves. Used by: the ommer
    characterization, to apply `merkleRoot_eq_spineFrom`-style facts. -/
theorem length_drop_baseIndex_le {H : Type} (L : List H) (j : Nat) (hL : 1 ≤ L.length) :
    (L.drop (baseIndex (L.length - 1) j)).length ≤ 2 ^ j := by
  rw [length_drop_baseIndex L j hL]
  have := Nat.mod_lt (L.length - 1) (Nat.pos_of_ne_zero (by positivity) : 0 < 2 ^ j)
  omega

/-- When bit `j` is set, going up a level pulls in the complete left sibling: the
    level-`(j+1)` subtree starts `2^j` earlier than the level-`j` subtree. Used
    by: the set-bit step of the ommer characterization (it rewrites the merkleRoot
    split offsets onto the base indices). -/
theorem baseIndex_add_pow (m j : Nat) (h : m / 2 ^ j % 2 = 1) :
    baseIndex m (j + 1) + 2 ^ j = baseIndex m j := by
  unfold baseIndex
  have hmod : m % 2 ^ (j + 1) = m % 2 ^ j + 2 ^ j := by rw [mod_two_pow_succ, h, mul_one]
  have hle : m % 2 ^ (j + 1) ≤ m := Nat.mod_le _ _
  omega

/-- Incrementing an even number bumps the `2^(i+1)`-modulus by exactly one (no
    carry past bit 0). Used by: the even-append case of (A). -/
theorem mod_two_pow_succ_of_even (p i : Nat) (hp : p % 2 = 0) :
    (p + 1) % 2 ^ (i + 1) = p % 2 ^ (i + 1) + 1 := by
  have hm : 2 ∣ 2 ^ (i + 1) := dvd_pow_self 2 (Nat.succ_ne_zero i)
  have hpar : p % 2 ^ (i + 1) % 2 = 0 := by rw [Nat.mod_mod_of_dvd p hm]; exact hp
  have hlt : p % 2 ^ (i + 1) < 2 ^ (i + 1) := Nat.mod_lt _ (by positivity)
  have hMeven : 2 ^ (i + 1) % 2 = 0 := by rw [pow_succ]; omega
  have hpow2 : 2 ≤ 2 ^ (i + 1) := by
    rw [pow_succ]; have := Nat.one_le_two_pow (n := i); omega
  have hsum : p % 2 ^ (i + 1) + 1 < 2 ^ (i + 1) := by omega
  rw [Nat.add_mod, Nat.mod_eq_of_lt (by omega : (1 : Nat) < 2 ^ (i + 1)),
    Nat.mod_eq_of_lt hsum]

/-- The subtree start at level `i+1` is unchanged by an even increment. Used by:
    the even-append case of (A) (the higher-level left-sibling slices match). -/
theorem baseIndex_succ_of_even (p i : Nat) (hp : p % 2 = 0) :
    baseIndex (p + 1) (i + 1) = baseIndex p (i + 1) := by
  unfold baseIndex
  rw [mod_two_pow_succ_of_even p i hp]
  have hlt : p % 2 ^ (i + 1) < 2 ^ (i + 1) := Nat.mod_lt _ (by positivity)
  have h1 : p % 2 ^ (i + 1) ≤ p := Nat.mod_le _ _
  omega

/-- An even increment leaves every bit above bit 0 unchanged. Used by: the
    even-append case of (A) (the higher set bits match). -/
theorem testBit_succ_of_even (p i : Nat) (hp : p % 2 = 0) :
    (p + 1).testBit (i + 1) = p.testBit (i + 1) := by
  rw [Nat.testBit_succ, Nat.testBit_succ]; congr 1; omega

/-- A bit is set iff the corresponding `div/mod` value is 1. Used by: deriving the
    set-bit `baseIndex_add_pow` precondition in (A). -/
theorem testBit_iff_div_mod (n k : Nat) : n.testBit k = true ↔ n / 2 ^ k % 2 = 1 := by
  rw [Nat.testBit, Nat.shiftRight_eq_div_pow, Nat.and_comm, Nat.and_one_is_mod]
  rcases Nat.mod_two_eq_zero_or_one (n / 2 ^ k) with h | h <;> simp [h]

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

/-- The depth-`d` root of a single leaf is its empty-sibling spine. -/
theorem merkleRoot_singleton {H : Type} [Hashable H] (a : H) (d : Nat) :
    merkleRoot d [a] = spineRoot a d := (spineRoot_eq_merkleRoot a d).symm

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

@[simp] theorem ofList_nil {H : Type} [Hashable H] (v0 : H) : ofList v0 [] = new v0 := rfl

/-- The snoc step for induction: building from `vs ++ [w]` is one `append` onto
    the frontier built from `vs`. -/
theorem ofList_append {H : Type} [Hashable H] (v0 w : H) (vs : List H) :
    ofList v0 (vs ++ [w]) = (ofList v0 vs).append w := by
  simp [ofList, List.foldl_append]

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

/-- Depth-padding reduction for the frontier root theorem P2.3: if a frontier's
    root already equals the reference `merkleRoot` at a level `k` that holds all
    of `L` (`L.length <= 2^k`, and the position has no set bit at or above `k`),
    then equality lifts to every higher level `k + n`, because both sides climb
    the same empty-sibling spine above `k`. Used by: P2.3. This is the
    "everything above the tight level" half of the centerpiece; it reduces P2.3
    to the single tight-level obligation `hk` (the ommer characterization). -/
theorem root_merkleRoot_lift {H : Type} [Hashable H]
    (f : NonEmptyFrontier H) (L : List H) (k n : Nat)
    (hbits : ∀ i, k ≤ i → i < k + n → f.position.val.getLsbD i = false)
    (hlen : L.length ≤ 2 ^ k)
    (hk : f.root k = merkleRoot k L) :
    f.root (k + n) = merkleRoot (k + n) L := by
  rw [f.root_eq_spineFrom k n hbits, hk, ← merkleRoot_eq_spineFrom k L hlen n]

/-- Clear-bit step of the P2.3 joint invariant (`.1` component): when bit `j` of
    the position is clear, the level-`(j+1)` subtree root wraps the level-`j` root
    with an empty right sibling. Used by: the ommer characterization induction. -/
theorem rootState_fst_succ_clear {H : Type} [Hashable H] (f : NonEmptyFrontier H)
    (L : List H) (j : Nat) (hpos : f.position.val.toNat = L.length - 1)
    (hL : 1 ≤ L.length) (hbit : (L.length - 1) / 2 ^ j % 2 = 0)
    (hIH : (rootState f j).1 = merkleRoot j (L.drop (baseIndex (L.length - 1) j))) :
    (rootState f (j + 1)).1
      = merkleRoot (j + 1) (L.drop (baseIndex (L.length - 1) (j + 1))) := by
  have hclear : f.position.val.getLsbD j = false := by
    have h := ite_getLsbD_eq_div_mod f.position.val j
    rw [hpos, hbit] at h
    by_contra hc
    simp only [Bool.not_eq_false] at hc
    rw [hc] at h; simp at h
  rw [rootState_succ]
  simp only [hclear, Bool.false_eq_true, if_false]
  have hb : baseIndex (L.length - 1) (j + 1) = baseIndex (L.length - 1) j := by
    rw [baseIndex_succ, hbit]; simp
  rw [hb, merkleRoot_succ_of_le _ _ (length_drop_baseIndex_le L j hL), hIH]

/-- Set-bit step of the P2.3 joint invariant (`.1` component): when bit `j` is
    set, the next root combines the consumed ommer (the complete left sibling,
    value `o`) with the level-`j` root. The ommer value `ho` is supplied by the
    ommer-value characterization. Used by: the ommer characterization induction. -/
theorem rootState_fst_succ_set {H : Type} [Hashable H] (f : NonEmptyFrontier H)
    (L : List H) (j : Nat) (o : H) (rest : List H)
    (hpos : f.position.val.toNat = L.length - 1)
    (hbit : (L.length - 1) / 2 ^ j % 2 = 1)
    (hommers : (rootState f j).2 = o :: rest)
    (ho : o = merkleRoot j ((L.drop (baseIndex (L.length - 1) (j + 1))).take (2 ^ j)))
    (hIH : (rootState f j).1 = merkleRoot j (L.drop (baseIndex (L.length - 1) j))) :
    (rootState f (j + 1)).1
      = merkleRoot (j + 1) (L.drop (baseIndex (L.length - 1) (j + 1))) := by
  have hset : f.position.val.getLsbD j = true := by
    have h := ite_getLsbD_eq_div_mod f.position.val j
    rw [hpos, hbit] at h
    by_contra hc
    simp only [Bool.not_eq_true] at hc
    rw [hc] at h; simp at h
  rw [rootState_succ]
  simp only [hset, if_true, hommers]
  rw [merkleRoot_succ, List.drop_drop, baseIndex_add_pow (L.length - 1) j hbit, ← hIH, ← ho]

/-- An interior subtree slice is unchanged by appending one leaf at the end. Used
    by: the even-append case of the (A) ommer-value characterization (the higher
    ommers' left-sibling slices are stable when a new leaf is appended). -/
theorem take_drop_append_singleton {H : Type} (L : List H) (w : H) (a n : Nat)
    (h : a + n ≤ L.length) :
    ((L ++ [w]).drop a).take n = (L.drop a).take n := by
  rw [List.drop_append_of_le_length (by omega),
    List.take_append_of_le_length (by rw [List.length_drop]; omega)]

/-- The ommers feeding the carry, as `merkleRoot`s of complete subtree blocks at
    increasing levels. Used by: the carry-merge value `mergedCarry_blockOmmers`. -/
def blockOmmers {H : Type} [Hashable H] (level : Nat) : List (List H) → List H
  | [] => []
  | b :: bs => merkleRoot level b :: blockOmmers (level + 1) bs

/-- Carry-merge value (the crux of (A)): when the carried `cL` and every ommer
    block are complete subtrees (`|block i| = 2^(level+i)`) and every bit in the
    run is set, the merged carry is the `merkleRoot` of the concatenated blocks
    (left to right) followed by the carried leaves. Used by: the (A) ommer-value
    characterization's odd/carry case. -/
theorem mergedCarry_blockOmmers {H : Type} [Hashable H] (p : BitVec 64) :
    ∀ (blocks : List (List H)) (level : Nat) (cL : List H),
      cL.length = 2 ^ level →
      (∀ i (_ : i < blocks.length), (blocks[i]).length = 2 ^ (level + i)) →
      (∀ i (_ : i < blocks.length), p.getLsbD (level + i) = true) →
      mergedCarry p level (merkleRoot level cL) (blockOmmers level blocks)
        = merkleRoot (level + blocks.length) (blocks.reverse.flatten ++ cL) := by
  intro blocks
  induction blocks with
  | nil => intro level cL _ _ _; simp [mergedCarry, blockOmmers]
  | cons b bs ih =>
    intro level cL hc hlen hbit
    have hb0 : p.getLsbD level = true := by simpa using hbit 0 (by simp)
    have hblen : b.length = 2 ^ level := by
      have := hlen 0 (by simp); simpa using this
    rw [blockOmmers, mergedCarry, if_pos hb0, combine_merkleRoot level b cL hblen,
      ih (level + 1) (b ++ cL) (by rw [List.length_append, hblen, hc]; ring)
        (fun i _ => by
          have := hlen (i + 1) (by rw [List.length_cons]; omega)
          simp only [List.getElem_cons_succ] at this
          rw [show level + 1 + i = level + (i + 1) from by omega]; exact this)
        (fun i _ => by
          have := hbit (i + 1) (by rw [List.length_cons]; omega)
          rw [show level + 1 + i = level + (i + 1) from by omega]; exact this)]
    rw [List.reverse_cons, List.flatten_append]
    simp only [List.flatten_cons, List.flatten_nil, List.append_nil, List.append_assoc]
    have hdepth : level + 1 + bs.length = level + (b :: bs).length := by
      rw [List.length_cons]; omega
    rw [hdepth]

/-- The expected ommer list of a frontier over leaves `L` at position `p`, read
    from level `j` upward over `fuel` levels: one ommer per set bit `i` of `p`,
    namely the level-`i` complete left-sibling subtree root. The full ommer list
    is `expOmmers L (n-1) 0 64`. Used by: the (A) ommer-value characterization. -/
def expOmmers {H : Type} [Hashable H] (L : List H) (p : Nat) (j : Nat) : Nat → List H
  | 0 => []
  | fuel + 1 =>
    (if p.testBit j then [merkleRoot j ((L.drop (baseIndex p (j + 1))).take (2 ^ j))] else [])
      ++ expOmmers L p (j + 1) fuel

/-- At position 0 there are no ommers. Used by: the base case of (A). -/
theorem expOmmers_zero {H : Type} [Hashable H] (L : List H) (j fuel : Nat) :
    expOmmers L 0 j fuel = [] := by
  induction fuel generalizing j with
  | zero => rfl
  | succ fuel ih => rw [expOmmers]; simp [Nat.zero_testBit, ih]

/-- An even append leaves the higher-level (`>= 1`) expected ommers unchanged:
    above bit 0 the position bits and the complete left-sibling slices are stable
    (`testBit_succ_of_even`, `baseIndex_succ_of_even`, `take_drop_append_singleton`).
    Used by: the even-append case of the (A) ommer-value characterization. -/
theorem expOmmers_succ_even {H : Type} [Hashable H] (L : List H) (w : H) (p : Nat)
    (hp : p % 2 = 0) (hpL : p < L.length) :
    ∀ (fuel j : Nat), 1 ≤ j →
      expOmmers (L ++ [w]) (p + 1) j fuel = expOmmers L p j fuel := by
  intro fuel
  induction fuel with
  | zero => intro j _; rfl
  | succ fuel ih =>
    intro j hj
    obtain ⟨j0, rfl⟩ : ∃ j0, j = j0 + 1 := ⟨j - 1, by omega⟩
    rw [expOmmers, expOmmers, testBit_succ_of_even p j0 hp,
      baseIndex_succ_of_even p (j0 + 1) hp]
    by_cases hbit : p.testBit (j0 + 1)
    · have hset : p / 2 ^ (j0 + 1) % 2 = 1 := (testBit_iff_div_mod p (j0 + 1)).mp hbit
      have hrange : baseIndex p (j0 + 1 + 1) + 2 ^ (j0 + 1) ≤ L.length := by
        rw [baseIndex_add_pow p (j0 + 1) hset]
        have := baseIndex_le p (j0 + 1); omega
      simp only [hbit, if_true]
      rw [take_drop_append_singleton L w _ _ hrange, ih (j0 + 1 + 1) (by omega)]
    · rw [if_neg hbit, if_neg hbit, ih (j0 + 1 + 1) (by omega)]

end NonEmptyFrontier

end Imt
