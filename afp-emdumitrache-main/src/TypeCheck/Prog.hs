module TypeCheck.Prog (infer) where

import Control.Monad.Except (throwError)
import Lang.Abs (Program (..), Stmt (..), Type)
import Tc       (Tc)
import qualified TypeCheck.Stmt as S
import qualified TypeCheck.Expr as E

-- Here we type-check the whole program.
-- A program must end with an expression, because that expression gives the final result type of the program.
-- Each statement is checked one by one.
-- After each statement, borrows that are not used anymore are released early.
infer :: Program -> Tc Type
infer (Program [])         = throwError "The program is missing a return statement"
infer (Program [SExpr e])  = E.infer e
infer (Program (s : rest)) = do
  S.infer s
  S.releaseExpiredBorrows (S.mentionedVars rest)
  infer (Program rest)
