---
sidebar_position: 16
title: "Study Plan"
description: "A week-by-week reading and exercise plan that converges on a real, mergeable pull request to the incrementalmerkletree workspace."
---

# Study Plan

## 1. Why this chapter exists

This chapter sequences the course into a one-to-two week plan that ends
with you opening a small, correct PR. It also names the hot files where
contributions land and the concrete shapes a first PR can take. The
ordering follows the dependency graph: you cannot understand `shardtree`
operations before frontiers, and you cannot test a change before the
harness chapter.

## 2. Definitions

**Definition 16.1 (hot files).** From the last 12 months of history, the
files contributions actually touch, with the usual reason:

| File | Touches | What contributors change |
| --- | --- | --- |
| `shardtree/src/lib.rs` | 7 | Witness/checkpoint/cap-caching edge cases |
| `shardtree/CHANGELOG.md` | 5 | The entry for the above (dedicated commit) |
| `shardtree/src/prunable.rs` | 3 | Pruning, merge, frontier extraction |
| `supply-chain/*`, `deny.toml` | 1 each | Dependency/audit updates |

**Definition 16.2 (a good first PR).** A small, self-contained change with
a test, in the failing-test-first shape the maintainers use (see
`4d78d5b` then `202fb2a`). Candidates: an added test vector, a clarified
doc comment with a corrected invariant, a new differential `Operation`
that exercises an untested path, or a focused edge-case fix.

## 3. The plan

### Week 1: the core and the simple trees

- **Day 1.** [Overview](./index.md), [Chapter 1](./01-workspace-map.md),
  [Chapter 2](./02-build-test-contribute.md). Run the full local pre-push
  sequence; get a green `cargo test --all-features --workspace`.
- **Day 2.** [Chapter 3](./03-tree-navigation.md). Do every exercise; the
  addressing arithmetic underpins everything.
- **Day 3.** [Chapter 4](./04-hashing-and-merklepath.md) and
  [Chapter 5](./05-frontiers.md). Trace the append carry by hand.
- **Day 4.** [Chapter 6](./06-retention-and-checkpointing.md),
  [Chapter 7](./07-incremental-witness.md).
- **Day 5.** [Chapter 8](./08-bridgetree.md). Implement the differential
  test exercise; this is your first contact with the harness.

### Week 2: the production tree and a contribution

- **Day 6.** [Chapter 9](./09-shardtree-structure.md),
  [Chapter 10](./10-prunable-tree.md).
- **Day 7.** [Chapter 11](./11-shardtree-operations.md). Reproduce the
  cap-corruption bug (Exercise 3) by checking out `4d78d5b~1`.
- **Day 8.** [Chapter 12](./12-shard-stores.md),
  [Chapter 13](./13-batch-insertion.md).
- **Day 9.** [Chapter 14](./14-testing-framework.md),
  [Chapter 15](./15-failure-modes-and-audits.md). Run a 1000-case
  differential proptest.
- **Day 10.** Open a PR. Pick from Definition 16.2; follow the
  [PR Checklist](./18-pr-checklist.md).

## 4. Failure modes

- **Skipping the harness chapter before contributing.** A change without a
  differential test will be asked for one in review. Read
  [Chapter 14](./14-testing-framework.md) before you write code. Caught
  by: review, not CI.
- **A PR that mixes a code change and a changelog edit in one commit.**
  The workspace keeps changelog entries in dedicated commits (see
  `7c7ae94`). Caught by: review/convention; not enforced by a bot here.
- **A PR too large to review.** Keep it to one invariant and its test.
  Caught by: review.

## 5. Spec pointers

- [Zcash Protocol Specification](https://zips.z.cash/protocol/protocol.pdf),
  Section 3.8: read once for context on why this data structure exists, so
  your PR description can connect the change to the wallet requirement it
  serves.

## 6. Exercises

1. **Pick a target (answer from code).** Run
   `gh issue list --repo zcash/incrementalmerkletree --state open` and
   `gh pr list --repo zcash/incrementalmerkletree --state merged --limit 10`.
   Identify one merged PR whose shape (test + small fix) you could
   replicate, and name the file it touched.
2. **Write a failing test first (modify).** Choose one untested edge case
   from the failure-modes sections of Chapters 10-13, add a test that
   fails (or would fail under the old behaviour), and confirm it passes
   against current `main`. This is a candidate PR.
3. **Draft the PR (modify).** Create a branch, add your test, write a
   changelog entry in a dedicated commit under the right crate's
   `## Unreleased`, and run the full pre-push sequence from
   [Chapter 2](./02-build-test-contribute.md).

### Answers in the code

- Exercise 1: recent merged PRs are visible in `git log --merges`; e.g.
  `#139` (prunable tree frontier), `#140` (cap corruption fix).
- Exercise 2 and 3: use the [PR Checklist](./18-pr-checklist.md).

## 7. Further reading

- The [Local Dev Cheat Sheet](./17-local-dev-cheat-sheet.md),
  [PR Checklist](./18-pr-checklist.md), and [Glossary](./19-glossary.md)
  are the pages you will keep open while working.
