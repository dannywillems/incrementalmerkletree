---
sidebar_position: 14
title: "The Testing Framework"
description: "incrementalmerkletree-testing: the Tree trait, the CompleteTree reference oracle, CombinedTree differential testing, and check_operations."
---

# The Testing Framework

## 1. Why this chapter exists

The strongest correctness argument in this workspace is differential: run
each efficient tree (`bridgetree`, `shardtree`) next to a slow,
fully-materialised reference tree and assert they agree after every random
operation. This is what catches the subtle pruning, witness, and
checkpoint bugs that unit tests miss. If you add a feature to either tree,
you make it pass this harness; if you find a bug, you reproduce it as an
`Operation` sequence here first. The crate is
[`incrementalmerkletree-testing`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs).

## 2. Definitions

**Definition 14.1 (the Tree trait).** `Tree<H, C>` is the common interface
every implementation provides: `append(value, retention)`,
`current_position`, `get_marked_leaf`, `marked_positions`,
`root(checkpoint_depth)`, `witness(position, checkpoint_depth)`,
`remove_mark`, `checkpoint(id)`, `checkpoint_count`, `rewind(depth)`. Both
`BridgeTree` and `ShardTree` implement it.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L16-L96
```

**Definition 14.2 (CompleteTree, the oracle).** `complete_tree.rs`
implements `Tree` by storing *every* leaf and recomputing roots and
witnesses from scratch. It is slow and memory-hungry but obviously
correct, the specification the efficient trees are checked against.

```rust reference title="incrementalmerkletree-testing/src/complete_tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/complete_tree.rs#L1-L40
```

**Definition 14.3 (Operation).** `Operation<A, C>` is a scriptable tree
action: `Append`, `CurrentPosition`, `MarkedLeaf`, `Unmark`, `Checkpoint`,
`Rewind`, `Witness`, `GarbageCollect`, and so on. A test is a sequence of
operations; `apply`/`apply_all` runs them against any `Tree`.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L124-L205
```

**Definition 14.4 (CombinedTree).** `CombinedTree<H, C, I, E>` wraps an
"inefficient" tree `I` (the oracle) and an "efficient" tree `E`. Every
trait method applies to both and asserts the observable results are equal
before returning. Any divergence panics at the operation that caused it.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L385-L484
```

**Definition 14.5 (check_operations).** The driver: given a sequence of
operations, it applies each to a tree and asserts roots and witnesses
match the independently maintained reference state, including recomputing
witnesses with `compute_root_from_witness` to confirm a path actually
reproduces the root.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L269-L361
```

## 3. The code: witness verification and proptest

`compute_root_from_witness(value, position, path)` folds a path back to a
root, the same arithmetic as `MerklePath::root` ([Chapter 4](./04-hashing-and-merklepath.md))
but standalone, used to verify any tree's witness without trusting that
tree.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L362-L383
```

`arb_operation` is the proptest strategy that generates random operation
sequences; combined with `CombinedTree`, it fuzzes the efficient trees
against the oracle.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L207-L246
```

`SipHashable` is the lightweight deterministic `Hashable` used so that
roots are cheap to compute and stable across runs.

```rust reference title="incrementalmerkletree-testing/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree-testing/src/lib.rs#L103-L124
```

## 4. Failure modes

- **Adding a `Tree` method without updating `CombinedTree`.** The
  combined wrapper must apply and cross-check the new method on both
  trees, or the new behaviour is untested differentially. Caught by: the
  trait will not compile for `CombinedTree` until you implement the
  method; but a method that does not assert equality compiles and silently
  skips the check. Partly caught by the compiler; the equality assertion
  is the author's responsibility.
- **A reference oracle that shares a bug with the tree under test.** If
  `CompleteTree` had the same off-by-one as `ShardTree`, the differential
  test would pass spuriously. The oracle is deliberately written in the
  simplest possible way to avoid this. Caught by: code review of the
  oracle; no test can catch a shared bug.
- **Shrinking that loses the failing case.** When proptest shrinks a
  failing operation sequence, an over-aggressive shrink can hide the bug.
  Use the printed seed to reproduce. Caught by: proptest's persisted
  regression seeds.

## 5. Spec pointers

- [proptest documentation](https://proptest-rs.github.io/proptest/):
  explains `Strategy`, shrinking, and the regression-seed file. Cited
  because every differential test is a `proptest!` and you will read
  shrink output when one fails.
- The witness verification (`compute_root_from_witness`) checks the same
  Merkle-path validity as [Zcash Protocol
  Specification](https://zips.z.cash/protocol/protocol.pdf) Section 5.4.8.

## 6. Exercises

1. **Answer from code.** How does `CombinedTree::root` detect a divergence
   between the two trees? Cite the method body.
2. **Script a bug repro.** Write a fixed `Operation` sequence (append,
   mark, append, checkpoint, rewind, witness) and run it through
   `check_operations` against a `(6, 3)` `ShardTree`. Confirm it passes.
3. **Fuzz a change (modify).** Add a `proptest!` in the `shardtree`
   testing module that builds a `CombinedTree` of `CompleteTree` and
   `ShardTree`, applies `arb_operation` sequences of length up to 100, and
   asserts no panic. Run it with
   `PROPTEST_CASES=1000 cargo test -p shardtree`. Confirm it passes.

### Answers in the code

- Exercise 1: `CombinedTree::root` computes both roots and asserts
  equality before returning (`incrementalmerkletree-testing/src/lib.rs:418-424`).
- Exercise 2: `check_operations` is `lib.rs:269-361`.
- Exercise 3: model on `shardtree/src/testing.rs` (the `(6, 3)` instance
  at `shardtree/src/testing.rs:100-114`).

## 7. Further reading

- [Chapter 15: Failure Modes and Audits](./15-failure-modes-and-audits.md)
  catalogues the real bugs this harness has caught and the supply-chain
  gate that complements it.
