---
sidebar_position: 5
title: "Frontiers"
description: "The NonEmptyFrontier and Frontier types: a constant-space summary of an append-only tree, its append carry algorithm, root, and witness."
---

# Frontiers

## 1. Why this chapter exists

A frontier is the minimal state needed to keep appending to a Merkle tree
and to compute its root: the most recent leaf plus a list of left-sibling
subtree roots ("ommers"). It is the heart of every tree in the workspace,
`bridgetree` stores a frontier per bridge, `shardtree` extracts one via
`ShardTree::frontier`. The append algorithm is a binary carry, and getting
the carry wrong silently corrupts every future root. This chapter derives
that algorithm from the addressing arithmetic of
[Chapter 3](./03-tree-navigation.md) and anchors it to
[`incrementalmerkletree/src/frontier.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs).

## 2. Definitions

**Definition 5.1 (NonEmptyFrontier).** A `NonEmptyFrontier<H>` is a triple
$(p,\, \mathit{leaf},\, [\,o_0, \dots, o_{k-1}\,])$ where $p$ is the
`Position` of the most recently appended leaf, $\mathit{leaf} \in H$ is its
value, and the ommers are stored left siblings, ordered from lowest level
to highest. By Lemma 3.7 the well-formedness condition is
$k = \mathrm{popcount}(p)$, checked by `from_parts`.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L32-L64
```

**Definition 5.2 (Frontier).** A `Frontier<H, DEPTH>` wraps an
`Option<NonEmptyFrontier<H>>` and enforces the depth bound: a frontier is
only valid while its position's root level is at most `DEPTH`. `append`
returns `false` when the tree is full (the current position is a complete
subtree at `DEPTH`).

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L273-L347
```

**Definition 5.3 (frontier root).** Given target level $L$, the root is
computed by folding `witness_addrs(L)`: starting from the leaf, fold up,
pairing the running digest with each ommer (`Source::Past`) on its **left**
or with $\varnothing_\ell$ (`Source::Future`) on its **right**, inserting
empty roots to bridge level gaps. Formally, for each step with sibling at
level $\ell$:

$$
\mathit{digest} \leftarrow
\begin{cases}
\mathrm{combine}(\ell,\ o_i,\ \mathit{digest}) & \text{Source::Past}(i) \\
\mathrm{combine}(\ell,\ \mathit{digest},\ \varnothing_\ell) & \text{Source::Future.}
\end{cases}
$$

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L138-L165
```

**Definition 5.4 (frontier witness).** `witness(depth, complement)`
produces the path elements for the tip leaf: each `Source::Past(i)` step
contributes ommer $o_i$ directly; each `Source::Future` step asks the
caller's `complement` function for the node at that address, returning the
address as an error if it is unavailable. This is how a witness for the
*tip* is read off a frontier given a source of right-hand nodes.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L167-L186
```

## 3. The code: the append carry

**Invariant 5.5 (append).** Appending a leaf advances $p \to p+1$. Two
cases:

1. **New position is odd** ($p+1$ is a right child): the old leaf becomes
   a level-0 ommer, inserted at the front of the ommer list. No hashing.
2. **New position is even**: the old leaf must be hashed up the tree,
   combining with successive ommers until an empty slot is found, exactly
   a binary increment with carry. The `carry` local holds the value being
   propagated and its level; at each `Source::Past` address whose level
   matches the carry, the stored ommer and the carry are combined and the
   carry rises a level; at the first mismatch the carry and the remaining
   ommers settle into the new ommer list.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L88-L136
```

Worked example, building `"a".."g"` (positions 0-6) with the string
`Hashable`, then reading the tip root: the unit test
`nonempty_frontier_root` asserts the running roots `"a"`, then `"ab"`,
then `"abc_"`, where `_` is the empty leaf padding the missing position 3.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L782-L792
```

The witness test makes the `complement` source explicit: future siblings
at level 0 and level 3 are supplied by a closure, and the resulting path
is `["h", "ef", "abcd", "xxxxxxxx"]`.

```rust reference title="incrementalmerkletree/src/frontier.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L817-L835
```

## 4. Failure modes

- **Ommer list inconsistent with position.** If `from_parts` is given an
  ommer count $\ne \mathrm{popcount}(p)$ it returns
  `FrontierError::PositionMismatch`. Hand-constructing a frontier with the
  wrong ommers (for example when deserialising) is the classic corruption
  source. Caught by: `tests::frontier_from_parts`.
- **Exceeding `DEPTH`.** `NonEmptyFrontier -> Frontier` conversion fails
  with `MaxDepthExceeded` if the position's root level is above `DEPTH`;
  `Frontier::append` returns `false` rather than overflowing. Caught by:
  the `TryFrom` impl and `tests::frontier_root` (which appends up to
  capacity).
- **Wrong argument order in the root fold.** Ommers are *left* siblings
  and must be the left argument to `combine`; future siblings are *right*.
  Swapping them produces a root that passes for symmetric test hashes but
  fails for any real hash. Caught by: `tests::nonempty_frontier_root` and
  `tests::frontier_witness` (the string hash is order-sensitive).

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8 specifies that the note commitment tree is append-only and
  that wallets retain only the frontier ("the rightmost path") plus
  witnesses for their own notes. Cited because the frontier is the
  in-protocol representation of "the tree so far".

## 6. Exercises

1. **Answer from code.** In `NonEmptyFrontier::append`, why is the
   odd-position case a single `self.ommers.insert(0, prior_leaf)` with no
   hashing? Relate it to the binary increment $p \to p+1$.
2. **Trace the carry.** Append `"a".."d"` to a fresh `NonEmptyFrontier`
   and write down the ommer list after each append. Confirm that after
   appending `"d"` (position 3) the ommer count is
   $\mathrm{popcount}(3) = 2$.
3. **Add a property test (modify).** In the `frontier.rs` test module, add
   a `proptest!` that appends a random non-empty sequence of `TestNode`s
   to a `Frontier<TestNode, 8>`, then asserts that its `root()` equals the
   root computed by an independent full re-hash via
   `random_with_prior_subtree_roots`. Use the existing
   `test_random_frontier_structure` as a template. Confirm it passes.

### Answers in the code

- Exercise 1: odd $p+1$ means the new leaf is a right child, so the prior
  leaf is exactly its (already complete) left sibling, a level-0 ommer;
  `frontier.rs:96-99`.
- Exercise 2: after `"d"`, ommers are `[combine(0,a,b)`-derived carry`,
  ...]`; the count check is `from_parts` at `frontier.rs:53-64`.
- Exercise 3: model on `frontier.rs:904-930`.

## 7. Further reading

- [Chapter 8: bridgetree](./08-bridgetree.md) builds witness maintenance
  on top of frontiers via `MerkleBridge`, which stores one
  `NonEmptyFrontier` and a set of tracked ommers.
- [Chapter 7](./07-incremental-witness.md) covers the legacy
  `CommitmentTree`, an alternative frontier encoding kept for `zcashd`
  compatibility.
