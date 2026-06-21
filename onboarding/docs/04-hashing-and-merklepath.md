---
sidebar_position: 4
title: "Hashing and the Merkle Path"
description: "The Hashable trait, empty subtree roots, and how a MerklePath recomputes a root from a leaf and its siblings."
---

# Hashing and the Merkle Path

## 1. Why this chapter exists

The workspace never names a concrete hash function. Everything is written
against the `Hashable` trait, and the one structural assumption the code
makes, that the parent of two nodes is `combine(level, left, right)`, is
encoded there. Understanding `Hashable` and `MerklePath::root` tells you
exactly which obligations a downstream crate (`orchard`, `sapling-crypto`)
must satisfy when it plugs in Sinsemilla or Pedersen hashing, and lets you
reason about root computation without picking a hash. You will touch
[`incrementalmerkletree/src/lib.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs)
lines 612-679.

## 2. Definitions

**Definition 4.1 (Hashable).** A type $H$ is `Hashable` if it provides:

- $\mathrm{emptyLeaf}() : H$, the value of an empty level-0 leaf;
- $\mathrm{combine} : \mathrm{Level} \times H \times H \to H$, the parent
  of two nodes that both sit at the given level.

The level is passed to `combine` so that domain separation by height is
possible (Sapling and Orchard hash differently per level). $H$ must also be
`Debug`.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L658-L679
```

**Definition 4.2 (empty root).** The root of an all-empty subtree of
height $\ell$ is defined by the recurrence

$$
\varnothing_0 = \mathrm{emptyLeaf}(), \qquad
\varnothing_{\ell+1} = \mathrm{combine}(\ell,\ \varnothing_\ell,\ \varnothing_\ell).
$$

`empty_root(level)` folds this from level $0$ up. Because empty roots
recur, a sparse tree can substitute $\varnothing_\ell$ wherever a whole
subtree is absent, which is the mechanism that makes frontiers and pruned
trees able to compute a full-depth root without storing empty regions.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L667-L678
```

**Definition 4.3 (Merkle path).** A `MerklePath<H, DEPTH>` is a vector of
exactly `DEPTH` sibling values plus the witnessed `Position`. The leaf is
combined with the path bottom-up, the bit of the position at each level
selecting whether the running digest is the left or right argument:

$$
r_0 = \mathit{leaf}, \qquad
r_{i+1} =
\begin{cases}
\mathrm{combine}(i,\ r_i,\ h_i) & \text{if bit } i \text{ of } p = 0 \\
\mathrm{combine}(i,\ h_i,\ r_i) & \text{if bit } i \text{ of } p = 1,
\end{cases}
$$

and the root is $r_{\mathsf{DEPTH}}$. This is the `fold` in
`MerklePath::root`.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L612-L656
```

**Invariant 4.4 (path length equals depth).** `MerklePath::from_parts`
returns `Err(())` unless `path_elems.len() == DEPTH`. A path is therefore
always full-depth; sparsity is handled by filling missing siblings with
$\varnothing_\ell$ before construction, not by shortening the path.

## 3. The code: the string hash used in tests

The test suite uses a deliberately trivial `Hashable` where `combine` is
string concatenation and `empty_leaf` is `"_"`, so that roots are
human-readable. This makes the path arithmetic auditable by eye:
`MerklePath` of `["a", "cd", "efgh"]` over leaf `"b"` at position 1 yields
`"abcdefgh"`.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L871-L888
```

The position bit selects argument order: at level 0, position 1 is odd, so
the sibling `"a"` goes on the left and the leaf `"b"` on the right, giving
`"ab"`; position 2 is even at level 0, so leaf `"c"` is left and sibling
`"d"` is right, giving `"cd"`. The differential `String` `Hashable` used by
the testing crate is the same idea with level-tagged separators.

## 4. Failure modes

- **`combine` that ignores its `level` argument.** A hash that does not
  separate by level lets a node at one height be reinterpreted at another.
  The trait passes the level precisely so implementations can prevent
  this; the test `Hashable` for `TestNode` hashes the level in. Caught
  by: no test in this workspace enforces domain separation (it is the
  downstream hash's obligation). No automated test in this workspace;
  caught by audit only.
- **Building a `MerklePath` of the wrong length.** `from_parts` rejects
  it, returning `Err(())`. A caller that `unwrap`s without padding to
  `DEPTH` panics. Caught by: `tests::merkle_path_root` exercises the
  exact-length path; the frontier's `witness` always pads to depth.
- **Recomputing `empty_root` in a hot loop.** It is $O(\ell)$ `combine`
  calls each time. Downstream code that needs many empty roots should
  cache them. Caught by: not a correctness bug; no test. Performance only.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 5.4.1.3 (Pedersen hash, Sapling) and Section 5.4.1.9 (Sinsemilla
  hash, Orchard) define the concrete `combine` functions that downstream
  crates implement for `Hashable`. Cited because the level argument to
  `combine` maps to the per-layer domain separation these sections
  require.
- Section 3.8 (Note Commitment Trees) fixes `DEPTH = 32` for both Sapling
  and Orchard; the `MerklePath<H, DEPTH>` const generic carries that
  depth.

## 6. Exercises

1. **Answer from code.** Why does `MerklePath::from_parts` take
   `DEPTH` as a const generic rather than a runtime length? Cite the
   struct definition and the length check.
2. **Compute a root by hand.** Using the test `Hashable` for `String`,
   give the root of leaf `"c"` at position 2 with path
   `["d", "ab", "efgh"]`. Verify against the second assertion in
   `tests::merkle_path_root`.
3. **Implement `Hashable` (modify).** In a scratch test, implement
   `Hashable` for a newtype `Xor(u64)` where `combine` is
   `Xor(a ^ b ^ (level as u64))` and `empty_leaf` is `Xor(0)`. Assert
   that `Xor::empty_root(Level::from(2))` equals what the recurrence in
   Definition 4.2 predicts. This forces you to exercise the empty-root
   fold.

### Answers in the code

- Exercise 1: `MerklePath` is `lib.rs:613-640`; the const generic lets the
  length be checked at `from_parts` (`lib.rs:622-631`) and makes depth
  part of the type so two different-depth paths cannot be mixed.
- Exercise 2: yields `"abcdefgh"`, asserted at `lib.rs:881-887`.
- Exercise 3: model your implementation on `TestNode`'s at
  `incrementalmerkletree/src/frontier.rs:704-717`.

## 7. Further reading

- [Chapter 6: Retention and Checkpointing](./06-retention-and-checkpointing.md)
  shows how leaf values carry metadata (`Retention`) on top of the bare
  `Hashable` value, which is what lets the trees prune.
