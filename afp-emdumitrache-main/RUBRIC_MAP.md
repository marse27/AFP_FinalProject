# Rubric Map — AFP Ownership Type System

This file maps every rubric requirement and phase feature to the implementing
module(s) and test(s). Updated at the end of every stage.

---

## Grade 6 Requirements

| Requirement | Module(s) | Test(s) | Status |
|-------------|-----------|---------|--------|
| Phase 0: immutable + mutable variables | `TypeCheck/Stmt.hs` `Interp/Stmt.hs` | `TypeCheckTests` "mutable bindings", "immutable reassignment is rejected" · `InterpTests` "mutable reassignment" | **Done** |
| Phase 0: block scoping | `TypeCheck/Stmt.hs:checkBlock` `Interp/Stmt.hs:interpBlock` `ScopeStack.hs` | `TypeCheckTests` "block scoping" · `InterpTests` "block scoping" | **Done** |
| Phase 0: if / while statements | `TypeCheck/Stmt.hs` `Interp/Stmt.hs` | `TypeCheckTests` "if / if-else statements", "while loop" · `InterpTests` same | **Done** |
| Phase 0: multi-param functions + mutable params | `TypeCheck/Stmt.hs:SFun` `Interp/Stmt.hs:SFun` `TypeCheck/Expr.hs:ECall` `Interp/Expr.hs:ECall` | `TypeCheckTests` "functions", "function error cases" · `InterpTests` "functions", "mutable parameters" | **Done** |
| Phase 1: affine types / move semantics | `TypeCheck/Expr.hs:infer(EVar)` · `TypeCheck/Stmt.hs:SAssign` · `Context.hs:VarInfo` · `Value.hs:isCopyable` | `TypeCheckTests` "Phase 1: Light bindings", "use-after-move is rejected", "int/bool remain copyable" · `InterpTests` "Phase 1: Light literals", "affine move through let", "mutable Light reassignment", "Light through function" | **Done** |
| Technique: persistence | `ScopeStack.hs` | implicit in all scope tests | **Done** |
| Technique: lenses/traversals | `Context.hs` — `view`/`over`/`set` | implicit in all context-state tests | **Done** |
| Technique: monad transformers | `Tc.hs` `Eval.hs` | implicit in all tests | **Done** |
| Technique: concurrency | `Logger.hs` — `forkIO`/`Chan`/`MVar`; `Main.hs` — `--log` flag | `LoggerTests` — 5 tests confirming results unchanged + clean drain | **Done** |
| Basic module/function docs | all `src/` modules | — | **Done** (one-line `-- \|` per function) |
| Demo presentation | `DESIGN.md` | — | In progress |

---

## Grade 7 Requirements (Phase 2: 3 features)

| Requirement | Module(s) | Test(s) | Status |
|-------------|-----------|---------|--------|
| Phase 2A: lists/vectors | `grammar/Lang.cf` (TList, EList, EIndex, SIndexAssign, SPush, SInsert, SRemove) · `TypeCheck/{Expr,Stmt}.hs` · `Interp/{Expr,Stmt}.hs` · `Value.hs:VList` | `TypeCheckTests` "Phase 2A" · `InterpTests` "Phase 2A" | **Done** |
| Phase 2B: copyable primitives (`int`, `bool`) | `Value.hs:isCopyable` · `TypeCheck/Expr.hs:infer(EVar)` | `TypeCheckTests` "Phase 2B" · `InterpTests` "Phase 2B" | **Done** |
| Phase 2C: `Result`, pairs, pattern matching | `grammar/Lang.cf` (TResult, TPair, EOk, EErr, EPair, EMatch, Pat, Arm) · `Value.hs:VOk/VErr/VPair` · `TypeCheck/Expr.hs:infer(EOk/EErr/EPair/EMatch)` · `Interp/Expr.hs:interp(EOk/EErr/EPair/EMatch)` | `TypeCheckTests` "Phase 2C" · `InterpTests` "Phase 2C" | **Done** |

---

## Grade 8 Requirements (Phase 3: 2 features)

| Requirement | Module(s) | Test(s) | Status |
|-------------|-----------|---------|--------|
| Phase 3A: immutable borrows (`&x`) | `grammar/Lang.cf` (TRef, ERef, EDeref) · `Value.hs:VRef/isCopyable` · `Context.hs:VarInfo(varBorrows,varBorrowOf)` · `ScopeStack.hs:topBindings` · `TypeCheck/Expr.hs:infer(ERef/EDeref/EVar)` · `TypeCheck/Stmt.hs:letBorrow/releaseTopBorrows` · `Interp/Expr.hs:interp(ERef/EDeref)` | `TypeCheckTests` "Phase 3A" (20 tests) · `InterpTests` "Phase 3A" (8 tests) | **Done** |
| Phase 3B: mutable borrows (`&mut x`) | `grammar/Lang.cf` (TRefMut, ERefMut, SDerefAssign) · `Value.hs:VRefMut/isCopyable(TRefMut=False)` · `Context.hs:VarInfo(varMutBorrows)` · `ScopeStack.hs:updateSkipping` · `TypeCheck/Expr.hs:infer(ERefMut/EDeref place-expr)` · `TypeCheck/Stmt.hs:letMutBorrow/SDerefAssign/exclusivity` · `Interp/Expr.hs:interp(ERefMut/EDeref VRefMut)` · `Interp/Stmt.hs:SDerefAssign` | `TypeCheckTests` "Phase 3B" (22 tests) · `InterpTests` "Phase 3B" (8 tests) | **Done** |

---

## Grade 9 Requirements (Phase 3: 3rd feature + advanced usage)

| Requirement | Module(s) | Test(s) | Status |
|-------------|-----------|---------|--------|
| Phase 3C: non-lexical lifetimes | — | — | Planned (Stage 11) |
| Advanced usage: persistent scope stack (used throughout checker) | `ScopeStack.hs` used in every `TypeCheck/*` and `Interp/*` module | — | **Done** — stack is the sole mechanism for scoping, mutability, and ownership in all phases |
| Advanced usage: NLL traversal (optics advanced) | — | — | Planned (Stage 11) |
| Advanced usage: custom effect/transformer | — | — | Planned (Stage 5) |

---

## Grade 10 Requirements (Phase 4: 2 features)

| Requirement | Module(s) | Test(s) | Status |
|-------------|-----------|---------|--------|
| Phase 4A: explicit lifetime annotations | — | — | Planned (Stage 12) |
| Phase 4B: user-facing multithreading (`spawn`) | — | — | Planned (Stage 13) |

---

## Bonus (+1.0)

| Requirement | Module(s) | Status |
|-------------|-----------|--------|
| Comprehensive docs (all types, monads, top-level fns) | all `src/` | In progress — one-line doc on every function; full pass in Stage 14 |
| Demo answers correct and complete | `DESIGN.md` | In progress |

---

## Required Techniques Checklist

| Technique | Where used | Advanced usage? | Status |
|-----------|-----------|-----------------|--------|
| Persistent data structure | `ScopeStack` — push/pop on every block/function entry; `lookupStack`/`updateStack` for reads and mutable writes | **Yes** — used as the sole scoping + mutability + ownership mechanism throughout every phase | **Done** |
| Lenses/traversals | `Context.tcVars`, `tcFuns`, `evalVars`, `evalFuns`; `view`/`over`/`set` used in all TypeCheck + Interp modules | Advanced: NLL traversal planned Stage 11 | **Done** |
| Monad transformers/effects | `Tc = ExceptT String (State TcCtx)`; `Eval = ExceptT String (State EvalCtx)`; `throwError`/`gets`/`modify` throughout | Advanced: custom `Log` effect planned Stage 5 | **Done** |
| Concurrency | `Logger.hs`: background thread (`forkIO`), channel (`Chan (Maybe LogMsg)`), synchronisation (`MVar`); `Main.hs`: `--log` toggle | Advanced: user-facing `spawn` planned Stage 13 | **Done** |

---

## Stage Progress

| Stage | Description | Status |
|-------|-------------|--------|
| 0 | Toolchain baseline + doc skeletons | **Done** |
| 1 | Core architecture (monads + lenses + persistent stack) | **Done** |
| 2 | New Rust-like grammar + AST | **Done** |
| 3 | Phase 0 semantics (mutability, scoping, control flow, functions) | **Done** |
| 4 | Phase 1: affine types / move semantics | **Done** |
| 5 | Concurrent logging subsystem | **Done** |
| 6 | Phase 2A: lists | **Done** |
| 7 | Phase 2B: copyable primitives | **Done** |
| 8 | Phase 2C: Result + pairs + pattern matching | **Done** |
| 9 | Phase 3A: immutable borrows | **Done** |
| 10 | Phase 3B: mutable borrows | **Done** |
| 11 | Phase 3C: NLL + optics advanced usage | Planned |
| 12 | Phase 4A: explicit lifetimes | Planned |
| 13 | Phase 4B: multithreading | Planned |
| 14 | Hardening + comprehensive docs + demo | Planned |

---

## Phase 1 Acceptance Evidence

All commands run from the project root under GHC 9.10.3 (via ghcup):

```
cabal test
# 49 type-checker tests, 36 interpreter tests, 2 bogus tests — all pass

cabal run afp-lang -- examples/phase1_affine.afp    # → 1
cabal run afp-lang -- examples/phase1_ownership.afp # → Green
```

Key ownership semantics verified:

| Program | Expected | Actual |
|---|---|---|
| `let x = Red; x` | `Red` | `Red` ✓ |
| `let x = Red; let y = x; x` | "used after being moved" | type error ✓ |
| `fn f(s: Light) -> Light { s }; let x = Red; f(x); x` | "used after being moved" | type error ✓ |
| `let mut x = Red; x = Green; x` | `Green` (ownership restored) | `Green` ✓ |
| `let x = 42; let y = x; x + y` | `84` (int is Copy) | `84` ✓ |

---

## Phase 0 Acceptance Evidence

All commands run from the project root under GHC 9.10.3 (via ghcup):

```
cabal test
# 35 type-checker tests, 27 interpreter tests, 2 bogus tests — all pass

cabal run afp-lang -- examples/phase0_mutable.afp    # → 5
cabal run afp-lang -- examples/phase0_block.afp      # → 5
cabal run afp-lang -- examples/phase0_control.afp    # → 5
cabal run afp-lang -- examples/phase0_functions.afp  # → 48
```

Key spec examples verified:

| Spec example | Expected | Actual |
|---|---|---|
| `let mut x = 0; x = 5; x` | `5` | `5` ✓ |
| block example (inner y mutates outer x) | `5` | `5` ✓ |
| returning inner `y` outside block | type error | type error ✓ |
| `double_in_place(3)` | `6` | `6` ✓ |
| `let x = 0; x = 5; x` | "Cannot assign to immutable" | error ✓ |
