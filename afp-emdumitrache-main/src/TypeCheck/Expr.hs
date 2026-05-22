module TypeCheck.Expr where

import Control.Monad

import Evaluator

import Env

import Value ( TClosure( TFun ) )

import Lang.Abs ( Exp(..)
                , Ident
                , Type(..) )
import Lang.Print ( printTree )



arithmetic :: (Exp, Exp) -> (Env Type, Env TClosure) -> Result Type
arithmetic (e1, e2) env = do
    check e1 TInt env
    check e2 TInt env
    return TInt

logic :: (Exp, Exp) -> (Env Type, Env TClosure) -> Result Type
logic (e1, e2) env =  do
    check e1 TBool env
    check e2 TBool env
    return TBool

comparison :: (Exp, Exp) -> (Env Type, Env TClosure) -> Result Type
comparison (e1, e2) env =  do
    check e1 TInt env
    check e2 TInt env
    return TBool

-- EXPRESSION TYPE CHECKER -----------------------------------------------------------

check :: Exp -> Type -> (Env Type, Env TClosure) -> Result ()
check e expected env = do
  actual <- infer e env
  unless (expected == actual) $ throw $
    "Expression " ++ printTree e ++
    " should be of type " ++ printTree expected ++
    ", but it has type " ++ printTree actual ++ " instead."

infer :: Exp -> (Env Type, Env TClosure) -> Result Type

-- Arithmetic
infer (EInt _) _ = return TInt

infer (EMul e1 e2) env = arithmetic (e1, e2) env
infer (EDiv e1 e2) env = arithmetic (e1, e2) env
infer (EAdd e1 e2) env = arithmetic (e1, e2) env
infer (ESub e1 e2) env = arithmetic (e1, e2) env

-- Booleans
infer ETrue  _ = return TBool
infer EFalse _ = return TBool

infer (ENot e) env = do
    check e TBool env
    return TBool
infer (EAnd e1 e2) env = logic (e1, e2) env
infer (EOr  e1 e2) env = logic (e1, e2) env

-- Comparisons
infer (EEq e1 e2) env = do
    t1 <- infer e1 env
    check e2 t1 env
    return TBool
infer (ELt  e1 e2) env = comparison (e1, e2) env
infer (EGt  e1 e2) env = comparison (e1, e2) env
infer (ELeq e1 e2) env = comparison (e1, e2) env
infer (EGeq e1 e2) env = comparison (e1, e2) env

-- Control flow
infer (EIf c iff els) env = do
    check c TBool env
    t <- infer iff env
    check els t env
    return t

-- Let bindings
infer (ELet x e body) env@(vars, funs) = do
    t <- infer e env
    infer body (bind x t vars, funs)
infer (EVar x) (vars, _) =
    case find x vars of
        Just t  -> return t
        Nothing -> throw $ "Variable " ++ show x ++ " is not bound"
