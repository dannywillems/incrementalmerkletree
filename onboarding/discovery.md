# Discovery Notes

Ground-truth notes from the discovery phase. The chapter graph is derived
from these notes; do not invent topics not anchored here.

## Pin

- Upstream: `zcash/incrementalmerkletree`
- Fork hosting the course: `dannywillems/incrementalmerkletree`, branch
  `onboarding`
- Pinned commit (every source embed): `edf24f2b2e727776e290f292d831d4ac61c3e1bd`
  (HEAD of `origin/main` at generation time).
- Per-crate release tags (stable anchors):
  - `incrementalmerkletree-v0.8.2` -> `2e76b90d9a12b42b7aef22a1c8d5e15f90241e17`
  - `shardtree-v0.6.2` -> `879c7e6f0c55372b868b7d0df7e8c81714da3ef0`
  - `incrementalmerkletree-testing-v0.3.0` ->
    `44065917a399a921a2151bd14d399a192eb61960`
  - `bridgetree 0.7.0` -> no annotated tag; embeds use the pinned commit.

## Workspace layout

Cargo workspace (`resolver = "2"`), MSRV `1.64`, `rust-toolchain.toml`
pins channel `1.64.0` with `clippy` + `rustfmt`. `bridgetree` is
`exclude`d from the workspace (it depends on the published
`incrementalmerkletree 0.8`, not the path dependency).

Members:

- `incrementalmerkletree` (v0.8.2): core types. `no_std`. Modules:
  `lib.rs` (Level, Position, Address, Source, Hashable, MerklePath,
  Retention, Marking), `frontier.rs` (NonEmptyFrontier, Frontier,
  CommitmentTree), `witness.rs` (IncrementalWitness, legacy-api),
  `testing.rs`. Features: `std`, `legacy-api`, `test-dependencies`.
- `incrementalmerkletree-testing` (v0.3.0): the `Tree<H, C>` comparison
  trait, `CombinedTree`, `Operation`, proptest strategies,
  `complete_tree.rs` reference oracle.
- `shardtree` (v0.6.2): the sharded, prunable, checkpointed tree. Modules:
  `lib.rs` (ShardTree), `tree.rs` (Node, Tree, LocatedTree),
  `prunable.rs` (PrunableTree, RetentionFlags, LocatedPrunableTree),
  `store.rs` (ShardStore trait, Checkpoint, TreeState),
  `store/memory.rs`, `store/caching.rs`, `batch.rs`, `error.rs`,
  `legacy.rs`, `testing.rs`. Features: `legacy-api`, `test-dependencies`.
- `bridgetree` (v0.7.0): the append-only bridge-based tree. Single
  `lib.rs` (MerkleBridge, BridgeTree, Checkpoint).

## Public API entry points

- `incrementalmerkletree`: re-exports nothing at crate root beyond the
  primitive types; `frontier`, `witness`, `testing` are modules.
- `shardtree`: re-exports `ShardTree`, `LocatedTree`, `Node`, `Tree`,
  `PrunableTree`, `LocatedPrunableTree`, `RetentionFlags`,
  `IncompleteAt`, `BatchInsertionResult`; `error` and `store` modules.
- `bridgetree`: re-exports the `incrementalmerkletree` primitives plus
  its own `BridgeTree`, `MerkleBridge`.

## Test layout

- Unit tests inline (`#[cfg(test)] mod tests`) in every module.
- Property tests via `proptest` throughout.
- Cross-implementation differential testing: `CombinedTree` in
  `incrementalmerkletree-testing` runs an "inefficient" reference tree
  (`CompleteTree`) alongside an "efficient" tree (`BridgeTree`,
  `ShardTree`) and asserts identical observable behaviour.
- `shardtree` tests use `ShardTree<MemoryShardStore<_, usize>, 6, 3>`
  (DEPTH 6, SHARD_HEIGHT 3) as the canonical small instance.
- No `benches/` directory currently present; CI's `bitrot` job still
  runs `cargo build --workspace --benches --all-features` (a no-op when
  there are no benches, kept to catch future bitrot).

## CI graph (`.github/workflows/`)

- `ci.yml` (push + PR): `cargo test --all-features --workspace` on
  ubuntu/windows/macos, working-tree-clean check, `--benches` bitrot
  build, `cargo doc --workspace --document-private-items` (intra-doc
  links), `cargo fmt --all -- --check`.
- `lints-stable.yml` (PR): clippy MSRV `--all-features --all-targets --
  -D warnings`.
- `lints-beta.yml` (PR): clippy beta, `continue-on-error`.
- `audits.yml` (push to main + PR): `cargo vet --locked`, `cargo deny
  check licenses`, and a `required-audits` gate job.

## Release / versioning

- Each crate released independently; tags are `<crate>-vX.Y.Z`.
- Per-crate `CHANGELOG.md`, Keep a Changelog format. Changelog hygiene
  matters: the repo keeps a dedicated `Fixed`/`Added`/`Changed`
  structure (see commit `7c7ae94`).

## Recent activity (hot files, last 12 months)

`git log --since="12 months ago"`: 15 commits. Most-changed:

1. `shardtree/src/lib.rs` (7 touches) - the main contribution surface.
2. `shardtree/CHANGELOG.md` (5).
3. `shardtree/src/prunable.rs` (3).
4. supply-chain config, `deny.toml`, workspace `Cargo.toml` (1 each).

Recent substantive fixes (all in shardtree):

- `202fb2a` / `4d78d5b`: root_caching could corrupt the cap by splitting
  cap leaves into sub-shard `Parent` nodes (failing test then fix).
- `513972b` / `b0b3eb9`: Parent annotation fast-path ignored truncation
  in `root_internal`.
- `04b97bd`: distinguish empty tree vs incomplete tree in frontier
  generation; `fa2c7cd` / `59f660d`: `frontier()` extraction methods.

## Contribution gate

No `CONTRIBUTING.md`, `AGENTS.md`, or `CLAUDE.md`. `COPYING.md`
documents the dual MIT/Apache-2.0 license and an implicit DCO-style
inbound=outbound contribution clause (Apache-2.0 section 5). No
issue-required gate, no sign-off bot. The de-facto gate is CI:
`cargo test --all-features`, `cargo fmt --check`, clippy MSRV with
`-D warnings`, and `cargo vet` + `cargo deny`.

## External references

- Zcash Protocol Specification:
  <https://zips.z.cash/protocol/protocol.pdf> (note commitment trees,
  Sapling/Orchard incremental Merkle trees). The crate is hash-function
  agnostic (the `Hashable` trait), so the spec is background, not a
  line-by-line authority over this code.
