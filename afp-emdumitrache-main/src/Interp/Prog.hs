-- Interpreter for whole programs, it returns the value of the final expression.
module Interp.Prog (interp) where

import Control.Monad.Except (throwError)
import Lang.Abs (Program (..), Stmt (..))
import Value    (Value)
import Eval     (Eval)
import qualified Interp.Stmt as S
import qualified Interp.Expr as E

-- Here we evaluate the whole program. 
-- A program must end with an expression, because that expression gives the final value of the program. 
-- Each statement before that is executed in order.
interp :: Program -> Eval Value
interp (Program [])         = throwError "The program is missing a return statement"
interp (Program [SExpr e])  = E.interp e
interp (Program (s : rest)) = S.interp s >> interp (Program rest)
