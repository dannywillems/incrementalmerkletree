---
sidebar_position: 20
title: "Lean 4 Formalization Plan"
description: "Mapping the workspace's structures and correctness properties to a Lean 4 formalization: the reference Merkle model, the refinement methodology, and a layered, ranked catalog of theorems."
---

# Lean 4 Formalization Plan

## 1. Why this chapter exists

The earlier chapters established, in prose and code, the invariants that the
crates rely on. This chapter turns those invariants into a concrete plan for
machine-checked proofs in [Lean 4](https://lean-lang.org/). It is the bridge
from "we believe this holds and there are unit tests" to "this is proved for
all inputs against an abstract hash."

The planning artifact lives in the repository root at `formalization/PLAN.md`,
with a buildable Lean scaffold under `formalization/Imt/`. This chapter
summarizes that plan and explains the methodology.

:::warning Not authoritative

Like the rest of this site, this chapter is auto-generated and is a plan, not a
verified result. The theorems below are targets; a target is not a proof.

:::

## 2. The one idea

Every structure in the workspace is a different representation of the same
mathematical object: a binary Merkle tree over an append-only leaf sequence,
hashed by an abstract `combine`. The whole effort reduces to one pattern,
applied at each layer:

> Define a **reference model** (the naive full Merkle root over a leaf list),
> an **abstraction function** $\mathrm{repr}$ from each concrete structure to
> the list of leaves it represents, and prove the concrete operations
> **refine** the model.

Concretely, for a structure $T$ with operations `append` and `root`:

$$
\mathrm{repr}(\mathtt{append}(t, v)) = \mathrm{repr}(t) \mathbin{+\!\!+} [v],
\qquad
\mathtt{root}(t) = \mathrm{merkleRoot}_{\mathsf{DEPTH}}(\mathrm{repr}(t)).
$$

The clever, storage-efficient representation is correct exactly when its
`root` equals the obviously-correct `merkleRoot` of the same leaves.

## 3. What is and is not in scope

In scope is **structural** correctness, which is what the Rust code actually
guarantees:

- the addressing arithmetic of [Level, Position, Address](./03-tree-navigation.md);
- that each representation's root equals the reference Merkle root;
- that `append` / `insert` / `batch_insert` refine "add a leaf";
- that produced witnesses verify against the root;
- that pruning, merging, checkpointing, and garbage collection preserve all
  still-observable roots and witnesses.

Out of scope is **cryptographic soundness**: that a valid witness *binds* its
leaf. That needs a collision-resistance assumption on `combine` and is a
separate theory. We model `combine` as an unconstrained function so the
structural theorems hold for any hash, and add collision-resistance only where
binding is claimed.

## 4. The Lean model

### 4.1 Numbers: BitVec

The wrapping integer types map directly onto Lean `BitVec`, faithful to Rust's
`u8` / `u64` semantics and friendly to the `bv_decide` decision procedure.

```lean
abbrev Level := BitVec 8          -- Rust u8
structure Position where val : BitVec 64
structure Address  where level : Level; index : BitVec 64
```

For lemmas that recurse on bit count (population count, $\log_2$), proofs
bridge through `BitVec.toNat` into `Nat` and use Mathlib's `Nat.testBit`,
`Nat.log2`, `Nat.popCount`. Rust's panicking subtractions become discharged
side-conditions.

### 4.2 The hash: abstract, unconstrained

```lean
class Hashable (H : Type) where
  emptyLeaf : H
  combine   : Level -> H -> H -> H
```

No algebraic axioms. Every structural theorem is universally quantified over
`H` and its `Hashable` instance.

### 4.3 The reference model

```lean
def merkleRoot [Hashable H] (level : Level) (leaves : List H) : H
```

The naive padded-tree root. Its simplicity is the point: every "root
correctness" theorem says a representation computes the same value as
`merkleRoot`.

## 5. The property map

Difficulty key: E (easy, decided automatically), M (medium, induction or a
`Nat` bridge), H (the substantive theorems). The crates form a strict
dependency stack; the recommended proof order is bottom-up.

### Layer 0: addressing arithmetic

Source: [`incrementalmerkletree/src/lib.rs`](./03-tree-navigation.md). Pure
bit arithmetic; the most tractable layer.

| ID | Property | Difficulty |
| --- | --- | --- |
| P0.1 | navigation round-trips: $\mathrm{sibling}(\mathrm{sibling}(a)) = a$; parent/children inverse | E |
| P0.3 | $\mathrm{rootLevel}(p) = 64 - \mathrm{clz}(p)$ | M |
| P0.4 | $\mathrm{pastOmmerCount}(p) = \mathrm{popcount}(p)$ (Lemma 3.7) | M |
| P0.5 | $\mathrm{isCompleteSubtree}(p,\ell)$ iff the low $\ell$ bits of $p$ are all set | E |
| P0.6 | `is_ancestor_of` is a strict partial order; `contains` is its reflexive closure | M |
| P0.7 | `common_ancestor` is the join (least common ancestor) | H |
| P0.9 | `witness_addrs` enumerates exactly the leaf-to-root siblings; $\#\mathrm{Past} = \mathrm{popcount}$ | M |

### Layer 1: hashing and Merkle path

Source: [hashing chapter](./04-hashing-and-merklepath.md).

| ID | Property | Difficulty |
| --- | --- | --- |
| P1.1 | $\varnothing_{\ell+1} = \mathrm{combine}(\ell, \varnothing_\ell, \varnothing_\ell)$ | E |
| P1.3 | `MerklePath.root(leaf)` reproduces the model root from true siblings | H |

### Layer 2: frontier

Source: [frontiers chapter](./05-frontiers.md).

| ID | Property | Difficulty |
| --- | --- | --- |
| P2.1 | well-formedness $\mathrm{ommers.len} = \mathrm{popcount}(p)$ preserved by `append` | M |
| P2.2 | `append` refines $\mathrm{repr} \mathbin{+\!\!+} [v]$ | M |
| **P2.3** | **root correctness**: `frontier.root(L)` $= \mathrm{merkleRoot}_L(\mathrm{repr})$ | H |
| P2.4 | witness soundness: the produced path verifies to the frontier root | H |
| P2.6 | `CommitmentTree` and `Frontier` are inter-convertible without loss | M |

P2.3 is the centerpiece: it proves the ommer-fold-with-empty-roots equals the
naive padded-tree root.

### Layer 3: incremental witness

Source: [incremental witness chapter](./07-incremental-witness.md).

| ID | Property | Difficulty |
| --- | --- | --- |
| P3.1 | appending the same leaves to tree and witness keeps roots equal; the path verifies | H |
| P3.2 | $\mathrm{tip} = \mathrm{witnessed} + \sum_{s \in \mathit{filled}} 2^{\mathrm{level}(s)} + \mathrm{cursor.size}$ | M |

### Layer 4: bridgetree

Source: [bridgetree chapter](./08-bridgetree.md). Theorems become refinement
and observational equivalence.

| ID | Property | Difficulty |
| --- | --- | --- |
| P4.1 | a continuous bridge chain equals one frontier (concatenation) | M |
| P4.3 | mark/witness soundness: a marked-position witness verifies at its checkpoint | H |
| P4.5 | `garbage_collect` preserves all still-observable witnesses and roots | H |

### Layer 5: shardtree / prunable tree

Source: [shardtree structure](./09-shardtree-structure.md),
[prunable tree](./10-prunable-tree.md), [batch insertion](./13-batch-insertion.md).
The most complex layer.

| ID | Property | Difficulty |
| --- | --- | --- |
| P5.1 | root agreement under truncation; a `Some` annotation is a sound cache | H |
| P5.2 | `prune` preserves the root and never drops a marked/checkpoint/reference leaf | H |
| P5.3 | `merge_checked` yields the information-union; conflict iff materialized disagreement | H |
| P5.4 | insert agreement: append-loop $=$ `batch_insert` $=$ parallel build | H |
| P5.5 | structural well-formedness preserved by every operation | H |

The three documented regression bugs of the
[failure-modes chapter](./15-failure-modes-and-audits.md) are negations of
P5.5, P5.1, and a frontier-generation edge case. Proving these theorems is
proving those bugs cannot recur.

## 6. Roadmap

Bottom-up, each milestone independently useful:

1. **M0** project scaffold: Level/Position/Address plus bit helpers.
2. **M1** Layer 0: the automatic identities first, then P0.4, P0.9, then the
   partial-order/lattice block P0.6 to P0.8.
3. **M2** Layer 1: the `merkleRoot` model, P1.1, P1.3 (Mathlib added here).
4. **M3** Layer 2: P2.1, P2.2, then the centerpiece P2.3, then P2.4.
5. **M4 to M6** Layers 3 to 5 as refinements onto the foundation.

The de-risking first slice is M0 plus the automatically-decided subset of M1,
which validates the BitVec model and the test-oracle workflow before the harder
inductive proofs.

## 7. The scaffold and oracle checks

The repository ships a buildable starting point. `formalization/Imt/Basic.lean`
defines the Layer 0 types and closes a set of ground "oracle" checks by
`decide`, each mirroring a Rust unit test (for example
`tests::position_past_ommer_count` and `tests::position_root_level`). A wrong
definition fails the build, so continuous integration exercises the model
rather than only typechecking signatures.

The Lean project is built in CI on both the `stable` and `beta` Lean release
channels (see `.github/workflows/lean.yml`).

## 8. Further reading

- `formalization/PLAN.md` in the repository root: the full property catalog
  with Lean theorem signatures and the Rust-test-to-Lean-oracle map.
- [Chapter 3: Tree Navigation](./03-tree-navigation.md) and
  [Chapter 5: Frontiers](./05-frontiers.md): the prose and code that Layers 0
  and 2 formalize.
- [Mathlib documentation](https://leanprover-community.github.io/mathlib4_docs/)
  for the `Nat` and `BitVec` lemmas the harder proofs will use.
