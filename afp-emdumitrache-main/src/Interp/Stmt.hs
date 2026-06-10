-- | Interpreter for statements; updates the evaluation context in the Eval monad.
-- Phase 0: mutable assignment, block scoping, control flow, functions.
-- Phase 2A: list mutation (SIndexAssign, SPush, SInsert, SRemove).
-- Phase 3B: SDerefAssign writes through a mutable reference via updateSkipping.
-- Phase 4B: SSpawn runs the block synchronously (type checker enforces Copy captures).
module Interp.Stmt (interp) where

import Control.Monad.Except (throwError)
import Control.Monad.State  (gets, modify)
import qualified Data.Map.Strict as Map

import Lang.Abs   (Block (..), Param (..), Stmt (..))
import Context    (evalVars, evalFuns, view, over)
import ScopeStack (lookupStack, insertTop, updateStack, push, pop)
import qualified ScopeStack as SS
import Value      (Value (..), Closure (..))
import Eval       (Eval)
import qualified Interp.Expr as E

-- | Interpret a statement, updating the Eval context.
interp :: Stmt -> Eval ()
interp (SLetImm x e) = E.interp e >>= \v -> modify (over evalVars (insertTop x v))
interp (SLetMut x e) = E.interp e >>= \v -> modify (over evalVars (insertTop x v))
interp (SAssign x e) = E.interp e >>= \v -> modify (over evalVars (updateStack x v))
interp (SDerefAssign r e) = do
  vars <- gets (view evalVars)
  case lookupStack r vars of
    Nothing -> throwError $ "Variable " ++ show r ++ " is not in scope"
    Just v  -> case v of
      VRefMut x -> do
        val <- E.interp e
        modify (over evalVars (SS.updateSkipping isRef x val))
      _ -> throwError $ show r ++ " is not a mutable reference"
  where
    isRef (VRef _)    = True
    isRef (VRefMut _) = True
    isRef _           = False
interp (SIndexAssign x i e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not in scope"
    Just (VList vs) -> do
      idx <- E.interp i
      val <- E.interp e
      case idx of
        VInt n -> do
          newVs <- listSetAt (fromInteger n) val vs
          modify (over evalVars (updateStack x (VList newVs)))
        _ -> throwError "List index must be an integer"
    Just _ -> throwError $ show x ++ " is not a list"
interp (SPush x e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not in scope"
    Just (VList vs) -> do
      v <- E.interp e
      modify (over evalVars (updateStack x (VList (vs ++ [v]))))
    Just _ -> throwError $ show x ++ " is not a list"
interp (SInsert x i e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not in scope"
    Just (VList vs) -> do
      idx <- E.interp i
      val <- E.interp e
      case idx of
        VInt n -> modify (over evalVars (updateStack x (VList (listInsertAt (fromInteger n) val vs))))
        _      -> throwError "List index must be an integer"
    Just _ -> throwError $ show x ++ " is not a list"
interp (SRemove x i) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not in scope"
    Just (VList vs) -> do
      idx <- E.interp i
      case idx of
        VInt n -> do
          newVs <- listRemoveAt (fromInteger n) vs
          modify (over evalVars (updateStack x (VList newVs)))
        _ -> throwError "List index must be an integer"
    Just _ -> throwError $ show x ++ " is not a list"
interp (SBlock b)    = interpBlock b
interp (SIf cond body) = do
  v <- E.interp cond
  case v of
    VBool True  -> interpBlock body
    VBool False -> return ()
    _           -> throwError "If condition must be a boolean"
interp (SIfElse cond tbody fbody) = do
  v <- E.interp cond
  case v of
    VBool True  -> interpBlock tbody
    VBool False -> interpBlock fbody
    _           -> throwError "If condition must be a boolean"
interp (SWhile cond body) = loop
  where
    loop = do
      v <- E.interp cond
      case v of
        VBool True  -> interpBlock body >> loop
        VBool False -> return ()
        _           -> throwError "While condition must be a boolean"
interp (SFun f params _ body) =
  modify (over evalFuns (Map.insert f (Fun params body)))
interp (SFunLt f _ params _ body) =
  modify (over evalFuns (Map.insert f (Fun params body)))
interp (SSpawn body) = interpBlock body
interp (SExpr e) = E.interp e >> return ()

-- | Run a block in a fresh inner scope; mutations to outer vars persist.
interpBlock :: Block -> Eval ()
interpBlock (Block stmts) = do
  modify (over evalVars push)
  mapM_ interp stmts
  modify (over evalVars pop)

-- | Replace the element at position i; error if out of bounds.
listSetAt :: Int -> Value -> [Value] -> Eval [Value]
listSetAt i v vs = case splitAt i vs of
  (a, _:b) -> return (a ++ v : b)
  (_, [])  -> throwError $ "List index " ++ show i ++ " out of bounds"

-- | Insert a value before position i.
listInsertAt :: Int -> Value -> [Value] -> [Value]
listInsertAt i v vs = let (a, b) = splitAt i vs in a ++ v : b

-- | Remove the element at position i; error if out of bounds.
listRemoveAt :: Int -> [Value] -> Eval [Value]
listRemoveAt i vs = case splitAt i vs of
  (a, _:b) -> return (a ++ b)
  (_, [])  -> throwError $ "List index " ++ show i ++ " out of bounds"
