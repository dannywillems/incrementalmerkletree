---
sidebar_position: 17
title: "Local Dev Cheat Sheet"
description: "Every command a contributor to the incrementalmerkletree workspace needs: clone, toolchain, test, lint, format, doc, and audit."
---

# Local Dev Cheat Sheet

## 1. Why this chapter exists

One page with every command, so you do not have to reconstruct the CI
invocations from YAML. Each command here is the local equivalent of a CI
job ([Chapter 2](./02-build-test-contribute.md)) and matches the runnable
script
[`onboarding/scripts/dev-loop.sh`](https://github.com/dannywillems/incrementalmerkletree/blob/onboarding/onboarding/scripts/dev-loop.sh).

## 2. Definitions

**Definition 17.1 (the command set).** The commands below cover clone,
toolchain, the four CI test/lint/doc/format jobs, focused testing, and the
supply-chain gate.

## 3. The code

### Clone and toolchain

```bash
git clone https://github.com/zcash/incrementalmerkletree.git
cd incrementalmerkletree
# rust-toolchain.toml pins 1.64.0 with clippy + rustfmt; cargo installs it.
rustup show
```

### The full pre-push sequence

```bash
cargo fmt --all                                         # format
cargo clippy --all-features --all-targets -- -D warnings # lint (MSRV gate)
cargo test --all-features --verbose --workspace          # tests, all crates
cargo doc --workspace --document-private-items           # intra-doc links
```

### Focused testing

```bash
cargo test -p shardtree root_caching          # one test by substring
cargo test -p incrementalmerkletree --all-features
cargo test --doc -p incrementalmerkletree --all-features  # doctests only
PROPTEST_CASES=1000 cargo test -p shardtree   # heavier proptest run
```

### Supply-chain gate

```bash
cargo install cargo-vet --version '~0.10'
cargo vet --locked
cargo deny check licenses
```

### Note on `bridgetree`

`bridgetree` is excluded from the workspace, so `--workspace` does not
build it. Test it explicitly:

```bash
cargo test -p bridgetree --all-features
```

## 4. Failure modes

- **`cargo fmt` with the wrong toolchain.** Let `rust-toolchain.toml`
  select it; do not pass `+nightly`. Caught by: the `fmt` CI job.
- **Bare `cargo test` hiding feature-gated breakage.** Always pass
  `--all-features`. Caught by: the `test` CI job.
- **`--workspace` silently skipping `bridgetree`.** Run it with `-p
  bridgetree`. Caught by: nothing; remember it.

## 5. Spec pointers

- The exact CI definitions:
  [`.github/workflows/ci.yml`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/ci.yml),
  [`lints-stable.yml`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/lints-stable.yml),
  [`audits.yml`](https://github.com/zcash/incrementalmerkletree/blob/edf24f2b2e727776e290f292d831d4ac61c3e1bd/.github/workflows/audits.yml).
  Cited because the local commands must match these to predict CI.

## 6. Exercises

1. **Answer from code.** Which CI job runs `git diff --exit-code`, and
   what failure does it catch? Cite `ci.yml`.
2. **Reproduce green CI.** Run the full pre-push sequence on a clean
   checkout; all four commands pass and the working tree stays clean.
3. **Time a heavy run (modify).** Run
   `PROPTEST_CASES=2000 cargo test -p shardtree` and note the slowest
   test. Add a one-line note to your own dev notes recording it; this is
   the test you will wait on most while iterating.

### Answers in the code

- Exercise 1: the `test` job
  (`.github/workflows/ci.yml:20-21`); it catches tests that leave stray
  files in the working tree.

## 7. Further reading

- [PR Checklist](./18-pr-checklist.md) is the gate to run before pushing.
