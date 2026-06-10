# Complete Codebase Walkthrough — AFP Final Project

> A full explanation of every module, every function, and every design decision.
> Written to be understood from scratch — no prior knowledge assumed.

---

## Table of Contents

1. [What is this project?](#1-what-is-this-project)
2. [The Grammar — `Lang.cf` and `Lang/Abs.hs`](#2-the-grammar)
3. [Parsing — `Evaluator.hs`](#3-parsing)
4. [Values — `Value.hs`](#4-values)
5. [The Scope Stack — `ScopeStack.hs`](#5-the-scope-stack)
6. [The Contexts — `Context.hs`](#6-the-contexts)
7. [The Monads — `Tc.hs` and `Eval.hs`](#7-the-monads)
8. [The Logger — `Logger.hs`](#8-the-logger)
9. [Type Checker: Expressions — `TypeCheck/Expr.hs`](#9-type-checker-expressions)
10. [Type Checker: Statements — `TypeCheck/Stmt.hs`](#10-type-checker-statements)
11. [Type Checker: Programs — `TypeCheck/Prog.hs`](#11-type-checker-programs)
12. [Interpreter: Expressions — `Interp/Expr.hs`](#12-interpreter-expressions)
13. [Interpreter: Statements — `Interp/Stmt.hs`](#13-interpreter-statements)
14. [Interpreter: Programs — `Interp/Prog.hs`](#14-interpreter-programs)
15. [Top-level wiring — `Run.hs`](#15-top-level-wiring)
16. [The Executable — `app/Main.hs`](#16-the-executable)
17. [Complete Data Flow Diagram](#17-complete-data-flow-diagram)
18. [Design Decisions Summary](#18-design-decisions-summary)

---

## 1. What is this project?

This project is a **programming language built from scratch in Haskell**. It has three parts:

1. **Parser**: takes text like `"let x = 5; x + 1"` and turns it into a data structure (a tree)
2. **Type checker**: walks that tree and verifies it is safe — no using a variable after it was given away, no two people writing to the same memory at once
3. **Interpreter**: walks the tree again and actually *runs* it — variables get real values, arithmetic happens, functions are called

The language is inspired by **Rust** and implements an **ownership type system**. The core idea of ownership is:

- Every value has exactly **one owner** at any time
- Non-copyable values (like the `Light` traffic-light enum) are **consumed** when you use them — you can't use them again
- You can temporarily **borrow** a value without consuming it, using references (`&x` or `&mut x`)
- At most **one mutable borrow** can exist at a time (no aliased mutation)
- **Borrows expire automatically** when the variable holding them is no longer used (Non-Lexical Lifetimes)

All of these guarantees are checked **statically** — before the program runs.

---

## 2. The Grammar

### Files
- `grammar/Lang.cf` — the grammar definition (you write this)
- `grammar/Lang/Abs.hs` — the generated Abstract Syntax Tree types (BNFC generates this)

### What is a grammar?

A grammar is a formal description of what programs look like as text. You write rules like "a statement can be `let x = ...`" and a tool called **BNFC** (BNF Converter) automatically generates the lexer and parser for you.

A **lexer** turns raw text into tokens: the string `"let x = 5"` becomes `[Keyword "let", Ident "x", Symbol "=", Integer 5]`.

A **parser** turns tokens into a tree structure according to the grammar rules.

### The grammar file: `Lang.cf`

Every construct in the language is declared here. The format is:
```
ConstructorName. Category ::= "keyword" ... ;
```

**Types:**
```
TInt.     Type1 ::= "int" ;
TBool.    Type1 ::= "bool" ;
TRef.     Type1 ::= "&" Type ;       -- immutable borrow: &int
TRefMut.  Type1 ::= "&" "mut" Type ; -- mutable borrow: &mut int
TRefLt.   Type1 ::= "&" "'" Ident Type ;    -- lifetime-annotated: &'a int
TRefMutLt.Type1 ::= "&" "mut" "'" Ident Type ; -- &'a mut int
```

**Statements:**
```
SLetImm. Stmt ::= "let" Ident "=" Exp ;          -- let x = 5
SLetMut. Stmt ::= "let" "mut" Ident "=" Exp ;    -- let mut x = 5
SAssign. Stmt ::= Ident "=" Exp ;                -- x = 10
SSpawn.  Stmt ::= "spawn" Block ;                -- spawn { ... }
SFun.    Stmt ::= "fn" Ident "(" [Param] ")" "->" Type Block ;
SFunLt.  Stmt ::= "fn" Ident "<" [Lifetime] ">" "(" [Param] ")" "->" Type Block ;
```

**Expressions** use numbered precedence levels (`Exp8` through `Exp`). `Exp8` is the tightest-binding (atoms like integers and variables). `Exp` is the loosest (things like `if-then-else`). This makes `1 + 2 * 3` automatically parse as `1 + (2 * 3)` without writing any special rules.

### The generated AST: `Lang/Abs.hs`

BNFC reads `Lang.cf` and produces Haskell data types — one type per grammar category:

```haskell
data Program = Program [Stmt]

data Type
    = TInt | TBool | TVoid | TLight
    | TList Type              -- [int]
    | TResult Type            -- Result<int>
    | TPair Type Type         -- (int, bool)
    | TRef Type               -- &int
    | TRefMut Type            -- &mut int
    | TRefLt Ident Type       -- &'a int  (Ident = the lifetime name 'a)
    | TRefMutLt Ident Type    -- &'a mut int

data Stmt
    = SLetImm Ident Exp       -- let x = e
    | SLetMut Ident Exp       -- let mut x = e
    | SAssign Ident Exp       -- x = e
    | SDerefAssign Ident Exp  -- *r = e
    | SBlock Block            -- { ... }
    | SIf Exp Block           -- if e { ... }
    | SIfElse Exp Block Block -- if e { ... } else { ... }
    | SWhile Exp Block        -- while e { ... }
    | SFun Ident [Param] Type Block           -- fn f(...) -> T { ... }
    | SFunLt Ident [Lifetime] [Param] Type Block  -- fn f<'a>(...) -> T { ... }
    | SSpawn Block            -- spawn { ... }
    | SExpr Exp               -- bare expression statement

data Exp
    = EInt Integer            -- 42
    | EVar Ident              -- x
    | EAdd Exp Exp            -- e1 + e2
    | ERef Ident              -- &x
    | ERefMut Ident           -- &mut x
    | EDeref Exp              -- *e
    | ECall Ident [Exp]       -- f(e1, e2, ...)
    | EMatch Exp [Arm]        -- match e { ... }
    | EList [Exp]             -- [1, 2, 3]
    | EOk Exp | EErr Exp      -- Ok(e), Err(e)
    | EPair Exp Exp           -- (e1, e2)
    -- ... arithmetic, comparisons, booleans, if-then-else, let-in

data Pat
    = PLightRed | PLightYellow | PLightGreen
    | POk Ident | PErr Ident
    | PPair Ident Ident
    | PVar Ident              -- wildcard / variable capture

newtype Ident = Ident String  -- a variable or function name
```

**Why generated?** Parsing is tedious and error-prone. BNFC gives you a correct LALR(1) parser automatically. You write the *meaning* of the language (type checking and interpretation); the tool handles the *syntax*.

---

## 3. Parsing

### File: `src/Evaluator.hs`

This is the smallest module — it wraps the BNFC-generated parser:

```haskell
parse :: String -> Either String Program
parse = pProgram . myLexer
```

- `myLexer` turns a `String` into a list of tokens
- `pProgram` turns tokens into a `Program` AST, or returns an error string

`Either String Program` is Haskell's standard "might fail" type:
- `Left "parse error..."` — something went wrong
- `Right (Program [...])` — success, here is the AST

Both `myLexer` and `pProgram` were generated by BNFC from `Lang.cf`.

---

## 4. Values

### File: `src/Value.hs`

Before type-checking or interpreting, we need to define what the language's *values* are at runtime, and what its *type representations* look like at compile time.

### Runtime values (`Value`)

```haskell
data Value
    = VInt Integer        -- an integer: 42, -7, 0
    | VBool Bool          -- true or false
    | VUnit               -- () — nothing, like void
    | VLightRed           -- the traffic light enum value Red
    | VLightYellow        -- Yellow
    | VLightGreen         -- Green
    | VList [Value]       -- a list: [1, 2, 3]
    | VOk  Value          -- Result::Ok(v)
    | VErr Value          -- Result::Err(v)
    | VPair Value Value   -- a pair: (v1, v2)
    | VRef    Ident       -- an immutable reference — stores the VARIABLE NAME
    | VRefMut Ident       -- a mutable reference   — stores the VARIABLE NAME
```

**Important subtlety about references:** `VRef Ident` does not store the value being pointed at — it stores the **name** of the variable. At runtime, dereferencing a `VRef x` means looking up `x` in the variable environment. This is like a pointer that only works while the variable is still in scope. A `VRef "signal"` is a reference to whatever `signal` currently holds.

### `isCopyable :: Type -> Bool`

This function decides whether a type's values can be freely *copied* (used multiple times without consuming them):

```haskell
isCopyable TLight         = False   -- Light is affine: Red/Yellow/Green are consumed on use
isCopyable (TList _)      = False   -- lists are affine (ownership matters)
isCopyable (TResult t)    = isCopyable t   -- Result<int> is Copy, Result<Light> is not
isCopyable (TPair t u)    = isCopyable t && isCopyable u
isCopyable (TRef _)       = True    -- &T is Copy (read-only pointer, safe to share)
isCopyable (TRefMut _)    = False   -- &mut T is NOT Copy (exclusive access, can't share)
isCopyable (TRefMutLt _ _) = False
isCopyable _              = True    -- int, bool, () are Copy
```

**Why this distinction?** This mirrors Rust's `Copy` trait. Types like `int` and `bool` are "value types" — copying them is harmless (like copying a number on paper). Types like `Light` are "ownership types" — there is exactly one copy in the world, and using it means consuming it. References (`&T`) are safe to copy because they're read-only. Mutable references (`&mut T`) are not safe to copy because having two mutable references to the same data would allow two simultaneous writers — a data race.

### `eraseLifetime :: Type -> Type`

Lifetime annotations like `&'a int` exist only at compile time — they help the type checker track which reference came from which variable. When a lifetime-annotated function is *called*, the caller passes a plain `&int`. This function strips the lifetime annotation so the types match:

```haskell
eraseLifetime (TRefLt _ t)    = TRef t      -- &'a T  becomes  &T
eraseLifetime (TRefMutLt _ t) = TRefMut t   -- &'a mut T  becomes  &mut T
eraseLifetime t               = t           -- everything else unchanged
```

### Function closures

```haskell
-- Used by the INTERPRETER — stores the actual code to run
data Closure = Fun [Param] Block

-- Used by the TYPE CHECKER — stores only the type signature
data TClosure = TFun   [Param] Type             -- plain function
              | TFunLt [Ident] [Param] Type     -- lifetime-generic function
```

`TFunLt` carries the list of lifetime names (`[Ident]`) so that at call sites the type checker can resolve which argument provides the return borrow.

---

## 5. The Scope Stack

### File: `src/ScopeStack.hs`

### The problem it solves

Programs have nested scopes:

```
let x = 5;          -- outer scope
{                   -- inner scope opens
  let y = x + 1;   -- y is only visible here
};                  -- inner scope closes; y is gone, x remains
x                   -- x is still accessible here
```

We need a data structure that:
1. Looks up a variable (searching from innermost scope outward)
2. Opens a new scope on block entry
3. Closes a scope on block exit, automatically discarding inner variables
4. Updates a variable in an outer scope from inside an inner one (mutation: `x = 10` inside the block should change the outer `x`)

### The structure

```haskell
newtype ScopeStack a = ScopeStack [Map.Map Ident a]
```

It's a **list of hash maps**. The head of the list is the innermost (most recently opened) scope. Each map holds the variable bindings declared in that scope.

Visualized:
```
[
  { y -> ... },        -- innermost scope (head)
  { x -> ... },        -- outer scope
  {           }        -- global scope (tail)
]
```

### Every operation explained

```haskell
empty :: ScopeStack a
empty = ScopeStack [Map.empty]
-- One global scope, initially empty.
```

```haskell
push :: ScopeStack a -> ScopeStack a
push (ScopeStack fs) = ScopeStack (Map.empty : fs)
-- Add a new empty map at the front = open a new scope.
-- O(1). The old stack is unchanged (Haskell is pure).
```

```haskell
pop :: ScopeStack a -> ScopeStack a
pop (ScopeStack (_:fs@(_:_))) = ScopeStack fs
pop (ScopeStack _)             = ScopeStack [Map.empty]
-- Remove the head = close the innermost scope, discarding all its bindings.
-- The safety case handles trying to pop the very last (global) scope.
```

```haskell
insertTop :: Ident -> a -> ScopeStack a -> ScopeStack a
insertTop x v (ScopeStack (f:fs)) = ScopeStack (Map.insert x v f : fs)
-- Put x into the INNERMOST scope only. Shadows any outer binding with the same name.
```

```haskell
lookupStack :: Ident -> ScopeStack a -> Maybe a
lookupStack x (ScopeStack fs) = go fs
  where
    go []       = Nothing
    go (f:rest) = case Map.lookup x f of
      Just v  -> Just v    -- found it in this frame
      Nothing -> go rest   -- not here, look in the next (outer) frame
-- Searches innermost → outward. Returns the first (innermost) match.
```

```haskell
updateStack :: Ident -> a -> ScopeStack a -> ScopeStack a
updateStack x v (ScopeStack fs) = ScopeStack (go fs)
  where
    go []       = []
    go (f:rest)
      | Map.member x f = Map.insert x v f : rest  -- found it, update this frame
      | otherwise       = f : go rest              -- not here, keep looking outward
-- Searches innermost → outward, updates the FIRST frame that contains x.
-- This is how `x = 10` from inside a nested block correctly updates the outer x.
```

```haskell
updateSkipping :: (a -> Bool) -> Ident -> a -> ScopeStack a -> ScopeStack a
-- Like updateStack, but SKIPS frames where the current value satisfies the predicate.
-- Used for deref-assign (*r = 5):
--   r holds VRefMut "signal", so we want to update "signal", not r itself.
--   But "signal" might appear twice: once as VRefMut (the reference binding)
--   and once as the actual value. `skip (VRef _) = True` makes it skip the
--   reference binding and find the real value.
```

```haskell
topBindings :: ScopeStack a -> Map.Map Ident a
-- Returns just the innermost scope's map.
-- Used by releaseTopBorrows to find all variables about to go out of scope.
```

```haskell
traverseWithKey :: Applicative f
                => (Ident -> a -> f a) -> ScopeStack a -> f (ScopeStack a)
traverseWithKey f (ScopeStack frames) =
  ScopeStack <$> traverse (Map.traverseWithKey f) frames
-- A van Laarhoven traversal over all (name, value) pairs across all frames.
-- When f returns Const [...], acts as a structural fold (collects data, no allocation).
-- When f returns Identity ..., acts as a uniform map (modifies all values).
-- This is the advanced technique used in NLL borrow release.
```

### Why a persistent (immutable) structure?

Haskell is a **pure functional language** — you cannot mutate data in place. Instead, every operation returns a *new* scope stack. Unchanged frames are **shared** between the old and new stack (no copying). This is safe and efficient.

Because the structure is persistent, you can always "go back" to a previous version — useful for type-checking both branches of an `if-else` (each branch starts from the same pre-branch context).

---

## 6. The Contexts

### File: `src/Context.hs`

The type checker and interpreter both need to thread *state* through all their computations. This state is called the **context**. There are two different contexts — one for type checking and one for interpreting.

### `VarInfo` — per-variable state for the type checker

```haskell
data VarInfo = VarInfo
  { varType       :: Type       -- what type does this variable have?
  , varMut        :: Bool       -- was it declared with `mut`?
  , varOwned      :: Bool       -- False = value has been moved away (consumed)
  , varBorrows    :: Int        -- how many active immutable borrows point TO this variable?
  , varMutBorrows :: Int        -- how many active mutable borrows? (max 1 by exclusivity)
  , varBorrowOf   :: Maybe Ident-- if THIS variable IS a borrow, what does it borrow from?
  }
```

**Example walkthrough:**

```
let x = Red
```
→ `x` gets `VarInfo { varType=TLight, varMut=False, varOwned=True, varBorrows=0, varMutBorrows=0, varBorrowOf=Nothing }`

```
let y = x   -- MOVES x (Light is not Copy)
```
→ `x` gets `varOwned=False`. Any future use of `x` triggers "used after being moved".

```
let r = &x  -- BORROWS x
```
→ `x` gets `varBorrows=1`
→ `r` gets `VarInfo { varType=TRef TLight, varBorrowOf=Just x, ... }`

When `r` goes out of scope, `x.varBorrows` is decremented back to 0.

### The two contexts

```haskell
-- Context used by the TYPE CHECKER:
data TcCtx = TcCtx
  { _tcVars :: ScopeStack VarInfo        -- type + ownership info per variable
  , _tcFuns :: Map.Map Ident TClosure    -- type signatures of defined functions
  }

-- Context used by the INTERPRETER:
data EvalCtx = EvalCtx
  { _evalVars :: ScopeStack Value        -- current runtime values of variables
  , _evalFuns :: Map.Map Ident Closure   -- function bodies (closures)
  }
```

**Why is `tcFuns` a flat `Map`, not a `ScopeStack`?** Functions need to be globally visible — you can call `f` from anywhere in the program after it's been defined. A flat map is simpler and the function names don't go out of scope within the scope stack.

### Van Laarhoven Lenses

Without lenses, updating the `_tcVars` field of a `TcCtx` looks like this:

```haskell
ctx { _tcVars = updateStack x newInfo (_tcVars ctx) }
```

With lenses it looks like this:

```haskell
over tcVars (updateStack x newInfo) ctx
```

And in the monad (where `ctx` is implicit state):

```haskell
modify (over tcVars (updateStack x newInfo))
```

**What is a lens?** A lens is a first-class "pointer" into a nested field. It can both read and write. The encoding used here is the **van Laarhoven** style:

```haskell
type Lens' s a = forall f. Functor f => (a -> f a) -> s -> f s
```

Reading: "a lens from structure `s` into field `a` is a function that, given any functor-wrapped modifier `(a -> f a)` and a structure `s`, produces `f s`."

The same lens works for both reading and writing, depending on which functor `f` you use:

```haskell
-- READING: use Const functor (captures the value, ignores the structure)
view :: Lens' s a -> s -> a
view l s = getConst (l Const s)
-- Const ignores the "write back" step, so only the field value is captured.

-- MODIFYING: use Identity functor (applies the modification, wraps the structure)
over :: Lens' s a -> (a -> a) -> s -> s
over l f s = runIdentity (l (Identity . f) s)
-- Identity just wraps and unwraps, so the modification is applied.

-- SETTING (special case of over):
set :: Lens' s a -> a -> s -> s
set l v = over l (const v)
```

A concrete lens looks like:

```haskell
tcVars :: Lens' TcCtx (ScopeStack VarInfo)
tcVars f ctx = (\v -> ctx { _tcVars = v }) <$> f (_tcVars ctx)
```

Read this as: "extract `_tcVars` from `ctx`, apply the functor-wrapped modifier `f` to it, and map the 'put it back' function over the result." The `<$>` is `fmap`, which works for any `Functor f`.

**Why hand-rolled instead of the `lens` library?** The `lens` library is enormous and uses Template Haskell (compile-time code generation). With only 5 lenses needed, writing them by hand is cleaner, faster to compile, and fully transparent.

### Initial contexts

```haskell
emptyTcCtx :: TcCtx
emptyTcCtx = TcCtx SS.empty Map.empty
-- One empty global scope, no functions defined.

emptyEvalCtx :: EvalCtx
emptyEvalCtx = EvalCtx SS.empty Map.empty
-- Same, but for the interpreter.
```

---

## 7. The Monads

### Files: `src/Tc.hs` and `src/Eval.hs`

### What is a monad?

A monad is a design pattern for **chaining computations that share some context or effect**.

- The `Maybe` monad chains computations that might return `Nothing` (fail silently)
- The `Either e` monad chains computations that might fail with an error of type `e`
- The `State s` monad chains computations that read and write shared state `s`
- The `IO` monad chains computations that do input/output

The key benefit: you don't have to manually thread the shared state through every function call — the monad does it for you automatically.

### Why `ExceptT String (State TcCtx)`?

The type checker needs **two capabilities at the same time**:

1. **Mutable state** — the context `TcCtx` changes as variables come into scope, get moved, and get borrowed
2. **Short-circuiting errors** — when a type error is found, stop immediately; don't continue checking the rest of the program

Neither alone is enough:
- Plain `State TcCtx` can't abort execution on error
- Plain `Either String a` can't thread state (you'd have to manually pass `TcCtx` into and out of every function)

The solution is a **monad transformer stack**:

```haskell
type Tc a = ExceptT String (State TcCtx) a
```

`State TcCtx` is the **inner monad** — it handles state. `ExceptT String` is **wrapped around it** — it adds error-throwing on top. Working together:

- `gets f` — reads a field from the current `TcCtx` (via `State`)
- `modify f` — updates the `TcCtx` (via `State`)
- `throwError msg` — aborts immediately with an error message (via `ExceptT`)

```haskell
runTc :: TcCtx -> Tc a -> Either String a
runTc ctx m = evalState (runExceptT m) ctx
```

`runExceptT m` peels off the `ExceptT` layer, giving `State TcCtx (Either String a)`.
`evalState ... ctx` runs the state computation starting from `ctx`, returning just the final `Either String a` (the initial state is consumed; the final state is discarded since we only care about the result).

### The interpreter monad

```haskell
type Eval a = ExceptT String (State EvalCtx) a

runEval :: EvalCtx -> Eval a -> Either String a
runEval ctx m = evalState (runExceptT m) ctx
```

Structurally identical to `Tc` — just `EvalCtx` instead of `TcCtx`. This means every combinator (`throwError`, `gets`, `modify`) works the same way in both halves of the implementation. The two codebases are parallel in structure.

---

## 8. The Logger

### File: `src/Logger.hs`

### Theory: concurrent programming in Haskell

Haskell has **lightweight threads** via `forkIO :: IO () -> IO ThreadId`. Forking is cheap (thousands of threads are normal). Two key concurrency primitives:

- `Chan a` — an unbounded FIFO channel. `writeChan ch v` puts `v` in; `readChan ch` blocks until a value is available and returns it.
- `MVar a` — a mutex box. Either empty or holding a value. `putMVar mv v` fills it (blocks if already full). `takeMVar mv` empties it and returns the value (blocks if already empty).

### The design

```haskell
data Logger = Logger
  { _chan    :: Chan (Maybe LogMsg)  -- messages flow through here
  , _done    :: MVar ()             -- background thread signals "I finished" here
  , _enabled :: Bool                -- if False, logMsg is a no-op
  }
```

The channel carries `Maybe LogMsg`: `Just msg` is a real message, `Nothing` is the "stop" sentinel.

```haskell
startLogger :: Bool -> IO Logger
startLogger enabled = do
  ch   <- newChan           -- create the channel
  done <- newEmptyMVar      -- create the "I'm done" signal, initially empty
  _    <- forkIO (drain ch done)  -- start the background drain thread
  return (Logger ch done enabled)
```

`forkIO (drain ch done)` starts `drain` in a **new background thread**. The main thread continues immediately — it does not wait.

```haskell
drain :: Chan (Maybe LogMsg) -> MVar () -> IO ()
drain ch done = do
  msg <- readChan ch        -- BLOCK until a message arrives
  case msg of
    Nothing ->
      putMVar done ()       -- got the stop sentinel: signal completion and exit
    Just (LogMsg phase text) -> do
      putStrLn $ "[" ++ phase ++ "] " ++ text  -- print the message
      drain ch done         -- loop: wait for the next message
```

```haskell
stopLogger :: Logger -> IO ()
stopLogger (Logger ch done _) = do
  writeChan ch Nothing      -- send the stop sentinel
  takeMVar done             -- BLOCK until drain has finished (MVar is filled by drain)
```

`takeMVar done` blocks the main thread until the drain thread has called `putMVar done ()`. This is a **synchronization barrier** — it prevents the program from exiting before all log messages are printed.

```haskell
logMsg :: Logger -> LogMsg -> IO ()
logMsg (Logger ch _ enabled) msg =
  when enabled (writeChan ch (Just msg))
-- Non-blocking: the main thread puts the message in the channel and moves on.
-- The background thread will print it eventually.
```

### Why this is useful

The logger demonstrates the classic **producer-consumer** concurrency pattern:
- Main thread (producer) puts messages into the channel asynchronously
- Background thread (consumer) reads and prints them
- The `MVar` provides a clean shutdown barrier

In the actual program, `logMsg` is called before and after each program evaluation, so you can see the timing of evaluations when `--log` is passed.

---

## 9. Type Checker: Expressions

### File: `src/TypeCheck/Expr.hs`

This module type-checks all expressions. It runs in the `Tc` monad, so it can read/write the typing context and throw errors.

### The two entry points

```haskell
infer :: Exp -> Tc Type
-- Figure out what type this expression has. Updates context for moves.

check :: Exp -> Type -> Tc ()
-- Verify that this expression has a specific expected type.
-- Just calls infer and compares.
```

```haskell
check e expected = do
  actual <- infer e
  unless (expected == actual) $ throwError $
    "Expression " ++ printTree e ++
    " should be of type " ++ printTree expected ++
    " but has type " ++ printTree actual
```

### Literal expressions (trivial cases)

```haskell
infer (EInt _)        = return TInt
infer ETrue           = return TBool
infer EFalse          = return TBool
infer ELightRed       = return TLight
infer ELightYellow    = return TLight
infer ELightGreen     = return TLight
```

These can't fail — they always have a known type.

### Arithmetic and logic helpers

```haskell
arithmetic :: Exp -> Exp -> Tc Type
arithmetic e1 e2 = check e1 TInt >> check e2 TInt >> return TInt
-- Both operands must be int; result is int.

logic :: Exp -> Exp -> Tc Type
logic e1 e2 = check e1 TBool >> check e2 TBool >> return TBool
-- Both operands must be bool; result is bool.

comparison :: Exp -> Exp -> Tc Type
comparison e1 e2 = check e1 TInt >> check e2 TInt >> return TBool
-- Both operands must be int; result is bool.
```

Used by: `infer (EAdd e1 e2) = arithmetic e1 e2`, etc.

### `EVar x` — the ownership check (most important case)

```haskell
infer (EVar x) = do
  vars <- gets (view tcVars)          -- read the variable scope from context
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ show x ++ " is not bound"
    Just vi  -> do
      let t = varType vi

      -- CHECK 1: If non-Copy, is the value still owned?
      unless (isCopyable t || varOwned vi) $
        throwError $ "Value of " ++ printTree x ++ " used after being moved"

      -- CHECK 2: If non-Copy, is it currently borrowed? (can't move a borrowed value)
      when (not (isCopyable t) && (varBorrows vi > 0 || varMutBorrows vi > 0)) $
        throwError $ "Cannot move " ++ printTree x ++ ": value is borrowed"

      -- CONSUME: If non-Copy, mark as moved (so future uses get CHECK 1 error)
      unless (isCopyable t) $
        modify (over tcVars (updateStack x vi { varOwned = False }))

      return t
```

After the `CONSUME` step, `x.varOwned = False`. Any future `EVar x` hits CHECK 1. This implements **affine types** — non-Copy values can only be used once.

For `Copy` types (like `int`), all three checks are skipped and the type is returned unchanged. Ints can be read any number of times.

### `ERef x` — creating an immutable borrow (expression form)

```haskell
infer (ERef x) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError "not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError "Cannot borrow: value has been moved"
      return (TRef (varType vi))   -- &x has type &T where x : T
```

This only checks validity and returns the type. The actual borrow counter increment (`x.varBorrows += 1`) happens in `TypeCheck/Stmt.hs` when the result is bound via `let r = &x`. A bare `&x` expression (not bound to anything) doesn't track borrows.

### `ERefMut x` — creating a mutable borrow (expression form)

```haskell
infer (ERefMut x) = do
  ...
  unless (varOwned vi) $ throwError "Cannot borrow: value has been moved"
  unless (varMut vi) $ throwError "Cannot borrow as mutable: variable is not mutable"
  return (TRefMut (varType vi))
```

Adds the extra check: the variable must have been declared with `mut`. You can't take a mutable borrow of an immutable variable.

### `EDeref e` — dereferencing a reference

```haskell
-- Special case: dereferencing a plain variable (place expression)
infer (EDeref (EVar r)) = do
  vars <- gets (view tcVars)
  case lookupStack r vars of
    ...
    Just vi -> case varType vi of
      TRef inner        -> return inner    -- *r : T when r : &T
      TRefMut inner     -> return inner    -- *r : T when r : &mut T
      TRefLt _ inner    -> return inner    -- same for lifetime-annotated versions
      TRefMutLt _ inner -> return inner
      t -> throwError $ "Cannot dereference " ++ printTree r ++ " of type " ++ printTree t
```

Why the special case for `EDeref (EVar r)` before the general `EDeref e`?

`TRefMut` is **not Copy**. If we evaluated `r` as a plain `EVar`, the ownership check in `infer (EVar r)` would consume it (set `varOwned = False`). But `*r` is a **place expression** — it names the thing `r` points at, without consuming `r`. By pattern-matching on `EDeref (EVar r)` first, we bypass the move semantics and just look at `r`'s type directly.

### `ECall f args` — function calls

```haskell
infer (ECall f args) = do
  funs <- gets (view tcFuns)
  case Map.lookup f funs of
    Nothing -> throwError "Function not defined"

    -- Plain function: check argument types, return the return type
    Just (TFun params retTy) -> do
      when (length args /= length params) $ throwError "argument count mismatch"
      mapM_ (\(e, p) -> check e (paramType p)) (zip args params)
      return retTy

    -- Lifetime-generic function: erase lifetimes before checking args
    Just (TFunLt _ params retTy) -> do
      when (length args /= length params) $ throwError "argument count mismatch"
      mapM_ (\(e, p) -> check e (eraseLifetime (paramType p))) (zip args params)
      case retTy of
        -- If the return type is a lifetime-annotated reference, REJECT here.
        -- It must be bound with `let r = f(...)` so borrow tracking can be set up.
        TRefLt _ _    -> throwError "must be immediately bound: use 'let r = f(...)'"
        TRefMutLt _ _ -> throwError "must be immediately bound: use 'let r = f(...)'"
        _ -> return retTy
```

### `EMatch e arms` — pattern matching

```haskell
infer (EMatch e arms) = do
  scrutTy <- infer e                              -- type of what we're matching on
  case arms of
    [] -> throwError "Empty match expression"
    (first : rest) -> do
      checkExhaustive scrutTy (map getArmPat arms)  -- must cover all cases statically
      t <- inferArm scrutTy first                   -- type of the first arm's body
      mapM_ (\arm -> checkArmType scrutTy arm t) rest  -- all arms must have same type
      return t
```

```haskell
inferArm scrutTy (MatchArm pat body) = do
  modify (over tcVars push)   -- open a new scope for pattern variables
  bindArmPat scrutTy pat      -- bind pattern variables (e.g., Ok(x) binds x : T)
  t <- infer body             -- type-check the arm body
  modify (over tcVars pop)    -- close the scope (pattern variables go away)
  return t
```

```haskell
-- Exhaustiveness check: every possible value must be covered
checkExhaustive TLight pats
  | any isWild pats = return ()   -- PVar matches anything, so always exhaustive
  | PLightRed `elem` pats && PLightYellow `elem` pats && PLightGreen `elem` pats = return ()
  | otherwise = throwError "Non-exhaustive match on Light: must cover Red, Yellow, and Green"

checkExhaustive (TResult _) pats
  | any isWild pats = return ()
  | any isOkPat pats && any isErrPat pats = return ()
  | otherwise = throwError "Non-exhaustive match on Result: must cover Ok and Err"
```

This is a **static** exhaustiveness check — verified at compile time, not at runtime.

---

## 10. Type Checker: Statements

### File: `src/TypeCheck/Stmt.hs`

Statements don't produce values — they update the typing context. The function signature is:

```haskell
infer :: Stmt -> Tc ()
```

Returns `()` (nothing), but modifies the `TcCtx` state in the `Tc` monad.

### Pattern-matching order matters

The first few clauses of `infer` are special cases that must come before the general ones:

```haskell
infer (SLetImm r (ERef    x)) = letBorrow    r x False   -- let r = &x
infer (SLetMut r (ERef    x)) = letBorrow    r x True    -- let mut r = &x
infer (SLetImm r (ERefMut x)) = letMutBorrow r x False   -- let r = &mut x
infer (SLetMut r (ERefMut x)) = letMutBorrow r x True    -- let mut r = &mut x
infer (SLetImm r (ECall f args)) = callAndBind r f args False  -- let r = f(...)
infer (SLetMut r (ECall f args)) = callAndBind r f args True

-- General case: any other expression
infer (SLetImm x e) = E.infer e >>= \t ->
  modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))
infer (SLetMut x e) = E.infer e >>= \t ->
  modify (over tcVars (insertTop x (VarInfo t True  True 0 0 Nothing)))
```

Why pattern match first on `ERef` and `ERefMut`? Because `let r = &x` is not just a normal let-binding — it establishes a borrow relationship that needs to be tracked in `x.varBorrows`. The general `E.infer (ERef x)` case only returns a type; `letBorrow` does the full tracking.

### `letBorrow r x isMut` — `let r = &x`

```haskell
letBorrow r x isMut = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError "Variable x is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError "Cannot borrow: value has been moved"
      when (varMutBorrows vi > 0) $ throwError "Cannot borrow: already mutably borrowed"
      -- Step 1: increment x's immutable borrow count
      modify (over tcVars (updateStack x vi { varBorrows = varBorrows vi + 1 }))
      -- Step 2: insert r with borrow-of pointer back to x
      modify (over tcVars (insertTop r (VarInfo (TRef (varType vi)) isMut True 0 0 (Just x))))
```

After this:
- `x.varBorrows = 1`
- `r.varBorrowOf = Just x`
- `r.varType = TRef T`

The borrow relationship is tracked in both directions: `x` knows it's borrowed; `r` knows it is a borrow of `x`.

### `letMutBorrow r x isMut` — `let r = &mut x`

```haskell
letMutBorrow r x isMut = do
  ...
  unless (varOwned vi)        $ throwError "Cannot borrow: value has been moved"
  unless (varMut vi)          $ throwError "Cannot borrow as mutable: variable is not mutable"
  when (varBorrows vi > 0)    $ throwError "Cannot borrow as mutable: already borrowed"
  when (varMutBorrows vi > 0) $ throwError "Cannot borrow as mutable: already mutably borrowed"
  modify (over tcVars (updateStack x vi { varMutBorrows = varMutBorrows vi + 1 }))
  modify (over tcVars (insertTop r (VarInfo (TRefMut (varType vi)) isMut True 0 0 (Just x))))
```

The critical **exclusivity rule**: you can't create a mutable borrow if there are ANY existing borrows (shared or exclusive). This statically guarantees **no aliased mutation** — the core safety property of the type system.

### `SAssign x e` — reassignment

```haskell
infer (SAssign x e) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError "not in scope"
    Just vi -> do
      unless (varMut vi) $ throwError "Cannot assign to immutable variable"
      when (varBorrows vi > 0 || varMutBorrows vi > 0) $
        throwError "Cannot assign to x: value is borrowed"
      E.check e (varType vi)          -- expression must have the same type as x
      releaseVarBorrow vi             -- if x was itself a borrow, release that relationship
      modify (over tcVars (updateStack x vi { varOwned = True, varBorrowOf = Nothing }))
```

Assigning to `x` **restores ownership** (`varOwned = True`). If `x` was previously a reference variable pointing somewhere, that borrow relationship is cleared.

### `SDerefAssign r e` — writing through a mutable reference

```haskell
infer (SDerefAssign r e) = do
  vars <- gets (view tcVars)
  case lookupStack r vars of
    Nothing -> throwError "not in scope"
    Just vi -> case varType vi of
      TRefMut t      -> E.check e t   -- must write the correct type through the reference
      TRefMutLt _ t  -> E.check e t
      TRef _         -> throwError "immutable reference: cannot write through it"
      _              -> throwError "not a reference"
```

### `SFun f params retTy body` — function definitions

```haskell
infer (SFun f params retTy body) = do
  -- Cannot return a reference without lifetime annotation (dangling reference risk)
  case retTy of
    TRef _    -> throwError "cannot return reference type without lifetime"
    TRefMut _ -> throwError "cannot return reference type without lifetime"
    _         -> return ()
  -- Register the function's type signature globally
  modify (over tcFuns (Map.insert f (TFun params retTy)))
  -- Type-check the body in a fresh scope with parameters bound
  modify (over tcVars push)
  mapM_ bindParam params        -- bind each parameter
  checkBody retTy body          -- check body returns retTy
  releaseTopBorrows             -- clean up borrows before closing scope
  modify (over tcVars pop)
```

`bindParam` inserts each parameter into the innermost scope as a `VarInfo`.

### `SFunLt f lts params retTy body` — lifetime-generic functions

```haskell
infer (SFunLt f lts params retTy body) = do
  let ltNames = [lt | MkLifetime lt <- lts]   -- extract names from Lifetime wrappers
  -- Validate: return type lifetime must be declared in the function's lifetime list
  case retTy of
    TRefLt lt _ -> unless (lt `elem` ltNames) $
      throwError "return type uses undeclared lifetime"
    TRefMutLt lt _ -> unless (lt `elem` ltNames) $
      throwError "return type uses undeclared lifetime"
    _ -> return ()
  modify (over tcFuns (Map.insert f (TFunLt ltNames params retTy)))
  -- Same body checking as SFun
  ...
```

Example: `fn first<'a,'b>(x: &'a int, y: &'b int) -> &'a int` — the return lifetime `'a` must appear in `['a, 'b]`.

### `SSpawn body` — Phase 4B

```haskell
infer (SSpawn body) = do
  let freeVs = mentionedBlock body     -- all variable names mentioned in the block
  vars <- gets (view tcVars)
  let checkCapture x = case lookupStack x vars of
        Nothing -> return ()           -- x is defined INSIDE the block: OK
        Just vi -> unless (isCopyable (varType vi)) $ throwError $
          "Cannot capture non-Copy variable '" ++ printTree x ++ "' in spawn block"
  mapM_ checkCapture (Set.toList freeVs)  -- check every mentioned outer variable
  checkBlock body                          -- then type-check the block body
```

**Why only `Copy` captures?** If a thread captured a `Light` value, the spawning thread and the spawned thread would both own it — two owners of an affine value is a contradiction. If a thread captured `&mut T`, two threads could mutate the same memory simultaneously — a data race. `Copy` types (like `int`, `bool`, `&T`) are safe to share: either they're value types (no aliasing possible) or they're read-only (immutable references can't be used to mutate).

### The NLL (Non-Lexical Lifetimes) subsystem

#### `mentionedVars :: [Stmt] -> Set.Set Ident`

```haskell
mentionedVars :: [Stmt] -> Set.Set Ident
mentionedVars = foldMap mentionedStmt
```

Collects every identifier that appears syntactically in a list of statements. `foldMap` applies `mentionedStmt` to each statement and unions all the resulting sets.

```haskell
mentionedStmt (SLetImm _ e)     = mentionedExp e
mentionedStmt (SAssign x e)     = Set.singleton x <> mentionedExp e
mentionedStmt (SBlock b)        = mentionedBlock b
mentionedStmt (SIf e b)         = mentionedExp e <> mentionedBlock b
-- ... and so on for every statement constructor
```

```haskell
mentionedExp (EVar x)           = Set.singleton x
mentionedExp (ERef x)           = Set.singleton x
mentionedExp (EAdd e1 e2)       = mentionedExp e1 <> mentionedExp e2
-- ... and so on for every expression constructor
mentionedExp (EInt _)           = Set.empty   -- literals mention no variables
```

#### `checkStmtsNLL :: [Stmt] -> Tc ()`

```haskell
checkStmtsNLL []       = return ()
checkStmtsNLL (s:rest) = do
  infer s                                     -- check current statement
  releaseExpiredBorrows (mentionedVars rest)  -- NLL: release borrows not needed in rest
  checkStmtsNLL rest
```

After each statement, compute the "live set" (variables mentioned in remaining statements) and release any borrows whose holders are not in the live set.

**Why NLL?** Without it, this would fail:
```
let x = 5;
let r = &x;      -- r borrows x
let y = *r;      -- LAST USE of r
let z = &mut x;  -- with lexical lifetimes: ERROR (r is still alive in scope)
z
```
With NLL: after `let y = *r`, `r` is not mentioned in any remaining statement, so its borrow is released. `let z = &mut x` then succeeds.

#### `releaseExpiredBorrows :: Set.Set Ident -> Tc ()`

```haskell
releaseExpiredBorrows live = do
  vars <- gets (view tcVars)
  let expired = getConst $
        Map.traverseWithKey
          (\x vi -> Const $
            if x `Set.notMember` live && isJust (varBorrowOf vi)
            then [(x, vi)]   -- x is a borrow holder not in the live set
            else [])
          (topBindings vars)
  mapM_ releaseAndClear expired
```

**The traversal trick:** `Map.traverseWithKey f m` is a van Laarhoven traversal over a map's `(key, value)` pairs. When `f` returns `Const [...]`, the `Applicative` instance for `Const [(k,v)]` concatenates lists (since `[(k,v)]` is a `Monoid`). The entire traversal produces `Const [list of expired borrows]` — a structural fold with no intermediate allocations.

The same `traverseWithKey` instantiated with `Identity` would map over the values; with `Const` it collects data. Same code, different behavior — this is the power of the abstraction.

#### `releaseTopBorrows :: Tc ()`

```haskell
releaseTopBorrows :: Tc ()
releaseTopBorrows = do
  vars <- gets (view tcVars)
  let top = topBindings vars
  -- Step 1: release borrows held by variables in the closing scope
  mapM_ releaseBorrow (Map.toList top)
  -- Step 2: verify no variable in the closing scope is still being borrowed
  vars2 <- gets (view tcVars)
  let top2 = topBindings vars2
  mapM_ checkNotBorrowed (Map.toList top2)
```

When a scope closes (block exit), any reference variables in that scope must decrement their referents' borrow counters. After that, we verify no variable in the closing scope is still being borrowed by something in an outer scope (which would be a dangling reference).

### `callAndBind r f args isMut` — `let r = f(...)` with lifetime tracking

For plain `TFun` functions, this just delegates to `E.infer (ECall f args)` and inserts `r` normally.

For `TFunLt` functions (lifetime-generic), it:
1. Checks argument types (with lifetime erasure)
2. Calls `resolveReturnBorrow` to figure out which argument provides the return borrow
3. Sets up borrow tracking on `r` (incrementing the appropriate counter on the source variable)

```haskell
resolveReturnBorrow lts params args retTy = case retTy of
  TRefLt lt inner -> do
    -- Find which parameter has lifetime `lt`
    case findIndex (\p -> case paramType p of { TRefLt lt2 _ -> lt2 == lt; _ -> False }) params of
      Nothing -> throwError "lifetime does not appear in any parameter"
      Just i  -> case args !! i of
        ERef z    -> return (TRef inner, Just z)   -- return borrows from z
        ERefMut z -> return (TRef inner, Just z)
        _         -> throwError "argument must be a reference for this lifetime"
  ...
```

Example: `fn first<'a,'b>(x: &'a int, y: &'b int) -> &'a int` called as `let r = first(&a, &b)`.
- Return type is `TRefLt 'a int` → find the parameter with lifetime `'a` → that's `x` at index 0 → the argument at index 0 is `&a` → so `r` borrows from `a`.

---

## 11. Type Checker: Programs

### File: `src/TypeCheck/Prog.hs`

```haskell
infer :: Program -> Tc Type
infer (Program [])         = throwError "Missing return statement"
infer (Program [SExpr e])  = E.infer e       -- last expression is the return value
infer (Program (s : rest)) = do
  S.infer s
  S.releaseExpiredBorrows (S.mentionedVars rest)  -- NLL between top-level statements
  infer (Program rest)
```

A program is a list of statements. The last statement must be a bare expression (`SExpr e`) — its type is the program's return type. NLL is applied between every top-level statement, not just inside blocks.

---

## 12. Interpreter: Expressions

### File: `src/Interp/Expr.hs`

The interpreter runs in the `Eval` monad and produces `Value`s.

### Simple cases

```haskell
interp (EInt i)     = return $ VInt i
interp ETrue        = return $ VBool True
interp ELightRed    = return VLightRed
interp (EAdd e1 e2) = arithm e1 e2 (+)
-- etc.
```

### `EVar x`

```haskell
interp (EVar x) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Just v  -> return v
    Nothing -> throwError $ "Variable " ++ show x ++ " is not bound"
```

The interpreter is **simpler** than the type checker — it just looks up the value. There is no ownership tracking at runtime. The type checker has already verified everything is safe at compile time; the interpreter just executes.

### `ERef x` and `ERefMut x`

```haskell
interp (ERef x)    = return (VRef x)
interp (ERefMut x) = return (VRefMut x)
```

A borrow expression produces a value containing the **variable name**. No copying of the actual value. Dereferencing later will look up that name in the current scope.

### `EDeref e`

```haskell
interp (EDeref e) = do
  v <- interp e
  case v of
    VRef x -> do
      vars <- gets (view evalVars)
      case lookupStack x vars of
        Just val -> return val        -- follow the name to the current value
        Nothing  -> throwError "Dangling reference"
    VRefMut x -> do
      vars <- gets (view evalVars)
      case lookupStack x vars of
        Just val -> return val
        Nothing  -> throwError "Dangling mutable reference"
    _ -> throwError "Cannot dereference a non-reference value"
```

### `ECall f args`

```haskell
interp (ECall f args) = do
  funs <- gets (view evalFuns)
  case Map.lookup f funs of
    Nothing -> throwError "Function not defined"
    Just (Fun params body) -> do
      argVals <- mapM interp args          -- evaluate all arguments first
      modify (over evalVars push)          -- open a new scope for the function call
      mapM_ (\(p, v) -> bindParam p v) (zip params argVals)  -- bind params to arg values
      result <- runBody body               -- execute the function body
      modify (over evalVars pop)           -- close the function scope
      return result
```

```haskell
runBody :: Block -> Eval Value
runBody (Block [])         = return VUnit       -- empty body returns ()
runBody (Block [SExpr e])  = interp e           -- last expression is the return value
runBody (Block (s : rest)) = S.interp s >> runBody (Block rest)  -- run statements, then return value
```

### `EMatch e arms`

```haskell
interp (EMatch e arms) = do
  v <- interp e
  matchArms v arms

matchArms _ [] = throwError "Non-exhaustive match"
matchArms v (MatchArm pat body : rest) =
  case tryMatch v pat of
    Nothing    -> matchArms v rest   -- pattern didn't match, try next arm
    Just binds -> do
      modify (over evalVars push)    -- open scope for pattern variables
      mapM_ (\(x, bv) -> modify (over evalVars (insertTop x bv))) binds  -- bind pattern vars
      result <- interp body
      modify (over evalVars pop)
      return result
```

```haskell
-- Pattern matching: returns Nothing (no match) or Just [(name, value)] (bindings)
tryMatch VLightRed    PLightRed     = Just []             -- no bindings produced
tryMatch (VOk v)      (POk x)      = Just [(x, v)]        -- bind x to inner value
tryMatch (VErr v)     (PErr x)     = Just [(x, v)]
tryMatch (VPair v1 v2) (PPair x y) = Just [(x, v1), (y, v2)]
tryMatch v            (PVar x)     = Just [(x, v)]        -- wildcard: always matches
tryMatch _            _            = Nothing              -- no match
```

### Helper functions

```haskell
arithm :: Exp -> Exp -> (Integer -> Integer -> Integer) -> Eval Value
arithm e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VInt a, VInt b) -> return $ VInt (f a b)
    _ -> throwError "Arithmetic on non-integers"

logicOp :: Exp -> Exp -> (Bool -> Bool -> Bool) -> Eval Value
logicOp e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VBool a, VBool b) -> return $ VBool (f a b)
    _ -> throwError "Boolean operation on non-booleans"

listGet :: Int -> [Value] -> Eval Value
listGet i vs = case drop i vs of
  (v:_) -> return v
  [] -> throwError $ "List index " ++ show i ++ " out of bounds"
```

---

## 13. Interpreter: Statements

### File: `src/Interp/Stmt.hs`

```haskell
interp :: Stmt -> Eval ()
```

Statements update the evaluation context but don't produce values.

### Simple cases

```haskell
interp (SLetImm x e) = E.interp e >>= \v -> modify (over evalVars (insertTop x v))
interp (SLetMut x e) = E.interp e >>= \v -> modify (over evalVars (insertTop x v))
-- Both let-bindings behave identically at runtime (mutability is a compile-time concept)

interp (SAssign x e) = E.interp e >>= \v -> modify (over evalVars (updateStack x v))
-- updateStack searches outward from innermost scope, updates the first frame that has x
```

### `SDerefAssign r e` — writing through a mutable reference

```haskell
interp (SDerefAssign r e) = do
  vars <- gets (view evalVars)
  case lookupStack r vars of
    Nothing -> throwError "not in scope"
    Just v  -> case v of
      VRefMut x -> do
        val <- E.interp e
        modify (over evalVars (SS.updateSkipping isRef x val))
        -- updateSkipping: update x but SKIP frames where x is bound to a reference
      _ -> throwError "not a mutable reference"
  where
    isRef (VRef _)    = True
    isRef (VRefMut _) = True
    isRef _           = False
```

Why `updateSkipping`? When `r` holds `VRefMut "signal"`, we need to update `signal`'s actual value. But `signal` might appear in multiple frames (once as a `VRefMut` in the reference frame, once as the real value). `updateSkipping isRef` skips reference bindings and finds the owned value.

### List mutation

```haskell
interp (SPush x e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Just (VList vs) -> do
      v <- E.interp e
      modify (over evalVars (updateStack x (VList (vs ++ [v]))))  -- append to list
    ...

interp (SIndexAssign x i e) = do
  ...
  newVs <- listSetAt (fromInteger n) val vs    -- replace element at index
  modify (over evalVars (updateStack x (VList newVs)))

listSetAt :: Int -> Value -> [Value] -> Eval [Value]
listSetAt i v vs = case splitAt i vs of
  (a, _:b) -> return (a ++ v : b)   -- replace the i-th element
  (_, [])  -> throwError "List index out of bounds"
```

### Control flow

```haskell
interp (SIf cond body) = do
  v <- E.interp cond
  case v of
    VBool True  -> interpBlock body   -- run the body
    VBool False -> return ()          -- do nothing
    _ -> throwError "If condition must be a boolean"

interp (SWhile cond body) = loop
  where
    loop = do
      v <- E.interp cond
      case v of
        VBool True  -> interpBlock body >> loop  -- run body, then repeat
        VBool False -> return ()                  -- stop
        _ -> throwError "While condition must be a boolean"
```

### `SFun` and `SFunLt` — storing closures

```haskell
interp (SFun f params _ body) =
  modify (over evalFuns (Map.insert f (Fun params body)))

interp (SFunLt f _ params _ body) =
  modify (over evalFuns (Map.insert f (Fun params body)))
```

The type information and lifetimes are discarded — the interpreter only needs the parameter list and body. The function is stored in the global function map.

### `SSpawn body`

```haskell
interp (SSpawn body) = interpBlock body
```

The interpreter runs the spawn block **synchronously** — exactly like a regular block. The type checker has already verified Copy-capture safety at compile time. A real concurrent runtime would `forkIO` here, but that would require lifting `Eval` into `IO`, breaking the pure deterministic test suite.

### `interpBlock`

```haskell
interpBlock :: Block -> Eval ()
interpBlock (Block stmts) = do
  modify (over evalVars push)   -- open a new scope
  mapM_ interp stmts            -- run all statements
  modify (over evalVars pop)    -- close the scope (inner bindings are discarded)
```

When `pop` is called, all variables declared inside the block are gone. But mutations to outer variables (made via `updateStack`) persist — they were written into outer frames.

---

## 14. Interpreter: Programs

### File: `src/Interp/Prog.hs`

```haskell
interp :: Program -> Eval Value
interp (Program [])         = throwError "Missing return statement"
interp (Program [SExpr e])  = E.interp e       -- final expression is the return value
interp (Program (s : rest)) = S.interp s >> interp (Program rest)
```

A program is a list of statements. Run each statement in order, then evaluate the final expression and return its value.

---

## 15. Top-level wiring

### File: `src/Run.hs`

```haskell
-- Parse and type-check only (returns the program's result type)
infertype :: String -> Either String Type
infertype input = do
  prog <- parse input                           -- Step 1: parse text → AST
  case runTc emptyTcCtx (TC.infer prog) of      -- Step 2: type-check
    Left err -> Left ("Type error: " ++ err)
    Right t  -> Right t

-- Parse, type-check, AND evaluate (returns the program's final value)
run :: String -> Either String Value
run input = do
  prog <- parse input
  case runTc emptyTcCtx (TC.infer prog) of      -- type-check first
    Left err -> Left ("Type error: " ++ err)
    Right _  -> Right ()                        -- type is discarded; we just need it to pass
  case runEval emptyEvalCtx (IP.interp prog) of -- then interpret
    Left err -> Left ("Runtime error: " ++ err)
    Right v  -> Right v
```

This is the **complete pipeline**:
```
String → parse → Program → type-check → (type) → interpret → Value
```

Type checking **always runs before** interpretation. If the type checker rejects the program, it never runs. This means the interpreter can assume the program is safe and doesn't need to re-check ownership rules.

`emptyTcCtx` and `emptyEvalCtx` create fresh contexts with one empty global scope and no functions defined.

---

## 16. The Executable

### File: `app/Main.hs`

```haskell
main :: IO ()
main = do
  args <- getArgs
  let (flags, files) = partition ("--" `isPrefixOf`) args
  let logEnabled = "--log" `elem` flags
  logger <- startLogger logEnabled    -- start background logger
  case files of
    []           -> loop logger       -- no files: enter interactive REPL
    (fileName:_) -> do
      program <- readFile fileName    -- one file: read and run it
      eval logger program
  stopLogger logger                   -- drain logger before exiting
```

Two modes:
1. **File mode**: `afp-lang myprogram.afp` — reads the file, runs it, prints the result
2. **REPL mode**: `afp-lang` — interactive loop where you type expressions one at a time

Optional flag: `--log` enables the background logging thread.

```haskell
eval :: Logger -> String -> IO ()
eval logger program = do
  logMsg logger (LogMsg "run" "start")    -- log before
  putStrLn $ case run program of
    Left  err -> err                       -- print error
    Right val -> printTree val             -- or print the result value
  logMsg logger (LogMsg "run" "done")     -- log after
```

```haskell
loop :: Logger -> IO ()
loop logger = do
  putStr "Enter an expression (:q to quit): "
  input <- getLine
  case input of
    ":q" -> putStrLn "Goodbye!"
    prog -> eval logger prog >> loop logger  -- evaluate and loop
```

---

## 17. Complete Data Flow Diagram

```
User input (String)
        │
        ▼
  Evaluator.parse          src/Evaluator.hs
  (myLexer + pProgram)     grammar/Lang/Lex.hs + Par.hs (generated)
        │
        ▼
  Program (AST)            grammar/Lang/Abs.hs (generated)
        │
        ▼
  TypeCheck.Prog.infer     src/TypeCheck/Prog.hs
    ├── TypeCheck.Stmt.infer   src/TypeCheck/Stmt.hs
    │     ├── letBorrow / letMutBorrow  (borrow tracking)
    │     ├── releaseVarBorrow          (borrow release on reassign)
    │     ├── releaseTopBorrows         (borrow cleanup on scope exit)
    │     ├── releaseExpiredBorrows     (NLL: release at last use)
    │     ├── checkStmtsNLL             (NLL driver)
    │     ├── mentionedVars/Stmt/Exp    (free-variable analysis for NLL)
    │     ├── callAndBind               (let r = f(...) with lifetime tracking)
    │     └── resolveReturnBorrow       (lifetime resolution at call sites)
    │
    └── TypeCheck.Expr.infer   src/TypeCheck/Expr.hs
          ├── EVar: ownership check + consume
          ├── ERef/ERefMut: borrow validity
          ├── EDeref: place expression handling
          ├── ECall: argument type checking
          ├── EMatch: exhaustiveness + arm type checking
          └── helpers: arithmetic, logic, comparison
        │
        ▼
  Either String Type    (Left = type error, Right = program's type)
        │ (if Right, proceed)
        ▼
  Interp.Prog.interp       src/Interp/Prog.hs
    ├── Interp.Stmt.interp     src/Interp/Stmt.hs
    │     ├── SDerefAssign: updateSkipping (dereference write)
    │     ├── SWhile: recursive loop
    │     ├── SFun/SFunLt: store closures in evalFuns
    │     ├── SSpawn: interpBlock (synchronous)
    │     └── list mutation: SPush, SInsert, SRemove, SIndexAssign
    │
    └── Interp.Expr.interp     src/Interp/Expr.hs
          ├── EVar: simple lookup
          ├── ERef/ERefMut: store variable name
          ├── EDeref: follow name to value
          ├── ECall: push scope, bind params, run body, pop scope
          ├── EMatch: tryMatch, bind pattern vars, run arm body
          └── helpers: arithm, logicOp, eqOp, cmpOp, listGet
        │
        ▼
  Either String Value   (Left = runtime error, Right = final value)
        │
        ▼
  printTree value       grammar/Lang/Print.hs (generated)
        │
        ▼
  Output to stdout
```

### Shared infrastructure (used by both halves)

```
ScopeStack.hs  ──────────────────────── both TcCtx._tcVars and EvalCtx._evalVars
Context.hs     ──────────────────────── TcCtx, EvalCtx, VarInfo, lenses (view/over/set)
Value.hs       ──────────────────────── Value, TClosure, Closure, isCopyable, eraseLifetime
Tc.hs / Eval.hs ─────────────────────── Tc monad, Eval monad (ExceptT String (State ...))
Logger.hs      ──────────────────────── background logging (Main.hs only)
Env.hs         ──────────────────────── thin alias (unused; retained for compatibility)
```

---

## 18. Design Decisions Summary

| Decision | What we chose | Why | Trade-off |
|---|---|---|---|
| **Scope structure** | `ScopeStack [Map Ident a]` | O(1) push/pop; `updateStack` correctly propagates mutation to outer scopes; persistent (no mutation in Haskell) | Lookup is O(d · log n) for nesting depth d, but d is small in practice |
| **Ownership tracking** | `VarInfo` with integer counters (`varBorrows`, `varMutBorrows`) | Single source of truth; counter check for exclusivity is O(1) (`> 0`); simpler than a borrow graph | Counter doesn't identify *which* specific reference holds a borrow; error messages are slightly less precise than a set-based design |
| **Monad stack** | `ExceptT String (State TcCtx)` | Exactly two effects needed: mutable state + short-circuiting errors. The transformer stack composes them without boilerplate | Adding more effects (e.g., IO) would require additional transformer layers |
| **Lenses** | Hand-rolled van Laarhoven lenses (5 total) | Avoids the huge `lens` library and Template Haskell compilation; fully transparent and understandable | Doesn't scale to large codebases with dozens of fields; no auto-derive |
| **NLL** | Syntactic `mentionedVars` over-approximation | Avoids constructing a control-flow graph; sound (never misses a live borrow) | Incomplete: borrows stay live longer when a variable appears in a dead branch (e.g., unreachable else branch) |
| **References at runtime** | `VRef Ident` (store the name, not the value) | Simple; follows the scope stack naturally; no heap allocation needed | Dereferencing requires a scope-stack lookup; doesn't model raw memory addresses |
| **Synchronous `spawn`** | `interpBlock body` — run the spawn block exactly like a regular block | Keeps `Eval` pure; deterministic tests; type safety guarantee is in the type checker, not the runtime | Not truly concurrent; a real concurrent runtime would need `forkIO` and lifting `Eval` into `IO` |
| **`isCopyable` as a predicate** | A simple recursive function on `Type` | Separates the semantic question ("can this type be shared?") from every check that needs it; used in `EVar`, `spawn`, list element checking | Has to be kept in sync with any new types added to the language |
| **`Const` applicative for NLL** | Instantiate `Map.traverseWithKey` with `Const` instead of `Identity` | Reuses the traversal abstraction as a fold; no extra traversal function; no intermediate allocations | Requires understanding the van Laarhoven / applicative functor abstraction; less obvious than a plain `filter` |
| **Borrow direction tracking** | Both `varBorrows` on the *borrowee* AND `varBorrowOf` on the *borrower* | `varBorrows` allows O(1) exclusivity check; `varBorrowOf` allows cleanup when the *borrower* leaves scope | Two pieces of state must be kept consistent; bugs in release logic could corrupt both |

---

*This document covers the complete codebase: ~1200 lines of Haskell across 15 source files, implementing a Rust-inspired ownership type system from scratch. All 291 tests pass.*
