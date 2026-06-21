---
sidebar_position: 19
title: "Glossary"
description: "The domain vocabulary of the incrementalmerkletree workspace, each term linked to the file where it is defined."
---

# Glossary

## 1. Why this chapter exists

The workspace uses a small fixed vocabulary consistently; this page fixes
one name per concept and links each to its defining file, so prose,
reviews, and PR descriptions stay aligned. Use these exact terms.

## 2. Definitions

- **Address** $(\ell, i)$: a node locator (level + index). Defined in
  [`incrementalmerkletree/src/lib.rs:360`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L360-L367).
- **Annotation**: the cached subtree root stored on a `Node::Parent`.
  Defined in
  [`shardtree/src/tree.rs:8`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/tree.rs#L8-L22).
- **Bridge**: the minimal delta to advance witnesses between two tree
  states (`MerkleBridge`). Defined in
  [`bridgetree/src/lib.rs:78`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L78-L100).
- **Cap**: the `PrunableTree` over levels `SHARD_HEIGHT..DEPTH` whose
  leaves are shard roots. Defined in
  [`shardtree/src/store.rs:1`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L1-L23).
- **Checkpoint**: a rollback boundary; `shardtree` records a `TreeState`,
  `bridgetree` records a bridge count. Defined in
  [`shardtree/src/store.rs:271`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L271-L320)
  and
  [`bridgetree/src/lib.rs:326`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/bridgetree/src/lib.rs#L320-L390).
- **Checkpoint depth**: a 0-based index into checkpoints in reverse id
  order (0 = most recent). Defined in
  [`shardtree/src/store.rs:96`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L96-L116).
- **CommitmentTree** (legacy): the `zcashd`-compatible frontier encoding.
  Defined in
  [`incrementalmerkletree/src/frontier.rs:442`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L442-L450).
- **Frontier**: the rightmost path plus ommers; the append-and-root
  summary. Defined in
  [`incrementalmerkletree/src/frontier.rs:32`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L32-L40).
- **Hashable**: the trait providing `empty_leaf` and `combine`. Defined in
  [`incrementalmerkletree/src/lib.rs:658`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L658-L679).
- **Level** $\ell$: height above the leaves (0 = leaf). Defined in
  [`incrementalmerkletree/src/lib.rs:282`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L282-L303).
- **Mark**: flag a leaf so its witness is maintained (`Retention::Marked`).
  Defined in
  [`incrementalmerkletree/src/lib.rs:88`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L88-L107).
- **Ommer**: a stored left-sibling subtree root in a frontier;
  `bridgetree` also uses it for a parent's sibling. Defined in
  [`incrementalmerkletree/src/frontier.rs:36`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/frontier.rs#L36-L40).
- **Position** $p$: the 0-based index of a leaf at level 0. Defined in
  [`incrementalmerkletree/src/lib.rs:185`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L185-L188).
- **PrunableTree**: a `Tree` with retention-flagged leaves and cached-root
  annotations. Defined in
  [`shardtree/src/prunable.rs:80`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/prunable.rs#L80-L80).
- **Retention / Marking**: leaf metadata controlling pruning. Defined in
  [`incrementalmerkletree/src/lib.rs:73`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L73-L107).
- **Shard**: a `LocatedPrunableTree` rooted at level `SHARD_HEIGHT`.
  Defined in
  [`shardtree/src/store.rs:33`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L33-L37).
- **Source (Past/Future)**: whether a witness sibling is an existing ommer
  or a not-yet-materialised node. Defined in
  [`incrementalmerkletree/src/lib.rs:144`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L144-L152).
- **TreeState**: a checkpoint's `Empty` or `AtPosition(p)` state. Defined
  in
  [`shardtree/src/store.rs:257`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/store.rs#L257-L265).
- **Witness**: the authentication path (siblings leaf-to-root) for a
  position. The verb sense ("maintain a witness") means keeping that path
  current as leaves are appended. Used throughout; computed by
  [`incrementalmerkletree/src/lib.rs:642`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L642-L656).

## 3. The code

The single most useful cross-reference is the module docstring that
defines the navigation vocabulary (parent, sibling, cousin, ommer,
ancestor) in one place:

```rust reference title="incrementalmerkletree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/incrementalmerkletree/src/lib.rs#L29-L44
```

## 4. Failure modes

- **Using "Merkle root" and "anchor" interchangeably in prose.** This
  workspace computes roots; downstream protocol code calls a committed
  root an "anchor". Keep "root" here. Caught by: review only.
- **Calling `zcashd` integration "legacy" vs "in maintenance".** Match
  upstream wording: the `legacy-api` feature is so named in code, but the
  `zcashd` daemon itself is "in maintenance". Caught by: review only.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf)
  Section 3.8 fixes the protocol-level terms (note commitment tree,
  anchor) that the downstream crates map these structural terms onto.

## 6. Exercises

1. **Answer from code.** Find every place the word "ommer" is used and
   note the two distinct senses (frontier left-sibling vs parent's
   sibling). Cite both module docstrings.
2. **Disambiguate.** For the term "checkpoint depth", write the one-
   sentence definition and cite the storage primitive that implements it.
3. **Extend the glossary (modify).** Add one missing term you encountered
   (for example `IncompleteAt` or `BatchInsertionResult`) with its
   defining file and line, matching the format above.

### Answers in the code

- Exercise 1: `incrementalmerkletree/src/lib.rs:38` (ommer = parent's
  sibling) and `frontier.rs:36` (ommer = stored left sibling);
  `bridgetree/src/lib.rs:31` notes its usage.
- Exercise 2: see `get_checkpoint_at_depth`
  (`shardtree/src/store.rs:96-116`).

## 7. Further reading

- Return to [Chapter 6](./06-retention-and-checkpointing.md) for the
  retention vocabulary in depth.
