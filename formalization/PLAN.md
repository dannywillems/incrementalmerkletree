# Lean 4 formalization plan: incrementalmerkletree

This document maps the data structures and correctness properties of the
workspace to a concrete Lean 4 formalization. It is the planning artifact;
no `.lean` files exist yet. Theorem signatures below are the contracts we
intend to state and prove.

ASCII note: signatures here are written in an ASCII rendering (`forall`,
`->`, `<=`, `/\`) to match the house style in `~/.claude/rules/lean.md`.
The actual `.lean` sources may use the standard unicode notation
(`forall`, `->`, `<=`, `/\` become the usual symbols); that is a cosmetic
choice to settle when the project is scaffolded.

## 1. goal and scope

Prove that each tree representation in the workspace correctly implements a
single mathematical object: a binary Merkle tree over an append-only leaf
sequence, hashed by an abstract `combine`.

In scope (this is what the Rust code actually guarantees):

- structural correctness of addressing arithmetic (Level, Position,
  Address);
- that each representation's `root` equals the reference Merkle root of the
  leaves it represents;
- that `append` / `insert` / `batch_insert` refine "add a leaf to the
  sequence";
- that witnesses produced by the structures verify against the root;
- that pruning, merging, checkpointing, and garbage collection preserve all
  still-observable roots and witnesses (refinement / observational
  equivalence).

Explicitly out of scope (not provable from this code alone):

- cryptographic soundness, i.e. that a valid witness *binds* its leaf. That
  requires a collision-resistance assumption on `combine` and is a separate
  theory layered on top. We will model `combine` as an unconstrained
  function so the structural theorems hold for any hash, and add the
  collision-resistance hypothesis only where binding is claimed.

## 2. modeling decisions

### 2.1 number model: BitVec

Per the chosen approach, the wrapping integer types map directly onto Lean
`BitVec`:

```lean
abbrev Level    := BitVec 8     -- Rust u8
abbrev PosNat   := BitVec 64    -- Rust u64, used for Position and index
structure Position where val : BitVec 64
structure Address  where level : Level; index : BitVec 64
```

Rationale and consequences:

- `BitVec 64` / `BitVec 8` match Rust's `u64` / `u8` wrapping semantics
  exactly, so the model is faithful to overflow behavior at the boundaries.
- The decision procedure `bv_decide` discharges quantifier-free fixed-width
  goals automatically. This covers the bit-identity lemmas (P0.1, P0.2,
  P0.5) cheaply.
- For lemmas that quantify over all bit positions or recurse on bit count
  (popcount = P0.4, log2 = P0.3), `bv_decide` may not scale; we fall back to
  `BitVec.toNat` bridging into `Nat` and Mathlib's `Nat.testBit`,
  `Nat.log2`, `Nat.size`, `Nat.popCount` lemmas, then transfer back.
- Rust's panicking subtractions (`Position - u64`, `Level - u8`) become
  side-conditions: either guard the call sites with hypotheses
  (`other <= self`) or use the natural `BitVec` sub and prove the guard
  holds wherever the code relies on it.

Helper definitions we will need early:

```lean
def popcount (x : BitVec n) : Nat := (List.range n).countP (fun i => x.getLsbD i)
def clz (x : BitVec 64) : Nat := 64 - Nat.size x.toNat   -- count leading zeros
```

### 2.2 the hash: abstract and unconstrained

```lean
class Hashable (H : Type) where
  emptyLeaf : H
  combine   : Level -> H -> H -> H

def emptyRoot [Hashable H] : Level -> H
  | l => Nat.rec emptyLeaf
           (fun k acc => Hashable.combine (BitVec.ofNat 8 k) acc acc)
           l.toNat
```

No algebraic axioms on `combine`. Every structural theorem below is
`forall H [Hashable H], ...`.

### 2.3 the reference model

The single source of truth all representations are compared against:

```lean
-- the leaf list, padded with emptyLeaf to length 2^level, folded into a root
def merkleRoot [Hashable H] (level : Level) (leaves : List H) : H
```

`merkleRoot` is the naive, obviously-correct definition (build the perfect
tree of the given level, pad with `emptyLeaf`, fold `combine` upward). Its
simplicity is the point: every "root correctness" theorem says a clever
representation computes the same value as `merkleRoot`.

### 2.4 abstraction functions and refinement

For each concrete structure `T` we define `repr : T -> List H` (the leaf
sequence it represents) and prove:

- `append` refines `++ [v]` on `repr`;
- `root` equals `merkleRoot DEPTH (repr t)`;
- witnesses verify (`MerklePath.root leaf = root`).

This `repr` + refinement pattern is reused verbatim at every layer.

## 3. proposed project layout

```
formalization/
|-- PLAN.md                     (this file)
|-- lakefile.toml               (depends on mathlib)
|-- lean-toolchain
`-- Imt/
    |-- Basic.lean              Level, Position, Address + bit helpers
    |-- Addressing.lean         Layer 0 theorems (P0.*)
    |-- Hash.lean               Hashable, emptyRoot, merkleRoot model (P1.*)
    |-- MerklePath.lean         MerklePath.root + verification (P1.3)
    |-- Frontier.lean           NonEmptyFrontier / Frontier (P2.*)
    |-- Witness.lean            IncrementalWitness (P3.*)
    |-- Bridge.lean             MerkleBridge / BridgeTree (P4.*)
    `-- Shard/
        |-- Tree.lean           Node / Tree / LocatedTree (P5.5)
        |-- Prunable.lean       PrunableTree, root_hash, merge (P5.1-5.3)
        `-- ShardTree.lean      cap+shards, batch_insert (P5.4)
```

The module dependency order is the recommended proof order (Section 5).

## 4. property catalog

Difficulty key: E easy (`bv_decide`/`simp`/`omega`), M medium (induction or
Nat bridge), H hard (the substantive theorems). Source = file:line in the
Rust crates.

### layer 0: addressing arithmetic  (`incrementalmerkletree/src/lib.rs`)

```lean
-- P0.1  navigation round-trips                                   [E, L399-431]
theorem sibling_sibling (a : Address) : a.sibling.sibling = a
theorem parent_children (a : Address) (h : a.level <> 0) :
  let (l, r) := a.children.get h; l.parent = a /\ r.parent = a

-- P0.2  above_position / from_position                           [E, L376-381]
theorem above_position_index (l : Level) (p : Position) :
  (Address.abovePosition l p).index = p.val >>> l.toNat

-- P0.3  root level = floor(log2)+1 (0 at 0)                      [M, L199-201]
theorem root_level_eq (p : Position) :
  (Position.rootLevel p).toNat = 64 - clz p.val

-- P0.4  past ommer count = popcount   (Lemma 3.7)               [M, L205-211]
theorem past_ommer_count_eq_popcount (p : Position) :
  (Position.pastOmmerCount p).toNat = popcount p.val

-- P0.5  complete subtree iff low bits set                        [E, L216-218]
theorem is_complete_subtree_iff (p : Position) (l : Level) :
  Position.isCompleteSubtree p l
    <-> forall i, i < l.toNat -> p.val.getLsbD i = true

-- P0.6  is_ancestor_of is a strict partial order; contains is the
--       reflexive closure                                        [M, L434-464]
theorem contains_refl (a : Address) : a.contains a
theorem is_ancestor_trans (a b c : Address) :
  a.isAncestorOf b -> b.isAncestorOf c -> a.isAncestorOf c
theorem contains_antisymm (a b : Address) :
  a.contains b -> b.contains a -> a = b

-- P0.7  common_ancestor is the join (least common ancestor)      [H, L439-458]
theorem common_ancestor_contains (a b : Address) :
  (a.commonAncestor b).contains a /\ (a.commonAncestor b).contains b
theorem common_ancestor_least (a b c : Address) :
  c.contains a -> c.contains b -> c.contains (a.commonAncestor b)

-- P0.8  position ranges partition; ancestor iff range containment [M, L466-524]
theorem ancestor_iff_range_subset (a b : Address) :
  a.contains b <-> (b.positionRange.subset a.positionRange)

-- P0.9  witness_addrs enumerates the leaf-to-root siblings,
--       #Past = popcount, tags match child parity               [M, L154-231]
theorem witness_addrs_past_count (p : Position) (L : Level) :
  ((Position.witnessAddrs p L).filter isPast).length
    = popcount (p.val &&& (BitVec.allOnes 64 >>> (64 - L.toNat)))

-- P0.10 current_incomplete / next_incomplete_parent terminate
--       and are characterized                                    [M, L536-563]
theorem next_incomplete_parent_spec (a : Address) : ...
```

The Rust unit tests (`tests::position_witness_addrs`,
`tests::position_past_ommer_count`, `tests::addr_common_ancestor`, etc.) are
exact value oracles; each becomes a Lean `example`/`#eval`-checked sanity
lemma alongside the universal theorem.

### layer 1: hashing and Merkle path  (`lib.rs` L612-679)

```lean
-- P1.1  empty root recurrence                                    [E, L671-678]
theorem empty_root_succ [Hashable H] (l : Level) :
  emptyRoot (l + 1) = Hashable.combine l (emptyRoot l) (emptyRoot l)

-- P1.3  MerklePath.root reproduces the model root from true siblings
--                                                                [H, L642-656]
theorem merkle_path_root_correct [Hashable H]
    (leaves : List H) (pos : Position) (depth : Nat)
    (h : pos.val.toNat < 2 ^ depth) :
  (truePathFor leaves pos depth).root (leaves.get pos)
    = merkleRoot (BitVec.ofNat 8 depth) leaves

-- P1.4  path length invariant                                    [E, L619-631]
theorem from_parts_length [Hashable H] (elems : List H) (pos : Position) :
  (MerklePath.fromParts elems pos (DEPTH := d)).isSome -> elems.length = d
```

### layer 2: frontier  (`incrementalmerkletree/src/frontier.rs`)

`repr (f : NonEmptyFrontier H) : List H` recovers the leaf sequence.

```lean
-- P2.1  well-formedness preserved: ommers.length = popcount position
--                                                                [M, L53-136]
theorem frontier_wf_append [Hashable H] (f : NonEmptyFrontier H) (v : H) :
  f.WF -> (f.append v).WF
  -- where WF := f.ommers.length = popcount f.position.val

-- P2.2  append refines the leaf list                             [M, L91-136]
theorem repr_append [Hashable H] (f : NonEmptyFrontier H) (v : H) :
  f.WF -> repr (f.append v) = repr f ++ [v]

-- P2.3  ROOT CORRECTNESS (centerpiece)                           [H, L139-165]
theorem frontier_root_eq_model [Hashable H]
    (f : NonEmptyFrontier H) (L : Level) (h : f.WF) :
  f.root (some L) = merkleRoot L (repr f)

-- P2.4  witness soundness                                        [H, L172-185]
theorem frontier_witness_verifies [Hashable H]
    (f : NonEmptyFrontier H) (depth : Nat) (complement : Address -> Option H)
    (path : List H) (h : f.witness depth complement = .ok path) :
  (MerklePath.fromParts path f.position).get.root f.leaf = f.root (some ...)

-- P2.5  Frontier (depth-bounded) wrapper                         [E/M, L335-358]
theorem frontier_empty_root [Hashable H] :
  (Frontier.empty (DEPTH := d)).root = emptyRoot (BitVec.ofNat 8 d)
theorem frontier_append_full [Hashable H] (f : Frontier H d) :
  f.append v = false <-> f.isFullAtDepth d

-- P2.6  CommitmentTree <-> Frontier isomorphism + root agreement
--                                                          [M, L547-596]
theorem commitment_frontier_roundtrip [Hashable H] (ct : CommitmentTree H d) :
  CommitmentTree.fromFrontier ct.toFrontier = ct
theorem commitment_frontier_root_agree [Hashable H] (ct : CommitmentTree H d) :
  ct.toFrontier.root = ct.root
```

P2.3 is the crown jewel: it states the ommer-fold-with-empty-roots in
`NonEmptyFrontier::root` computes the same value as the naive padded tree.
Prove by induction on `repr f` length, using P0.9 to characterize the fold.

### layer 3: incremental witness  (`incrementalmerkletree/src/witness.rs`)

```lean
-- P3.1  WITNESS TRACKING (centerpiece)                           [H, L180-264]
theorem witness_tracks_root [Hashable H]
    (t : CommitmentTree H d) (extra : List H) (h : not t.isEmpty) :
  let w := (IncrementalWitness.fromTree t).get
  (w.appendAll extra).root = (t.appendAll extra).root
theorem witness_path_verifies [Hashable H] (w : IncrementalWitness H d) :
  forall p, w.path = some p -> p.root (leafAt w) = w.root

-- P3.2  tip position formula                                     [M, L118-138]
theorem tip_position_eq (w : IncrementalWitness H d) :
  w.tipPosition.val.toNat
    = w.witnessedPosition.val.toNat
      + (w.filled.map (2 ^ levelOf .)).sum + w.cursorSize
```

### layer 4: bridgetree  (`bridgetree/src/lib.rs`)

```lean
-- P4.1  continuity: a continuous bridge chain = one frontier     [M, L164-186]
theorem continuous_chain_repr [Hashable H] (bs : List (MerkleBridge H))
    (h : Chain.continuous bs) :
  repr (BridgeTree.fuse bs) = (bs.map repr).flatten

-- P4.2  root agreement                                           [H, L633-687]
theorem bridgetree_root_eq_model [Hashable H] (bt : BridgeTree H C d) :
  bt.root 0 = some (merkleRoot (BitVec.ofNat 8 d) (repr bt))

-- P4.3  mark/witness soundness                                   [H, L820-910]
theorem bridge_witness_verifies [Hashable H] (bt : BridgeTree H C d)
    (pos : Position) (path : MerklePath H d) :
  bt.witness pos cd = .ok path -> path.root (leafAt bt pos) = (bt.root cd).get

-- P4.4  checkpoint id monotonic; rewind . checkpoint = id        [M, L760-818]
theorem rewind_checkpoint_id [Hashable H] (bt : BridgeTree H C d) (id : C) :
  bt.checkpoint id = true -> (bt.checkpointed id).rewind.observable = bt.observable

-- P4.5  garbage_collect preserves observable witnesses/roots     [H, L911-..]
theorem gc_observational_eq [Hashable H] (bt : BridgeTree H C d) :
  bt.garbageCollect.observable = bt.observable
```

`observable` projects the externally visible behavior (roots at every
checkpoint depth, witnesses for every marked position); P4.4/P4.5 are
observational-equivalence statements rather than equalities of internal
state.

### layer 5: shardtree / prunable tree  (`shardtree/src/`)

```lean
-- P5.1  root agreement under truncation; Some annotation is a sound cache
--                                                          [H, prunable.rs L174-220]
theorem root_hash_eq_model [Hashable H] (t : PrunableTree H)
    (addr : Address) (truncateAt : Position) (h : t.WF addr) :
  t.rootHash addr truncateAt
    = .ok (merkleRoot addr.level (t.materializedLeaves addr truncateAt))
theorem annotation_sound [Hashable H] (t : PrunableTree H) (addr : Address) :
  t.annotation = some r -> t.WF addr -> r = (t.rootHash addr addr.maxPos).get

-- P5.2  prune preserves root and never drops retained leaves [H, L256-269]
theorem prune_preserves_root [Hashable H] (t : PrunableTree H)
    (lvl : Level) (addr : Address) (tr : Position) :
  (t.prune lvl).rootHash addr tr = t.rootHash addr tr
theorem prune_keeps_marked [Hashable H] (t : PrunableTree H) (lvl : Level) :
  t.containsMarked -> (t.prune lvl).containsMarked

-- P5.3  merge_checked is the information-union; conflict iff disagreement
--                                                          [H, L277-..]
theorem merge_checked_root [Hashable H] (t u : PrunableTree H) (addr : Address)
    (m : PrunableTree H) (h : t.mergeChecked addr u = .ok m) :
  m.rootHash addr p = t.rootHash addr p \/ m.rootHash addr p = u.rootHash addr p
theorem merge_checked_comm [Hashable H] (t u : PrunableTree H) (addr : Address) :
  (t.mergeChecked addr u).map rootOf = (u.mergeChecked addr t).map rootOf

-- P5.4  insert agreement: append-loop = batch_insert = parallel build
--                                                          [H, batch.rs]
theorem batch_insert_eq_append_loop [Hashable H]
    (start : Position) (leaves : List (H x Retention)) :
  (ShardTree.empty.batchInsert start leaves).tree
    = (leaves.foldl (fun st (v, r) => st.append v r) (paddedTo start)).tree

-- P5.5  structural well-formedness preserved by every op    [H, tree.rs/lib.rs]
def WF : LocatedPrunableTree H -> Prop   -- no Parent(Nil,Nil); no Parent at lvl 0;
                                          -- cap holds only shard-root leaves
theorem append_preserves_wf  [Hashable H] : t.WF -> (t.append v r).tree.WF
theorem merge_preserves_wf   [Hashable H] : t.WF -> u.WF -> (mergeOk).WF
theorem root_caching_preserves_wf [Hashable H] : st.WF -> st.rootCaching.WF

-- P5.6  RetentionFlags conversion + prunability predicate  [E/M, prunable.rs L44-80]
theorem retention_flags_from (r : Retention C) : RetentionFlags.ofRetention r = ...
theorem prunable_iff (leaf : H x RetentionFlags) (siblingPrunable : Bool) :
  leaf.prunable <-> (leaf.2.flags &&& (CHECKPOINT ||| MARKED ||| REFERENCE) = 0
                     /\ siblingPrunable)
```

The three documented regression bugs are negations of theorems here:
P5.5 (cap held a sub-shard Parent: `4d78d5b` test, `202fb2a` fix), P5.1
(cached root ignored truncation: `b0b3eb9` test, `513972b` fix), and a
frontier-gen empty-vs-incomplete edge (`04b97bd`). Proving these theorems is
proving those bugs cannot recur.

## 5. roadmap

Milestones in dependency order. Each is independently useful.

1. M0 - project scaffold: `lakefile.toml`, Mathlib dep, `Imt/Basic.lean`
   with Level/Position/Address and the bit helpers (`popcount`, `clz`).
2. M1 - Layer 0 (`Addressing.lean`): P0.1, P0.2, P0.5 by `bv_decide`;
   then P0.3, P0.4, P0.9; then the partial-order/lattice block P0.6-P0.8.
   This is the foundation and the proof that the BitVec approach scales.
3. M2 - Layer 1 (`Hash.lean`, `MerklePath.lean`): `merkleRoot` model,
   P1.1, P1.3.
4. M3 - Layer 2 (`Frontier.lean`): P2.1, P2.2, then the centerpiece P2.3,
   then P2.4. Reaching P2.3 validates the whole methodology.
5. M4 - Layer 3 (`Witness.lean`): P3.1.
6. M5 - Layer 4 (`Bridge.lean`): P4.1-P4.3.
7. M6 - Layer 5 (`Shard/`): P5.5 (well-formedness) first, then P5.1, then
   P5.2/P5.3, then the big refinement P5.4.

Suggested first vertical slice to de-risk: M0 + the `bv_decide` subset of M1
(P0.1, P0.2, P0.5). That confirms the BitVec model, Mathlib integration, and
the test-oracle workflow before committing to the harder inductive proofs.

## 6. rust test -> lean oracle map

Each existing Rust test gives concrete expected values to cross-check the
universal Lean theorems (state them as `example` lemmas closed by `decide`
or `native_decide` on the BitVec model):

| Rust test | crate | pins | Lean check for |
|-----------|-------|------|----------------|
| `position_witness_addrs` | imt | witness_addrs values | P0.9 |
| `position_past_ommer_count` | imt | popcount values | P0.4 |
| `position_root_level` | imt | root_level values | P0.3 |
| `addr_common_ancestor` | imt | LCA values | P0.7 |
| `address_current_incomplete`, `address_next_incomplete_parent` | imt | helper values | P0.10 |
| `merkle_path_root` | imt | string-hash root | P1.3 |
| `nonempty_frontier_root`, `frontier_root` | imt | concat-hash roots | P2.3 |
| `nonempty_frontier_witness`, `frontier_witness` | imt | path elements | P2.4 |
| `prop_commitment_tree_roundtrip` | imt | round-trip | P2.6 |
| `witness_tip_position` | imt | tip position | P3.2 |
| `check_operations` proptests | shardtree | differential ops | P5.1, P5.4 |
