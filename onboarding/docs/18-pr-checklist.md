---
sidebar_position: 18
title: "PR Checklist"
description: "The pre-push checklist for a pull request to the incrementalmerkletree workspace, derived from the CI gate and the repo's conventions."
---

# PR Checklist

## 1. Why this chapter exists

There is no `CONTRIBUTING.md` in this repository, so the PR rules live
only in the CI YAML and the commit history. This page makes them explicit
so your PR passes the gate on the first try
([Chapter 2](./02-build-test-contribute.md) explains each item).

## 2. Definitions

**Definition 18.1 (the gate).** A PR must pass, on the trial-merge:
multi-OS `cargo test --all-features --workspace` with a clean working
tree, `cargo fmt --all -- --check`, MSRV
`cargo clippy --all-features --all-targets -- -D warnings`,
`cargo doc --workspace --document-private-items`, and the `cargo vet` +
`cargo deny` audits. There is no issue-required or sign-off bot; the
inbound license is dual MIT/Apache-2.0 per `COPYING.md`.

## 3. The checklist

Before you push:

- [ ] `cargo fmt --all` (then confirm `--check` is clean).
- [ ] `cargo clippy --all-features --all-targets -- -D warnings` is clean.
- [ ] `cargo test --all-features --workspace` passes.
- [ ] `cargo test -p bridgetree --all-features` passes (it is outside the
      workspace).
- [ ] `cargo doc --workspace --document-private-items` passes (intra-doc
      links resolve).
- [ ] If you added a dependency: a `supply-chain/audits.toml` entry and a
      license allowed by `deny.toml`; `cargo vet --locked` and
      `cargo deny check licenses` pass.
- [ ] A new or updated test accompanies any behaviour change, preferably
      added as a failing test in its own commit before the fix (the
      `4d78d5b` then `202fb2a` shape).
- [ ] A `CHANGELOG.md` entry under the affected crate's `## Unreleased`,
      in its own dedicated commit (the `7c7ae94` convention).
- [ ] The working tree is clean after running the tests
      (`git diff --exit-code`).
- [ ] PR scope is one invariant and its test; large PRs get split.

## 4. Failure modes

- **Skipping `bridgetree`.** `--workspace` does not include it; a change to
  the core that breaks `bridgetree` passes your local `--workspace` run but
  fails its own CI. Caught by: the `bridgetree` test job.
- **Changelog and code in one commit.** The repo keeps changelog entries
  in dedicated commits. Caught by: review/convention.
- **Clippy clean on stable but not MSRV.** Run clippy under the pinned
  1.64 toolchain. Caught by: `lints-stable.yml`.

## 5. Spec pointers

- `COPYING.md` (inbound=outbound dual license) and the workflows in
  `.github/workflows/` are the authoritative rules. Cited because they are
  the only written contribution policy in the repo.

## 6. Exercises

1. **Answer from code.** Which two audit tools must pass, and which file
   configures each? Cite `audits.yml`.
2. **Dry-run the gate.** On a trivial no-op change, run every command in
   the checklist and confirm all pass.
3. **Add a changelog entry (modify).** For a hypothetical added test,
   write the `## Unreleased` entry under `shardtree/CHANGELOG.md` in the
   Keep a Changelog format, in a separate commit from the test. Confirm
   the formatting matches the existing 0.6.2 entry.

### Answers in the code

- Exercise 1: `cargo vet` (`supply-chain/`) and `cargo deny`
  (`deny.toml`), both in
  [`.github/workflows/audits.yml`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/audits.yml).

## 7. Further reading

- [Local Dev Cheat Sheet](./17-local-dev-cheat-sheet.md) for the exact
  commands; [Glossary](./19-glossary.md) for the terms a PR description
  should use consistently.
