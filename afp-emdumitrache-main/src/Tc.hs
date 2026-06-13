-- Type-checker monad: ExceptT for type errors layered over State for the
-- typing context. All TypeCheck.* modules run inside this stack.
module Tc
  ( Tc
  , runTc
  ) where

import Control.Monad.Except (ExceptT, runExceptT)
import Control.Monad.State  (State, evalState)
import Context (TcCtx)

-- This is the monad used by the type checker. 
-- It can return an error message if type checking fails, and it can also update the type-checking context while running.
type Tc a = ExceptT String (State TcCtx) a

-- Here we run a type-checking action starting from a given context. 
-- The final result is either an error message or the checked result.
runTc :: TcCtx -> Tc a -> Either String a
runTc ctx m = evalState (runExceptT m) ctx
