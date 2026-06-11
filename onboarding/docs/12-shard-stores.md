---
sidebar_position: 12
title: "Shard Stores"
description: "The ShardStore trait and its in-memory and write-back caching implementations: how shardtree persists shards, the cap, and checkpoints."
---

# Shard Stores

## 1. Why this chapter exists

`ShardTree` is generic over storage. The `ShardStore` trait is the
contract any backend must satisfy, and `librustzcash` implements it over
SQLite. To add persistence, debug a corruption, or write a test backend,
you must know the trait's invariants, especially the rule that shard roots
sit at exactly `SHARD_HEIGHT`. The two in-tree implementations,
`MemoryShardStore` and `CachingShardStore`, are your reference and your
test double. The code is
[`shardtree/src/store.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs)
and `shardtree/src/store/`.

## 2. Definitions

**Definition 12.1 (ShardStore).** A `ShardStore` provides typed access to
shards (`get_shard`, `put_shard`, `last_shard`, `get_shard_roots`,
`truncate_shards`), the cap (`get_cap`, `put_cap`), and checkpoints
(`add_checkpoint`, `get_checkpoint_at_depth`, `with_checkpoints`,
`update_checkpoint_with`, `remove_checkpoint`,
`truncate_checkpoints_retaining`). It carries three associated types:
`H` (node), `CheckpointId`, and `Error`.

```rust reference title="shardtree/src/store.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L33-L148
```

**Invariant 12.2 (shard root level).** Every `put_shard` subtree must have
its root at level `SHARD_HEIGHT`; the trait documents this as a MUST.
Implementations index shards by `address.index()` at that level. A store
that accepts a shard at the wrong level breaks the cap/shard split of
[Chapter 9](./09-shardtree-structure.md).

**Definition 12.3 (checkpoint depth).** `get_checkpoint_at_depth(d)`
returns the $d$-th most recent checkpoint (depth 0 = most recent). This is
the storage-level primitive behind every `_at_checkpoint_depth` operation;
it returns `None` when fewer than $d+1$ checkpoints exist.

```rust reference title="shardtree/src/store.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L96-L116
```

**Definition 12.4 (MemoryShardStore).** The reference implementation:
`shards: Vec<LocatedPrunableTree>`, `checkpoints: BTreeMap<C, Checkpoint>`,
`cap: PrunableTree`. Its `Error` is `Infallible`. `put_shard` pads the
shard vector with empty shards up to the inserted index, so the vector is
dense by shard index.

```rust reference title="shardtree/src/store/memory.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store/memory.rs#L11-L59
```

**Definition 12.5 (CachingShardStore).** A write-back cache over any
backend `S`: it loads the backend into an in-memory `MemoryShardStore`,
serves reads from the cache, records mutations as `deferred_actions`, and
applies them to the backend only on `flush`. Dropping discards uncommitted
changes. This is the pattern `librustzcash` uses to batch SQLite writes.

```rust reference title="shardtree/src/store/caching.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store/caching.rs#L17-L40
```

## 3. The code: the blanket impl and padding

`ShardStore` is implemented for `&mut S` so that operations can take a
mutable reference generically, the blanket impl simply forwards.

```rust reference title="shardtree/src/store.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L150-L185
```

The padding logic in `MemoryShardStore::put_shard` is worth reading: it
fills gaps with empty shards so that `get_shard(index)` is a direct vector
lookup. A persistent store does the analogous thing with explicit
empty-shard rows.

```rust reference title="shardtree/src/store/memory.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store/memory.rs#L48-L60
```

## 4. Failure modes

- **Putting a shard at the wrong level.** Violates Invariant 12.2;
  `get_shard`/indexing then misaligns. Caught by: no runtime assertion in
  `MemoryShardStore` (it trusts the caller); the `ShardTree` layer is
  responsible for only ever putting `SHARD_HEIGHT` roots. No automated
  test in this workspace guards a hand-written bad store; caught by review
  only.
- **Forgetting to `flush` a `CachingShardStore`.** Mutations are buffered;
  dropping without `flush` silently discards them. This is intended (it
  lets you abort), but a caller expecting persistence loses data. Caught
  by: the doc comment; no test asserts you flushed.
- **Non-monotonic checkpoint ids in the store.** `add_checkpoint` expects
  ids consistent with `get_checkpoint_at_depth`'s ordering; inserting out
  of order corrupts depth queries. Caught by: the `ShardTree` layer
  rejects out-of-order ids before they reach the store (`error.rs`
  `CheckpointOutOfOrder`).

## 5. Spec pointers

- This layer has no protocol-spec dependency: it is pure storage. The
  authoritative reference for the SQLite schema that implements
  `ShardStore` in production is the `zcash_client_sqlite` crate in
  [`librustzcash`](https://github.com/zcash/librustzcash). Cited because
  that is the real-world `ShardStore` the in-tree ones model.

## 6. Exercises

1. **Answer from code.** Why is `MemoryShardStore::Error` `Infallible`,
   and what does that let callers do with the `Result`? Cite the impl.
2. **Trace a deferred action.** List the three `Action` variants a
   `CachingShardStore` defers, and explain when each is applied. Cite the
   `Action` enum.
3. **Implement a counting store (modify).** Write a test-only wrapper
   `ShardStore` that delegates to a `MemoryShardStore` but counts
   `put_shard` calls, and assert in a test that appending $N$ leaves
   issues the expected number of shard writes for a `(6, 3)` tree.
   Confirm `cargo test -p shardtree` passes.

### Answers in the code

- Exercise 1: `Infallible` means every `Result` is statically `Ok`, so
  callers can `unwrap`/`?` without a real error path
  (`store/memory.rs:33`).
- Exercise 2: the variants are `TruncateShards`, `RemoveCheckpoint`,
  `TruncateCheckpointsRetaining` (`store/caching.rs:11-15`), applied on
  `flush`.
- Exercise 3: model the wrapper on the `&mut S` blanket impl
  (`store.rs:150-255`).

## 7. Further reading

- [Chapter 13: Batch Insertion](./13-batch-insertion.md) shows how many
  leaves are turned into shards and written through the store at once.
