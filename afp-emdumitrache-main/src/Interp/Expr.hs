-- | Interpreter for expressions, running in the Eval monad.
-- Phase 2C: EOk/EErr/EPair construct Result/pair values; EMatch dispatches
--           arms using tryMatch and runs the matching arm's body.
-- Phase 3A: ERef stores a VRef (variable name); EDeref looks up through the ref.
-- Phase 3B: ERefMut stores a VRefMut; EDeref also handles VRefMut.
module Interp.Expr (interp) where

import Control.Monad        (when)
import Control.Monad.Except (throwError)
import Control.Monad.State  (gets, modify)
import qualified Data.Map.Strict as Map

import Lang.Abs   (Arm (..), Block (..), Exp (..), Ident, Pat (..), Param (..), Stmt (..))
import Context    (evalVars, evalFuns, view, over)
import ScopeStack (lookupStack, insertTop, push, pop)
import Value      (Value (..), Closure (..))
import Eval       (Eval)
import {-# SOURCE #-} qualified Interp.Stmt as S

-- | Evaluate an expression to a value.
interp :: Exp -> Eval Value
interp (EInt i)       = return $ VInt i
interp ETrue          = return $ VBool True
interp EFalse         = return $ VBool False
interp ELightRed      = return VLightRed
interp ELightYellow   = return VLightYellow
interp ELightGreen    = return VLightGreen
interp (ENeg e)       = interp e >>= \v -> case v of
  VInt i -> return $ VInt (negate i)
  _      -> throwError "Negation applied to non-integer"
interp (EMul e1 e2)   = arithm e1 e2 (*)
interp (EDiv e1 e2)   = arithm e1 e2 div
interp (EAdd e1 e2)   = arithm e1 e2 (+)
interp (ESub e1 e2)   = arithm e1 e2 (-)
interp (ENot e)       = interp e >>= \v -> case v of
  VBool b -> return $ VBool (not b)
  _       -> throwError "Boolean operation on non-boolean"
interp (EAnd e1 e2)   = logicOp e1 e2 (&&)
interp (EOr  e1 e2)   = logicOp e1 e2 (||)
interp (EEq  e1 e2)   = eqOp e1 e2
interp (ENeq e1 e2)   = eqOp e1 e2 >>= \v -> case v of
  VBool b -> return $ VBool (not b)
  _       -> throwError "Type error in inequality"
interp (ELt  e1 e2)   = cmpOp e1 e2 (<)
interp (EGt  e1 e2)   = cmpOp e1 e2 (>)
interp (ELeq e1 e2)   = cmpOp e1 e2 (<=)
interp (EGeq e1 e2)   = cmpOp e1 e2 (>=)
interp (EIf c t f)    = interp c >>= \v -> case v of
  VBool True  -> interp t
  VBool False -> interp f
  _           -> throwError "Condition must be a boolean"
interp (ELet x e body) = do
  val <- interp e
  modify (over evalVars (insertTop x val . push))
  result <- interp body
  modify (over evalVars pop)
  return result
interp (EVar x) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Just v  -> return v
    Nothing -> throwError $ "Variable " ++ show x ++ " is not bound"
interp (EList es) = VList <$> mapM interp es
interp (EIndex x i) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ show x ++ " is not bound"
    Just v  -> case v of
      VList vs -> do
        idx <- interp i
        case idx of
          VInt n -> listGet (fromInteger n) vs
          _      -> throwError "List index must be an integer"
      _ -> throwError $ "Cannot index a non-list value"
interp (ECall f args) = do
  funs <- gets (view evalFuns)
  case Map.lookup f funs of
    Nothing -> throwError $ "Function " ++ show f ++ " is not defined"
    Just (Fun params body) -> do
      when (length args /= length params) $
        throwError $ "Function " ++ show f ++ " argument count mismatch"
      argVals <- mapM interp args
      modify (over evalVars push)
      mapM_ (\(p, v) -> bindParam p v) (zip params argVals)
      result <- runBody body
      modify (over evalVars pop)
      return result
interp (EOk  e) = VOk  <$> interp e
interp (EErr e) = VErr <$> interp e
interp (EPair e1 e2) = VPair <$> interp e1 <*> interp e2
interp (ERef x)    = return (VRef x)
interp (ERefMut x) = return (VRefMut x)
interp (EDeref e) = do
  v <- interp e
  case v of
    VRef x -> do
      vars <- gets (view evalVars)
      case lookupStack x vars of
        Just val -> return val
        Nothing  -> throwError $ "Dangling reference to " ++ show x
    VRefMut x -> do
      vars <- gets (view evalVars)
      case lookupStack x vars of
        Just val -> return val
        Nothing  -> throwError $ "Dangling mutable reference to " ++ show x
    _ -> throwError "Cannot dereference a non-reference value"
interp (EMatch e arms) = do
  v <- interp e
  matchArms v arms

-- | Try matching a value against each arm in order; evaluate the first match.
matchArms :: Value -> [Arm] -> Eval Value
matchArms _ [] = throwError "Non-exhaustive match: no arm matched at runtime"
matchArms v (MatchArm pat body : rest) =
  case tryMatch v pat of
    Nothing    -> matchArms v rest
    Just binds -> do
      modify (over evalVars push)
      mapM_ (\(x, bv) -> modify (over evalVars (insertTop x bv))) binds
      result <- interp body
      modify (over evalVars pop)
      return result

-- | Return the variable bindings produced by matching value against pattern,
-- or Nothing if the pattern does not match.
tryMatch :: Value -> Pat -> Maybe [(Ident, Value)]
tryMatch VLightRed    PLightRed    = Just []
tryMatch VLightYellow PLightYellow = Just []
tryMatch VLightGreen  PLightGreen  = Just []
tryMatch (VOk  v)      (POk  x)   = Just [(x, v)]
tryMatch (VErr v)      (PErr x)   = Just [(x, v)]
tryMatch (VPair v1 v2) (PPair x y) = Just [(x, v1), (y, v2)]
tryMatch v             (PVar x)   = Just [(x, v)]
tryMatch _             _          = Nothing

-- | Bind a parameter name to a value in the current (innermost) scope.
bindParam :: Param -> Value -> Eval ()
bindParam (ParamImm x _) v = modify (over evalVars (insertTop x v))
bindParam (ParamMut  x _) v = modify (over evalVars (insertTop x v))

-- | Evaluate a function body: last SExpr is the return value, else VUnit.
runBody :: Block -> Eval Value
runBody (Block [])           = return VUnit
runBody (Block [SExpr e])    = interp e
runBody (Block (s : rest))   = S.interp s >> runBody (Block rest)

listGet :: Int -> [Value] -> Eval Value
listGet i vs = case drop i vs of
  (v:_) -> return v
  []    -> throwError $ "List index " ++ show i ++ " out of bounds"

arithm :: Exp -> Exp -> (Integer -> Integer -> Integer) -> Eval Value
arithm e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VInt a, VInt b) -> return $ VInt (f a b)
    _                -> throwError "Arithmetic on non-integers"

logicOp :: Exp -> Exp -> (Bool -> Bool -> Bool) -> Eval Value
logicOp e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VBool a, VBool b) -> return $ VBool (f a b)
    _                  -> throwError "Boolean operation on non-booleans"

eqOp :: Exp -> Exp -> Eval Value
eqOp e1 e2 = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VBool a,      VBool b)      -> return $ VBool (a == b)
    (VInt  a,      VInt  b)      -> return $ VBool (a == b)
    (VLightRed,    VLightRed)    -> return $ VBool True
    (VLightYellow, VLightYellow) -> return $ VBool True
    (VLightGreen,  VLightGreen)  -> return $ VBool True
    (VLightRed,    _)            -> return $ VBool False
    (VLightYellow, _)            -> return $ VBool False
    (VLightGreen,  _)            -> return $ VBool False
    _                            -> throwError "Cannot compare values of different types"

cmpOp :: Exp -> Exp -> (Integer -> Integer -> Bool) -> Eval Value
cmpOp e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VInt a, VInt b) -> return $ VBool (f a b)
    _                -> throwError "Comparison on non-integers"
