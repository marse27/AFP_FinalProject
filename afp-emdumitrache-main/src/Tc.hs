-- | Type-checker monad: ExceptT for type errors layered over State for the
-- typing context. All TypeCheck.* modules run inside this stack.
module Tc
  ( Tc
  , runTc
  ) where

import Control.Monad.Except (ExceptT, runExceptT)
import Control.Monad.State  (State, evalState)
import Context (TcCtx)

-- | The type-checker monad: error + mutable typing context.
type Tc a = ExceptT String (State TcCtx) a

-- | Run a type-checking action from an initial context.
runTc :: TcCtx -> Tc a -> Either String a
runTc ctx m = evalState (runExceptT m) ctx
