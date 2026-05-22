module Interp.Stmt where

import Evaluator

import Lang.Abs ( Stmt(..) )

import Env
import Value ( Value
             , Closure( Fun ) )

import qualified Interp.Expr as E

-- STATEMENT INTERPRETER -------------------------------------------------------------

interp :: Stmt -> (Env Value, Env Closure) -> Result (Env Value, Env Closure)

interp (SLet x e) env@(vars, funs) = do
    val <- E.interp e env
    return (bind x val vars, funs)

interp (SFun f x _ e) env@(vars, funs) = return (vars, bind f (Fun x e) funs)

interp (SCall x f e) env@(vars, funs) = do
    case find f funs of
        Just (Fun y body) -> do
            arg <- E.interp e env
            val <- E.interp body (bind y arg vars, funs)
            return (bind x val vars, funs)
        _        -> throw "Arguments can only be applied to functions"

interp (SRet e) env = throw "Return can only appear as final statement"
