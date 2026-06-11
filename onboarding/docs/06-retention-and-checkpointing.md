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
