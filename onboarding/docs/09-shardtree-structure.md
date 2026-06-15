---
sidebar_position: 9
title: "shardtree: Structure"
description: "The Node, Tree, and LocatedTree types and the cap-plus-shards decomposition that lets shardtree persist a depth-32 tree."
---

# shardtree: Structure

## 1. Why this chapter exists

`shardtree` is the tree used in production wallets (it is the engine behind
`librustzcash`'s SQLite-backed note commitment tree). Before you can read
any operation on it, you need its skeleton: the generic annotated binary
tree (`Tree`/`Node`), its located variant (`LocatedTree`), and the
top-level decomposition into a **cap** over fixed-height **shards**. This
chapter establishes that skeleton from
[`shardtree/src/tree.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs)
and
[`shardtree/src/store.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs).

## 2. Definitions

**Definition 9.1 (Node).** `Node<C, A, V>` is one layer of a binary tree:
either a `Parent { ann: A, left: C, right: C }`, a `Leaf { value: V }`, or
`Nil` (a subtree about which nothing is known). The annotation `A` on a
parent caches its subtree root; `V` is the leaf payload. Crucially, a
`Leaf` may appear at any level: it then holds a computed subtree root, not
a level-0 value.

```rust reference title="shardtree/src/tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L8-L22
```

**Definition 9.2 (Tree).** `Tree<A, V>` ties the knot:
`Tree(Node<Arc<Tree<A, V>>, A, V>)`. Children are reference-counted, so
subtrees are cheaply shared and cloned. `Tree::empty()`, `Tree::leaf(v)`,
and `Tree::parent(ann, l, r)` are the constructors.

```rust reference title="shardtree/src/tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L78-L112
```

**Invariant 9.3 (no parent with two Nil children).** The code never
constructs a `Parent` whose children are both `Nil`; such a node carries
no information and would break `incomplete_nodes`. The invariant is
asserted rather than handled, because a violation indicates a bug
elsewhere.

```rust reference title="shardtree/src/tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L130-L154
```

**Definition 9.4 (LocatedTree).** A `LocatedTree<A, V>` is a `Tree`
together with the `Address` of its root. `from_parts` validates that no
`Parent` node sits at level 0 relative to the root address (a structural
precondition the rest of the crate relies on). Location lets the tree map
positions to leaves (`value_at_position`), extract subtrees (`subtree`),
and split into shard-sized pieces (`decompose_to_level`).

```rust reference title="shardtree/src/tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L192-L231
```

**Definition 9.5 (cap and shards).** A `ShardTree<S, DEPTH, SHARD_HEIGHT>`
splits the depth-`DEPTH` tree into:

- **shards**: subtrees whose roots are at level `SHARD_HEIGHT`, each a
  `LocatedPrunableTree`, stored individually;
- the **cap**: a `PrunableTree` over the nodes at levels
  `SHARD_HEIGHT..DEPTH`, whose leaves are the shard roots.

The store module documents the layout directly:

```rust reference title="shardtree/src/store.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L1-L23
```

Why split the tree this way? A depth-32 tree has $2^{32}$ leaf positions,
which cannot be held in memory or rewritten on every append. Sharding
makes a tree of that size storable and updatable:

- **Storage locality.** Shards are stored and loaded individually
  (`ShardStore::get_shard` / `put_shard` / `last_shard`). An append
  touches only the rightmost shard; completed shards to its left are
  never rewritten.
- **Per-shard pruning.** Each shard is a `PrunableTree`, so once a region
  is fully scanned its interior collapses to a single retained root hash,
  which becomes the leaf the cap holds for that shard.
- **Cheap witness advancement.** Because completed shards collapse to
  their roots, moving a witness across a large gap needs only the roots of
  the complete shards between the marked leaf and the frontier, plus the
  path inside the shard that holds the marked leaf, rather than every
  intermediate leaf. The module header states this directly.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L1-L21
```

The cap-versus-shard cut line at level `SHARD_HEIGHT` is also where root
computation changes strategy: walking the cap answers from cached shard
roots, while reaching the cut delegates to shard data via
`root_from_shards` ([Chapter 11](./11-shardtree-operations.md)).

## 3. The code: locating and decomposing

`value_at_position` walks from the root address into the correct child by
testing which child's position range contains the target, the run-time
use of Definition 3.5.

```rust reference title="shardtree/src/tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L263-L288
```

`decompose_to_level` splits a tree into the vector of its subtrees at a
given level, the operation that turns a freshly built subtree into
shard-sized pieces before they are stored. It unwraps shared `Arc`s where
it can to avoid cloning.

```rust reference title="shardtree/src/tree.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L375-L417
```

The `ShardTree` type itself binds the two const generics and a store:

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L60-L130
```

The canonical small instance used throughout the tests is
`ShardTree<MemoryShardStore<_, usize>, 6, 3>`: depth 6, shard height 3, so
the cap spans levels 3 to 6 and each shard spans levels 0 to 3.

## 4. Failure modes

- **Putting a `Parent` at level 0 of a `LocatedTree`.** `from_parts`
  returns `Err(address)`. Many crate methods assume no sub-leaf parents;
  violating it is the precise shape of the cap-corruption bug
  ([Chapter 15](./15-failure-modes-and-audits.md)). Caught by:
  `LocatedTree::from_parts`'s `check` recursion and the regression tests
  added in `4d78d5b`.
- **Constructing a `Parent` with both children `Nil`.** Asserts in debug;
  in release it would make `incomplete_nodes` and root computation wrong.
  Caught by: the `assert!` in `Tree::incomplete_nodes`
  (`tree.rs:141`).
- **Confusing a high-level `Leaf` (a cached subtree root) with a level-0
  leaf.** `value_at_position` only returns a value when the leaf address
  is at level 0; a `Leaf` higher up is a pruned subtree root, not a leaf
  value. Caught by: the `addr.level() == Level::from(0)` guard in
  `value_at_position` and `tests::located`.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8 fixes `DEPTH = 32`. The shard decomposition is an
  implementation strategy not mandated by the spec; `librustzcash` chooses
  `SHARD_HEIGHT = 16` so each shard spans $2^{16}$ positions. Cited
  because the const-generic depth is the protocol's, while the shard
  height is the implementation's.

## 6. Exercises

1. **Answer from code.** Why is a `LocatedTree` allowed to contain `Leaf`
   nodes at non-zero levels but not `Parent` nodes at level 0? Cite the
   `check` function in `from_parts`.
2. **Decompose.** Predict the result of `decompose_to_level(Level::from(1))`
   on the two-level tree built in `tree.rs`'s `located` test, then verify
   against that test.
3. **Walk a position (modify).** Add a unit test to `tree.rs` building a
   `LocatedTree` rooted at `Address::from_parts(Level(2), 1)` with four
   leaves and asserting `value_at_position` for each of positions 4..8,
   plus `None` for position 3 (out of range). Confirm
   `cargo test -p shardtree` passes.

### Answers in the code

- Exercise 1: leaves at any level represent pruned subtree roots, which is
  legal; a level-0 parent is structurally impossible and signals
  corruption. See `tree.rs:204-231`.
- Exercise 2: the `located` test asserts the two-element decomposition at
  `tree.rs:490-502`.
- Exercise 3: model on `tests::located` (`tree.rs:466-503`).

## 7. Further reading

- [Chapter 10: The Prunable Tree](./10-prunable-tree.md) specialises
  `Tree` to `PrunableTree<H>` and defines root computation over a
  partially pruned tree.
