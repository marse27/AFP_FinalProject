# AFP Language Project

This project is a template for implementing the final project of Advanced Functional Programming at the TU Delft.
It contains a grammar definition for a small language, its type checker, and its interpreter.

The repository consists of the following components:

* `app`: the home directory for the executable (contains only the `Main.hs` function)
* `grammar`: the grammar library, automatically generated using [BNFC](https://bnfc.readthedocs.io/) from the `Lang.cf` file
* **`src`:** contains source code for the `lang` library
* `test`: the test suite

## Building, Running, and Testing

You will need to have Cabal installed for this project.

### Setup BNFC

Once done, use cabal to install BNFC:

```
cabal update
cabal install BNFC --overwrite-policy=always
```

*TIP:* Install the [LBNF](https://marketplace.visualstudio.com/items?itemName=agurodriguez.vscode-lbnf) extension for VS Code for syntax highlighting on `.cf` files.

### Building

To build the grammar library, use BNFC to generate the Haskell files into the `grammar/` directory:

```
bnfc -d grammar/Lang.cf -o grammar
```

Then, build the whole project using cabal:

```
cabal build
```

Optionally, you can install the executable `afp-lang` on your system globally:

```
cabal install --overwrite-policy=always
```

### Running

To run the project, your grammar library needs to be generated (see [Building](#building)).
To run an interactive interpreter where you can input programs and have them immediately evaluated, simply run

```
cabal run
```

To run the interpreter on a program in a file, pass the path to the file as a parameter to cabal, e.g.:

```
cabal run exes -- examples/sample.afp
```

### Testing

To run the test suite, your grammar library needs to be generated (see [Building](#building)).
Then, simply run

```
cabal test
```

### Makefile

If you have `make` available, you can use the following commands to interact with the project:

```bash

make build              # building the project
make install            # installing afp-lang executable (optional)
make run                # running the interactive interpreter
make run FILE="<path>"  # running the interpreter on a program file
                        # e.g. make run FILE="examples/sample.afp"

make test               # running the test suite

make clean              # cleans all generated files and cabal
```

## Language Specification

A program in this language consists of an arbitrary number of statements separated by `;`.
A valid program looks like this (available in `examples/sample.afp`):

```haskell
val x = 3;
val y = 5;
fun orFalse (a : Bool) = a || False;
val z = x + y < 10;
res = orFalse(z);
res;
```

The language supports the following statements:

* variable binding (`val x = 7;`),
* function declaration (`fun plus_two (x : int) = x + 2;`),
* function calls (`y = plus_two(x)`),
* return statements (`y > 8`), which should only appear as the final statement in a program.

as well as the following expressions:

* integers (`1`, `-23796`) and integer operations:
  * addition (`+`),
  * subtraction (`-`),
  * multiplication (`*`), and
  * division (`/`),
* booleans (`True` and `False`) and boolean operations:
  * "and" (`&&`),
  * "or" (`||`), and
  * "not" (`!`),
* comparison operations:
  * "equal to" (`==`),
  * "less than" (`<`) and "less than or equal to" (`<=`), and
  * "greater than" (`>`) and "greater than or equal to" (`>=`),
* branching (`if ... then ... else ...`),
* variables (`x`, `y`),
* let bindings (`let x = ... in ...`), and
* brackets (`(...)`).

Orders of operation follow these priority levels (`0` being lowest and `8` being highest):

```
0:  (==)  equal to
1:  (||)  or
2:  (&&)  and
3:  (!)   not
          booleans*
4:  (<)   less than
    (<=)  less than or equal to
    (>)   greater than
    (>=)  greater than or equal to
5:  (+)   addition (+)
    (-)   subtraction (-)
6:  (*)   multiplication
    (/)   division
7:        integers*
8:        brackets
          branching
          let bindings
          variables
```

`*`: types must have the same priority level than the highest one in which they are used

