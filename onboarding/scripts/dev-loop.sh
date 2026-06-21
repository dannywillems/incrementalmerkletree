#!/usr/bin/env bash
#
# dev-loop.sh - the local commands a contributor to
# zcash/incrementalmerkletree runs day to day. Each labelled block below is
# imported into the course via `bash reference` fenced blocks, so the chapter
# text and this runnable script cannot drift.
#
# This script is a reference, not an orchestrator: run the individual blocks,
# do not execute the whole file.
set -euo pipefail

# --- clone ---
git clone https://github.com/zcash/incrementalmerkletree.git
cd incrementalmerkletree
# --- end clone ---

# --- toolchain ---
# rust-toolchain.toml pins channel 1.64.0 with clippy + rustfmt, so rustup
# installs the right toolchain automatically on first cargo invocation.
rustup show
# --- end toolchain ---

# --- test-all ---
# The exact command CI runs on every push and PR.
cargo test --all-features --verbose --workspace
# --- end test-all ---

# --- test-focused ---
# Run a single test by path filter (substring match on the test name).
cargo test -p shardtree root_caching
# Run one crate's tests only.
cargo test -p incrementalmerkletree --all-features
# --- end test-focused ---

# --- test-doc ---
# Doctests are part of the suite; the witness.rs example is a real doctest.
cargo test --doc -p incrementalmerkletree --all-features
# --- end test-doc ---

# --- fmt ---
# CI fails on any diff. rustfmt is pinned via the 1.64.0 toolchain.
cargo fmt --all -- --check   # check only
cargo fmt --all              # apply
# --- end fmt ---

# --- clippy ---
# The MSRV clippy gate: identical to lints-stable.yml.
cargo clippy --all-features --all-targets -- -D warnings
# --- end clippy ---

# --- doc-links ---
# Intra-doc link check; mirrors the doc-links CI job.
cargo doc --workspace --document-private-items
# --- end doc-links ---

# --- audits ---
# Supply-chain gate; mirrors audits.yml. Requires the tools installed.
cargo install cargo-vet --version '~0.10'
cargo vet --locked
cargo deny check licenses
# --- end audits ---
