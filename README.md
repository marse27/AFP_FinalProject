# AFP Project: Implementing an advanced type system

This is the assignment for the final project of the Advanced Functional Programming course (CS4565).
The goal of this project is for you to implement a type checker and interpreter
for a small language with an advanced type system.

This project can be made either individually or in groups of two.
You are allowed to discuss the assignment with other students and ask general questions.
However, you should avoid sharing complete or partial solutions with other students.
See www.tudelft.nl/en/student/legal-position/fraud-plagiarism/ for the general TU Delft policy regarding fraud.

You will choose one of two projects to implement for your assignment:
1. an [Agda](https://agda.readthedocs.io/en/latest/index.html)-like language
   with [dependent types](./projects/1-dependent-type-checker.md) for those
   interested in formal methods and proof assistants, or
2. a [Rust](https://www.rust-lang.org/)-like language with [ownership
   types](./projects/2-ownership-type-system.md) for those interested in the
   practical applications of advanced types.

The instructions consist of a number of phases, of which you should at least
implement phases 0 and 1. Implementing features from higher phases will lead to
a higher grade, where the required number of features depends on whether you are
working alone or in a group of two (see rubric).

While the instructions in each project give examples from their respective
inspiration languages, we encourage you to design your own syntax and make this
language your own!

To start with, you are given a **template** of a small language implemented in
Haskell that you can adapt. It includes a grammar, a type checker, an
interpreter, and a test suite. It is meant as a starting point, but you are free
to modify or delete anything you want about it, or even to not use it at all.

You are required to use **each of the following techniques** at least once in your project:

* persistent usage of a purely functional data structure (queue, heap, tree, heap...),
* lenses and/or traversals,
* monad transformers and/or free monads, and
* only if working in a group of 2: concurrency (e.g. for logging).

**Final deliverables** include

* your implementation in Haskell which should include
  * a type checker for your language,
  * an interpreter for your language,
  * an accompanying test suite with positive and negative tests for each of the features you have implemented, and
  * comments explaining the purpose of each module and the important functions in it
* a design / architecture overview document (in Markdown of PDF format) that includes:
  * a description of the syntax of your language
  * an overview of all the features you implemented
  * two or three example programs demonstrating how it works in practice
  * an explanation of how each of the required techniques above are used in the project
* an in-person demonstration of your project where you should answer questions about its design and implementation

During the demo session itself, you should:

* Give an overview of the grammar of your language and the features you implemented, using some example programs.
* Give a global overview of the implementation of the type checker and evaluator, explaining any important design decisions or challenges that came up during the implementation.
* Explain how you used the three/four required techniques for the project.

You can either prepare a few slides or just prepare some example code and present it directly from your IDE.

There are two deadlines for the project:

- You should submit a first version by the end of week 8 (**14th of June at 23:59**). This is the version that we'll look at for the demo presentation.
- After the demo presentation you can still make changes based on the feedback you got, the deadline for these changes is at the end of week 10 (**28th of June at 23:59**). This is the version that will determine your final grade.

Some recommendations for working on the project:

* The template uses a basic `Either` monad to propagate errors. It is
  recommended to replace this with your own monad (or multiple monads) that
  provides more functionality such as accessing and updating the environment,
  printing debug logs, etc.
* When writing error messages for the type checker, please use the `prettyTree`
  function from the `Lang.Print` module instead of `show`.
* The type checking tests in the template only check whether the type checker
  accepts or rejects a given program. It is recommended to also add tests that
  ensure that the correct error message is printed on ill-typed test cases.
* The template project has separate syntactic categories for expressions and
  statements. If this separation proves to be annoying, you are free to merge
  these into a single syntactic category.
