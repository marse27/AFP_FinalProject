module Interp.Expr where

import Evaluator

import Env
import Value
import Lang.Abs ( Exp(..), Ident )

arithmetic :: (Exp, Exp) -> (Env Value, Env Closure) -> (Integer -> Integer -> Integer) -> Result Value
arithmetic (e1, e2) env f = do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VInt i1, VInt i2) -> return $ VInt (f i1 i2)
        _                  -> throw "Arithmetic can only be performed on integers"

logic :: (Exp, Exp) -> (Env Value, Env Closure) -> (Bool -> Bool -> Bool) -> Result Value
logic (e1, e2) env f =  do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VBool b1, VBool b2) -> return $ VBool (f b1 b2)
        _                    -> throw "Boolean operations can only be performed on booleans"

-- EXPRESSION INTERPRETER ------------------------------------------------------------

interp :: Exp -> (Env Value, Env Closure) -> Result Value

-- Arithmetic
interp (EInt i) _ = return $ VInt i

interp (EMul e1 e2) env = arithmetic (e1, e2) env (*)
interp (EDiv e1 e2) env = arithmetic (e1, e2) env div
interp (EAdd e1 e2) env = arithmetic (e1, e2) env (+)
interp (ESub e1 e2) env = arithmetic (e1, e2) env (-)

-- Booleans
interp ETrue  _ = return $ VBool True
interp EFalse _ = return $ VBool False

interp (ENot e) env =  do
    v <- interp e env
    case v of
        VBool b -> return $ VBool (not b)
        _       -> throw "Boolean operations can only be performed on booleans"
interp (EAnd e1 e2) env = logic (e1, e2) env (&&)
interp (EOr e1 e2)  env = logic (e1, e2) env (||)

-- Comparisons
interp (EEq e1 e2) env = do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VBool b1, VBool b2) -> return $ VBool (b1 == b2)
        (VInt  i1, VInt  i2) -> return $ VBool (i1 == i2)
        _                    -> throw "Cannot compare different types"
interp (ELt e1 e2) env = do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VInt i1, VInt i2) -> return $ VBool (i1 < i2)
        _                  -> throw "Cannot compare different types"
interp (EGt e1 e2) env = do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VInt i1, VInt i2) -> return $ VBool (i1 > i2)
        _                  -> throw "Cannot compare different types"
interp (ELeq e1 e2) env = do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VInt i1, VInt i2) -> return $ VBool (i1 <= i2)
        _                  -> throw "Cannot compare different types"

interp (EGeq e1 e2) env = do
    v1 <- interp e1 env
    v2 <- interp e2 env
    case (v1, v2) of
        (VInt i1, VInt i2) -> return $ VBool (i1 >= i2)
        _                  -> throw "Cannot compare different types"

-- Control flow
interp (EIf c iff els) env = do
    cond <- interp c env
    case cond of
        VBool True  -> interp iff env
        VBool False -> interp els env
        _           -> throw "Condition must be a boolean"

-- Let bindings
interp (ELet x e body) env@(vars, funs) = do
    arg <- interp e env
    interp body (bind x arg vars, funs)
interp (EVar x) (vars, _) =
    case find x vars of
        Just val -> return val
        Nothing  -> throw $ "Variable " ++ show x ++ " is not bound"

