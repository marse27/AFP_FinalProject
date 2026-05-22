module Interp.Prog where

import Evaluator

import Env
import Value ( Value
             , Closure )

import Lang.Abs ( Program( Program )
                , Stmt( .. ) )

import qualified Interp.Stmt as S
import qualified Interp.Expr as E

-- PROGRAM INTERPRETER ---------------------------------------------------------------

interp :: Evaluator Value Closure
interp (Program []) env = throw "Missing return statement"
interp (Program [SRet exp]) env = E.interp exp env
interp (Program (stmt:prog)) env = do
  nenv <- S.interp stmt env
  interp (Program prog) nenv
