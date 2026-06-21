---
sidebar_position: 2
title: "Build, Test, and the Contribution Loop"
description: "Toolchain setup, the exact CI commands, the de-facto PR gate, hot files, and what a good first contribution looks like."
---

# Build, Test, and the Contribution Loop

## 1. Why this chapter exists

This chapter unlocks contribution. It maps the CI graph to commands you
run locally, so that "green on my machine" means "green in CI". It also
states the de-facto PR gate, because there is no `CONTRIBUTING.md` to read
and the rules are encoded only in the workflow YAML. Get this wrong and
your PR bounces on a clippy warning or a `cargo fmt` diff before a human
ever reads it. You will run these commands daily; the same list is
mirrored in the runnable, shellcheck-clean script
[`onboarding/scripts/dev-loop.sh`](https://github.com/dannywillems/incrementalmerkletree/blob/onboarding/onboarding/scripts/dev-loop.sh).

## 2. Definitions

**Definition 2.1 (the PR gate).** There is no `CONTRIBUTING.md`,
`AGENTS.md`, or bot-enforced issue/sign-off requirement in this
repository. `COPYING.md` states the inbound=outbound dual-license rule
(MIT OR Apache-2.0) verbatim:

> Unless you explicitly state otherwise, any contribution intentionally
> submitted for inclusion in the work by you, as defined in the
> Apache-2.0 license, shall be dual licensed as above, without any
> additional terms or conditions.

The gate that actually blocks merges is the set of **required status
checks** in CI. A PR must pass, on the trial-merge:

1. `cargo test --all-features --workspace` on Linux, Windows, and macOS,
   **and** leave the working tree clean (`git diff --exit-code`).
2. `cargo fmt --all -- --check` (toolchain-pinned rustfmt).
3. `cargo clippy --all-features --all-targets -- -D warnings` at the MSRV
   toolchain (Clippy warnings are hard errors).
4. `cargo doc --workspace --document-private-items` (intra-doc links).
5. `cargo vet --locked` and `cargo deny check licenses` (on PRs and pushes
   to `main`).

**Definition 2.2 (MSRV and toolchain).** The Minimum Supported Rust
Version is `1.64`, pinned by `rust-toolchain.toml` so that the right
toolchain installs automatically. Clippy runs at this version, so an idiom
that needs a newer Rust will fail the lint gate even if it compiles for
you on stable.

```toml reference title="rust-toolchain.toml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/rust-toolchain.toml#L1-L4
```

## 3. The code: CI mapped to local commands

### 3.1 The `ci.yml` jobs

```yaml reference title=".github/workflows/ci.yml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/ci.yml#L1-L52
```

The four jobs map one-to-one to local commands:

| CI job | Local command |
| --- | --- |
| `test` | `cargo test --all-features --verbose --workspace` |
| `bitrot` | `cargo build --workspace --benches --all-features` |
| `doc-links` | `cargo doc --workspace --document-private-items` |
| `fmt` | `cargo fmt --all -- --check` |

The `test` job also runs `git diff --exit-code`. Several tests assert the
working tree is unchanged (no stray generated files); if your change
writes a file during tests, that job fails.

### 3.2 The clippy gate

```yaml reference title=".github/workflows/lints-stable.yml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/lints-stable.yml#L1-L19
```

Run it locally exactly as CI does:

```bash
cargo clippy --all-features --all-targets -- -D warnings
```

`lints-beta.yml` runs the same on beta with `continue-on-error: true`; it
is informational and does not block merges.

### 3.3 The supply-chain gate

```yaml reference title=".github/workflows/audits.yml"
https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/audits.yml#L1-L60
```

`cargo vet` checks that every dependency has an audit or trust entry in
`supply-chain/`; `cargo deny check licenses` enforces the allowlist in
`deny.toml` (only MIT and Apache-2.0, with one Unicode exception). Adding
a dependency means adding a `supply-chain` entry and possibly a license
exception. See [Chapter 15](./15-failure-modes-and-audits.md).

### 3.4 The full local pre-push sequence

```bash
cargo fmt --all
cargo clippy --all-features --all-targets -- -D warnings
cargo test --all-features --workspace
cargo doc --workspace --document-private-items
```

A focused single-test run during development:

```bash
cargo test -p shardtree root_caching        # substring filter
cargo test -p incrementalmerkletree --all-features
```

## 4. Failure modes

- **Formatting with a non-pinned rustfmt.** Running a nightly `cargo fmt`
  can produce output the 1.64 rustfmt rejects, and vice versa. Always let
  `rust-toolchain.toml` select the toolchain (do not `cargo +nightly
  fmt`). Caught by: the `fmt` CI job.
- **Clippy passes on stable, fails on MSRV.** The gate runs at 1.64. A
  lint or a language feature available only on a newer compiler slips
  past your local stable run. Caught by: `lints-stable.yml` (named
  "Clippy (MSRV)").
- **Forgetting `--all-features`.** The `legacy-api` and
  `test-dependencies` code only compiles under those features; a change
  that breaks them is invisible to a bare `cargo test`. Caught by: the
  `test` job, which always passes `--all-features`.
- **Adding a dependency without a supply-chain entry.** `cargo vet
  --locked` fails closed. Caught by: the `cargo-vet` job in `audits.yml`.

## 5. Spec pointers

- [`cargo vet` documentation](https://mozilla.github.io/cargo-vet/):
  explains the `supply-chain/audits.toml`, `config.toml`, and
  `imports.lock` files. Cited because the `audits.yml` job will reject
  PRs that add un-vetted dependencies and you need to know how to add an
  entry.
- [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/): the
  format every `CHANGELOG.md` in the workspace follows. Cited because a
  user-facing change should add a changelog entry under `## Unreleased`.

## 6. Exercises

1. **Reproduce CI locally.** Run the four-command pre-push sequence from
   3.4 on a clean checkout. All four must pass with zero output changes.
   Confirm `git diff --exit-code` is clean afterwards.
2. **Break and observe (modify).** Introduce an unused variable in
   `incrementalmerkletree/src/frontier.rs`, run the clippy gate command,
   and read the exact error. Revert. This is the failure your PR would
   show in `lints-stable`.
3. **Trace a real fix.** Run `git show 4d78d5b --stat` and
   `git show 202fb2a --stat`. Identify which file the failing test was
   added to and which file the fix changed. This pair (failing test
   first, fix second) is the contribution shape this repo prefers; the
   `nuttycom/cap_corruption` branch was merged this way (`bfe5cc5`).

### Answers in the code

- Exercise 2: clippy reports `unused_variable` as a denied warning
  because of `-D warnings`.
- Exercise 3: the failing test landed in `shardtree/src/lib.rs`
  (`4d78d5b`); the fix is `202fb2a`, also in `shardtree/src/lib.rs`.

## 7. Further reading

- The hot-files list and a concrete "good first PR" template are in
  [Chapter 16: Study Plan](./16-study-plan.md) and the
  [PR Checklist](./18-pr-checklist.md). The most-changed file over the
  last year is `shardtree/src/lib.rs`; new contributors most often touch
  it to fix a witness/checkpoint edge case or add a test vector.
