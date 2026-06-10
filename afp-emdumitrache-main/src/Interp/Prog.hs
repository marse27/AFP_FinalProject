-- | Interpreter for whole programs; returns the value of the final expression.
module Interp.Prog (interp) where

import Control.Monad.Except (throwError)
import Lang.Abs (Program (..), Stmt (..))
import Value    (Value)
import Eval     (Eval)
import qualified Interp.Stmt as S
import qualified Interp.Expr as E

-- | Evaluate a program and return its final value.
interp :: Program -> Eval Value
interp (Program [])         = throwError "Missing return statement"
interp (Program [SExpr e])  = E.interp e
interp (Program (s : rest)) = S.interp s >> interp (Program rest)
