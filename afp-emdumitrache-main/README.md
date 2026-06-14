# AFP Ownership Type System

An ownership type system for memory safety, implemented in Haskell as the final project for Advanced Functional Programming at TU Delft.

The language is inspired by Rust and supports affine types, move semantics, immutable and mutable borrows, non-lexical lifetimes, explicit lifetime annotations, and user-facing spawn blocks for safe concurrency.

The repository consists of the following components:

- `app/` - entry point (`Main.hs`) with interactive REPL and `--log` flag support
- `grammar/` - BNFC-generated parser and AST for the language
- `src/` - type checker and interpreter source code
- `test/` - test suite (type checker, interpreter, logger tests)
- `examples/` - example programs for each phase
- `examples/errors/` - example programs that demonstrate type errors

---

## Building and Running

You will need GHC and Cabal installed. The project is tested with GHC 9.10.3 and Cabal 3.16.

### Build

```
cabal build
```

### Run a file

```
cabal run afp-lang -- examples/phase0_mutable.afp
```

### Run with logging enabled

Passing `--log` prints a message when the run starts and finishes, produced by the concurrent logger running on a background thread:

```
cabal run afp-lang -- --log examples/phase0_mutable.afp
```

Output:

```
[run] start
5
[run] done
```

### Run the interactive REPL

Type a program and press Enter to evaluate it immediately:

```
cabal run afp-lang
```

### Run all tests

```
cabal test
```

---

## Example Programs

All examples are in the `examples/` folder. Each file has a comment at the top explaining what it demonstrates and the expected output.

### Valid programs (should succeed)

| File | Phase | Expected output |
|---|---|---|
| `phase0_mutable.afp` | Mutable variables | `5` |
| `phase0_block.afp` | Block scoping | `5` |
| `phase0_control.afp` | If-else and while | `5` |
| `phase0_functions.afp` | Multi-param functions | `48` |
| `phase1_affine.afp` | Affine types / move semantics | `1` |
| `phase1_ownership.afp` | Ownership transfer | `Green` |
| `phase2a_lists.afp` | Mutable list operations | `2` |
| `phase2b_copy.afp` | Copyable primitives (int, bool) | `15` |
| `phase2c_match.afp` | Result type and pattern matching | `42` |
| `phase3a_borrow.afp` | Immutable borrows | `42` |
| `phase3b_mut_borrow.afp` | Mutable borrows | `42` |
| `phase3c_nll.afp` | Non-lexical lifetimes | `10` |
| `phase4a_lifetimes.afp` | Explicit lifetime annotations | `5` |
| `phase4b_spawn.afp` | Spawn blocks (safe concurrency) | `5` |

Run all valid examples at once:

```
cabal run afp-lang -- examples/phase0_mutable.afp ; cabal run afp-lang -- examples/phase0_block.afp ; cabal run afp-lang -- examples/phase0_control.afp ; cabal run afp-lang -- examples/phase0_functions.afp ; cabal run afp-lang -- examples/phase1_affine.afp ; cabal run afp-lang -- examples/phase1_ownership.afp ; cabal run afp-lang -- examples/phase2a_lists.afp ; cabal run afp-lang -- examples/phase2b_copy.afp ; cabal run afp-lang -- examples/phase2c_match.afp ; cabal run afp-lang -- examples/phase3a_borrow.afp ; cabal run afp-lang -- examples/phase3b_mut_borrow.afp ; cabal run afp-lang -- examples/phase3c_nll.afp ; cabal run afp-lang -- examples/phase4a_lifetimes.afp ; cabal run afp-lang -- examples/phase4b_spawn.afp
```

### Error programs (should be rejected by the type checker)

These programs are in `examples/errors/`. Each one demonstrates a specific type error that the type checker is expected to catch.

| File | Phase | Error demonstrated |
|---|---|---|
| `phase1_error_move.afp` | Phase 1 | Use after move |
| `phase2a_error_immutable.afp` | Phase 2A | Mutating an immutable list |
| `phase2b_error_move.afp` | Phase 2B | List is not Copy |
| `phase3a_error_borrow.afp` | Phase 3A | Move while borrowed |
| `phase3b_error_exclusivity.afp` | Phase 3B | Mutable and immutable borrow conflict |
| `phase3c_error_dangle.afp` | Phase 3C | Dangling borrow |
| `phase4a_error_lifetime.afp` | Phase 4A | Returning reference without lifetime |
| `phase4b_error_spawn.afp` | Phase 4B | Non-Copy capture in spawn |

Run all error examples at once:

```
cabal run afp-lang -- examples/errors/phase1_error_move.afp ; cabal run afp-lang -- examples/errors/phase2a_error_immutable.afp ; cabal run afp-lang -- examples/errors/phase2b_error_move.afp ; cabal run afp-lang -- examples/errors/phase3a_error_borrow.afp ; cabal run afp-lang -- examples/errors/phase3b_error_exclusivity.afp ; cabal run afp-lang -- examples/errors/phase3c_error_dangle.afp ; cabal run afp-lang -- examples/errors/phase4a_error_lifetime.afp ; cabal run afp-lang -- examples/errors/phase4b_error_spawn.afp
```

---

## Language Overview

A program is a sequence of statements separated by `;`, ending with a final expression that produces the result.

### Types

| Type | Description |
|---|---|
| `int` | Integer (Copy) |
| `bool` | Boolean (Copy) |
| `Light` | Traffic light: `Red`, `Yellow`, `Green` (affine, non-Copy) |
| `[T]` | List of copyable elements (non-Copy) |
| `Result<T>` | Either `Ok(v)` or `Err(v)` |
| `(T1, T2)` | Pair |
| `&T` | Immutable reference (Copy) |
| `&mut T` | Mutable reference (non-Copy) |
| `&'a T` | Immutable reference with lifetime annotation |
| `&mut 'a T` | Mutable reference with lifetime annotation |
| `()` | Unit / void |

### Statements

```
let x = e              // immutable variable
let mut x = e          // mutable variable
x = e                  // reassignment (x must be mut)
*r = e                 // write through mutable reference
list.push(e)           // append to list
list.insert(i, e)      // insert at index
list.remove(i)         // remove at index
list[i] = e            // assign at index
if c { ... }           // conditional
if c { ... } else { ...}  // conditional with else
while c { ... }        // loop
fn f(x: T) -> T { ... }              // function
fn f<'a>(x: &'a T) -> &'a T { ... } // lifetime function
spawn { ... }          // spawn block (Copy captures only)
{ ... }                // block (own scope)
```

### Expressions

```
e + e   e - e   e * e   e / e     // arithmetic
e && e  e || e  !e                 // boolean
e == e  e != e  e < e  e > e      // comparison
e <= e  e >= e
&x      &mut x                     // borrow
*e                                 // dereference
[e, e, ...]                        // list literal
list[i]                            // index read
Ok(e)   Err(e)                     // Result constructors
(e, e)                             // pair
match e { pat => e, ... }          // pattern match
if e then e else e                 // if expression
let x = e in e                     // let expression
f(e, ...)                          // function call
spawn { ... }                      // spawn block
```

### Ownership rules

- A non-Copy value can be used exactly once (affine/move semantics).
- `int`, `bool`, and `&T` are Copy and can be used any number of times.
- While a value is borrowed, it cannot be moved or mutated.
- A mutable borrow is exclusive: no other borrow can coexist with it.
- Borrows expire at their last use (non-lexical lifetimes).
- Only Copy values can be captured by a `spawn` block.
