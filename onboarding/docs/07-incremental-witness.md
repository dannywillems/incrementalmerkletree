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

**Remark 7.4a (why `cursor_depth` is a height).** Each future sibling of the
witnessed leaf sits at a level $k$ on the path to the root, and a perfect
subtree rooted at level $k$ contains exactly $2^{k}$ leaves. So
`cursor_depth` is simultaneously the level of the next unfilled sibling and
the height of the subtree the cursor must fill: the completion test "holds
$2^{\text{cursor\_depth}}$ leaves" is just "this subtree is full". The
siblings are filled bottom-up, so `cursor_depth` increases over the witness's
lifetime. The degenerate case $k = 0$ is a height-0 subtree (a single leaf):
there is nothing to accumulate, so the appended node is pushed straight onto
`filled` and no cursor is created (`if self.cursor_depth == 0 {
self.filled.push(node) }`).

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

**Figure 7.4b (the past/future split).** A witness for one leaf splits that
leaf's authentication path into a fixed *past* part, supplied by the snapshot
`tree`, and a *future* part, filled in by later appends. The figure witnesses
position $1$ in a depth-3 tree (the doctest uses depth $8$; depth $3$ is shown
for legibility), created right after appending $L_0, L_1$:

```text
 level 3                       root              (recomputed each append)
                         ______/  \______
 level 2          H(0..3)           F = H(4..7)   <- FUTURE sibling -> filled[1]
                  /     \
 level 1     H(0,1)   B = H(2,3)                  <- FUTURE sibling -> filled[0]
              /  \
 level 0    L0    L1
            ^     ^
       PAST       witnessed leaf (position 1)
   (tree.left)
```

The path for $L_1$ is $[\,L_0,\ B,\ F\,]$: the level-0 sibling $L_0$ is in the
past (`tree.left`, fixed forever); the level-1 sibling $B = H(2,3)$ is locked
into `filled[0]` once $L_2, L_3$ arrive; the level-2 sibling $F = H(4..7)$ is
locked into `filled[1]` once $L_4 \dots L_7$ arrive.

**Table 7.4c (state trace, appending $L_2 \dots L_7$).** Starting from the
snapshot above. Write `E_k` for `empty_root(k)` and `` F*[...] `` for the
cursor's current padded root over the leaves listed so far. The path stays
valid for the current tree at every step (the doctest invariant
`tree.root() == witness.root()`); future siblings begin as padded placeholders
and sharpen into final values as their subtree completes.

| after append | `cursor_depth` | cursor holds | `filled`            | `path()` = [lvl0, lvl1, lvl2]     |
| ------------ | -------------- | ------------ | ------------------- | --------------------------------- |
| (created)    | 0              | none         | `[]`                | `[L0, E_1, E_2]`                  |
| `L2`         | 1              | `[L2]`       | `[]`                | `` [L0, B*[2], E_2] ``            |
| `L3`         | 1              | none         | `[H(2,3)]`          | `[L0, H(2,3), E_2]`               |
| `L4`         | 2              | `[L4]`       | `[H(2,3)]`          | `` [L0, H(2,3), F*[4]] ``         |
| `L5`         | 2              | `[L4,L5]`    | `[H(2,3)]`          | `` [L0, H(2,3), F*[4,5]] ``       |
| `L6`         | 2              | `[L6; H(4,5)]` | `[H(2,3)]`        | `` [L0, H(2,3), F*[4,5,6]] ``     |
| `L7`         | 2              | none         | `[H(2,3), H(4..7)]` | `[L0, H(2,3), H(4..7)]` (final)   |

Reading the trace: the level-1 sibling snaps from the padded `` B*[2] `` to the
final `H(2,3)` the instant $L_3$ completes that height-1 subtree and moves it
into `filled`; the level-2 sibling refines `` F*[4] -> F*[4,5] -> F*[4,5,6] ``
and locks to `H(4..7)` when $L_7$ completes its height-2 subtree.

**Definition 7.4d (witnessed vs tip position).** Two positions coexist:
`witnessed_position` is the leaf the witness proves, fixed at `tree.size() - 1`
when the witness is created; `tip_position` is the newest leaf appended to the
witness and grows with every `append`. Their relation is

$$
\mathrm{tip} = \mathrm{witnessed} +
\!\!\sum_{s \in \mathit{filled}} 2^{\mathrm{level}(s)}
+ \mathrm{cursor.size()},
$$

that is, the witnessed leaf plus all leaves absorbed into completed future
siblings plus the leaves in the in-progress cursor. The `witness_tip_position`
test makes this concrete: witness position $6$ in a depth-6 tree, append $18$
more leaves, and `tip_position` lands at $24$ while `witnessed_position` stays
at $6$.

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
