---
sidebar_position: 3
title: "Tree Navigation: Level, Position, Address"
description: "The integer arithmetic of binary-tree addressing that every crate in the workspace is built on, with proofs and code."
---

# Tree Navigation: Level, Position, Address

## 1. Why this chapter exists

Every higher-level operation in the workspace, appending a leaf, computing
a witness, pruning a shard, reduces to integer arithmetic on positions and
addresses. If you understand `Position::witness_addrs` and
`Address::common_ancestor`, the rest of the code reads as bookkeeping
around them. This chapter establishes that arithmetic formally, so that
when you edit
[`incrementalmerkletree/src/lib.rs`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs)
you can prove your change preserves the addressing invariants.

## 2. Definitions

**Definition 3.1 (Level).** A `Level` is a `u8`, $\ell \in \{0, \dots,
255\}$. Level $0$ is a leaf. A node at level $\ell$ is the root of a
perfect subtree spanning $2^{\ell}$ leaf positions. Capable of addressing
trees with up to $2^{255}$ leaves.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L282-L303
```

**Definition 3.2 (Position).** A `Position` is a `u64`, $p$, the 0-based
index of a leaf at level $0$. It is a `#[repr(transparent)]` newtype so it
cannot be confused with an arbitrary integer.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L185-L231
```

**Definition 3.3 (Address).** An `Address` is a pair $a = (\ell, i)$ with
$\ell$ a `Level` and $i \in \{0, \dots, 2^{64}-1\}$ an index. It denotes
the $i$-th subtree, counting from the left, whose root is at level $\ell$.
The address above a position is $\mathrm{above}(\ell, p) = (\ell,\,
p \gg \ell)$.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L360-L431
```

**Invariant 3.4 (navigation identities).** For an address $a = (\ell, i)$:

$$
\mathrm{parent}(\ell, i) = (\ell+1,\, i \gg 1), \qquad
\mathrm{sibling}(\ell, i) = (\ell,\, i \oplus 1),
$$
$$
\mathrm{children}(\ell, i) = \big((\ell-1,\, 2i),\ (\ell-1,\, 2i+1)\big)
\text{ for } \ell > 0,
$$

and $a$ is a right child iff $i \wedge 1 = 1$. These are exactly the bit
operations in `parent`, `sibling`, `children`, and `is_right_child`.

**Figure 3.4a (an `Address` is a level-relative coordinate, not a leaf
count).** The index counts nodes *at the address's own level*, so the same
horizontal location carries a different index at each level. Leaf $8$ is
$(0, 8)$; its parent is $(1,\, 8 \gg 1) = (1, 4)$. So $(0, 8)$ is a child of
$(1, 4)$ even though $8 \ne 4$. This is not an inconsistency: at level $1$
there is one node per two leaves, so indices halve as you climb.

```text
 level 2                 (2,2) = H(8..11)
                        /                \
 level 1        (1,4) = H(8,9)      (1,5) = H(10,11)
                /        \
 level 0     (0,8)      (0,9)     <- index counts level-0 nodes from the left
              ^
          leaf 8;  parent = (1, 8 >> 1) = (1,4)
```

Definition 3.3 says an address denotes a subtree "counting from the left ...
in a binary tree of arbitrary height": an `Address` is a coordinate in an
*unbounded* tree and carries no notion of tree size. Both $(0,8)$ and $(1,4)$
exist in any tree of depth $\ge 4$, and `parent`/`sibling`/`next_at_level` may
legitimately name nodes above or beyond a given root. The size-bearing types
are separate: a `Position` together with `DEPTH` ([Chapter 5](./05-frontiers.md))
fixes a concrete tree, while the bare `Address` stays a pure coordinate.

**Definition 3.5 (position range of an address).** The leaf positions
spanned by $a = (\ell, i)$ are the half-open interval

$$
\mathrm{range}(a) = \big[\, i \cdot 2^{\ell},\ (i+1) \cdot 2^{\ell} \,\big).
$$

In code, `position_range_start = index << level` and
`position_range_end = (index + 1) << level`.

**Definition 3.6 (root level of a position).** The minimum level of a
root of a tree containing at least $p + 1$ leaves is

$$
\mathrm{rootLevel}(p) = 64 - \mathrm{clz}(p) =
\begin{cases} 0 & p = 0 \\ \lfloor \log_2 p \rfloor + 1 & p > 0, \end{cases}
$$

where $\mathrm{clz}$ is the count of leading zero bits. This is
`Position::root_level`.

**Lemma 3.7 (past ommer count = popcount).** The number of stored left
siblings needed to authenticate position $p$ to the root at level
$\mathrm{rootLevel}(p)$ equals the number of set bits of $p$:

$$
\mathrm{pastOmmerCount}(p) = \mathrm{popcount}(p).
$$

*Proof sketch.* Walk from leaf $p$ to the root. At level $\ell$, the
current node is a right child iff bit $\ell$ of $p$ is set. A right child
has a **left** sibling that lies entirely to its left, hence is a fully
materialised subtree whose root is a stored ommer; a left child's sibling
lies to its right and is not yet materialised. So each set bit of $p$
contributes exactly one past ommer, and clear bits contribute none.
$\square$ This is the `filter(... & 0x1 == 1).count()` in
`past_ommer_count`.

**Definition 3.8 (Source).** When enumerating the siblings on the path
from $p$ to a root, each sibling is tagged:

- `Source::Past(k)` if it is a left sibling already available as ommer
  index $k$ (the node is a right child),
- `Source::Future` if it is a right sibling not yet materialised (the node
  is a left child).

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L144-L183
```

**Definition 3.9 (witness addresses).** `Position::witness_addrs(root)`
returns the iterator over $(\,\mathrm{sibling\ address},\ \mathrm{Source}\,)$
pairs from the leaf's sibling up to the sibling of the ancestor just below
`root`. This single iterator drives append, root computation, and witness
construction in the frontier.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L220-L231
```

**Definition 3.10 (common ancestor).** `common_ancestor(a, b)` returns the
lowest-level address whose subtree contains both $a$ and $b$. It lifts the
lower node to the higher node's level, XORs the indices to find how many
levels their Merkle paths differ on, and returns that join. Used by
`shardtree` to find where two subtrees must be merged.

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L438-L458
```

## 3. The code: reading `witness_addrs`

Worked example. For $p = 3$ in a tree of root level $3$
(`Position::from(3).witness_addrs(Level::from(3))`), the iterator yields:

| Step | Sibling address $(\ell, i)$ | Source | Why |
| --- | --- | --- | --- |
| 0 | $(0, 2)$ | `Past(0)` | leaf 3 is a right child; its left sibling (leaf 2) is materialised |
| 1 | $(1, 0)$ | `Past(1)` | node $(1,1)$ is a right child; sibling $(1,0)$ is materialised |
| 2 | $(2, 1)$ | `Future` | node $(2,0)$ is a left child; sibling is not yet filled |

This is asserted directly in the unit test:

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L741-L750
```

Note that the two `Past` siblings correspond to the two set bits of
$3 = 0b11$, confirming Lemma 3.7.

## 4. Failure modes

- **Off-by-one in `root_level` for $p = 0$.** `rootLevel(0) = 0`, not
  $1$: a single-leaf tree has its root at the leaf. A naive
  $\lfloor \log_2 p \rfloor + 1$ underflows at $0$; the code uses
  `64 - leading_zeros`, which gives $0$. Caught by:
  `tests::position_root_level`.
- **Treating index as position at level &gt; 0.** Only at level $0$ does
  index equal position. `Address::from(position)` always sets level $0$;
  going the other way (`Option<Position>` from an address) yields `None`
  unless the level is $0$. Caught by: the `From`/`Into` impls and
  `tests::addr_above_position`.
- **`Sub` underflow.** `Position - u64` and `Level - u8` panic on
  underflow by design (`position underflow`, `underflow`). A subtraction
  that can go negative must be guarded by the caller. Caught by: no
  dedicated test; the panic is the contract. No automated test in this
  workspace; caught by review only.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 5.4.8 (Merkle path validity) defines the leaf-to-root path whose
  sibling enumeration `witness_addrs` computes. Cited because the
  ordering of path elements (leaf-adjacent first) must match what the
  protocol's Merkle-path verifier expects.

## 6. Exercises

1. **Answer from code.** What does
   `Address::from_parts(Level(3), 1).context(Level(0))` return, and why?
   Give the line range that defines `context`.
2. **Compute by hand, then verify.** Predict the full output of
   `Position::from(6).witness_addrs(Level::from(4))`, including the
   `Source` tag of each element, using Lemma 3.7 to predict the count of
   `Past` entries. Verify against `tests::position_witness_addrs`.
3. **Add a test (modify).** Add a unit test to the `tests` module in
   `lib.rs` asserting `Position::from(8).past_ommer_count() == 1` and
   `Position::from(7).past_ommer_count() == 3`, then explain the result
   in terms of the binary representations $8 = 0b1000$ and $7 = 0b111$.
   Confirm `cargo test -p incrementalmerkletree` passes.

### Answers in the code

- Exercise 1: `context` is at
  `incrementalmerkletree/src/lib.rs:497-510`; the answer is
  `Either::Right(8..16)`, asserted in `tests::addr_context`.
- Exercise 2: predicted by Lemma 3.7 ($\mathrm{popcount}(6) = 2$ past
  entries); asserted at `incrementalmerkletree/src/lib.rs:762-772`.
- Exercise 3: `past_ommer_count` is `lib.rs:205-211`; existing assertions
  in `tests::position_past_ommer_count` cover both values.

## 7. Further reading

- [Chapter 5: Frontiers](./05-frontiers.md) shows how `witness_addrs`
  drives `NonEmptyFrontier::append` and `root` together, which is the
  payoff for the arithmetic in this chapter.
