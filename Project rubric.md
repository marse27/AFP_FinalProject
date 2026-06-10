# AFP project rubric

This document explains how your grade for the project will be determined. Some
of the requirements depend on whether you are working alone or in a group of
two. For those requirements, the requirement for a group of two is marked
between [square brackets].

To get a 6:

- Implement all features of phase 0 and 1. To count as implemented, each feature
  should come with associated tests (both positive and negative ones).
- Include a description of how you used each of the required techniques
  (persistence, lenses, transformers/effects, [concurrency]) in your project.
- Have basic documentation describing the purpose of each module in your
  project and the important functions in it.
- Give a demo presentation of your implementation.

To get to 7:

- meet all the requirements for a 6
- implement at least 2 [3] features from phase 2

To get to 8:

- meet all the requirements for a 7
- implement at least 1 [2] feature from phase 3

To get to 9:

- meet all the requirements for a 8
- implement one additional feature from phase 3 (total 2 [3])
- make advanced* usage of at least one of the required techniques in the project

To get to 10:

- meet all the requirements for a 9
- implement at least 1 [2] of the features of phase 4

Finally, you can earn +0.5 bonus on your grade for each of the following (for a
total of +1.0, with a cap of 10.0):

* you have comprehensive documentation of all the types, monads, and top-level
  functions in your implementation
* your answers to the questions at the demo presentation are correct and
  complete

(*) With 'advanced usage' we mean for example:
  * Implement a new data structure that you use persistently throughout your
    type checker (not just in one place).
  * Define your own monad transformer or effect functor and a handler for it,
    and use it throughout your implementation (not just defining a monad by
    combining transformers from the library).
  * Implement a custom optic, or use optics in a structurally non-trivial way
    (e.g., a traversal that drives a real transformation in your type checker,
    not just field access).
