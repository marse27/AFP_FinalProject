# Project 2: An Ownership Type System for Memory Safety

This project requires you to implement an ownership type system with which programmers can ensure memory safety in their programs.
The expected functionality will be presented in [Rust](https://www.rust-lang.org/), but remember that you are free to design your language however you find suitable (i.e., you do not have to follow Rust's syntax).
If you are not sure how certain features should work, we recommend playing around with Rust and using it to determine expected behaviour.
You may deviate from this behaviour, if you can explain the reasoning behind your choices.

This project has five phases:
* `[0]` [Extending the Language](#phase-0-extending-the-language)
* `[1]` [Affine Types](#phase-1-affine-types)
* `[2]` [Lists and Copyable Primitives](#phase-2-lists-and-copyable-primitives)
* `[3]` [Borrowing & Lifetimes](#phase-3-borrowing--lifetimes)
* `[4]` [Threads](#phase-4-explicit-lifetimes-or-multithreading)

## Phase 0: Extending the Language

To start off with this project, you will need to extend the provided language with a few more constructs: (1) mutable variables, (2) control-flow statements, and (3) more complex functions.

### (1) Mutable Variables

The current language contains no way to mutate variables, and as such, all of them are immutable by default.
Add a way to distinguish between declaring an immutable and mutable variable, and a way to reassign the value of a mutable variable.

**Note.** Due to the simplified way of handling ownership explained in phase
one, it should not be allowed to return a reference to a new (mutable or
immutable) variable from a function. This restriction can be removed if you
implement explicit lifetimes in phase three.

<details><summary>Immutable Variables</summary>

```rust
let imm_var = 0;
imm_var = 1; // error! "Cannot assign a new value to an immutable variable more than once"
```

</details>

<details><summary>Mutable Variables</summary>

```rust
let mut mut_var = 0;
mut_var = 1;
```

</details>

### (2) Blocks and Control-Flow Statements

Your language should support blocks of statements surrounded by curly braces.
Any variables that are declared within a block should not be accessible from outside the block.
However, modifications to mutable variables declared outside the block should be kept.

<details><summary>Blocks</summary>

```rust
let mut x = 0;
{
    let y = 5;
    x = y;
};
x
```

This should return 5. Using `y` as the final expression instead should be an error.
</details>

The language already contains `if_then_else_` *expressions*, but you should also add `if_then_` and `if_then_else_` *statements*.
Additionally, your language should have a loop construct (e.g., a `while` loop).

<details><summary>If-Then</summary>

```rust
if x < 1 {
    y = 1;
}
```

</details>

<details><summary>If-Then-Else</summary>

```rust
if x < 1 {
    y = 1;
} else {
    y = 2;
}
```

Note that the following two programs should have equivalent behaviour:

```rust
let mut y = 0;
if x < 1 {
    y = 1;
} else {
    y = 2;
}
y
```

```rust
if x < 1 {
    1
} else {
    2
}
```

</details>

<details><summary>While Loop</summary>

```rust
while x < 10 {
    x = x + 1;
}
```

</details>

### (3) More Complex Functions

Extend function definitions with the following features:
* function bodies can contain statements,
* a function can take 0, 1, or many parameters,
* a parameter can be mutable.

You might want to change the syntax to require explicit type annotations for the function's return type.

<details><summary>Statements in Function Bodies</summary>

```rust
fn double(x: i32) -> i32 {
    let y = x * 2;
    y
}

fn two_or_thirteen(x: bool) -> i32 {
    if x {
        2
    } else {
        13
    }
}
```

</details>

<details><summary>Varying Parameter Amounts</summary>

```rust
fn no_arg() -> i32 {
    42
}

fn plus(x: i32, y: i32) -> i32 {
    x + y
}
```

</details>

<details><summary>Mutable Parameters</summary>

```rust
fn double_in_place(mut x: i32) -> i32 {
    x = x * 2;
    x
}
```

</details>


## Phase 1: Affine Types

> **Note:**
> The behaviour described in this phase is only replicable with non-primitive types in Rust (see Phase Two).
> As such, all examples use a simple `Light` type which has exactly three possible values: `Red`, `Yellow`, and `Green`.

An "affine" type system allows each variable to be used at most once.
You can intuitively think of this as "each variable is *consumed* when used".
The following is a simple example of this behaviour:

```rust
let light = Light::Red;
do_something(light);
do_something(light); // error!
```

The `do_something` function on line 2 *consumes* the `light` variable, and as a result, line 3 will throw a "Value used after being moved" error.
In Rust, this behaviour is called "transferring ownership".
In the following example, binding `a` transfers the ownership of value `Light::Red` to binding `b` on line 2
    and is therefore not allowed to use it on line 3.

```rust
let a = Light::Red;
let b = a;
do_something(a); // error!
```

However, reassigning this variable and then using it again should not throw any errors:

```rust
let light = Light::Red;
do_something(light);
let light = Light::Yellow;
do_something(light);
```

Assigning a new value to a mutable binding gives that binding ownership over the new value.

```rust
let mut a = Light::Red;
let mut b = Light::Yellow;

b = a;
a = Light::Green;

do_something(a); // a is Green
do_something(b); // b is Red
```

This is why the following piece of code is valid (parameter `light` in function `change` takes ownership over the original value in `x`, but `x` is given ownership over the resulting value):

```rust
fn change(light: Light) -> Light { ... }

let mut x = Light::Red;
x = change(x);
```

### More Examples

<details><summary>You cannot transfer ownership twice.</summary>

```rust
let a = Light::Red;
let b = a;
let c = a; // error!
```

</details>

<details>
<summary>
You <emph>can</emph> transfer ownership from <code>a</code> to <code>b</code> and then bind <code>a</code> to a new value.
Both bindings will then own a value.
</summary>


```rust
let a = Light::Red;
let b = a;
let a = Light::Yellow;
do_something(a);
do_something(b);
```

</details>

<details><summary>Calling a function is also transferring ownership: you are transferring the value to the parameter of the function</summary>

```rust
let d = Light::Yellow;
do_something(d);
let e = d; // error!
```

</details>

<details><summary>
You can transfer ownership from an immutable to a mutable binding and vice versa.
The current owner determines whether the value is mutable.
</summary>

```rust
let a = Light::Red; // immutable
let mut b = a;      // mutable
let c = b;          // immutable
```

```rust
fn immutable(light: Light) {...}

fn mutable(mut light: Light) {...}

let imm_light = Light::Red;
immutable(imm_light);

let imm_light = Light::Red;
mutable(imm_light);

let mut mut_light = Light::Yellow;
immutable(mut_light);

let mut mut_light = Light::Yellow;
mutable(mut_light);
```

</details>

## Phase 2: Lists and Copyable Primitives

### Feature 2A: Lists

Extend the language with (polymorphic) lists.
To start with, you should only allow lists of value types such as `int` or `bool`.
(To soundly handle lists of reference types, you first need explicit lifetimes as in phase three.)
The following operations should be available on lists:
* **non-mutating:**
  * extracting the element at a certain index (`let x = list[0]`),
* **mutating:**
  * assigning an element at a certain index (`list[0] = x`),
  * adding an element to the end of the list (`list.push(13)`),
  * adding an element to a certain index of the list (`list.insert(0, 13)`), and
  * removing an element from a certain index in a list (`list.remove(1)`).

Mutating a vector or any of its elements should only be possible if that vector is bound to a mutable variable!

> **Note:**
> Lists in Rust are called vectors.
> To compose the list `[1, 2]`, you can use the `vec![1, 2]` macro.

<details><summary>Immutable List</summary>

```rust
let imm_list = vec![1, 2];
let snd = imm_list[1];

imm_list.push(4); // error!
imm_list[0] = 4;  // error!
```

</details>

<details><summary>Mutable List</summary>

```rust
let mut mut_list = vec![1, 2];  // [1, 2]
mut_list.push(3);               // [1, 2, 3]
mut_list[0] = 4;                // [4, 2, 3]
mut_list.remove(2);             // [4, 2]
let snd = mut_list[1];          // 2
mut_list.insert(1, 13);         // [4, 13, 2]
```

</details>

### Feature 2B: Copyable Primitives

Unlike lists, primitives such as integers and booleans are very cheap to copy.
This means that we can make life easier for ourselves and instead of *transferring ownership* of primitives to new bindings, we can simply give these bindings a new copy of the value.
For example, in the following example, `x` never loses ownership of its value - it simply provides a copy for the parameter of `do_something` as well as for binding `y`:

```rust
let x = 0;
do_something(x);
do_something(x);
let y = x;
do_something(x);
```

Implement this behaviour for `ints` and `bools` but **not** for functions or lists.

### Feature 2C: Result and pairs

Add other structures to the language, such as:
* A `Result` type, which either contains a value or an error,
* *Pairs*, which can be primitive if both components are primitive.

You might also want to add *pattern matching*!

## Phase 3: Borrowing & Lifetimes

To start off the final phase, let's define some terms:

* **Binding:** A *binding* holds a value of a certain type.
  Mutable bindings can mutate their values to different values of the same type.
* **Ownership:**
  The *binding* which *owns* a value has full control over it and decides whether that value is mutable.
* **Scope:**
  A *binding* is in *scope* from the moment it is declared, until the end of the block.
* **Lifetime:**
  A *value's lifetime* begins when it is created (e.g., when it is bound)
    and ends when its *owner* goes out of *scope*`*`.
  A *value* is **alive** if its *lifetime* has begun but not ended.
* **Destruction:**
  When a *value's lifetime* ends, it can be safely *destroyed*, i.e. erased from memory.

```rust
fn do_things(light: Light) {
                            // continues living            +---+
                            //                             |   |
    do_something(light);    // is destroyed here when  <---+   |
}                           // owner goes out of scope         |
                            //                                 |
let a = Light::Yellow;      // lifetime starts here     ---+   |
                            //                             |   |
                            // continues living            |   |
                            //                             |   |
do_something(a);            // changes owners              +---+

                            // is not alive here anymore
```

> `*` Rust actually lets a value's lifetime end directly after it's point of usage.
> See the [Artificial Blocks](#artificial-blocks) section for an explanation of *why*.
> Unfortunately, this does mean that some examples do not work exactly as presented in Rust.

In many cases, passing ownership (pass-by-value) is just too restrictive and might not even be necessary - values can instead be *borrowed* (pass-by-reference).
The type checker must then guarantee that these borrowed references always point to a valid value,
    meaning that while a reference exists, the original value cannot be destroyed.
There are two types of borrows:

### Feature 3A: Immutable Borrows

**Immutable borrows** provide read access to the value they are referencing.
You can make an *unlimited* amount of immutable borrows for one value.

```rust
fn do_something_borrowed(light: &Light) { ... }

let a = Light::Red;         // a : Light
let b = &a;                 // b : &Light (borrowed from a)
let c = &a;                 // c : &Light (borrowed from a)
do_something_borrowed(b);
do_something_borrowed(c);
```

<details><summary>An (immutable or mutable) borrow `x` can be dereferenced with `*x`.</summary>

```rust
let a = 21;
let b = &a;
*b  // = 21
```

</details>

### Feature 3B: Mutable Borrows

**Mutable borrows** provide read and write access to the value they are referencing.
They can only be made on values with mutable owners.

```rust
let mut a = Light::Red;
let b = &mut a;

let c = Light::Red;
let d = &mut c; // error! Cannot borrow immutable local variable `c` as mutable
```


<details><summary>A mutable borrow `x` can be mutated with `*x = ...`.</summary>

```rust
let mut a = 21;
let b = &mut a;
*b = *b + *b;
*b   // = 42
```

</details>


<details><summary>Functions should be able to take (immutable and mutable) borrows as arguments.</summary>

```rust
fn set_red(light: &mut Light) {
    *light = Light::Red
}
let mut light = Light::Green;
set_red(&mut light);
light  // returns Red
```

Note that the function `set_red` does not have a return type. If your language
does not already support this, we recommend that you add a void type `()` and
use this as the default return type for functions lacking an explicit return
type.
</details>


<details>
<summary>
    Mutable borrows are <emph>exclusive</emph>, meaning that there may be no other borrow for this value as long as the mutable borrow is alive.
</summary>

```rust
let mut a = Light::Red;
let b = &mut a;
let c = &mut a; // error! Cannot borrow `a` as mutable more than once at a time
```

While a mutable borrow is alive, there cannot be any immutable borrows either.

```rust
let mut a = Light::Red;
let b = &mut a;
let c = &a; // error! Cannot borrow `a` as mutable more than once at a time
```

You cannot create a mutable borrow while an immutable borrow is alive.

```rust
let mut a = Light::Red;
let b = &a;
let c = &mut a; // error! Cannot borrow `a` as mutable because it is also borrowed as immutable
```

</details>


#### Some Clarifications

For a value of type `T`, an immutable borrow has type "reference to `T`" and a mutable borrow has type "reference to `T`".
References are just a different type of value.
If a *binding* borrows a value, that binding becomes the *owner* of the reference to the value but **not** of the value itself.
Just as with normal values, a reference (a "borrow") is alive as long as its *owner* is in *scope*.

Mutable borrows can be changed to immutable borrows, but not vice versa.
The table below shows which bindings `x` can transfer ownership of their values to bindings `y`:

|    `x` ↓  `y` → | `a : A` | `mut a : A` | `a : &A` | `mut a : &A` | `a: &mut A` | `mut a: &mut A` |
|----------------:|:-------:|:-----------:|:--------:|:------------:|:-----------:|:---------------:|
|         `a : A` |    ✓    |      ✓      |          |              |             |                 |
|     `mut a : A` |    ✓    |      ✓      |          |              |             |                 |
|        `a : &A` |         |             |     ✓    |       ✓      |             |                 |
|    `mut a : &A` |         |             |     ✓    |       ✓      |             |                 |
|     `a: &mut A` |         |             |     ✓    |       ✓      |      ✓      |        ✓        |
| `mut a: &mut A` |         |             |     ✓    |       ✓      |      ✓      |        ✓        |

A value is *borrowed* as long as at least one of its *borrows* is alive.
While a value is *borrowed*, its owner may not manipulate it in any way.

```rust
let a = Light::Red;
let b = &a;

do_something(a);    // error! Cannot move out of `a` because it is borrowed
a = Light::Yellow;  // error! Cannot assign to `a` because it is borrowed
```

A mutable binding of a reference can be assigned a new value but only a mutable borrow can mutate the referenced value.

```rust
let a = Light::Red;
let mut b = &a;
b = &Light::Yellow; // ok

let mut c = Light::Red;
let d = &mut c;
d = &mut Light::Yellow; // error! Cannot assign a new value to an immutable variable more than once
```

#### Borrowing and lifetimes

For the basic version of this project, you can assume that a value's lifetime
ends when its owner goes out of scope. In particular, your language should
ensure that a borrow (whether it is immutable or mutable) never outlives the
value that it is referencing.

```rust
let x = 6;
let mut y = &x;
{
    let z = 12;
    y = &z;     // this should error
}   // z goes out of scope here
*y  // use after free
```

As long as there is any borrow of a value still active, moving that value should
not be allowed. For example, in the following snippet, the type checker throws
an error on the `do_something(a)`, because the value that `a` owns is borrowed
by `b` and the borrow in `b` is still alive because `b` has not gone out of
scope.

```rust
fn foo() {
    let a = Light::Red;
    let b = &a;
    do_something_borrowed(b);
    do_something(a); // error! Cannot move out of 'a' because it is borrowed!

    // some other code not using b
}
```

Since blocks have their own local scope, and bindings declared inside them go
out of scope when the block ends - anything (including borrows) owned by these
bindings also reaches the end of its lifetime. This can be used to fix the code
above:

```rust
fn foo() {
    let a = Light::Red;
    {
        let b = &a;
        do_something_borrowed(b);
    } // scope of b and lifetime of the borrow in b end here

    do_something(a);

    // some other code not using b, since b is not in scope
}
```

This restriction can be relaxed if you implement non-lexical lifetimes (see below).

Finally, it should not be allowed to return a (immutable or mutable) borrow from
a function. Allowing this would cause problems because the lifetime of the
returned borrow could be unknown or could even be dependent on other inputs.

```rust
fn choose(b : bool, x : &Light, y : &Light) -> &Light {
    if b { return x } else { return y };
}
let b = true;
let mut x = Light::Red;
let x_ref = &x;
{
    let y = Light::Green;
    let y_ref = &y;
    x = *choose(b, x_ref, y_ref); // lifetime depends on value of b
}
x
```

Returning borrows from a function can be allowed if you implement explicit
lifetime annotations (see phase 4).


### Feature 3C: Non-Lexical Lifetimes

To make borrowing less restrictive and easier to use, you can add support for
non-lexical lifetimes. With non-lexical lifetimes, the lifetime of a value or
reference should end at the point of their last usage, instead of when it goes
out of scope. Consult Rust's features report on [non-lexical
lifetimes](https://rust-lang.github.io/rfcs/2094-nll.html).

```rust
fn do_something(light: Light) { ... }
fn do_something_borrowed(light: &Light) { ... }

let a = Light::Red;         // a : Light
let b = &a;                 // b : &Light (borrowed from a)
let c = &a;                 // c : &Light (borrowed from a)
do_something_borrowed(b);   // b no longer used after this, so lifetime ends
do_something_borrowed(c);   // c no longer used after this, so lifetime ends
let d = a;                  // d : Light (ownership moved from a)
let e = &d;                 // e : &Light (borrowed from d)
do_something_borrowed(e);   // e no longer used after this, so lifetime ends
do_something(d);            // ownership moved to parameter of do_something
```



## Phase 4: Explicit lifetimes or multi-treading

### Feature 4A: Explicit Lifetime Annotations

Though Rust has some shortcuts for common patterns built in, by default you have to explicitly annotate lifetimes of function parameters and return values.
For example, consider the following code snippet:

```rust
fn foo<'a>(input: &'a Light) -> &'a Light { ... }
fn remove(input: Light) { ... }

let input = Light::Red;
let right = Light::Yellow;
let output = foo(&input);
do_something_borrowed(output);
remove(input); // error! Cannot move out of `input` because it is borrowed
do_something_borrowed(output);
```

The lifetime annotations on the `foo` function indicate that the return value is a reference to a value with the same lifetime as the value referenced in `input`.
This means that `input` cannot be destroyed before the lifetime of `output` ends.

However, the following code snippet will *not* throw an error because the lifetime of the return value does not depend on the lifetime of `right`:

```rust
fn foo<'a, 'b>(left: &'a Light, right: &'b Light) -> &'a Light { ... }
fn remove(input: Light) {}

let left = Light::Red;
let right = Light::Yellow;
let output = foo(&left, &right);
do_something_borrowed(output);
remove(right);
do_something_borrowed(output);
```

This does, of course, restrict how you can use `right` within the `foo` function:

```rust
fn foo<'a, 'b>(left: &'a Light, right: &'b Light) -> &'a Light {
    return right; // error!
                  // lifetime may not live long enough
                  // function was supposed to return data with lifetime `'a`
                  //    but it is returning data with lifetime `'b`
}
```

For some more intuition on lifetimes, see
* [Rust's documentation on lifetimes](https://doc.rust-lang.org/beta/rust-by-example/scope/lifetime.html) or
* [this response](https://www.reddit.com/r/rust/comments/1ck2716/comment/l2kdij3/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button) to a Reddit question.

### Feature 4B: Multi-threading

Ownership type should guarantee memory safety and as such, multi-threading should not cause any memory issues such as data races or deadlocks.
Implement multi-threading for your language!

The main goal here is to implement multi-threading as a user-facing feature in your language, for example by having a primitive function to fork a new thread. It is not necessary that the evaluator actually uses multi-threading to execute these programs, you can instead also choose to use interleaving of the instructions on a single thread.
