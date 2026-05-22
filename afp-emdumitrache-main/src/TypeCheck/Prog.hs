module TypeCheck.Prog where

import Evaluator

import Env

import Value ( TClosure )

import Lang.Abs ( Program( Program )
                , Stmt( .. )
                , Type )

import qualified TypeCheck.Stmt as S
import qualified TypeCheck.Expr as E
import qualified Lang.ErrM as S

-- PROGRAM TYPE CHECKER --------------------------------------------------------------

infer :: Evaluator Type TClosure
infer (Program []) env = throw "Missing return statement"
infer (Program [SRet exp]) env = E.infer exp env
infer (Program (stmt:prog)) env = do
  nenv <- S.infer stmt env
  infer (Program prog) nenv
