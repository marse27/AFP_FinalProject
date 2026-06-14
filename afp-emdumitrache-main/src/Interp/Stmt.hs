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

-- Here we execute statements. 
-- Let statements evaluate the expression first, then store the result in the runtime environment. 
-- At runtime, immutable and mutable variables are stored the same way and mutability was already checked by the type checker.
interp :: Stmt -> Eval ()
interp (SLetImm x e) = E.interp e >>= \v -> modify (over evalVars (insertTop x v))
interp (SLetMut x e) = E.interp e >>= \v -> modify (over evalVars (insertTop x v))

-- Here we execute normal assignment, like x = e. 
-- The new expression is evaluated first, then the stored value of x is updated.
interp (SAssign x e) = E.interp e >>= \v -> modify (over evalVars (updateStack x v))

-- Here we execute assignment through a mutable reference, like *r = e. 
-- First r is looked up and it must contain a mutable reference. 
-- Then the new value is evaluated and written into the variable that r points to. 
-- updateSkipping avoids accidentally updating the reference variable itself instead of the real target behind the reference.
interp (SDerefAssign r e) = do
  vars <- gets (view evalVars)
  case lookupStack r vars of
    Nothing -> throwError $ "Variable " ++ show r ++ " is not declared in scope"
    Just v  -> case v of
      VRefMut x -> do
        val <- E.interp e
        modify (over evalVars (SS.updateSkipping isRef x val))
      _ -> throwError $ show r ++ " is not a mutable reference"
  where
    isRef (VRef _)    = True
    isRef (VRefMut _) = True
    isRef _           = False

-- Here we execute changing one element of a list, like list[i] = e. 
-- The list must exist at runtime and really be a list. 
-- The index and the new value are evaluated, then the list is updated at that position.
interp (SIndexAssign x i e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not declared in scope"
    Just (VList vs) -> do
      idx <- E.interp i
      val <- E.interp e
      case idx of
        VInt n -> do
          newVs <- listSetAt (fromInteger n) val vs
          modify (over evalVars (updateStack x (VList newVs)))
        _ -> throwError "The The list index must be an integer"
    Just _ -> throwError $ show x ++ " is not a list"

-- Here we execute adding a value to the end of a list, like list.push(e). 
-- The list must exist and really be a list. 
-- The new value is evaluated and appended to the stored list.
interp (SPush x e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not declared in scope"
    Just (VList vs) -> do
      v <- E.interp e
      modify (over evalVars (updateStack x (VList (vs ++ [v]))))
    Just _ -> throwError $ show x ++ " is not a list"

-- Here we execute inserting a value into a list, like list.insert(i, e). 
-- The list must exist and really be a list. 
-- The index and value are evaluated, then the value is inserted at the given position.
interp (SInsert x i e) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not declared in scope"
    Just (VList vs) -> do
      idx <- E.interp i
      val <- E.interp e
      case idx of
        VInt n -> do
          newVs <- listInsertAt (fromInteger n) val vs
          modify (over evalVars (updateStack x (VList newVs)))
        _      -> throwError "The list index must be an integer"
    Just _ -> throwError $ show x ++ " is not a list"

-- Here we execute removing a value from a list, like list.remove(i). 
-- The list must exist and really be a list. 
-- The index is evaluated, then the value at that position is removed.
interp (SRemove x i) = do
  vars <- gets (view evalVars)
  case lookupStack x vars of
    Nothing        -> throwError $ "Variable " ++ show x ++ " is not declared in scope"
    Just (VList vs) -> do
      idx <- E.interp i
      case idx of
        VInt n -> do
          newVs <- listRemoveAt (fromInteger n) vs
          modify (over evalVars (updateStack x (VList newVs)))
        _ -> throwError "The list index must be an integer"
    Just _ -> throwError $ show x ++ " is not a list"

-- Here we execute a block of statements. 
-- The actual scope handling is done inside interpBlock.
interp (SBlock b)    = interpBlock b

-- Here we execute an if-statement. 
-- The condition is evaluated first. 
-- If it becomes True, the body is executed. 
-- If it becomes False, nothing happens.
interp (SIf cond body) = do
  v <- E.interp cond
  case v of
    VBool True  -> interpBlock body
    VBool False -> return ()
    _           -> throwError "The if condition must be a boolean"

-- Here we execute an if-else statement. 
-- The condition is evaluated first. 
-- If it becomes True, the first block is executed. 
-- If it becomes False, the else block is executed.
interp (SIfElse cond tbody fbody) = do
  v <- E.interp cond
  case v of
    VBool True  -> interpBlock tbody
    VBool False -> interpBlock fbody
    _           -> throwError "The if condition must be a boolean"

-- Here we execute a while loop. 
-- The condition is checked before every loop iteration. 
-- If it becomes True, the body runs and the loop checks again. 
-- If it becomes False, the loop stops.
interp (SWhile cond body) = loop
  where
    loop = do
      v <- E.interp cond
      case v of
        VBool True  -> interpBlock body >> loop
        VBool False -> return ()
        _           -> throwError "While condition must be a boolean"

-- Here we store a normal function in the runtime function environment. 
-- The function body is not executed now and it is only saved so it can be called later.
interp (SFun f params _ body) =
  modify (over evalFuns (Map.insert f (Fun params body)))

-- Here we store a lifetime function at runtime. 
-- Lifetimes only matter during type checking, so the interpreter stores it the same way as a normal function.
interp (SFunLt f _ params _ body) =
  modify (over evalFuns (Map.insert f (Fun params body)))

-- Here we execute a spawn block. 
-- In this interpreter, spawn just runs the block normally. 
-- The type checker already handled the safety rules for what can be captured.
interp (SSpawn body) = interpBlock body

-- Here we execute a statement that is just an expression. 
-- The expression is evaluated, but its result is ignored.
interp (SExpr e) = E.interp e >> return ()

-- Here we execute a block of statements. 
-- A new scope is opened before running the block. 
-- After all statements are executed, that scope is removed.
interpBlock :: Block -> Eval ()
interpBlock (Block stmts) = do
  modify (over evalVars push)
  mapM_ interp stmts
  modify (over evalVars pop)

-- Here we replace the value at a specific list index. 
-- If the index exists, a new updated list is returned. 
-- If the index is outside the list, an error is thrown.
listSetAt :: Int -> Value -> [Value] -> Eval [Value]
listSetAt i v vs
  | i < 0    = throwError $ "List index " ++ show i ++ " cannot be negative"
  | otherwise = case splitAt i vs of
      (a, _:b) -> return (a ++ v : b)
      (_, [])  -> throwError $ "List index " ++ show i ++ " out of bounds"

-- Here we insert a value at a specific list index.
-- The index must be non-negative and at most the current list length (inserting at length appends).
-- Inserting beyond the end is rejected as an out-of-bounds error.
listInsertAt :: Int -> Value -> [Value] -> Eval [Value]
listInsertAt i v vs
  | i < 0         = throwError $ "List index " ++ show i ++ " cannot be negative"
  | i > length vs = throwError $ "List index " ++ show i ++ " out of bounds"
  | otherwise     = let (a, b) = splitAt i vs in return (a ++ v : b)

-- Here we remove the value at a specific list index.
-- If the index exists, a new list without that value is returned.
-- If the index is outside the list, an error is thrown.
listRemoveAt :: Int -> [Value] -> Eval [Value]
listRemoveAt i vs
  | i < 0    = throwError $ "List index " ++ show i ++ " cannot be negative"
  | otherwise = case splitAt i vs of
      (a, _:b) -> return (a ++ b)
      (_, [])  -> throwError $ "List index " ++ show i ++ " out of bounds"
