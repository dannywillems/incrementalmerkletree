---
sidebar_position: 8
title: "bridgetree"
description: "The append-only tree whose state is a sequence of MerkleBridges, with marking, checkpoints, rollback, and garbage collection."
---

# bridgetree

## 1. Why this chapter exists

`bridgetree` is the simpler of the two production trees and the easier
mental model: a single in-memory structure that appends leaves, maintains
witnesses for marked leaves, and supports checkpoint/rollback. Its state
is a list of **bridges**, each a `NonEmptyFrontier` plus the ommers it is
tracking. If you understand how a bridge advances a witness, `shardtree`
becomes "the same idea, but sharded and persisted". Everything is in one
file,
[`bridgetree/src/lib.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs).

## 2. Where bridgetree is used in the zcash stack

Before studying the internals, it helps to know where this code actually
runs. As of 2026, `bridgetree` is largely legacy in the wider Zcash
stack: newer code maintains witnesses with `shardtree`
([Chapter 9](./09-shardtree-structure.md)) and tracks consensus tree
state with a bare `Frontier` ([Chapter 5](./05-frontiers.md)). Two
distinct things share the name "bridgetree", and they show up in
different places:

1. **The standalone `bridgetree` crate** in this workspace (versions
   0.6 / 0.7), which is what this chapter documents.
2. **The older `incrementalmerkletree::bridgetree` module**, which lived
   inside `incrementalmerkletree` 0.3.x before the bridge code was split
   out into its own crate.

| Consumer | Tree it uses | Notes |
| --- | --- | --- |
| `zcashd` (Rust glue in the `zcash` repo) | the `incrementalmerkletree::bridgetree` module (0.3 API) | `incremental_merkle_tree.rs`, `merkle_frontier.rs`, `wallet.rs`; pins `incrementalmerkletree = "0.3"`, so no standalone `bridgetree` crate is in its lockfile |
| `zewif-zcashd` (wallet-migration tooling) | the standalone `bridgetree` crate, directly | parses the zcashd wallet on-disk format, which serialized a `BridgeTree`; see `orchard/bridgetree_parsing.rs` |
| `wallet` (zcash-devtool migration flow) | `shardtree` + `incrementalmerkletree` 0.8 for its own trees | pulls in `bridgetree` only transitively, via the `zewif-zcashd` dependency |
| `librustzcash`, `orchard` | `shardtree` for wallet-side witnessing | no `bridgetree` dependency |
| `zebra` (full node) | a bare `frontier::Frontier` from `incrementalmerkletree` 0.8.2 | a consensus node only appends commitments and computes anchors, never produces per-note witnesses, so it needs neither bridges nor shards |

In short, the standalone crate's only first-party direct consumer today
is `zewif-zcashd`, and that is because it has to decode data zcashd wrote
with an earlier version of this very code. New witness-tracking code
reaches for `shardtree` instead; consensus-only tree state uses
`Frontier`.

## 3. bridgetree vs shardtree at a glance

Both crates solve the same problem: an append-only Merkle tree that
maintains witnesses for marked leaves, prunes everything else, and
supports checkpoint and rollback up to a bounded count. They differ only
in how the tree state is represented and persisted. `shardtree` is "the
same idea, sharded and persisted"
([Chapter 9](./09-shardtree-structure.md)).

| Axis | bridgetree | shardtree |
| --- | --- | --- |
| In-memory shape | flat `Vec<MerkleBridge>` plus address/position maps | `Arc`-linked `Node`/`Tree`, a cap over fixed-height shards |
| Node addressing | bridge indices into the `Vec` | `Address` `(level, index)`; children reached via `Arc` in memory |
| Insertion | sequential append; bridges fuse and split | out-of-order insertion, batch insert, insert subtree roots |
| Persistence | whole structure serialized; in-memory oriented | per-shard via a `ShardStore`; only the touched shard is rewritten |
| Checkpoint / rewind | a bridge index (`bridges_len`); rewind truncates the `Vec` | a `TreeState` position plus `marks_removed`; rewind truncates by position |
| Sharing / clone | owned `Vec` data | `Arc` structural sharing, so clone and checkpoint are cheap |
| Scale target | modest, in-memory | depth-32 production wallets |
| Status (2026) | largely legacy (see section 2) | current production witnessing tree |

The two crates are independent: `shardtree` does not depend on
`bridgetree`. If you only need anchors and never per-note witnesses, a
bare `Frontier` ([Chapter 5](./05-frontiers.md)) is lighter than either.

## 4. Definitions

**Definition 8.1 (MerkleBridge).** A `MerkleBridge<H>` carries an optional
`prior_position` (the frontier tip of the preceding bridge), a set of
`tracking` addresses (ommers still being completed), a map `ommers` of
completed sibling values, and the current `NonEmptyFrontier`. A bridge
represents the minimal data to advance witnesses from `prior_position` to
its own tip.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L78-L100
```

**Definition 8.2 (continuity).** Two adjacent bridges are continuous iff
the successor's `prior_position` equals the predecessor's frontier
position. `check_continuity` enforces this; a violation is a
`ContinuityError`. Continuity is what makes a chain of bridges equivalent
to one tree.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L164-L186
```

**Definition 8.3 (bridge successor and append).** `successor` starts a new
bridge at the current tip (optionally tracking the current leaf for
witnessing); `append` extends a bridge's frontier by one leaf and updates
every tracked ommer whose address is now complete.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L188-L215
```

**Definition 8.4 (BridgeTree).** A `BridgeTree<H, C, DEPTH>` holds the
vector of `prior_bridges`, the `current_bridge`, a map
`marked_indices: Position -> usize` (which bridge witnesses each marked
position), and a `VecDeque<Checkpoint<C>>` bounded by `max_checkpoints`.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L426-L445
```

**Invariant 8.5 (witnessing).** A witness for a marked position is
assembled by fusing the bridges from the marked leaf's bridge forward,
reading past ommers from the bridge maps and future siblings from later
bridges. Failure modes (`AuthBaseNotFound`, `PositionNotMarked`,
`CheckpointTooDeep`) are enumerated in `WitnessingError`.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L820-L910
```

## 5. The code

### 5.1 The append / mark / checkpoint cycle

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L633-L727
```

`append` adds a leaf to the current bridge. `mark` starts a successor that
tracks the current leaf and records its position in `marked_indices`.
`checkpoint` pushes a `Checkpoint` recording the bridge count; `rewind`
pops it and truncates back.

### 5.2 Garbage collection

`garbage_collect` is what makes the structure space-efficient: it fuses
and drops bridges that are no longer needed to witness any marked leaf or
to reach any retained checkpoint. This is the operation that turns an
ever-growing bridge list back into a compact one.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L911-L995
```

### 5.3 Implementing the comparison trait

`BridgeTree` implements the `incrementalmerkletree-testing` `Tree<H,
usize>` trait, which is how it gets differentially tested against the
reference tree (see [Chapter 14](./14-testing-framework.md)).

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L996-L1000
```

## 6. Failure modes

- **Witnessing an unmarked position.** `witness` returns
  `WitnessingError::PositionNotMarked` if you never called `mark` at that
  position. The witness is only maintained for marked leaves. Caught by:
  the differential `check_operations` harness, which scripts `Mark` and
  `Witness` operations.
- **Rewinding past available checkpoints.** `rewind` returns `false` when
  there is no checkpoint to pop; `witness` at too great a checkpoint depth
  returns `CheckpointTooDeep`. Caught by: `check_operations` (it tracks the
  expected checkpoint count).
- **Breaking continuity in `from_parts`.** Reconstructing a `BridgeTree`
  from bridges that are not pairwise continuous yields a
  `ContinuityError`/`BridgeTreeError`. Caught by: `check_continuity` is
  called on reconstruction; `from_parts` validates.
- **Skipping `garbage_collect`.** Not a correctness bug, but the bridge
  list grows without bound and memory balloons. Caught by: no test asserts
  collection happens; it is a manual hygiene call. No automated test in
  this workspace; caught by review only.

## 7. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8: the wallet must maintain spend authorisation witnesses for
  its own notes across many appended blocks; a bridge is the minimal delta
  between two such states. Cited because `mark`/`witness` implement
  exactly the wallet's witness-maintenance requirement.

## 8. Exercises

1. **Answer from code.** What does `BridgeTree::mark` return when called
   twice at the same position without an intervening append, and why?
   Cite the body.
2. **Trace continuity.** Construct two bridges by hand (using `new` then
   `successor` + `append`) and call `check_continuity`. Then construct an
   intentionally discontinuous pair and confirm it returns
   `ContinuityError::PositionMismatch`.
3. **Differential test (modify).** In the `bridgetree` test module, add a
   `check_operations`-style sequence: append eight leaves, mark position
   3, append four more, checkpoint, append two more, then witness position
   3 at checkpoint depth 0 and assert the path recomputes the current
   root via `compute_root_from_witness`. Confirm
   `cargo test -p bridgetree` passes.

### Answers in the code

- Exercise 1: `mark` is at `bridgetree/src/lib.rs:689-726`; a second mark
  at the same already-marked position returns the existing position
  without creating a duplicate.
- Exercise 2: `check_continuity` is `lib.rs:164-186`.
- Exercise 3: `compute_root_from_witness` lives in the testing crate at
  `incrementalmerkletree-testing/src/lib.rs:362`.

## 9. Further reading

- [Chapter 9: shardtree Structure](./09-shardtree-structure.md) introduces
  the sharded tree; compare its per-shard frontier handling with
  `bridgetree`'s bridge chain.
