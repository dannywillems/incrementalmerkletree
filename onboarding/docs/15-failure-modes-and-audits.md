---
sidebar_position: 15
title: "Failure Modes and Audits"
description: "A map of real regressions in this workspace to the tests that catch them, plus the cargo-vet and cargo-deny supply-chain gate."
---

# Failure Modes and Audits

## 1. Why this chapter exists

This is the map from "regression" to "the test command that catches it"
and "the gate that blocks a bad dependency". Every entry below is a real
event in the repository's history (traceable by commit) or a real CI gate,
not a hypothetical. Read it before changing `shardtree/src/lib.rs` or
adding any dependency. The supply-chain config is in `supply-chain/` and
`deny.toml`.

## 2. Definitions

**Definition 15.1 (the regression map).** Each row: the invariant, the
commit that introduced the failing test, the commit that fixed it, and the
file. All are in `shardtree`, the only crate with active churn.

| Invariant broken | Failing test | Fix | File |
| --- | --- | --- | --- |
| Cap holds only shard-root leaves (no sub-shard `Parent`) | `4d78d5b` | `202fb2a` | `shardtree/src/lib.rs` |
| Parent annotation fast-path respects truncation | `b0b3eb9` | `513972b` | `shardtree/src/lib.rs` |
| Empty tree distinguished from incomplete tree in frontier gen | (in `04b97bd`) | `04b97bd` | `shardtree/src/prunable.rs` |

**Definition 15.2 (the supply-chain gate).** Two tools run in
`audits.yml`:

- `cargo vet --locked`: every dependency must have an audit or a
  `trusted` entry in `supply-chain/audits.toml`. The three workspace
  crates are trusted to crate author `nuttycom`.
- `cargo deny check licenses`: dependency licenses must be in the
  `deny.toml` allowlist (`Apache-2.0`, `MIT`, plus a `Unicode-DFS-2016`
  exception for `unicode-ident`).

```toml reference title="supply-chain/audits.toml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/supply-chain/audits.toml#L1-L22
```

```toml reference title="deny.toml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/deny.toml#L1-L31
```

## 3. The code: the cap-corruption bug

The most instructive bug. `root_caching` could, while writing computed
roots back into the cap, split a cap leaf (a shard root) into `Parent`
nodes spanning sub-shard positions, violating Invariant 9.3 at the cap
level. The fix asserts the cap contains only shard-root leaves. The
failing test was committed first (`4d78d5b`), the fix second (`202fb2a`),
both merged via `bfe5cc5`. This failing-test-first shape is the
contribution pattern the maintainers prefer.

```rust reference title="shardtree/src/lib.rs"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/src/lib.rs#L782-L800
```

The truncation bug (`b0b3eb9`/`513972b`) is in the same method family: a
`Parent` annotation cached a root that ignored a later `truncate_at`,
returning a root for leaves that should have been treated as empty.

The `shardtree` changelog records both fixes under 0.6.2:

```text reference title="shardtree/CHANGELOG.md"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/shardtree/CHANGELOG.md#L10-L21
```

## 4. Failure modes

Every bullet ends with the test (or "audit only") that catches it.

- **Cap corruption by sub-shard parents.** Caught by: the regression test
  added in `4d78d5b` in `shardtree/src/lib.rs`; run
  `cargo test -p shardtree`.
- **Cached root ignoring truncation.** Caught by: the regression test
  added in `b0b3eb9` in `shardtree/src/lib.rs`.
- **Incorrect node annotations stored in rare circumstances.** Caught by:
  the differential `check_operations` proptests (the 0.6.2 changelog
  "incorrect node annotations" fix).
- **Adding an un-vetted dependency.** Caught by: `cargo vet --locked` in
  `audits.yml`.
- **Adding a dependency with a disallowed license.** Caught by:
  `cargo deny check licenses`.
- **A new advisory (RUSTSEC) against a dependency.** Not configured here:
  `deny.toml` checks licenses only, not advisories. Caught by: no
  automated test in this workspace; caught by audit/manual review only.

## 5. Spec pointers

- [`cargo vet` book](https://mozilla.github.io/cargo-vet/): the
  `audits.toml`/`config.toml`/`imports.lock` format and how to add an
  audit. Cited because a PR that adds a dependency must add a
  `supply-chain` entry or the gate fails.
- [`cargo deny` book](https://embarkstudios.github.io/cargo-deny/):
  the `[licenses]` allowlist semantics in `deny.toml`. Cited because a new
  dependency's license must be in the allowlist or get an exception.

## 6. Exercises

1. **Answer from code.** Which crate licenses are allowed by `deny.toml`,
   and what single exception exists? Cite the `[licenses]` block.
2. **Reproduce a regression.** Check out `4d78d5b~1`, run
   `cargo test -p shardtree`, and confirm the cap-corruption test is
   absent or failing; then check out `202fb2a` and confirm it passes.
   Record the exact test name.
3. **Add a dependency end-to-end (modify).** Add a trivial dependency
   (for example `hex = "0.4"`) to `shardtree/Cargo.toml`, run
   `cargo deny check licenses` and `cargo vet --locked`, observe which
   gate fails and why, then revert. Write one paragraph on what a
   `supply-chain` entry would need to contain to satisfy `cargo vet`.

### Answers in the code

- Exercise 1: `Apache-2.0` and `MIT`, with a `Unicode-DFS-2016` exception
  for `unicode-ident` (`deny.toml:18-26`).
- Exercise 2: the test lives in `shardtree/src/lib.rs`; the fix is
  `202fb2a`.
- Exercise 3: `cargo vet` will fail until `hex` has an audit or trust
  entry in `supply-chain/audits.toml`.

## 7. Further reading

- [Chapter 16: Study Plan](./16-study-plan.md) turns this map into a
  concrete first contribution.
