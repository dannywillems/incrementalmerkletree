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

## 2. Definitions

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

## 3. The code

### 3.1 The append / mark / checkpoint cycle

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L633-L727
```

`append` adds a leaf to the current bridge. `mark` starts a successor that
tracks the current leaf and records its position in `marked_indices`.
`checkpoint` pushes a `Checkpoint` recording the bridge count; `rewind`
pops it and truncates back.

### 3.2 Garbage collection

`garbage_collect` is what makes the structure space-efficient: it fuses
and drops bridges that are no longer needed to witness any marked leaf or
to reach any retained checkpoint. This is the operation that turns an
ever-growing bridge list back into a compact one.

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L911-L995
```

### 3.3 Implementing the comparison trait

`BridgeTree` implements the `incrementalmerkletree-testing` `Tree<H,
usize>` trait, which is how it gets differentially tested against the
reference tree (see [Chapter 14](./14-testing-framework.md)).

```rust reference title="bridgetree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L996-L1000
```

## 4. Failure modes

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

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8: the wallet must maintain spend authorisation witnesses for
  its own notes across many appended blocks; a bridge is the minimal delta
  between two such states. Cited because `mark`/`witness` implement
  exactly the wallet's witness-maintenance requirement.

## 6. Exercises

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

## 7. Further reading

- [Chapter 9: shardtree Structure](./09-shardtree-structure.md) introduces
  the sharded tree; compare its per-shard frontier handling with
  `bridgetree`'s bridge chain.
