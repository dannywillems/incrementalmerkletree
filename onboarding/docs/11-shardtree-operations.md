---
sidebar_position: 11
title: "shardtree: Operations"
description: "The top-level ShardTree API: append, insert_tree, checkpoint, truncate, the cached-root fast path, and witnessing at a checkpoint depth."
---

# shardtree: Operations

## 1. Why this chapter exists

This is the API a wallet actually calls, and it is the most-changed file
in the repository (`shardtree/src/lib.rs`, 7 touches in the last year).
Most contributions land here: a witness edge case, a checkpoint off-by-one,
a cap-caching bug. You need to know which method does what, and in
particular the difference between `root` and `root_caching` (the caching
path is where the recent corruption bugs lived). The code is
[`shardtree/src/lib.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs).

## 2. Definitions

**Definition 11.1 (address helpers).** `ShardTree::root_addr()` is the
whole-tree address `(DEPTH, 0)`; `subtree_level()` is `SHARD_HEIGHT`;
`subtree_addr(pos)` is the address of the shard containing `pos`. These
fix how positions map to shards.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L112-L130
```

**Definition 11.2 (append).** `append(value, retention)` adds one leaf at
the next position with the given `Retention`, creating shards as needed.
It is the simplest write; `insert_tree` and the batch path
([Chapter 13](./13-batch-insertion.md)) are the bulk equivalents.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L273-L331
```

**Definition 11.3 (insert by frontier).** `insert_frontier` and
`insert_frontier_nodes` seed the tree from a `NonEmptyFrontier`, the way a
wallet starts mid-chain from a checkpoint shipped by a server rather than
replaying every leaf.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L332-L409
```

**Definition 11.4 (checkpoint and truncate).** `checkpoint(id)` records a
rollback boundary; `truncate_to_checkpoint_depth(d)` discards all state to
the right of the $d$-th most recent checkpoint; `truncate_to_checkpoint`
keeps the checkpoint but drops later leaves. Depth is a 0-based index in
reverse id order (Definition 6.5).

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L461-L470
```

**Definition 11.5 (root, cached and uncached).** `root(checkpoint_depth)`
computes the tree root by querying shards and the cap. `root_caching`
additionally writes back computed subtree roots into the cap so subsequent
roots are cheaper. The caching variant calls `root_internal` over the cap
and persists the updated cap via `put_cap`.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L762-L800
```

**Definition 11.6 (witness at depth).** `witness_at_checkpoint_depth(pos,
d)` produces the authentication path for a marked leaf as of the $d$-th
checkpoint, returning `QueryError::CheckpointPruned` if the leaf needed for
that checkpoint has been pruned. There is a `_caching` variant and an
`_id` variant keyed by checkpoint id.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L1284-L1340
```

## 3. The code: the cap-caching path

`root_caching` is the method to study before touching this file, because
it both reads and writes the cap, and the cap must contain only shard-root
leaves (levels `SHARD_HEIGHT..DEPTH`). `root_internal` walks the cap and
may compute and cache subtree roots; the bug fixed in `202fb2a` was that
it could split a cap leaf into sub-shard `Parent` nodes, violating
Invariant 9.3 at the cap level.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L782-L820
```

`frontier()` extracts a depth-bounded `Frontier<H, DEPTH>` from the tree,
distinguishing the empty tree from an incomplete one (the
`04b97bd`/`59f660d` work).

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L172-L215
```

`remove_mark(position, ...)` drops a maintained witness, allowing the
subtree to become prunable again.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L1405-L1410
```

## 4. Failure modes

- **Cap corruption via `root_caching`.** Caching a computed root must not
  introduce a `Parent` below the cap's leaf level. The fix asserts the cap
  holds only shard-root leaves. Caught by: the regression test added in
  `4d78d5b` (failing) and fixed in `202fb2a`, both in
  `shardtree/src/lib.rs`. See [Chapter 15](./15-failure-modes-and-audits.md).
- **Witnessing/rewinding with no checkpoint.** Since the 0.5.0 rework, all
  witnessing and rewinding require at least one checkpoint; depth indexes
  into existing checkpoints. A call with insufficient checkpoints returns
  `None`/`CheckpointPruned`. Caught by: the depth handling in
  `truncate_to_checkpoint_depth` and `check_operations` proptests.
- **Trusting a stale cached root after truncation.** The Parent
  annotation fast-path must respect `truncate_at`. Ignoring it returns a
  root for leaves that were supposed to be truncated away. Caught by:
  `b0b3eb9`/`513972b` regression test in `shardtree/src/lib.rs`.
- **Checkpoint id ordering.** `checkpoint` returns `false` (or
  `CheckpointOutOfOrder` on insert) for a non-increasing id. Caught by:
  `error.rs` + differential tests.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8 and the wallet reorg handling: a chain reorg requires
  rolling the note commitment tree back to a block boundary, which is
  exactly `truncate_to_checkpoint_depth`. The witness as of a checkpoint
  is the anchor a spend is proven against. Cited because the
  checkpoint/rewind semantics implement the wallet's reorg requirement.

## 6. Exercises

1. **Answer from code.** What is the difference in stored state after
   calling `root` versus `root_caching` on the same tree? Cite the
   `put_cap` call.
2. **Checkpoint depth.** Append leaves, create three checkpoints with ids
   `1, 2, 3`, then call `root_at_checkpoint_depth(1)`. Which checkpoint id
   does depth 1 select, and why? Verify with a small test.
3. **Reproduce a fixed bug (modify).** Check out the parent of `202fb2a`
   (`git checkout 4d78d5b~1`), run `cargo test -p shardtree`, and observe
   the cap-corruption test fail; then `git checkout 202fb2a` and confirm
   it passes. Write one paragraph in your own notes describing the
   invariant the test guards (cap holds only shard-root leaves).

### Answers in the code

- Exercise 1: `root_caching` persists computed roots via `put_cap`
  (`shardtree/src/lib.rs:794-797`); `root` does not write back.
- Exercise 2: depth 1 selects checkpoint id `2` (depth 0 is the most
  recent, id `3`); see the depth handling around
  `root_at_checkpoint_depth` (`lib.rs:1173-1202`).
- Exercise 3: the regression lives in `shardtree/src/lib.rs`; the fix is
  `202fb2a`.

## 7. Further reading

- [Chapter 12: Shard Stores](./12-shard-stores.md) is the persistence
  layer these operations read and write through.
- [Chapter 13: Batch Insertion](./13-batch-insertion.md) is the bulk write
  path that wallets use to ingest a whole block range at once.
