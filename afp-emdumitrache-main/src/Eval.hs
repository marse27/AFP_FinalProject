-- | Interpreter monad: ExceptT for runtime errors layered over State for the
-- evaluation context. All Interp.* modules run inside this stack.
module Eval
  ( Eval
  , runEval
  ) where

import Control.Monad.Except (ExceptT, runExceptT)
import Control.Monad.State  (State, evalState)
import Context (EvalCtx)

-- | The interpreter monad: error + mutable evaluation context.
type Eval a = ExceptT String (State EvalCtx) a

-- | Run an evaluation action from an initial context.
runEval :: EvalCtx -> Eval a -> Either String a
runEval ctx m = evalState (runExceptT m) ctx
