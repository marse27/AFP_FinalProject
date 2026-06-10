-- | Type checking for statements; updates the typing context in the Tc monad.
-- Phase 0: mutability checking, block scoping, control flow, functions.
-- Phase 1: ownership restore on SAssign; all new bindings start as owned.
-- Phase 2A: list mutation statements (SIndexAssign, SPush, SInsert, SRemove).
-- Phase 3A: immutable borrow let-bindings; releaseTopBorrows on scope exit.
-- Phase 3B: mutable borrow let-bindings (letMutBorrow); SDerefAssign writes
--           through a mutable reference; exclusivity enforced at borrow creation.
module TypeCheck.Stmt (infer) where

import Control.Monad        (unless, when)
import Control.Monad.Except (throwError)
import Control.Monad.State  (gets, modify)
import qualified Data.Map.Strict as Map

import Lang.Abs   (Block (..), Exp (..), Ident, Param (..), Stmt (..), Type (..))
import Lang.Print (printTree)

import Context    (VarInfo (..), tcVars, tcFuns, view, over)
import ScopeStack (lookupStack, insertTop, updateStack, push, pop)
import qualified ScopeStack as SS
import Tc         (Tc)
import Value      (TClosure (..))
import qualified TypeCheck.Expr as E

-- | Type-check a statement, updating the Tc context.
infer :: Stmt -> Tc ()
infer (SLetImm r (ERef    x)) = letBorrow    r x False
infer (SLetMut r (ERef    x)) = letBorrow    r x True
infer (SLetImm r (ERefMut x)) = letMutBorrow r x False
infer (SLetMut r (ERefMut x)) = letMutBorrow r x True
infer (SLetImm x e) = E.infer e >>= \t ->
  modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))
infer (SLetMut x e) = E.infer e >>= \t ->
  modify (over tcVars (insertTop x (VarInfo t True True 0 0 Nothing)))
infer (SAssign r (ERef x)) = do
  vars <- gets (view tcVars)
  case (lookupStack r vars, lookupStack x vars) of
    (Nothing, _) -> throwError $ "Variable " ++ printTree r ++ " is not in scope"
    (_, Nothing) -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    (Just rvi, Just xvi) -> do
      unless (varMut rvi) $ throwError $
        "Cannot assign to immutable variable " ++ printTree r
      unless (varType rvi == TRef (varType xvi)) $ throwError $
        "Type mismatch: expected " ++ printTree (varType rvi) ++
        " but borrow has type " ++ printTree (TRef (varType xvi))
      unless (varOwned xvi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      when (varMutBorrows xvi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": already mutably borrowed"
      releaseVarBorrow rvi
      modify (over tcVars (updateStack x xvi { varBorrows = varBorrows xvi + 1 }))
      modify (over tcVars (updateStack r rvi { varOwned = True, varBorrowOf = Just x }))
infer (SAssign r (ERefMut x)) = do
  vars <- gets (view tcVars)
  case (lookupStack r vars, lookupStack x vars) of
    (Nothing, _) -> throwError $ "Variable " ++ printTree r ++ " is not in scope"
    (_, Nothing) -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    (Just rvi, Just xvi) -> do
      unless (varMut rvi) $ throwError $
        "Cannot assign to immutable variable " ++ printTree r
      unless (varType rvi == TRefMut (varType xvi)) $ throwError $
        "Type mismatch: expected " ++ printTree (varType rvi) ++
        " but mutable borrow has type " ++ printTree (TRefMut (varType xvi))
      unless (varMut xvi) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: variable is not mutable"
      unless (varOwned xvi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      when (varBorrows xvi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: already borrowed"
      when (varMutBorrows xvi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: already mutably borrowed"
      releaseVarBorrow rvi
      modify (over tcVars (updateStack x xvi { varMutBorrows = varMutBorrows xvi + 1 }))
      modify (over tcVars (updateStack r rvi { varOwned = True, varBorrowOf = Just x }))
infer (SAssign x e) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not in scope"
    Just vi -> do
      unless (varMut vi) $ throwError $
        "Cannot assign to immutable variable " ++ printTree x
      when (varBorrows vi > 0 || varMutBorrows vi > 0) $ throwError $
        "Cannot assign to " ++ printTree x ++ ": value is borrowed"
      E.check e (varType vi)
      releaseVarBorrow vi
      modify (over tcVars (updateStack x vi { varOwned = True, varBorrowOf = Nothing }))
infer (SDerefAssign r e) = do
  vars <- gets (view tcVars)
  case lookupStack r vars of
    Nothing -> throwError $ "Variable " ++ printTree r ++ " is not in scope"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Value of " ++ printTree r ++ " used after being moved"
      case varType vi of
        TRefMut t -> E.check e t
        TRef _    -> throwError $
          printTree r ++ " is an immutable reference; cannot write through it"
        _         -> throwError $
          printTree r ++ " is not a mutable reference"
infer (SIndexAssign x i e) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not in scope"
    Just vi -> do
      unless (varMut vi)   $ throwError $ "Cannot mutate immutable list " ++ printTree x
      unless (varOwned vi) $ throwError $ "Value of " ++ printTree x ++ " used after being moved"
      case varType vi of
        TList elemT -> E.check i TInt >> E.check e elemT
        t           -> throwError $ "Cannot index a value of type " ++ printTree t
infer (SPush x e) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not in scope"
    Just vi -> do
      unless (varMut vi)   $ throwError $ "Cannot mutate immutable list " ++ printTree x
      unless (varOwned vi) $ throwError $ "Value of " ++ printTree x ++ " used after being moved"
      case varType vi of
        TList elemT -> E.check e elemT
        _           -> throwError $ printTree x ++ " is not a list"
infer (SInsert x i e) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not in scope"
    Just vi -> do
      unless (varMut vi)   $ throwError $ "Cannot mutate immutable list " ++ printTree x
      unless (varOwned vi) $ throwError $ "Value of " ++ printTree x ++ " used after being moved"
      case varType vi of
        TList elemT -> E.check i TInt >> E.check e elemT
        _           -> throwError $ printTree x ++ " is not a list"
infer (SRemove x i) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not in scope"
    Just vi -> do
      unless (varMut vi)   $ throwError $ "Cannot mutate immutable list " ++ printTree x
      unless (varOwned vi) $ throwError $ "Value of " ++ printTree x ++ " used after being moved"
      case varType vi of
        TList _ -> E.check i TInt
        _       -> throwError $ printTree x ++ " is not a list"
infer (SBlock b) = checkBlock b
infer (SIf cond body) = do
  E.check cond TBool
  checkBlock body
infer (SIfElse cond tbody fbody) = do
  E.check cond TBool
  checkBlock tbody
  checkBlock fbody
infer (SWhile cond body) = do
  E.check cond TBool
  checkBlock body
infer (SFun f params retTy body) = do
  case retTy of
    TRef _    -> throwError $ "Function " ++ printTree f ++ " cannot return a reference type"
    TRefMut _ -> throwError $ "Function " ++ printTree f ++ " cannot return a reference type"
    _         -> return ()
  modify (over tcFuns (Map.insert f (TFun params retTy)))
  modify (over tcVars push)
  mapM_ bindParam params
  checkBody retTy body
  releaseTopBorrows
  modify (over tcVars pop)
infer (SExpr e) = E.infer e >> return ()

-- | Check all statements in a block run in a fresh inner scope.
-- Releases borrows declared in the scope before popping; errors if any variable
-- being dropped still has outstanding borrows from an outer scope.
checkBlock :: Block -> Tc ()
checkBlock (Block stmts) = do
  modify (over tcVars push)
  mapM_ infer stmts
  releaseTopBorrows
  modify (over tcVars pop)

-- | Check that a function body matches its declared return type.
-- Void bodies just need to be well-typed; non-void bodies must end with
-- an expression of the correct type.
checkBody :: Type -> Block -> Tc ()
checkBody TVoid (Block stmts) = mapM_ infer stmts
checkBody _     (Block [])    = throwError "Missing return expression in function body"
checkBody retTy (Block [SExpr e])   = E.check e retTy
checkBody retTy (Block (s : rest))  = infer s >> checkBody retTy (Block rest)

bindParam :: Param -> Tc ()
bindParam (ParamImm x t) = modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))
bindParam (ParamMut  x t) = modify (over tcVars (insertTop x (VarInfo t True  True 0 0 Nothing)))

-- | Create an immutable borrow: let r = &x.
letBorrow :: Ident -> Ident -> Bool -> Tc ()
letBorrow r x isMut = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      when (varMutBorrows vi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": already mutably borrowed"
      modify (over tcVars (updateStack x vi { varBorrows = varBorrows vi + 1 }))
      modify (over tcVars (insertTop r (VarInfo (TRef (varType vi)) isMut True 0 0 (Just x))))

-- | Create a mutable borrow: let r = &mut x (x must be declared mutable).
letMutBorrow :: Ident -> Ident -> Bool -> Tc ()
letMutBorrow r x isMut = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      unless (varMut vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: variable is not mutable"
      when (varBorrows vi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: already borrowed"
      when (varMutBorrows vi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: already mutably borrowed"
      modify (over tcVars (updateStack x vi { varMutBorrows = varMutBorrows vi + 1 }))
      modify (over tcVars (insertTop r (VarInfo (TRefMut (varType vi)) isMut True 0 0 (Just x))))

-- | Release the borrow that vi holds (if any), decrementing the referent's
-- appropriate borrow counter.
releaseVarBorrow :: VarInfo -> Tc ()
releaseVarBorrow vi = case varBorrowOf vi of
  Nothing -> return ()
  Just y  -> do
    vars <- gets (view tcVars)
    case lookupStack y vars of
      Nothing  -> return ()
      Just yvi -> case varType vi of
        TRefMut _ -> modify (over tcVars (updateStack y yvi { varMutBorrows = varMutBorrows yvi - 1 }))
        _         -> modify (over tcVars (updateStack y yvi { varBorrows     = varBorrows     yvi - 1 }))

-- | On scope exit: release borrows in the current scope, then check no variable
-- being dropped still has outstanding borrows (which would dangle).
releaseTopBorrows :: Tc ()
releaseTopBorrows = do
  vars <- gets (view tcVars)
  let top = SS.topBindings vars
  mapM_ releaseBorrow (Map.toList top)
  vars2 <- gets (view tcVars)
  let top2 = SS.topBindings vars2
  mapM_ checkNotBorrowed (Map.toList top2)
  where
    releaseBorrow (_, vi) = case varBorrowOf vi of
      Nothing -> return ()
      Just y  -> do
        vars <- gets (view tcVars)
        case lookupStack y vars of
          Nothing  -> return ()
          Just yvi -> case varType vi of
            TRefMut _ -> modify (over tcVars (updateStack y yvi { varMutBorrows = varMutBorrows yvi - 1 }))
            _         -> modify (over tcVars (updateStack y yvi { varBorrows     = varBorrows     yvi - 1 }))
    checkNotBorrowed (x, vi) =
      when (varBorrows vi > 0 || varMutBorrows vi > 0) $ throwError $
        printTree x ++ " is dropped while still borrowed (borrow would dangle)"
