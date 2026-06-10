# Design Document — AFP Ownership Type System

## Overview

A type checker and interpreter for a small Rust-like language with ownership,
borrowing, and lifetime semantics, implemented in Haskell. The project targets
all four phases of the AFP spec (Phases 0–4) plus every required technique.

---

## Syntax Description

Programs are sequences of **statements** (`;`-separated) whose final
`SExpr` expression is the program's result value. Comments use `//`.

### Types

| Syntax | Meaning |
|--------|---------|
| `int` | Machine integer |
| `bool` | Boolean |
| `()` | Unit / void |
| `Light` | Non-copyable traffic-light type |

### Bindings and assignment

```rust
let x = expr;          // immutable binding
let mut x = expr;      // mutable binding
x = expr;              // reassignment (only allowed on mut bindings)
```

### Blocks

```rust
{ stmt; ...; stmt }    // block statement; creates a new scope
```

Inner bindings are not visible outside the block. Mutations to outer mutable
variables persist after the block exits.

### Control flow

```rust
if cond { ... }
if cond { ... } else { ... }
while cond { ... }
```

### Functions

```rust
fn name(x: T, mut y: U) -> RetType { ... }
name(arg1, arg2)       // call as expression
```

Zero or more parameters; parameters may be `mut`. The function body's last
expression is the return value (void bodies need no trailing expression).
Functions are registered before their bodies are checked, so recursion works.

### Expression-level let (functional style, still supported)

```rust
let x = expr in expr
```

### Boolean and comparison literals

```
true  false
==  !=  <  >  <=  >=  &&  ||  !
```

### Light literals

```
Red   Yellow   Green
```

---

## Feature Overview

| Phase | Feature | Status |
|-------|---------|--------|
| 0 | Mutable variables, blocks, if/while, multi-param functions | **Done** |
| 1 | Affine types / move semantics (`Light`) | Planned |
| 2A | Lists (vectors) | Planned |
| 2B | Copyable primitives (`int`, `bool`) | Planned |
| 2C | `Result`, pairs, pattern matching | Planned |
| 3A | Immutable borrows (`&x`) | Planned |
| 3B | Mutable borrows (`&mut x`) | Planned |
| 3C | Non-lexical lifetimes | Planned |
| 4A | Explicit lifetime annotations | Planned |
| 4B | User-facing multithreading (`spawn`) | Planned |

---

## Example Programs

### 1. Mutable variables and reassignment

```rust
let mut x = 0;
x = 5;
x
// → 5
```

### 2. Block scoping — inner binding invisible outside, outer mutation persists

```rust
let mut x = 0;
{
    let y = 5;
    x = y        // mutates outer x through the scope stack
};
x
// → 5
// Attempting "y" here would give: Variable "y" is not bound
```

### 3. Control flow and functions

```rust
fn double(x: int) -> int { x + x };
fn add(x: int, y: int) -> int { x + y };
fn double_in_place(mut x: int) -> int {
    x = x * 2;
    x
};
fn no_arg() -> int { 42 };

let mut y = 0;
if y < 1 { y = 1 } else { y = 2 };
while y < 5 { y = y + 1 };
add(double(y), no_arg())
// → add(10, 42) = 52
```

---

## Required Techniques

### 1. Persistent Purely-Functional Data Structure

**Module:** [`src/ScopeStack.hs`](src/ScopeStack.hs)

`ScopeStack a` is an immutable stack of `Map Ident a` frames:

```haskell
newtype ScopeStack a = ScopeStack [Map.Map Ident a]
```

- `push` / `pop` are O(1) list cons/tail — no mutation, the old stack is
  still valid (full persistence).
- `lookupStack` searches from innermost frame outward, implementing lexical
  scoping.
- `updateStack` rewrites the first frame that contains the name, which is how
  mutable assignment (`x = e`) inside inner blocks propagates outward.

Used in **every** type-checker and interpreter module via `TcCtx._tcVars` and
`EvalCtx._evalVars`. This qualifies as *advanced usage*: the same structure
is the primary mechanism for scoping, mutability, and (later) ownership tracking
throughout the whole checker.

### 2. Lenses and/or Traversals

**Module:** [`src/Context.hs`](src/Context.hs)

Hand-rolled van Laarhoven lenses (no external library):

```haskell
type Lens' s a = forall f. Functor f => (a -> f a) -> s -> f s
view :: Lens' s a -> s -> a
over :: Lens' s a -> (a -> a) -> s -> s
set  :: Lens' s a -> a -> s -> s
```

Lenses `tcVars`, `tcFuns`, `evalVars`, `evalFuns` are used throughout every
TypeCheck and Interp module: `modify (over tcVars ...)` replaces clunky record
updates. A second advanced-usage instance — a **traversal driving the NLL
last-use pass** — is planned for Stage 11.

### 3. Monad Transformers and/or Free Monads

**Modules:** [`src/Tc.hs`](src/Tc.hs), [`src/Eval.hs`](src/Eval.hs)

```haskell
type Tc   a = ExceptT String (State TcCtx)   a
type Eval a = ExceptT String (State EvalCtx) a
```

`ExceptT` gives typed errors; `State` threads the mutable context.
All TypeCheck and Interp modules run inside `Tc` / `Eval` respectively,
using `throwError`, `gets`, `modify` from `mtl`. A custom `Log` effect
(advanced usage) is planned for Stage 5.

### 4. Concurrency

A background logger thread draining a `Chan` of structured log messages is
planned for Stage 5. A user-facing `spawn` primitive is planned for Stage 13.

---

## Architecture

```
grammar/Lang.cf          BNFC grammar → Alex lexer + Happy parser
src/ScopeStack.hs        Persistent scope stack (data structure technique)
src/Value.hs             Runtime values + Closure / TClosure types
src/Context.hs           TcCtx / EvalCtx records + van Laarhoven lenses
src/Tc.hs                Tc monad  = ExceptT String (State TcCtx)
src/Eval.hs              Eval monad = ExceptT String (State EvalCtx)
src/TypeCheck/Expr.hs    Expression type inference
src/TypeCheck/Stmt.hs    Statement type checking (scoping, mutability, fns)
src/TypeCheck/Prog.hs    Program entrypoint for the type checker
src/Interp/Expr.hs       Expression evaluation
src/Interp/Stmt.hs       Statement evaluation (scoping, control flow, fns)
src/Interp/Prog.hs       Program entrypoint for the interpreter
src/Run.hs               Public API: infertype / run
app/Main.hs              CLI entry point
test/TypeCheckTests.hs   Type-checker Hspec tests (positive + negative + msg)
test/InterpTests.hs      Interpreter Hspec tests (positive)
```

### Mutual import cycle (Interp.Expr ↔ Interp.Stmt)

`ECall` in `Interp.Expr` must evaluate body statements (needs `Interp.Stmt`),
while `Interp.Stmt` must evaluate expressions (needs `Interp.Expr`). This is
broken with a standard GHC **hs-boot file** (`src/Interp/Stmt.hs-boot`), which
declares the `interp :: Stmt -> Eval ()` signature so GHC can compile
`Interp.Expr` before the full `Interp.Stmt` is available.
