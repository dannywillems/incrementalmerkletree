---
sidebar_position: 13
title: "Batch Insertion"
description: "How shardtree ingests many leaves at once: batch_insert, the parallelisable from_iter plus insert_tree path, and BatchInsertionResult."
---

# Batch Insertion

## 1. Why this chapter exists

Wallets do not append one leaf at a time; they ingest a block range
(thousands of note commitments) at once. The batch path is what makes that
fast, and it is also the path that exposes the most subtle pruning and
incomplete-node bookkeeping. This chapter covers
[`shardtree/src/batch.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/batch.rs)
and the `LocatedPrunableTree::from_iter` building block.

## 2. Definitions

**Definition 13.1 (batch_insert).** `ShardTree::batch_insert(start, iter)`
fills leaves starting at `start`, padding the tree to reach `start`,
consuming the whole iterator, building successive shards, and pruning
aggressively as it goes (retaining only marked leaves, their witness
nodes, and what is needed to truncate to any checkpoint). It returns an
`Option<BatchInsertionResult>`.

```rust reference title="shardtree/src/batch.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/batch.rs#L13-L40
```

**Definition 13.2 (BatchInsertionResult).** Reports `max_insert_position`
(a `Position` since 0.6.1, previously an `Option`), the `checkpoints`
created, and the `IncompleteAt` nodes, addresses where `Nil` was
introduced and whether they must be filled to witness a marked leaf.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L379-L393
```

**Definition 13.3 (the parallel path).** The single-threaded
`batch_insert` has a parallelisable equivalent: build subtrees
independently with `LocatedPrunableTree::from_iter` (each shard from a
slice of leaves, on its own thread), then graft each into the tree with
`ShardTree::insert_tree`. The barrier is the final `insert_tree` merge;
the per-shard `from_iter` work is embarrassingly parallel.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L410-L460
```

**Invariant 13.4 (insert agreement).** Inserting the same leaves via
`append` one at a time, via `batch_insert`, or via the
`from_iter`+`insert_tree` parallel path must all yield the same tree
(same root, same marked positions, same witnesses). The `batch.rs` tests
build two trees by the two routes and assert equality.

```rust reference title="shardtree/src/batch.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/batch.rs#L480-L510
```

## 3. The code: reading `from_iter`

`LocatedPrunableTree::from_iter` is the per-shard builder: it consumes
leaves with their retentions, builds a pruned subtree, and reports
incomplete nodes. Because it operates on one shard's worth of positions,
many invocations are independent and can run concurrently before the
serial `insert_tree` merge.

```rust reference title="shardtree/src/prunable.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L841-L955
```

`insert_tree` then merges each built subtree into the `ShardTree`,
reconciling against existing shards via `merge_checked`
([Chapter 10](./10-prunable-tree.md)) and updating the cap.

## 4. Failure modes

- **Assuming `max_insert_position` is optional.** Since 0.6.1 it is a
  `Position`, and the "no leaves inserted" case is represented by the
  outer `Option<BatchInsertionResult>` being `None`. Code written against
  the old `Option<Position>` field will not compile; that is the intended
  signal to update. Caught by: the type; the 0.6.1 changelog documents it.
- **Ignoring `IncompleteAt`.** A marked leaf whose witness needs a node
  that was left `Nil` will fail to witness until that node is filled. The
  `required` flag on `IncompleteAt` tells you which gaps matter. Caught
  by: differential tests that mark leaves and then witness them.
- **Parallel build without the serial merge barrier.** The per-shard
  `from_iter` is parallel, but `insert_tree` must run serially to merge
  consistently; merging two shards concurrently into the same cap races.
  Caught by: the equality tests in `batch.rs` (a racy merge diverges from
  the serial build). No concurrency test in this workspace; caught by
  review only.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8: note commitments are appended in block order, so a block's
  worth of commitments forms a contiguous position range, exactly the
  input shape `batch_insert` is optimised for. Cited because the batch
  API's "contiguous range from `start`" model mirrors block ingestion.

## 6. Exercises

1. **Answer from code.** What does `batch_insert` return when the input
   iterator is empty, and how does a caller distinguish that from "one
   leaf at position 0"? Cite the return type.
2. **Two routes agree.** Insert the same eight leaves via `append` in a
   loop and via `batch_insert`, then assert the roots are equal. Use the
   `batch.rs` test module as a model.
3. **Parallelise (modify).** Using `LocatedPrunableTree::from_iter` to
   build two shards and `insert_tree` to graft them, reproduce a tree that
   `batch_insert` would build for 16 leaves in a `(6, 3)` tree, and assert
   equality. Confirm `cargo test -p shardtree` passes.

### Answers in the code

- Exercise 1: it returns `Ok(None)` for an empty input; a single leaf
  yields `Ok(Some(result))` with `max_insert_position == Position(0)`
  (`batch.rs:13-40`, `prunable.rs:379-393`).
- Exercise 2: the route-equality assertion is at `batch.rs:480-510`.
- Exercise 3: `from_iter` is `prunable.rs:841-955`; `insert_tree` is
  `shardtree/src/lib.rs:410-460`.

## 7. Further reading

- [Chapter 14: The Testing Framework](./14-testing-framework.md) is how
  all of these write paths are proven equivalent to a slow reference tree.
