---
sidebar_position: 6
title: "Retention, Marking, and Checkpoints"
description: "The fixed vocabulary of leaf metadata that decides what the pruned trees keep: Ephemeral, Checkpoint, Marked, Reference, and the checkpoint model."
---

# Retention, Marking, and Checkpoints

## 1. Why this chapter exists

The whole point of `bridgetree` and `shardtree` is to *not* store most of
the tree. What they keep is governed by a small fixed vocabulary attached
to leaves: `Retention` and `Marking`. Every pruning decision, every
witness that survives, and every rollback boundary is expressed in these
terms. This is the vocabulary chapter; later chapters cite these
definitions instead of re-deriving them. The types live in
[`incrementalmerkletree/src/lib.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs)
lines 73-142; the `shardtree` bit-flag encoding is in
[`shardtree/src/prunable.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs).

## 2. Definitions

**Definition 6.1 (Retention).** `Retention<C>` is the metadata that
decides when and how a leaf may be pruned. The four variants:

- `Ephemeral`: prunable as soon as its sibling is also an ephemeral leaf.
  The default for leaves you do not care about.
- `Checkpoint { id: C, marking: Marking }`: the leaf's position is
  retained as a rollback boundary identified by `id`; the value may be
  merged away. When the checkpoint is later removed, the leaf's retention
  becomes `Ephemeral`, `Marked`, or `Reference` per the `marking` field.
- `Marked`: retained until explicitly unmarked. This is "I want a witness
  for this leaf forever."
- `Reference`: retained until overwritten by a non-reference value;
  cannot be added to an existing leaf.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L88-L107
```

**Definition 6.2 (Marking).** `Marking` is the residual retention a
checkpoint leaf takes after the checkpoint is removed: `Marked`,
`Reference`, or `None` (becomes `Ephemeral`). A checkpoint with
`Marking::Marked` is the standard "checkpoint a spendable note" case.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L73-L86
```

**Definition 6.3 (RetentionFlags).** `shardtree` encodes retention as a
`u8` bit-flag (`EPHEMERAL = 0`, `CHECKPOINT = 1`, `MARKED = 2`,
`REFERENCE = 4`) so a leaf can carry several at once (a leaf can be both a
checkpoint and marked). The `From<&Retention<C>>` conversion maps the
enum onto the flags.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L17-L42
```

Each flag pins a leaf against pruning in a different way:

| Flag | Bit | Prunable when |
| --- | --- | --- |
| `EPHEMERAL` | `0b000` | its sibling is also prunable and it is not part of a witness for a checkpoint or marked leaf |
| `CHECKPOINT` | `0b001` | more than `max_checkpoints` later checkpoint leaves exist, unless also `MARKED` |
| `MARKED` | `0b010` | only on an explicit unmark (delete) |
| `REFERENCE` | `0b100` | the `REFERENCE` flag is removed, which happens when the leaf is overwritten without it |

`EPHEMERAL` is the absence of bits, not a bit of its own. `CHECKPOINT`
only marks a position as a rewind boundary; the checkpoint id itself lives
in the store's checkpoint registry (Definition 6.5), not on the leaf.
`REFERENCE` is asymmetric: it cannot be added to an existing leaf, only
set at insertion, and is for externally supplied nodes (for example
subtree roots inserted by `zcash_client_sqlite`) that must be kept until
real data supersedes them.

Because the encoding is a bitset, the `From<&Retention<C>>` conversion can
set more than one bit, and a `Checkpoint` leaf's residual flags depend on
its `Marking` (Definition 6.2):

| `Retention<C>` | `RetentionFlags` |
| --- | --- |
| `Ephemeral` | `EPHEMERAL` (`0`) |
| `Checkpoint { marking: None }` | `CHECKPOINT` (`1`) |
| `Checkpoint { marking: Marked }` | `CHECKPOINT \| MARKED` (`3`) |
| `Checkpoint { marking: Reference }` | `CHECKPOINT \| REFERENCE` (`5`) |
| `Marked` | `MARKED` (`2`) |
| `Reference` | `REFERENCE` (`4`) |

The common wallet leaf is `CHECKPOINT | MARKED`: a block boundary at which
one of the wallet's own notes landed, so the position is both a rewind
anchor and permanently witnessed.

**Invariant 6.4 (prunability).** A leaf is prunable iff it carries none of
`CHECKPOINT`, `MARKED`, `REFERENCE`, and its sibling is also prunable.
This is the predicate the merge logic in
[Chapter 10](./10-prunable-tree.md) enforces; it is the formal meaning of
"densely filled from the left, sparse elsewhere".

**Definition 6.5 (Checkpoint, shardtree).** A `shardtree` `Checkpoint`
records a `TreeState` (either `Empty` or `AtPosition(p)`) plus the set of
marked positions removed since the previous checkpoint
(`marks_removed`). Checkpoints are stored in `CheckpointId` order; the
store can seek to "checkpoint depth $d$" meaning the $d$-th most recent.

```rust reference title="shardtree/src/store.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L257-L320
```

A `shardtree` checkpoint is a lightweight *rewind anchor*, not a snapshot.
It stores only a `TreeState` (a position, or `Empty`) and the
`marks_removed` delta, so rewinding means truncating everything appended
after that position rather than restoring a saved copy.
`ShardTree::checkpoint(id)` tags the current rightmost leaf with the
`CHECKPOINT` flag and registers the checkpoint;
`ShardTree::truncate_to_checkpoint` (and its `_depth` variant) is the
rewind. History is bounded: `ShardTree` carries a `max_checkpoints`, and
`prune_excess_checkpoints` drops the oldest once that limit is exceeded,
using each dropped checkpoint's `marks_removed` to clear the
corresponding `MARKED` flags. The `id` is generic (`Clone + Debug + Ord`);
in the wallet it is a block height, with one checkpoint per scanned block,
so a chain reorg rewinds the tree to the last valid block.

**Definition 6.6 (Checkpoint, bridgetree).** `bridgetree`'s `Checkpoint<C>`
instead records the number of bridges at checkpoint time
(`bridges_len`), the id, and the marked/forgotten position sets. A
`rewind` pops one checkpoint and truncates the bridge list back to that
length.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L320-L390
```

## 3. The code: how retention flows through an append

When you append with a `Retention`, the trees translate it as follows:

- `Ephemeral` leaves carry no flag and are eligible for immediate merge
  once their sibling is also ephemeral.
- `Checkpoint` both sets the `CHECKPOINT` flag on the leaf and registers a
  checkpoint with the store (`ShardTree::checkpoint`, `BridgeTree::checkpoint`).
- `Marked` sets `MARKED`; the position is added to the marked set so its
  witness is maintained on every later append.
- `Reference` sets `REFERENCE`; note the asymmetry in Definition 6.1 that
  it cannot be *added* to an existing leaf, only set on insertion.

The `is_checkpoint`/`is_marked` helpers on both `Retention` and
`RetentionFlags` are the predicates the pruning code branches on:

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L109-L142
```

## 4. Failure modes

- **Marking the empty tree.** You cannot give the empty-tree state
  `Marked` retention; there is no leaf to witness. `shardtree` returns
  `InsertionError::MarkedRetentionInvalid`. Caught by: the insertion path
  in `shardtree/src/lib.rs` (the error is constructed there).
- **Out-of-order checkpoints.** Checkpoint ids must be nondecreasing
  relative to tree position. A smaller-or-equal id than the current
  maximum is rejected: `shardtree` returns
  `InsertionError::CheckpointOutOfOrder`; `bridgetree::checkpoint`
  returns `false`. Caught by: `error.rs` defines the variant;
  differential `check_operations` proptests exercise the ordering.
- **Assuming `Reference` survives an overwrite.** `REFERENCE` is dropped
  whenever the leaf is rewritten without it. Code that relies on a
  reference persisting across a re-insert is wrong. Caught by: the
  `clear_flags` logic in `prunable.rs`. No dedicated named test; covered
  by proptests.
- **Confusing checkpoint *depth* with checkpoint *id*.** Depth is a
  0-based index in reverse id order ("0 = most recent"); id is the
  caller's identifier. The 0.5.0 rework made every witness/rewind take a
  depth. Caught by: see [Chapter 11](./11-shardtree-operations.md) and the
  `check_operations` harness.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8 and the wallet sections motivate marking (a wallet marks its
  own notes to maintain spend witnesses) and checkpoints (chain reorgs
  require rolling the tree back to a prior block boundary). Cited because
  `Retention::Checkpoint` corresponds to a block boundary and
  `Retention::Marked` to a wallet-owned note.

## 6. Exercises

1. **Answer from code.** What residual retention does a leaf inserted with
   `Retention::Checkpoint { marking: Marking::None, .. }` have after its
   checkpoint is removed? Cite the `Marking` docstring.
2. **Map the encoding.** Give the `RetentionFlags` `u8` value for a leaf
   that is simultaneously a checkpoint and marked. Verify against the
   `From<Retention<C>>` impl in `prunable.rs`.
3. **Add a test (modify).** Add a unit test in `prunable.rs` asserting
   that `RetentionFlags::from(&Retention::<u32>::Marked).is_marked()` is
   `true` and `is_checkpoint()` is `false`, and that the `EPHEMERAL`
   conversion yields the empty flag set. Confirm
   `cargo test -p shardtree` passes.

### Answers in the code

- Exercise 1: `Ephemeral` (Marking::None maps to Ephemeral),
  `incrementalmerkletree/src/lib.rs:83-85`.
- Exercise 2: `CHECKPOINT | MARKED = 0b011 = 3`; see the `From` impl at
  `shardtree/src/prunable.rs:54-78`.
- Exercise 3: model on the `is_marked`/`is_checkpoint` helpers at
  `shardtree/src/prunable.rs:44-52`.

## 7. Further reading

- [Chapter 10: The Prunable Tree](./10-prunable-tree.md) is where these
  flags decide what survives a merge.
- [Chapter 11](./11-shardtree-operations.md) covers checkpoint creation,
  rollback, and the depth-vs-id distinction in full.
