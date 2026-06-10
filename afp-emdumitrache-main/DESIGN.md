# Design Document — AFP Ownership Type System

## Overview

A type checker and interpreter for a small Rust-like language with ownership,
borrowing, non-lexical lifetimes, explicit lifetime annotations, and user-facing
multithreading — implemented in Haskell. Targets all four phases (0–4) of the AFP
spec plus all required techniques and bonus items.

---

## Syntax Reference

Programs are `;`-separated **statement** sequences; the final `SExpr` expression
is the program's return value. Comments use `//` and `/* ... */`.

### Types

| Syntax | Meaning |
|--------|---------|
| `int` | Integer (Copy) |
| `bool` | Boolean (Copy) |
| `()` | Unit / void |
| `Light` | Non-copyable traffic-light enum (`Red \| Yellow \| Green`) |
| `[T]` | List/vector of `T` (non-Copy) |
| `Result<T>` | `Ok(T) \| Err(T)` (non-Copy when T is non-Copy) |
| `(T, U)` | Pair (non-Copy unless both components are Copy) |
| `&T` | Immutable borrow of `T` (Copy) |
| `&mut T` | Mutable borrow of `T` (non-Copy, exclusive) |
| `&'a T` | Lifetime-annotated immutable borrow (Phase 4A) |
| `&mut 'a T` | Lifetime-annotated mutable borrow (Phase 4A) |

### Bindings and assignment

```rust
let x = expr;           // immutable binding
let mut x = expr;       // mutable binding
x = expr;               // reassignment (mut only)
```

### Blocks, control flow, functions

```rust
{ stmt; ...; stmt }                                   // block (new scope)
if cond { ... }
if cond { ... } else { ... }
while cond { ... }
fn name(x: T, mut y: U) -> R { ... }                 // function definition
fn name<'a, 'b>(x: &'a T) -> &'a T { ... }          // lifetime-generic (Phase 4A)
spawn { ... }                                          // concurrent block (Phase 4B)
```

### Lists

```rust
let x = [1, 2, 3];        // list literal
x[0]                       // index read
x[i] = v;                 // index assignment (mut)
x.push(v);                // append (mut)
x.insert(i, v);           // insert at index (mut)
x.remove(i);              // remove at index (mut)
```

### Borrows and dereference

```rust
let r = &x;               // immutable borrow
let b = &mut x;           // mutable borrow (x must be mut)
*r                         // dereference
*b = v;                   // write through mutable reference
```

### Result and pairs

```rust
Ok(expr)                   // construct Ok variant
Err(expr)                  // construct Err variant
(expr, expr)               // pair literal
match expr { Pat => expr, ... }
```

### Patterns

```
Red | Yellow | Green        // Light constructors
Ok(x) | Err(x)             // Result constructors
(x, y)                     // pair deconstruction
x                           // wildcard / variable capture
```

### Expression-level let

```rust
let x = expr in expr       // functional-style let (still supported)
```

---

## Feature Overview

| Phase | Feature | Status |
|-------|---------|--------|
| 0 | Mutable variables, blocks, if/while, multi-param functions | **Done** |
| 1 | Affine types / move semantics (`Light`) | **Done** |
| 2A | Lists (vectors) | **Done** |
| 2B | Copyable primitives (`int`, `bool`) | **Done** |
| 2C | `Result`, pairs, pattern matching | **Done** |
| 3A | Immutable borrows (`&x`) | **Done** |
| 3B | Mutable borrows (`&mut x`) | **Done** |
| 3C | Non-lexical lifetimes (NLL) | **Done** |
| 4A | Explicit lifetime annotations | **Done** |
| 4B | User-facing multithreading (`spawn`) | **Done** |

---

## Example Programs

### Phase 0 — Mutable variables, control flow, functions

```rust
fn double(x: int) -> int { x + x };
fn add(x: int, y: int) -> int { x + y };
fn double_in_place(mut x: int) -> int { x = x * 2; x };

let mut y = 0;
if y < 1 { y = 1 } else { y = 2 };
while y < 5 { y = y + 1 };
add(double(y), 42)
// → 52
```

### Phase 1 — Affine types (move semantics)

```rust
let x = Red;
let y = x;   // x is MOVED into y; x is no longer owned
// x          // ERROR: value of x used after being moved
y
// → Red

fn consume(s: Light) -> int { 0 };
let x = Green;
consume(x);
// x          // ERROR: value of x used after being moved
0
// → 0
```

### Phase 2A — Lists

```rust
let mut list = [1, 2];
list.push(3);
list[0] = 4;
list.remove(2);
let snd = list[1];
list.insert(1, 13);
snd
// → 2
```

### Phase 2C — Result + pattern matching

```rust
fn safe_div(x: int, y: int) -> Result<int> {
    if y == 0 then Err(0) else Ok(x / y)
};
let r = safe_div(84, 2);
match r { Ok(v) => v, Err(e) => e }
// → 42
```

### Phase 3A — Immutable borrows

```rust
fn deref_int(r: &int) -> int { *r };
let x = 42;
let r = &x;
deref_int(r) + x
// → 84   (r is a borrow; x is still accessible)
```

### Phase 3B — Mutable borrows

```rust
fn set_red(mut light: &mut Light) -> () { *light = Red };
let mut l = Green;
set_red(&mut l);
l
// → Red
```

### Phase 3C — Non-lexical lifetimes

```rust
let mut x = 5;
let r = &x;
*r;            // last use of r — borrow of x expires here (NLL)
x = 10;        // safe: r is no longer live
x
// → 10
```

### Phase 4A — Explicit lifetime annotations

```rust
fn first<'a, 'b>(x: &'a int, y: &'b int) -> &'a int { x };
let a = 3;
let b = 4;
let r = first(&a, &b);
*r
// → 3  (r borrows a; type checker tracks this across the call boundary)
```

### Phase 4B — User-facing spawn

```rust
let x = 5;
let flag = true;
spawn { let copy_x = x; let copy_flag = flag };
// spawn checks: x: int (Copy) ✓, flag: bool (Copy) ✓
// let y = Red; spawn { y }   // would be rejected: Light is not Copy
x
// → 5
```

---

## Required Techniques

### 1. Persistent Purely-Functional Data Structure

**Module:** [`src/ScopeStack.hs`](src/ScopeStack.hs)

`ScopeStack a` is an **immutable stack of scope frames**, where each frame is a
`Map Ident a`:

```haskell
newtype ScopeStack a = ScopeStack [Map.Map Ident a]
```

- `push` / `pop` are O(1) list cons/tail — the old stack remains valid (full persistence).
- `lookupStack` searches from the innermost frame outward, implementing **lexical scoping**.
- `updateStack` rewrites the first frame that contains the name — this is how mutable assignment inside inner blocks correctly propagates to outer scopes without breaking the persistent structure.
- `insertTop` shadows outer bindings by inserting into the innermost frame only.

**Advanced usage** (used throughout all phases): the same structure is the sole
mechanism for variable scoping, mutability, ownership tracking, borrow counting,
and lifetime tracking in both the type checker and the interpreter. All
`TypeCheck.*` and `Interp.*` modules access state only through `ScopeStack`.

### 2. Lenses and/or Traversals

**Module:** [`src/Context.hs`](src/Context.hs), advanced usage in [`src/TypeCheck/Stmt.hs`](src/TypeCheck/Stmt.hs)

**Hand-rolled van Laarhoven lenses** (no `lens` library):

```haskell
type Lens' s a = forall f. Functor f => (a -> f a) -> s -> f s

view :: Lens' s a -> s -> a           -- read via Const applicative
over :: Lens' s a -> (a -> a) -> s -> s  -- update via Identity functor
set  :: Lens' s a -> a -> s -> s      -- set = over . const
```

Four lenses focus into `TcCtx` and `EvalCtx`: `tcVars`, `tcFuns`, `evalVars`,
`evalFuns`. Every TypeCheck and Interp module uses `modify (over tcVars ...)` to
update nested fields without boilerplate record syntax.

**Advanced usage — NLL traversal with `Const` applicative as a structural fold**
(`TypeCheck/Stmt.hs:releaseExpiredBorrows`):

```haskell
releaseExpiredBorrows live = do
  vars <- gets (view tcVars)
  let expired = getConst $
        Map.traverseWithKey
          (\x vi -> Const $
            if x `Set.notMember` live && isJust (varBorrowOf vi)
            then [(x, vi)]
            else [])
          (topBindings vars)
  mapM_ releaseAndClear expired
```

`Map.traverseWithKey` is a van Laarhoven Traversal over `(Ident, VarInfo)` pairs.
With `Const [(Ident, VarInfo)]` as the applicative (where `<*>` = `<>` = list
concatenation), this performs a zero-allocation **structural fold** over the top
scope frame, collecting expired borrows without building an intermediate data
structure or requiring an extra traversal.

### 3. Monad Transformers

**Modules:** [`src/Tc.hs`](src/Tc.hs), [`src/Eval.hs`](src/Eval.hs)

```haskell
type Tc   a = ExceptT String (State TcCtx)   a
type Eval a = ExceptT String (State EvalCtx) a
```

`ExceptT` provides typed errors that short-circuit on the first failure;
`State` threads the mutable typing / evaluation context. All `TypeCheck.*` and
`Interp.*` modules run inside `Tc` / `Eval` respectively, using `throwError`,
`gets`, `modify` from `mtl`. The two stacks are structurally identical —
different context types give different capabilities with the same combinator
vocabulary.

### 4. Concurrency

**Two layers:**

**Background logger** ([`src/Logger.hs`](src/Logger.hs)):
```haskell
startLogger :: Bool -> IO Logger   -- forks a drain thread
logMsg      :: Logger -> LogMsg -> IO ()
stopLogger  :: Logger -> IO ()     -- sends sentinel, blocks until flushed
```
A `forkIO` background thread drains a `Chan (Maybe LogMsg)`. A `Nothing` sentinel
signals stop; `MVar ()` synchronises the drain-complete signal back to the caller.

**User-facing `spawn`** ([`src/TypeCheck/Stmt.hs`](src/TypeCheck/Stmt.hs), [`src/Interp/Stmt.hs`](src/Interp/Stmt.hs)):
```rust
spawn { block }
```
The ownership type system enforces thread safety: all variables captured from the
enclosing scope by a `spawn` block must be **Copy** types. Non-Copy types (`Light`,
lists, `Result` of non-Copy, `&mut T`) are rejected at the `spawn` site with a
type error. This statically prevents data races: Copy types have value semantics
(no aliasing), so concurrent access is always safe.

The type-safety story: `isCopyable` decides what can cross thread boundaries.
Immutable borrows (`&T`, `TRef`) are Copy and can be shared; mutable borrows
(`&mut T`, `TRefMut`) are non-Copy and cannot.

**Advanced usage**: the two concurrency mechanisms together demonstrate both
_infrastructure-level_ concurrency (the logger) and _language-level_ concurrency
(spawn as a type-checked language construct). The ownership type system IS the
thread-safety story — no locks required.

---

## Architecture

```
grammar/Lang.cf          BNFC grammar (99 rules) → Alex lexer + Happy LALR(1) parser
src/ScopeStack.hs        Persistent scope stack  [Technique 1]
src/Value.hs             Value / Closure / TClosure; isCopyable; eraseLifetime
src/Context.hs           TcCtx / EvalCtx; van Laarhoven lenses  [Technique 2]
src/Tc.hs                Tc  = ExceptT String (State TcCtx)   [Technique 3]
src/Eval.hs              Eval = ExceptT String (State EvalCtx) [Technique 3]
src/Logger.hs            Background logger (forkIO + Chan + MVar)  [Technique 4]
src/Evaluator.hs         Parsing shim (BNFC → Program AST)
src/TypeCheck/Expr.hs    Expression type inference (EVar ownership, borrows, EMatch)
src/TypeCheck/Stmt.hs    Statement checking (NLL, borrows, lifetimes, spawn)
src/TypeCheck/Prog.hs    Program entrypoint; top-level NLL pass
src/Interp/Expr.hs       Expression evaluation (ECall, EDeref, EMatch)
src/Interp/Stmt.hs       Statement evaluation (SAssign, SDerefAssign, SSpawn)
src/Interp/Prog.hs       Program entrypoint
src/Env.hs               Legacy flat environment (not used; ScopeStack supersedes it)
src/Run.hs               Public API: infertype / run
app/Main.hs              CLI (--log flag, file argument)
test/TypeCheckTests.hs   Type-checker Hspec tests (186 tests)
test/InterpTests.hs      Interpreter Hspec tests (98 tests)
test/LoggerTests.hs      Concurrency/logger tests (5 tests)
```

### Mutual import cycle (`Interp.Expr` ↔ `Interp.Stmt`)

`ECall` in `Interp.Expr` needs `Interp.Stmt.interp` (to run a function body),
while `Interp.Stmt` needs `Interp.Expr.interp` (to evaluate expressions). Broken
with a GHC **hs-boot file** (`src/Interp/Stmt.hs-boot`), which declares the
`interp :: Stmt -> Eval ()` signature so the compiler can type-check
`Interp.Expr` before the full `Interp.Stmt` is available.

---

## Key Design Decisions

### Why `ScopeStack` instead of `Map.Map`?

A flat map cannot represent lexical scoping or inner-block shadowing. `ScopeStack`
gives O(1) scope entry/exit and natural shadowing. Its persistence means the
old stack is never mutated — we pass it through the `State` monad and let GHC's
thunk-sharing recycle frames. The alternative (a `ReaderT (IORef ...)`) would
have lost the purely-functional property required by the course.

### Why hand-rolled lenses?

The `lens` package adds a significant dependency surface and pulls in Template
Haskell. Hand-rolling five lenses demonstrates understanding of the van Laarhoven
representation. The `Const` applicative trick in `releaseExpiredBorrows` is the
key payoff: the same `traverseWithKey` call that can map can also fold, with
zero overhead beyond what a plain fold would cost.

### Why `ExceptT String (State …)` and not `Either + Reader`?

`Either` doesn't thread mutable state — we need `State` to update variable
ownership flags, borrow counts, and the function table during checking. `Reader`
is immutable. The `ExceptT/State` stack gives both: errors short-circuit via
`throwError`, state persists via `gets`/`modify`. All checker and interpreter
functions are simple `Tc`/`Eval` actions; there are no `IO` or `unsafePerformIO`
calls in the core logic.

### NLL — borrow expiry before scope end

Classical lexical lifetimes expire borrows at `}`. Non-lexical lifetimes (NLL)
expire them at the last syntactic use. Implementation: after each statement in
`checkStmtsNLL`, `releaseExpiredBorrows (mentionedVars remainingStmts)` is called.
`mentionedVars` conservatively over-approximates live identifiers (if a variable
appears syntactically, it stays live). The `Const` applicative fold collects
all top-scope borrow variables not in the live set and releases them in one pass.

### Lifetime annotations — borrow tracking across call boundaries

`fn f<'a>(x: &'a T) -> &'a T { x }` binds a lifetime name `'a` to a parameter's
borrow. At call sites (`let r = f(&y)`), `resolveReturnBorrow` matches the return
lifetime to the parameter that carries it, finds the corresponding argument (`&y`
→ `y`), increments `y.varBorrows`, and sets `r.varBorrowOf = Just y`. This means
`r`'s borrow of `y` is tracked exactly as if `r = &y` had been written directly.

### Spawn and thread safety

`spawn { body }` enforces that all outer-scope variables mentioned in `body` are
`isCopyable`. Copy types have value semantics — sharing them between threads is
always safe because there is no aliasing. Non-Copy types (`Light`, lists, `&mut`)
have ownership/aliasing that would be a data race. The type system rejects the
program before any thread is spawned. The interpreter runs the block synchronously
(the safety guarantee is orthogonal to scheduling).

---

## Test Summary

| Suite | Count | Description |
|-------|-------|-------------|
| TypeCheckTests | 186 | Positive (type accepted), negative (rejected), error-message substring checks |
| InterpTests | 98 | Positive end-to-end: parse → typecheck → evaluate → value |
| LoggerTests | 5 | Concurrent logger: results unaffected by background thread; clean drain |
| BogusTests | 2 | Placeholder QuickCheck property + sanity test |
| **Total** | **291** | **0 failures** |
