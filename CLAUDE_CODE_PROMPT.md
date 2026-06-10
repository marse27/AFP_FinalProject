# Claude Code brief — AFP ownership type system (target grade 10, group of 2)

> **How to use this file.** Paste the whole thing into Claude Code as your first
> message inside the project repo (the unzipped `afp-emdumitrache-main`). Then drive
> it stage by stage: after each stage Claude Code stops and shows a summary, you
> test and reply `accept` (or give feedback), and only then say `continue` to the
> next stage. You can also keep this file in the repo as `CLAUDE.md` so it stays
> in context.

---

## 0. Read this first (context)

You are helping implement the final project for *Advanced Functional Programming
(CS4565, TU Delft)*: a **type checker + interpreter in Haskell for a small
Rust-like language with an ownership type system**. We work in a **group of 2**
and want **grade 10 + the full bonus**, so we implement **every phase and
feature**, all four required techniques, "advanced usage" of at least one
technique, and comprehensive documentation.

The repo already contains a working template: a BNFC grammar
(`grammar/Lang.cf`), a type checker (`src/TypeCheck/*`), an interpreter
(`src/Interp/*`), a tiny env (`src/Env.hs`), an `Either String` error monad
(`src/Evaluator.hs`), and an Hspec/QuickCheck test suite (`test/*`). Build/run
with `make build`, `make run FILE=...`, `make test` (the Makefile regenerates
the grammar with BNFC). We are free to redesign the syntax and replace any part
of the template.

The full phase spec lives in `2-ownership-type-system.md`, the grading rules in
`Project_rubric.md`, the deliverables in `README.md`. **Treat those three files
as the source of truth**; this brief just sequences the work.

---

## 1. Operating rules (follow these the whole way)

1. **One stage at a time, then stop.** Do exactly one numbered stage, make sure
   `make build` and `make test` are green, then **stop and wait** for me to test
   and say `continue`. Never start the next stage on your own.
2. **Every feature gets positive *and* negative tests** (the rubric requires
   this even for a 6). For the type checker, also add at least one test per
   feature that checks the *error message text*, not just accept/reject.
3. **Keep it as simple as possible** while keeping the required functionality.
   No speculative abstraction, no features we didn't ask for. If a simpler
   design satisfies the spec, choose it.
4. **Comments are short.** One `-- |` line per top-level function saying what it
   does, and a one-paragraph header comment per module saying the module's
   purpose. Nothing more verbose than that.
5. **Error messages use `prettyTree`/`printTree` from `Lang.Print`**, never
   `show`, when printing program fragments (README recommendation).
6. **Don't break the build flags.** The project uses `-Werror` and
   `-Werror=incomplete-patterns`; keep it warning-clean and pattern-complete.
7. **Regenerate the grammar** after editing `Lang.cf` (use `make build`, which
   runs BNFC first). If you add Cabal dependencies, update `AFPLang.cabal`.
8. **Maintain two living docs as you go** (create them in stage 0):
   - `DESIGN.md` — the architecture/design overview that is itself a deliverable
     (syntax description, feature overview, 2–3 example programs, and an
     explanation of how each required technique is used).
   - `RUBRIC_MAP.md` — a checklist mapping every rubric item and every phase
     feature to the module(s) and test(s) that satisfy it. Update it at the end
     of every stage. This doubles as our demo cheat-sheet.
9. **Surface big design forks.** If a choice would materially change the
   language design (syntax, type system semantics), implement the simplest
   reasonable option, but call it out in the stage summary and ask before
   building further on top of it.
10. **End-of-stage summary format.** After each stage, output a short summary:
    *what was implemented*, *which files changed*, *which rubric items / phase
    features / required techniques it advances*, *the new tests added*, and
    *exact commands + example programs I should run to accept it*. Keep it tight.

---

## 2. The four required techniques (where each lives)

These must each be used at least once; for grade 9 at least one must reach
"advanced usage". We pre-assign them so they're woven in deliberately, not
bolted on:

- **Persistent purely-functional data structure** → a **persistent scope /
  ownership stack** (an immutable stack of scope frames) threaded through the
  whole type checker for scoping, ownership and borrow state. Used in every
  phase ⇒ this is our primary *advanced-usage* candidate ("a new data structure
  used persistently throughout the type checker, not just in one place").
- **Lenses and/or traversals** → van Laarhoven lenses over the typing/runtime
  context record (env, ownership table, borrow table, logger handle) for clean
  nested get/update; plus a **traversal that drives a real transformation** in
  the checker (the non-lexical-lifetime last-use pass in stage 11) — a second
  advanced-usage candidate. Prefer `microlens` + `microlens-mtl` (light) or
  hand-rolled lenses; avoid the heavy full `lens` unless you have a reason.
- **Monad transformers and/or free monads** → replace `Either String` with our
  own checker monad `Tc` and interpreter monad `Eval`, built from a transformer
  stack (`ExceptT` for errors + `StateT` for the context + a logging effect).
  *Advanced-usage candidate:* define **one custom effect/transformer with its
  own handler** (e.g. a `Log` effect, or a `Fresh` supply for lifetime
  variables) and use it throughout — not just gluing library transformers.
- **Concurrency** (group-of-2 requirement) → a **concurrent logging subsystem**:
  a background logger thread that drains a channel of log messages from the
  checker/interpreter (stage 5). The phase-4B multithreading feature (stage 13)
  is a *second, user-facing* use of concurrency.

We will deliberately land **at least two** advanced-usage instances (persistent
ownership stack used throughout + a custom effect/handler + the NLL traversal)
so the grade-9 requirement is comfortably met.

---

## 3. The staged plan

Each stage lists: **Goal**, **Implement**, **Satisfies** (rubric/phase/
technique), **Accept** (how I test it). Stop after every stage.

> Grade milestones are marked **[→ grade N reachable]** so we always know where
> we stand.

### Stage 0 — Toolchain & baseline
- **Goal:** prove the environment works before touching anything.
- **Implement:** nothing functional. Run `make build` and `make test` on the
  untouched template and confirm green. Create empty `DESIGN.md` and
  `RUBRIC_MAP.md` skeletons (headings only). Note the GHC/Cabal/BNFC versions.
- **Satisfies:** sets up the deliverable docs.
- **Accept:** `make build` and `make test` are green; the two doc files exist.

### Stage 1 — Core architecture (monads + lenses + persistent stack), template ported
- **Goal:** stand up the architecture and prove it by porting the *existing*
  template features onto it, with the original tests still passing.
- **Implement:**
  - A `Context`/`Ctx` record holding the environments (variable env, function
    env) plus room for ownership/borrow state added later; **lenses** for its
    fields.
  - A **persistent scope stack** module (immutable stack of frames; push/pop a
    scope, look up through frames, update a frame) — the data structure we'll
    reuse everywhere. Document its persistence.
  - Checker monad `Tc` and interpreter monad `Eval` as a transformer stack
    (`ExceptT` + `StateT Ctx` + a logging effect). Keep a `throw`/typed-error
    story; errors print fragments via `printTree`.
  - Port `TypeCheck.*` and `Interp.*` onto `Tc`/`Eval` and the lens/stack API.
    Keep current grammar unchanged for now.
- **Satisfies:** introduces **persistence**, **lenses**, **transformers** (3 of
  4 techniques scaffolded).
- **Accept:** original template tests still pass on the new architecture;
  `RUBRIC_MAP.md` shows the three techniques as "introduced".

### Stage 2 — Phase 0a: new grammar + AST + parsing
- **Goal:** redesign the surface syntax to a clean Rust-like language and get it
  parsing into a new AST (semantics come next stage).
- **Implement:** extend `Lang.cf` for: immutable vs mutable bindings
  (`let x = …` / `let mut x = …`), reassignment (`x = …`), `{ … }` blocks,
  `if`/`if-else` **statements** (keep the existing `if-then-else` expression
  too), a `while` loop, functions with **0..n parameters** and **mutable
  parameters** and an explicit **return type annotation**, and a void type
  `()` used as the default return type. (You may merge the `Stmt`/`Exp`
  categories if the split gets annoying — README allows it.) Update
  `Lang.Print` usage as needed. Add `examples/phase0_*.afp` files. The type
  checker/interpreter only needs to compile here (stub/partial is fine).
- **Satisfies:** Phase 0 syntax groundwork.
- **Accept:** the example files parse without error and pretty-print back
  sensibly; `make build` green. (Run `make run FILE=examples/phase0_*.afp`;
  parsing succeeds even if evaluation is stubbed.)

### Stage 3 — Phase 0b: type checker + interpreter for Phase 0
- **Goal:** full Phase-0 semantics.
- **Implement:** immutable-binding reassignment is rejected ("cannot assign to
  an immutable variable") while mutable reassignment works; **block scoping** —
  bindings inside a block are invisible outside it, but mutations to
  outer mutable variables persist; `if`/`if-else` statement + `while`
  semantics; functions with many params / mutable params / return-type
  checking; `()`/void. Use the persistent scope stack (push on block/function
  entry, pop on exit) and lenses for state updates.
- **Satisfies:** **Phase 0 complete** (rubric "6" feature set, part 1).
- **Accept:** positive + negative + error-message tests for each Phase-0
  feature pass; the spec's Phase-0 example snippets behave as described (e.g.
  the block example returns 5; returning the inner `y` errors;
  `double_in_place` works).

### Stage 4 — Phase 1: affine types (ownership / move semantics)
- **Goal:** "each value used at most once"; ownership transfer.
- **Implement:** a built-in non-copyable `Light` type with values
  `Red`/`Yellow`/`Green` (matches the spec examples; primitives stay affine for
  now and become `Copy` in stage 7). Track ownership in the persistent stack:
  using/moving a value **consumes** it; binding `let b = a` moves ownership;
  re-binding/reassigning restores ownership; passing to a function moves into
  the parameter; the immutable↔mutable transfer rules from the spec table.
  "Value used after being moved" / "use after move" errors.
- **Satisfies:** **Phase 1 complete** (rubric "6" feature set, part 2).
- **Accept:** the spec's Phase-1 snippets pass/fail exactly as documented
  (double-move errors; move-then-rebind is fine; `x = change(x)` is fine; etc.),
  with positive + negative + error-message tests.

### Stage 5 — Concurrency: concurrent logging subsystem
- **Goal:** satisfy the group-of-2 concurrency technique.
- **Implement:** a background logger thread (`forkIO`) that drains a channel
  (`Chan`/`TQueue`) of structured log messages emitted by the checker/
  interpreter through the `Log` effect from stage 1; thread-safe; flushed
  cleanly at program end. Keep it small. Add a toggle so logs don't pollute
  normal output.
- **Satisfies:** **concurrency** technique ⇒ **all four required techniques now
  used [→ grade 6 reachable]** (assuming Phases 0+1 + module docs + demo).
- **Accept:** running a program with logging on prints interleaved log lines and
  the program result is unchanged; a test confirms results are identical with
  logging on vs off.

### Stage 6 — Phase 2A: lists (vectors)
- **Goal:** polymorphic lists of value types.
- **Implement:** list literals, indexing read `list[i]`, index assignment
  `list[i] = x`, `push`, `insert(i, x)`, `remove(i)`. Mutation only allowed when
  the list is bound mutably; lists are **move** types (not copyable). Restrict
  element types to value types for now (per spec).
- **Satisfies:** **Phase 2 feature 2A** (one of the 3 needed for "7").
- **Accept:** the spec's immutable-list errors and mutable-list sequence behave
  as shown; pos + neg + error-message tests.

### Stage 7 — Phase 2B: copyable primitives
- **Goal:** `int`/`bool` are `Copy`, not moved.
- **Implement:** using/binding/passing an `int` or `bool` copies instead of
  consuming, so `x` keeps ownership; lists and functions stay non-copyable.
- **Satisfies:** **Phase 2 feature 2B** (2nd of 3 for "7").
- **Accept:** the spec's copy example (reuse `x` repeatedly) type-checks and
  runs; moving a list still errors; pos + neg tests.

### Stage 8 — Phase 2C: Result, pairs, pattern matching
- **Goal:** richer data + matching.
- **Implement:** a `Result` type (ok value / error), **pairs** (primitive when
  both components are primitive, else move), and `match` pattern matching over
  them (and over `Light`). Exhaustiveness checked by the type checker.
- **Satisfies:** **Phase 2 feature 2C** ⇒ **3 Phase-2 features done
  [→ grade 7 reachable]**.
- **Accept:** constructing/destructuring `Result` and pairs works; non-exhaustive
  match is a type error; pos + neg + error-message tests.

### Stage 9 — Phase 3A: immutable borrows
- **Goal:** `&x` shared references with read access.
- **Implement:** reference types; `&x` creates an immutable borrow; unlimited
  simultaneous immutable borrows; dereference `*r`; functions taking `&T`; a
  borrowed value cannot be moved or assigned while a borrow is alive; a borrow
  must not outlive its referent (lexical lifetime = owner's scope, tracked via
  the scope stack); borrows cannot be returned from functions. Cannot return a
  reference to a fresh local.
- **Satisfies:** **Phase 3 feature 3A** (one of the 2 needed for "8").
- **Accept:** spec 3A snippets and the borrow-then-move error and the
  use-after-free-across-block error behave as documented; pos + neg +
  error-message tests.

### Stage 10 — Phase 3B: mutable borrows
- **Goal:** `&mut x` exclusive references with write access.
- **Implement:** `&mut x` (only on mutably-owned values); `*r = …` writes
  through it; **exclusivity** — while a `&mut` is alive there may be no other
  borrow (mut or immut) of that value, and no `&mut` may be created while any
  immutable borrow is alive; mut→immut coercion allowed, not vice-versa; the
  transfer-rules table from the spec; mutable-binding-of-reference vs
  mutable-borrow distinction.
- **Satisfies:** **Phase 3 feature 3B** ⇒ **2 Phase-3 features done
  [→ grade 8 reachable]**.
- **Accept:** the spec's exclusivity errors all fire; `*b = *b + *b` example
  returns 42; `set_red` example returns `Red`; pos + neg + error-message tests.

### Stage 11 — Phase 3C: non-lexical lifetimes (NLL)
- **Goal:** end a borrow's lifetime at its **last use**, not at end of scope.
- **Implement:** a **traversal over the AST/scope stack that computes last-use
  points and drives the lifetime-ending transformation** in the borrow checker
  (this is the optics *advanced-usage* instance). The spec's NLL example then
  type-checks where the lexical version would reject.
- **Satisfies:** **Phase 3 feature 3C** ⇒ **3 Phase-3 features
  [→ grade 9 reachable]**, and provides **advanced usage** of the optics
  technique. Also confirm the persistent-stack-used-throughout advanced usage
  in `RUBRIC_MAP.md`.
- **Accept:** the spec's NLL example passes; the pre-NLL lexical cases still
  pass/fail correctly; pos + neg tests.

### Stage 12 — Phase 4A: explicit lifetime annotations
- **Goal:** named lifetimes on function signatures.
- **Implement:** lifetime parameters (e.g. `<'a>`), annotated reference
  parameters/return (`&'a T`), and checking that the returned borrow's lifetime
  is tied to the right input(s) so callers are constrained accordingly;
  returning a borrow tied to the wrong lifetime is rejected. A `Fresh` supply
  effect for lifetime variables is a natural custom-effect home if you want a
  clean advanced-usage transformer here.
- **Satisfies:** **Phase 4 feature 4A** (one of the 2 needed for "10").
- **Accept:** the spec's `foo<'a>` / `foo<'a,'b>` examples accept/reject exactly
  as documented; pos + neg + error-message tests.

### Stage 13 — Phase 4B: multithreading (user-facing)
- **Goal:** a fork/spawn primitive in the language; ownership keeps it safe.
- **Implement:** a user-facing way to spawn a thread (e.g. `spawn { … }` or a
  `fork`/`join` primitive). The evaluator may use real threads or interleave on
  one thread (spec allows interleaving). The type/ownership rules must prevent
  data races (a moved value can't be used by two threads; shared access follows
  the borrow rules).
- **Satisfies:** **Phase 4 feature 4B** ⇒ **2 Phase-4 features
  [→ grade 10 reachable]**. Second use of the concurrency technique.
- **Accept:** a program that spawns work and joins produces the right result; a
  program that would race (use-after-move across threads) is rejected by the
  checker; pos + neg tests.

### Stage 14 — Hardening, full docs, design doc, demo prep (the +1.0 bonus)
- **Goal:** lock in the bonus and the deliverables.
- **Implement:**
  - **Comprehensive documentation** of *all* types, monads, and top-level
    functions (bonus +0.5) — still concise, one line each.
  - Finish `DESIGN.md`: syntax description, full feature overview, **2–3 worked
    example programs**, and a clear paragraph per required technique explaining
    *how* it's used (including the advanced-usage instances).
  - Finalize `RUBRIC_MAP.md` so every rubric line and phase feature points at
    code + tests.
  - A short **demo script** / talking points: grammar overview with example
    programs, type-checker + evaluator walkthrough, and the technique
    explanations (helps earn the +0.5 demo-answers bonus).
  - Sanity sweep: `make build` + `make test` green; remove dead code; confirm
    `-Werror` clean.
- **Satisfies:** rubric documentation requirement for the 6, plus the **+1.0
  bonus** caps us at a clean **10.0**.
- **Accept:** `make test` green; `DESIGN.md`, `RUBRIC_MAP.md`, and the demo
  script are complete and accurate.

---

## 4. Final deliverables checklist (from README + rubric)

- [ ] Haskell implementation: type checker + interpreter + test suite (positive
      and negative tests per feature) + module/function comments.
- [ ] `DESIGN.md`: syntax, feature overview, 2–3 example programs, per-technique
      explanation.
- [ ] All four techniques used (persistence, lenses/traversals,
      transformers/effects, concurrency) with ≥1 advanced usage.
- [ ] Phases 0–4 fully implemented (all features) — group-of-2 counts.
- [ ] Comprehensive type/monad/function docs (bonus) + demo prep (bonus).
- [ ] `RUBRIC_MAP.md` cross-referencing everything for the demo.

**Deadlines for our planning:** first submittable version by **14 June** (used
for the demo), final version by **28 June**.

---

### Start now with **Stage 0 only**, then stop and summarize.
