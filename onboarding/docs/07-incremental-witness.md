---
sidebar_position: 7
title: "The Legacy CommitmentTree and IncrementalWitness"
description: "The zcashd-compatible append-only tree and updatable witness behind the legacy-api feature flag."
---

# The Legacy CommitmentTree and IncrementalWitness

## 1. Why this chapter exists

`CommitmentTree` and `IncrementalWitness` are the original `zcashd`
data structures, parked here behind the `legacy-api` feature after being
removed from `zcash_primitives` 0.12. You need them for exactly one
reason: interoperability with `zcashd`'s serialized witnesses and test
vectors. Understanding them also clarifies, by contrast, why `bridgetree`
and `shardtree` exist. The code is in
[`incrementalmerkletree/src/frontier.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs)
(the tree) and
[`incrementalmerkletree/src/witness.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/witness.rs)
(the witness).

## 2. Definitions

**Definition 7.1 (CommitmentTree).** A `CommitmentTree<H, DEPTH>` stores
`left: Option<H>`, `right: Option<H>`, and `parents: Vec<Option<H>>`. It
is the same information as a `NonEmptyFrontier` in a different layout: the
`left`/`right` pair is the bottom-level fill, and `parents[i]` is the
stored left sibling at level $i+1$, present exactly when bit $i+1$ of the
size is set.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L442-L527
```

**Lemma 7.2 (frontier equivalence).** `CommitmentTree` and `Frontier`
are inter-convertible without loss: `to_frontier` and `from_frontier`
round-trip. The size of the tree is recovered from the occupancy of
`parents` treated as a binary number (Definition 7.1), implemented in
`CommitmentTree::size`.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L546-L596
```

**Definition 7.3 (IncrementalWitness).** An `IncrementalWitness<H, DEPTH>`
holds the `CommitmentTree` as of the witnessed position, a `filled` vector
of right-sibling values discovered by later appends, and a `cursor`
subtree that accumulates leaves until it completes the next unfilled
sibling. Appending the same leaves to the base tree and to the witness
keeps `root()` equal to the tree root.

```rust reference title="incrementalmerkletree/src/witness.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/witness.rs#L38-L97
```

**Invariant 7.4 (cursor completion).** The cursor is a `CommitmentTree`
collecting leaves to the right of the witnessed position. When it
completes a subtree of height `cursor_depth` (the depth of the next
unfilled sibling, computed by `next_depth`), its root is pushed onto
`filled` and the cursor resets. This is the "advance the witness" step.

```rust reference title="incrementalmerkletree/src/witness.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/witness.rs#L190-L220
```

## 3. The code: appending in lockstep

The doctest on `IncrementalWitness` is the canonical usage and is run as
part of `cargo test --doc`: build a tree, snapshot a witness at position
1, then append the same node to both and assert the roots stay equal.

```rust reference title="incrementalmerkletree/src/witness.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/witness.rs#L17-L37
```

The witness path is read off by `path`/`path_inner`, which pads missing
siblings from a `PathFiller` (a queue of `filled` values followed by the
cursor root, falling back to `empty_root`). `tip_position` reports how far
the witness has been advanced, accounting for filled subtrees and the
partial cursor.

```rust reference title="incrementalmerkletree/src/witness.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/witness.rs#L228-L264
```

## 4. Failure modes

- **Using `invalid_empty_witness` outside tests.** It constructs a witness
  with no witnessed position, valid only for reproducing `zcashd`'s
  encoding quirks. It is gated by `test-dependencies` for that reason.
  Caught by: the feature gate; misuse compiles only in test builds.
- **Forgetting that `from_tree`/`from_parts` return `Option`.** They
  return `None` for an empty tree (no position to witness). The 0.8.0
  changelog entry made this explicit; pre-0.8 callers that `unwrap`ped a
  non-optional result must be updated. Caught by: the type signature; the
  doctest exercises the `Some` path.
- **Assuming `filled` order.** `filled` is right-sibling-then-cursor
  order, consumed front-to-back by `PathFiller`. Reordering it silently
  corrupts the path. Caught by: `tests::witness_tip_position` and the
  doctest.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 5.4.8 (Merkle path) and the `zcashd` source's
  `IncrementalWitness` are the interoperability targets. Cited because the
  only reason to use this type today is to produce or consume `zcashd`
  encodings; the doc comment on `invalid_empty_witness` states this
  explicitly.

## 6. Exercises

1. **Answer from code.** Why does `IncrementalWitness::from_tree` return
   `Option<Self>` rather than `Self`? Cite the body.
2. **Round-trip.** Build a `CommitmentTree<String, 8>`, append four
   distinct leaves, convert to a `Frontier` and back, and assert
   equality. Use `tests::test_commitment_tree_roundtrip` as the model.
3. **Advance a witness (modify).** Extend `tests::witness_tip_position`:
   after building the base tree and appending through `'z'`, also assert
   that `witness.root()` equals the root of a fresh `CommitmentTree`
   containing the same full leaf sequence. Confirm
   `cargo test -p incrementalmerkletree --all-features` passes.

### Answers in the code

- Exercise 1: an empty tree has no position to witness, so `from_tree`
  guards with `(!tree.is_empty()).then(...)`,
  `incrementalmerkletree/src/witness.rs:51-58`.
- Exercise 2: `frontier.rs:880-902`.
- Exercise 3: the witness/tree root equality is the doctest invariant at
  `witness.rs:30-36`.

## 7. Further reading

- [Chapter 8: bridgetree](./08-bridgetree.md) is the modern replacement:
  one structure maintains *many* witnesses at once with shared state,
  instead of one `IncrementalWitness` per marked leaf.
