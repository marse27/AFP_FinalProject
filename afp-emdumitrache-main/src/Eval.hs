-- Interpreter monad: ExceptT for runtime errors
module Eval
  ( Eval
  , runEval
  ) where

import Control.Monad.Except (ExceptT, runExceptT)
import Control.Monad.State  (State, evalState)
import Context (EvalCtx)

-- This is the monad used by the interpreter.
-- It can return a runtime error message if evaluation fails, and it can also update the runtime context while the program runs.
type Eval a = ExceptT String (State EvalCtx) a

-- Here we run an evaluation action starting from a given context.
-- The final result is either a runtime error message or the evaluated result.
runEval :: EvalCtx -> Eval a -> Either String a
runEval ctx m = evalState (runExceptT m) ctx
