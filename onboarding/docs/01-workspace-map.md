---
sidebar_position: 1
title: "The Workspace Map"
description: "Every crate and module in the incrementalmerkletree workspace, what it owns, what depends on it, and which tests exercise it."
---

# The Workspace Map

## 1. Why this chapter exists

You cannot navigate four crates and ~13,000 lines of Rust by reading them
top to bottom. This chapter is the map you return to: it states what each
crate owns, the dependency direction between them, and where each
subsystem lives in code. Knowing that `bridgetree` is excluded from the
workspace, or that the `cap` lives in `shardtree/src/lib.rs` while the
`shards` live in `shardtree/src/prunable.rs`, saves an hour of grepping
before your first change to
[`shardtree/src/lib.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs).

## 2. Definitions

**Definition 1.1 (the workspace).** A Cargo workspace with
`resolver = "2"` whose members are `incrementalmerkletree`,
`incrementalmerkletree-testing`, and `shardtree`. `bridgetree` is listed
under `exclude`, so it is a sibling crate built separately.

```toml reference title="Cargo.toml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/Cargo.toml#L1-L24
```

**Why `bridgetree` is excluded.** The workspace `incrementalmerkletree`
is a path dependency at version 0.8.2. `bridgetree` depends on the
*published* `incrementalmerkletree = "0.8"` and on
`incrementalmerkletree-testing = "=0.2.0-backcompat.0.8"` as a
dev-dependency. Keeping it out of the workspace lets it pin published
versions independently of the in-tree path versions. We observe this is a
release-management choice; the code itself does not require it.

**Definition 1.2 (dependency direction).** The four crates form a DAG.
`incrementalmerkletree` is the root; everything depends on it. An arrow
`A -> B` reads "A depends on B".

```text
                 incrementalmerkletree   (core primitives)
                    ^      ^       ^
   workspace path  /       |        \  published "0.8"
                  /        |         \
        shardtree   incrementalmerkletree-testing   bridgetree
             \              ^   (differential harness)   /
              \             |                           /
               '-----------(dev / test-dependency)-----'
```

The solid edges are normal dependencies: `shardtree` and
`incrementalmerkletree-testing` use the workspace path version, while
`bridgetree` uses the published `0.8`. The dashed relationships
(`shardtree -> incrementalmerkletree-testing`, `bridgetree ->
incrementalmerkletree-testing`) are dev/test-only: the harness is pulled
in just to run the differential tests of [Chapter 14](./14-testing-framework.md).

## 3. The code

### 3.1 `incrementalmerkletree` (the core)

Owns the vocabulary every other crate speaks. `no_std` (it pulls in
`alloc`). Four modules:

- `lib.rs`: `Level`, `Position`, `Address`, `Source`, the `Hashable`
  trait, `MerklePath`, and the `Retention`/`Marking` model. This is
  Chapters 3, 4, and 6.
- `frontier.rs`: `NonEmptyFrontier`, `Frontier<H, DEPTH>`, and the
  `legacy-api` `CommitmentTree`. Chapter 5.
- `witness.rs` (`legacy-api`): `IncrementalWitness`. Chapter 7.
- `testing.rs`: a thin `Frontier`/`Tree` trait used by the testing crate.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L63-L71
```

Feature flags: `std` (only needed for `test-dependencies`), `legacy-api`
(types removed from `zcash_primitives` 0.12 and parked here), and
`test-dependencies` (proptest strategies and random generators).

### 3.2 `bridgetree` (append-only)

A single 1,247-line `lib.rs`. The tree state is a sequence of
`MerkleBridge` values plus a `VecDeque` of `Checkpoint`s. A bridge carries
the minimal data to advance a witness from one position to another.
Chapter 8.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L426-L445
```

### 3.3 `shardtree` (the production tree)

The largest crate. The tree is an ordered collection of fixed-height
**shards**, whose roots are the leaves of a **cap**. Modules:

- `tree.rs`: the generic `Node`/`Tree`/`LocatedTree` types. Chapter 9.
- `prunable.rs`: `PrunableTree` and `RetentionFlags` (the `Tree`
  specialised for pruning), `LocatedPrunableTree`. Chapters 9-10.
- `lib.rs`: `ShardTree<S, DEPTH, SHARD_HEIGHT>` and all its operations.
  Chapter 11.
- `store.rs` + `store/memory.rs` + `store/caching.rs`: the `ShardStore`
  trait and two implementations. Chapter 12.
- `batch.rs`: bulk insertion. Chapter 13.
- `error.rs`, `legacy.rs`, `testing.rs`.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L60-L73
```

### 3.4 `incrementalmerkletree-testing` (the harness)

Defines the `Tree<H, C>` trait that both `bridgetree` and `shardtree`
implement, a `CombinedTree` that runs two implementations in lockstep, an
`Operation` enum that scripts random tree usage, and `check_operations`
that asserts agreement. Chapter 14.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L18-L26
```

## 4. Failure modes

- **Editing the workspace `incrementalmerkletree` and expecting
  `bridgetree` tests to see it.** They will not; `bridgetree` builds
  against the published crate. To test a core change against
  `bridgetree`, add a `[patch.crates-io]` entry or bump the published
  dependency. Caught by: nothing automated; you will simply see stale
  behaviour. No automated test in this workspace; caught by review only.
- **Assuming the `cap` is a shard.** The cap stores parent nodes whose
  levels are in `SHARD_HEIGHT..DEPTH`; shards have roots at exactly
  `SHARD_HEIGHT`. Confusing the two is the root cause of the cap
  corruption bug fixed in `202fb2a`. Caught by: the regression test added
  in `4d78d5b` (see [Chapter 15](./15-failure-modes-and-audits.md)).
- **Adding a `std`-only API to `incrementalmerkletree` without gating
  it.** The core is `no_std`; an ungated `std` use breaks the
  `no_std` build. Caught by: the `cargo build` matrix in CI (the crate
  declares `#![no_std]`).

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8 (Note Commitment Trees) and Section 5.4.8 (Merkle path
  validity). These motivate *why* a wallet needs incremental witnesses
  and checkpoints; the crates implement the data structure, not the
  hashes. Cited because the `DEPTH` const and the "append-only,
  witness-maintaining" requirements come from there.

## 6. Exercises

1. **Locate.** Without grepping the body, name the file and the line
   where `ShardTree` is declared, and the file where `MerkleBridge::append`
   lives. Verify with `git grep -n 'pub struct ShardTree'` and
   `git grep -n 'fn append' bridgetree`.
2. **Dependency direction.** Run
   `cargo tree -p shardtree --edges normal -i incrementalmerkletree`.
   Explain why `incrementalmerkletree-testing` appears only under dev or
   test-dependency edges.
3. **Feature surface (modify).** Run
   `cargo doc -p incrementalmerkletree --no-default-features` and then
   `--features legacy-api`. List which public types appear only under
   `legacy-api`. Then add a one-line `//!` doc note in `lib.rs` next to
   the `pub mod witness` declaration recording your finding, and confirm
   `cargo doc --workspace --document-private-items` still passes.

### Answers in the code

- Exercise 1: `shardtree/src/lib.rs:68`;
  `bridgetree/src/lib.rs:215`.
- Exercise 3: the `witness` module and `frontier::{CommitmentTree,
  PathFiller}` are gated by `legacy-api`
  (`incrementalmerkletree/src/lib.rs:65-67`,
  `incrementalmerkletree/src/frontier.rs:417-446`).

## 7. Further reading

- The four `CHANGELOG.md` files. The `shardtree` changelog in particular
  is the clearest record of how the production tree's API has churned;
  read the 0.5.0 entry for the checkpoint-semantics rework.
