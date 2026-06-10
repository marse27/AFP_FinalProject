-- | Type-check a whole program; returns the type of its final expression.
module TypeCheck.Prog (infer) where

import Control.Monad.Except (throwError)
import Lang.Abs (Program (..), Stmt (..), Type)
import Tc       (Tc)
import qualified TypeCheck.Stmt as S
import qualified TypeCheck.Expr as E

-- | Infer the return type of a program (must end with a bare expression).
infer :: Program -> Tc Type
infer (Program [])         = throwError "Missing return statement"
infer (Program [SExpr e])  = E.infer e
infer (Program (s : rest)) = S.infer s >> infer (Program rest)
