---
sidebar_position: 0
title: "Overview and Notation"
description: "A code-anchored onboarding course for the zcash/incrementalmerkletree workspace: frontiers, witnesses, bridges, and shard trees."
---

# incrementalmerkletree Onboarding

This is a graduate-level, code-anchored course for the
[`zcash/incrementalmerkletree`](https://github.com/zcash/incrementalmerkletree)
workspace: four Rust crates that implement append-only, witness-bearing,
checkpointed Merkle trees. The goal is operational. After working through
the chapters and exercises you should be able to open a small,
correct pull request, not merely describe the code.

Every chapter points at a specific file and line range in the upstream
repository, pinned to commit
[`edf24f2b`](https://github.com/zcash/incrementalmerkletree/tree/edf24f2b2e727776e290f292d831d4ac61c3e1bd).
Where a claim is not anchored to code, it is marked as an opinion.

:::warning Not authoritative

This site is automatically generated using Claude Code. Errors may have
been introduced. **This site is not authoritative documentation or
explanation of the Zcash protocol or the incrementalmerkletree
crates.** The only authoritative material is what is published by the
Zcash-related organisations that maintain the protocol and its reference
implementations, in particular:

- The source in the
  [`zcash/incrementalmerkletree`](https://github.com/zcash/incrementalmerkletree)
  workspace (the code is the law).
- The [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf).
- The published crate docs:
  [incrementalmerkletree](https://docs.rs/incrementalmerkletree),
  [shardtree](https://docs.rs/shardtree),
  [bridgetree](https://docs.rs/bridgetree).

Found an error? Open an issue or PR on the
[fork's `onboarding` branch](https://github.com/dannywillems/incrementalmerkletree/tree/onboarding).

:::

## 1. What these crates are

A Merkle tree over a sequence of appended leaves, where you want to:

- compute the current root cheaply,
- produce and **maintain** an authentication path (a "witness") for a few
  selected leaves as more leaves are appended,
- **checkpoint** the tree state and later roll back to a checkpoint,
- do all of this without storing every leaf, because the trees have depth
  32 (Sapling) or 32 (Orchard) and may hold billions of leaves.

The workspace contains three implementations of that idea plus a shared
core:

| Crate | Strategy | When it is used |
| --- | --- | --- |
| `incrementalmerkletree` | Shared primitives: addressing, `Hashable`, frontiers, witnesses | Dependency of all the others |
| `bridgetree` | Append-only, witnesses advanced via "bridges" | In-memory wallet tree, simple model |
| `shardtree` | Sparse, pruned, sharded, pluggable storage | Persistent wallet tree (SQLite-backed in `librustzcash`) |
| `incrementalmerkletree-testing` | Differential-testing harness | Test-only; proves the above agree |

The crates are **hash-function agnostic**. The leaf and node type is any
`H: Hashable`; the workspace never fixes a concrete hash. There is
therefore no cryptographic adversary model in this code: the security
arguments (collision resistance of Sinsemilla / Pedersen, soundness of
the circuits that consume the roots) live in `orchard`, `sapling-crypto`,
and the protocol specification, not here. What this workspace owns is a
set of **structural invariants**: that the computed root equals the root
of the fully-materialised tree, that a maintained witness still
authenticates after appends, and that a rollback restores exactly the
prior observable state.

## 2. Why wallets need this

These structures exist to serve **wallets**, which have a narrow but
awkward requirement. To spend a shielded note, a wallet must present an
authentication path (a "witness") for that note's commitment against the
current tree root (the "anchor"). The note sits at one **position** in a
note-commitment tree that every participant shares and that grows by one
leaf for every shielded output on the chain, potentially billions of
them, almost all belonging to other people.

Two naive strategies both fail at that scale:

- **Recompute each witness from zero.** Rebuilding a witness on demand
  means re-reading the whole commitment tree, every leaf ever appended,
  on each update. The cost then grows with the chain, not with the
  wallet.
- **Remember the entire tree.** Storing every commitment so a witness can
  be produced later wastes space on the overwhelming majority of leaves
  the wallet has no interest in.

The structures in this workspace take a third path. A wallet **marks**
only the few positions it cares about and keeps just enough sibling data
to authenticate them. As the chain appends new, independent commitments,
each marked position's witness is **advanced incrementally**, computed on
the fly from the new leaves rather than reconstructed from scratch. The
marked positions together with their partial witness state are the thing
that must be persisted as the chain evolves: in memory as a chain of
bridges in `bridgetree` ([Chapter 8](./08-bridgetree.md)), or as pruned,
storage-backed shards in `shardtree`
([Chapter 9](./09-shardtree-structure.md) onward). The rest of the tree,
between the marked positions, can be summarised by a frontier
([Chapter 5](./05-frontiers.md)) and otherwise discarded.

This is why the crates optimise for "append a leaf, optionally mark it,
cheaply update the witnesses of previously marked leaves, and checkpoint
so a reorg can roll back", rather than for random access to an arbitrary
historical tree.

## 3. Notation

Fixed for the whole course. Each symbol maps to a type in
`incrementalmerkletree/src/lib.rs`.

- A binary tree. Leaves are at **level** $0$; a node at level $\ell$ is the
  root of a subtree spanning $2^{\ell}$ leaf positions. Type: `Level(u8)`.
- $p \in \{0, 1, \dots, 2^{64}-1\}$: a leaf **position**. Type:
  `Position(u64)`.
- An **address** $a = (\ell, i)$ with level $\ell$ and index
  $i \in \{0, \dots, 2^{64}-1\}$ locates any node: the $i$-th subtree
  rooted at level $\ell$, counting from the left. Type: `Address`.
- $\mathsf{DEPTH} \in \{0, \dots, 255\}$: the fixed tree depth, a const
  generic. The tree holds up to $2^{\mathsf{DEPTH}}$ leaves.
- $H$: the leaf/node type, constrained by the `Hashable` trait.
  $\mathsf{combine}_\ell(a, b)$ is `H::combine(level, a, b)`, the parent
  of two level-$\ell$ nodes. $\varnothing_\ell$ is `H::empty_root(level)`,
  the root of an all-empty subtree of height $\ell$.
- The **ommers** of a frontier are the stored left-sibling subtree roots
  needed to recompute the root and witnesses. (`bridgetree` reuses the
  word "ommer" for the sibling of a parent node.)
- A **witness** (authentication path) for position $p$ is the sequence of
  sibling node values from leaf $p$ up to the root.

The level/index/position vocabulary is defined precisely, with worked
examples, in the module docstring:

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L1-L44
```

## 4. Invariants and the tests that guard them

This is the data-structure analogue of a threat-model table: each row is
a load-bearing invariant, what breaks it, where it is enforced, and the
test that catches a regression. Use it as a map from "I changed X" to
"run this test".

| Invariant | What breaks it | Enforced in | Caught by |
| --- | --- | --- | --- |
| Frontier root = full-tree root | Wrong ommer carry on append | `incrementalmerkletree/src/frontier.rs` `NonEmptyFrontier::{append,root}` | `frontier::tests::nonempty_frontier_root` |
| Witness still authenticates after appends | Mis-tracking future vs past siblings | `bridgetree/src/lib.rs` `BridgeTree::witness` | `incrementalmerkletree-testing` `CombinedTree` proptests |
| Pruned root = unpruned root | Dropping a node needed for the root | `shardtree/src/prunable.rs` `PrunableTree::root_hash` | `shardtree` `prunable` unit + proptests |
| Cap holds only shard roots, never sub-shard parents | `root_caching` splitting a cap leaf | `shardtree/src/lib.rs` `root_internal` | `shardtree::tests` (added in `4d78d5b`/`202fb2a`) |
| Rollback restores prior observable state | Off-by-one in checkpoint depth | `shardtree/src/lib.rs` `truncate_to_checkpoint_depth` | differential `check_operations` proptests |
| Two implementations agree | Any of the above, in either tree | `incrementalmerkletree-testing/src/lib.rs` `CombinedTree` | `check_operations` over random `Operation` sequences |

The last row is the backstop. `CombinedTree` runs a slow,
fully-materialised reference tree next to each efficient tree and asserts
that every observable (root, witness, marked positions) is identical
after every random operation. Most structural bugs in this workspace are
caught there first.

## 5. How to read this course

- **Part I (Chapters 1-2):** the workspace map and the build/test/
  contribution loop. Read these first and return to them often.
- **Part II (Chapters 3-6):** the shared core in `incrementalmerkletree`:
  tree navigation, hashing, frontiers, and the retention model. Every
  later chapter depends on these.
- **Part III (Chapters 7-8):** the two "simple" trees: the legacy
  `IncrementalWitness` and `bridgetree`.
- **Part IV (Chapters 9-13):** `shardtree`, the production tree:
  structure, pruning, operations, storage, and batch insertion.
- **Part V (Chapters 14-15):** the differential-testing framework and the
  failure-modes/audit map.
- **Part VI (Chapter 16):** a week-by-week study plan converging on a
  real PR, followed by reference pages (cheat sheet, PR checklist,
  glossary).

Start at [Chapter 1: The Workspace Map](./01-workspace-map.md).
