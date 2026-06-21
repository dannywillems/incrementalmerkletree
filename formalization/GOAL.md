# Formalization goal and blueprint

This is the anchor for the Lean 4 formalization. Read it before each work
session, restate the current target, and work TOP-DOWN from it. Do not add a
lemma unless the current proof of a target needs it (demand-driven). Measure
progress by "is a target theorem proved", not by lemma count. See PLAN.md for
the full property catalog.

## Definition of done

Each layer is "done" when its root-correctness theorem is proved with no
`sorry`, on both CI tracks:

- the representation's `root` equals `merkleRoot` of the leaves it represents;
- the produced witnesses verify against that root;
- the structural invariants are preserved by every operation.

## Ranked targets (work these in order)

1. **P2.3 (centerpiece)**: `(NonEmptyFrontier.ofList v0 vs).root depth
   = merkleRoot depth (v0 :: vs)` (and the `Frontier` wrapper form), for
   `(v0 :: vs).length <= 2 ^ depth`.
2. **P2.1**: `append` preserves well-formedness, hence `ofList` is well-formed.
3. **P3 (witness)**, **P4 (bridgetree)**, **P5 (shardtree)** root/witness
   theorems.

## The open leaves blocking target 1 and 2 (the only things worth proving next)

- **Ommer characterization / tight-level case** (blocks P2.3): the frontier's
  ommers are the complete-left-subtree roots of the represented leaves. The
  depth-padding half is DONE (`root_merkleRoot_lift` + `getLsbD_eq_false_of_lt`),
  so P2.3 reduces to the tight-level obligation
  `(ofList v0 vs).root k = merkleRoot k (v0 :: vs)`.

  ALL level-step infrastructure is now in place (committed, no sorry):
  - fold state: `rootState`, `rootState_zero`, `rootState_succ`,
    `root_eq_rootState_fst`, `root_succ_split`, `root_succ_of_clear`.
  - merkleRoot step: `merkleRoot_succ`, `merkleRoot_succ_of_le`.
  - index arithmetic: `baseIndex` (+ `_zero`/`_succ`/`_le`/`_add_pow`),
    `mod_two_pow_succ`, `ite_getLsbD_eq_div_mod`,
    `length_drop_baseIndex(_le)`.

  REMAINING (the final assembly, two inductions):
  - (B) Joint invariant by induction on the level `j`:
    `rootState f j = (merkleRoot j (L.drop (baseIndex (n-1) j)), OMM j)` where
    `OMM j` is the remaining left-sibling roots for set bits >= j. Clear-bit
    step uses `merkleRoot_succ_of_le` + `root_succ_of_clear`; set-bit step uses
    `merkleRoot_succ` + `rootState_succ` + `baseIndex_add_pow`, and needs the
    consumed ommer value (from A). At the tight level `OMM = []` and the .1 is
    `merkleRoot k L`, giving the tight obligation.
  - (A) Ommer-value characterization: `(ofList v0 vs).ommers = OMM 0` (the
    left-sibling roots), by induction on `vs` via `ofList_append`/the carry.
    This supplies the consumed-ommer values that (B)'s set-bit step needs.
- **Carry-popcount** (blocks P2.1 odd case): `carryRun a 0 ommers
  = trailingOnes a` (under the WF length bound) and `popcount (a+1)
  = popcount a + 1 - trailingOnes a` (with `a + 1 != 0`, the wraparound
  hypothesis recorded in PLAN.md section 7). The supporting theory
  (`appendCarry_length`, `carryRun_*`, `trailingOnes_*`, the popcount/testBit
  bridge, inclusion-exclusion, monotonicity) is all in place.

## Discipline (why this file exists)

This formalization once accumulated ~135 supporting lemmas while the centerpiece
P2.3 stayed open, because work proceeded bottom-up under a "produce more lemmas"
instruction. The rule now: top-down, demand-driven, and every declaration's
docstring states which target it serves. A lemma that cannot be tied to a target
above should not be added.
