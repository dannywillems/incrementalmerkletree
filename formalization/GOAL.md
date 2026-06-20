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

- **Ommer characterization** (blocks P2.3): the frontier's ommers are the
  complete-left-subtree roots of the represented leaves. With this,
  P2.3 = ommer characterization, then `root_eq_spineFrom` +
  `merkleRoot_eq_spineFrom` (both already proved).
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
