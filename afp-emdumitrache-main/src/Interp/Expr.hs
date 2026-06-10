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

-- These are the basic expression cases. 
-- Literal values are directly turned into runtime values. 
-- Operators first evaluate their operands, then apply the matching operation. 
-- Even though the type checker should already catch wrong types, the interpreter still checks the runtime values to avoid invalid evaluation.
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

-- Here we evaluate an if-expression. 
-- The condition is evaluated first. 
-- If it becomes True, the then-branch is evaluated.
-- If it becomes False, the else-branch is evaluated. 
-- Any non-boolean condition is rejected.
interp (EIf c t f)    = interp c >>= \v -> case v of
  VBool True  -> interp t
  VBool False -> interp f
  _           -> throwError "Condition must be a boolean"

-- Here we evaluate a local let-expression. 
-- First the value assigned to x is evaluated. 
-- Then x is added in a new temporary scope while the body is evaluated. 
-- After the body is done, that scope is removed and the body result is returned.
interp (ELet x e body) = do
  val <- interp e
  modify (over evalVars (insertTop x val . push))
  result <- interp body
  modify (over evalVars pop)
  return result

-- Here we evaluate using a variable. 
-- The variable must already exist in the current runtime environment. 
-- If it exists, its stored value is returned.
interp (EVar x) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Just v  -> return v
    Nothing -> throwError $ "Variable " ++ show x ++ " is not bound"

-- Here we evaluate a list. 
-- Each element is evaluated, and the results are stored together as a runtime list.
interp (EList es) = VList <$> mapM interp es

-- Here we evaluate reading from a list, like list[i]. 
-- The list variable must exist and must really contain a list value. 
-- The index expression is evaluated and must become an integer. 
-- If everything is valid, the value at that position is returned.
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

-- Here we evaluate a function call. 
-- The function must exist and the number of given arguments must match. 
-- First all argument expressions are evaluated. 
-- Then a new scope is opened, the argument values are bound to the parameters, the function body is evaluated, and the scope is removed again.
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

-- Here we evaluate Result and pair values. 
-- Ok and Err evaluate their inner value first. 
-- A pair evaluates both sides and stores the two results together.
interp (EOk  e) = VOk  <$> interp e
interp (EErr e) = VErr <$> interp e
interp (EPair e1 e2) = VPair <$> interp e1 <*> interp e2

-- Here we create references at runtime. 
-- A reference only stores the name of the variable it points to. 
-- The actual value is looked up later when the reference is dereferenced.
interp (ERef x)    = return (VRef x)
interp (ERefMut x) = return (VRefMut x)

-- Here we evaluate dereferencing, like *r. 
-- First the reference expression is evaluated. 
-- If it points to a variable that still exists, that variable's value is returned. 
-- If the variable no longer exists, the reference is dangling. 
-- Non-reference values cannot be dereferenced.
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

-- Here we evaluate a match expression. 
-- First the value being matched is evaluated. 
-- Then the match arms are tried one by one until a matching pattern is found.
interp (EMatch e arms) = do
  v <- interp e
  matchArms v arms

-- Here we try the match arms one by one. 
-- If an arm matches, any variables introduced by the pattern are added in a temporary scope while the arm body is evaluated. 
-- If no arm matches, this is a runtime error.
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

-- Here we check if a runtime value matches a pattern. 
-- If it matches, the result is the list of variables that the pattern binds. 
-- If it does not match, Nothing is returned and the next match arm is tried.
tryMatch :: Value -> Pat -> Maybe [(Ident, Value)]
tryMatch VLightRed    PLightRed    = Just []
tryMatch VLightYellow PLightYellow = Just []
tryMatch VLightGreen  PLightGreen  = Just []
tryMatch (VOk  v)      (POk  x)   = Just [(x, v)]
tryMatch (VErr v)      (PErr x)   = Just [(x, v)]
tryMatch (VPair v1 v2) (PPair x y) = Just [(x, v1), (y, v2)]
tryMatch v             (PVar x)   = Just [(x, v)]
tryMatch _             _          = Nothing

-- Here we bind an argument value to a function parameter. 
-- At runtime, immutable and mutable parameters are stored the same way. 
-- The mutability was already checked by the type checker.
bindParam :: Param -> Value -> Eval ()
bindParam (ParamImm x _) v = modify (over evalVars (insertTop x v))
bindParam (ParamMut  x _) v = modify (over evalVars (insertTop x v))

-- Here we run the statements inside a function body or block. 
-- An empty body returns unit. 
-- If the last statement is an expression, that expression gives the result. 
-- Otherwise, each statement is executed in order.
runBody :: Block -> Eval Value
runBody (Block [])           = return VUnit
runBody (Block [SExpr e])    = interp e
runBody (Block (s : rest))   = S.interp s >> runBody (Block rest)

-- Here we get a value from a list at a given index. 
-- If the index exists, that value is returned. 
-- If the index is outside the list, an error is thrown.
listGet :: Int -> [Value] -> Eval Value
listGet i vs = case drop i vs of
  (v:_) -> return v
  []    -> throwError $ "List index " ++ show i ++ " out of bounds"

-- Here we evaluate arithmetic operations like +, -, *, and /. 
-- Both expressions are evaluated first. 
-- They must both become integers, then the given arithmetic function is applied.
arithm :: Exp -> Exp -> (Integer -> Integer -> Integer) -> Eval Value
arithm e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VInt a, VInt b) -> return $ VInt (f a b)
    _                -> throwError "Arithmetic on non-integers"

-- Here we evaluate boolean operations like && and ||. 
-- Both expressions are evaluated first. 
-- They must both become booleans, then the given boolean function is applied.
logicOp :: Exp -> Exp -> (Bool -> Bool -> Bool) -> Eval Value
logicOp e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VBool a, VBool b) -> return $ VBool (f a b)
    _                  -> throwError "Boolean operation on non-booleans"

-- Here we evaluate equality checks. 
-- Integers, booleans, and Light values can be compared. 
-- If the two values do not have compatible types, an error is thrown.
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

-- Here we evaluate comparisons like <, >, <=, and >=. 
-- Both expressions are evaluated first. 
-- They must both become integers, and the result is a boolean.
cmpOp :: Exp -> Exp -> (Integer -> Integer -> Bool) -> Eval Value
cmpOp e1 e2 f = do
  v1 <- interp e1; v2 <- interp e2
  case (v1, v2) of
    (VInt a, VInt b) -> return $ VBool (f a b)
    _                -> throwError "Comparison on non-integers"
