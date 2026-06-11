---
sidebar_position: 10
title: "The Prunable Tree"
description: "PrunableTree and RetentionFlags: root computation over a partially pruned tree, pruning, and the conflict-checked merge."
---

# The Prunable Tree

## 1. Why this chapter exists

`PrunableTree` is where `shardtree`'s space efficiency actually happens. It
specialises the generic `Tree` so that every leaf carries `RetentionFlags`
and every parent annotation caches a subtree root, then defines two
operations that must be provably correct: computing a root from a tree
with holes (`root_hash`), and merging two views of the same subtree
without losing data (`merge_checked`). A bug in either silently produces a
wrong root, which a wallet would turn into an invalid spend proof. The code
is
[`shardtree/src/prunable.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs).

## 2. Definitions

**Definition 10.1 (PrunableTree).** The type alias

$$
\mathtt{PrunableTree}\langle H \rangle =
\mathtt{Tree}\langle\ \mathtt{Option}\langle\mathtt{Arc}\langle H\rangle\rangle,\
(H,\ \mathtt{RetentionFlags})\ \rangle.
$$

A parent's annotation is `Some(root)` when the subtree root is cached,
`None` when it must be recomputed. A leaf is a pair of its hash and its
retention flags.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L80-L112
```

**Definition 10.2 (root with truncation).** `root_hash(root_addr,
truncate_at)` computes the subtree root, treating every position $\ge$
`truncate_at` as empty (so a root "as of" an earlier state can be
computed). It returns `Err(Vec<Address>)` listing the `Nil` addresses that
block the computation when a needed node is missing.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L174-L226
```

**Invariant 10.3 (root agreement).** For a fully materialised subtree and
any `truncate_at` beyond its max position, `root_hash` equals the
`Hashable` root of the same leaves. Pruning must never change a computable
root: a `Some` annotation is only ever a correct cache of what `root_hash`
would compute. This is the property the `prunable` proptests assert.

**Definition 10.4 (prune).** `prune(level)` collapses fully materialised
subtrees at or below `level` whose leaves carry no retention flag into a
single annotated `Leaf` (the cached root), discarding the children. This
is the size-reduction step.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L259-L275
```

**Definition 10.5 (conflict-checked merge).** `merge_checked(root_addr,
other)` combines two `PrunableTree`s over the same address into one that
contains the union of their information, returning
`MergeError::Conflict(addr)` if the two disagree on a materialised value
at any address. This is how a freshly computed subtree is reconciled with
the stored one.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L277-L375
```

**Definition 10.6 (LocatedPrunableTree).** A `PrunableTree` with a root
address. Adds the position-aware operations: `max_position`,
`marked_positions`, `witness(position, truncate_at)`,
`truncate_to_position`, `insert_subtree`, `append`, and `frontier`. A
shard is exactly a `LocatedPrunableTree` rooted at level `SHARD_HEIGHT`.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L376-L423
```

## 3. The code: witness from a shard

`LocatedPrunableTree::witness(position, truncate_at)` reads the
authentication path for a marked leaf out of the (possibly pruned) shard,
using cached annotations where available and `root_hash` of sibling
subtrees otherwise. A missing sibling surfaces as
`QueryError::TreeIncomplete`.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L517-L605
```

`insert_subtree` is the write path: it grafts a subtree in at its address,
merging against existing content and reporting any newly introduced `Nil`
nodes via `IncompleteAt`.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L666-L840
```

`frontier()` extracts a `NonEmptyFrontier` from the right edge of the
shard, the bridge back to [Chapter 5](./05-frontiers.md), added in the
0.6.2 release.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L1128-L1135
```

## 4. Failure modes

- **Stale `Some` annotation after truncation.** If a parent's cached root
  annotation is trusted while the subtree below it has been truncated, the
  root is wrong. This is exactly the "Parent annotation fast-path ignores
  truncation" bug (`b0b3eb9` failing test, `513972b` fix). Caught by: the
  regression test added in `b0b3eb9` in `shardtree/src/lib.rs`.
- **Merging conflicting subtrees.** `merge_checked` returns
  `MergeError::Conflict`. Swallowing that error and overwriting would
  corrupt the tree. Caught by: the `prunable` merge unit tests and
  `check_operations`.
- **Pruning a subtree that still backs a witness.** `prune` must not
  collapse a subtree containing a `MARKED`/`CHECKPOINT`/`REFERENCE` leaf
  (`contains_marked`). Pruning it would drop a needed witness node. Caught
  by: the retention checks in `prune`/`is_full`; differential tests assert
  marked witnesses survive.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 5.4.8: the witness `root_hash` produces must, when applied to the
  marked leaf, reproduce the anchor (tree root) the protocol checks a spend
  against. Cited because `root_hash`/`witness` correctness is what makes a
  shardtree-produced witness verify on-chain.

## 6. Exercises

1. **Answer from code.** What does `root_hash` return when a required
   node is `Nil`, and how does the caller distinguish "incomplete" from a
   genuine hash? Cite the return type and `QueryError::TreeIncomplete`.
2. **Conflict.** Construct two `PrunableTree`s over the same address that
   disagree on one leaf value and call `merge_checked`. Confirm it returns
   `MergeError::Conflict` at the expected address.
3. **Prune and re-root (modify).** In the `prunable.rs` test module, build
   a small `LocatedPrunableTree`, record its `root_hash`, call
   `prune(Level::from(1))`, and assert the `root_hash` is unchanged
   (Invariant 10.3) while the tree has fewer nodes. Confirm
   `cargo test -p shardtree` passes.

### Answers in the code

- Exercise 1: `root_hash` returns `Result<H, Vec<Address>>`
  (`prunable.rs:174`); the `ShardTree` layer maps the `Err` to
  `QueryError::TreeIncomplete` (`error.rs:133-135`).
- Exercise 2: `merge_checked` is `prunable.rs:277-375`; the conflict
  address is the first disagreeing materialised node.
- Exercise 3: `prune` is `prunable.rs:259-275`; use `root_hash`
  (`prunable.rs:459`) before and after.

## 7. Further reading

- [Chapter 11: shardtree Operations](./11-shardtree-operations.md) drives
  these subtree operations from the top-level `ShardTree` API: append,
  insert, checkpoint, witness, and the cached-root fast paths.
