-- | Type checking for statements; updates the typing context in the Tc monad.
-- Phase 0: mutability checking, block scoping, control flow, functions.
-- Phase 1: ownership restore on SAssign; all new bindings start as owned.
-- Phase 2A: list mutation statements (SIndexAssign, SPush, SInsert, SRemove).
-- Phase 3A: immutable borrow let-bindings; releaseTopBorrows on scope exit.
-- Phase 3B: mutable borrow let-bindings (letMutBorrow); SDerefAssign writes
--           through a mutable reference; exclusivity enforced at borrow creation.
-- Phase 3C: non-lexical lifetimes (NLL) — borrows expire at last syntactic use,
--           not at lexical scope end. Uses Map.traverseWithKey (a van Laarhoven
--           Traversal) with Const applicative as a structural fold to identify
--           expired borrows without intermediate data structures.
-- Phase 4A: explicit lifetime annotations — functions can return references when
--           the return lifetime names a bound lifetime parameter. Borrow tracking
--           propagates from the argument to the bound result variable.
-- Phase 4B: spawn blocks — type-safe concurrency. Captured variables must be
--           Copy (no aliasing across thread boundaries); enforced at spawn sites.
module TypeCheck.Stmt (infer, mentionedVars, releaseExpiredBorrows) where

import Control.Monad        (unless, when)
import Control.Monad.Except (throwError)
import Control.Monad.State  (gets, modify)
import Data.Functor.Const   (Const (..))
import Data.List            (findIndex)
import Data.Maybe           (isJust)
import qualified Data.Map.Strict as Map
import qualified Data.Set        as Set

import Lang.Abs   (Arm (..), Block (..), Exp (..), Ident, Lifetime (..), Param (..), Stmt (..), Type (..))
import Lang.Print (printTree)

import Context    (VarInfo (..), tcVars, tcFuns, view, over)
import ScopeStack (lookupStack, insertTop, updateStack, push, pop, topBindings)
import qualified ScopeStack as SS
import Tc         (Tc)
import Value      (TClosure (..), eraseLifetime, isCopyable, paramType)
import qualified TypeCheck.Expr as E

-- These are the special let-cases.
-- If a variable is created from a borrow, the borrow counters must be updated.
-- If a variable is created from a function call, callAndBind is used so lifetime-returning functions can be handled safely.
-- The Bool tells whether the new variable is mutable or immutable.
infer :: Stmt -> Tc ()
infer (SLetImm r (ERef    x)) = letBorrow    r x False
infer (SLetMut r (ERef    x)) = letBorrow    r x True
infer (SLetImm r (ERefMut x)) = letMutBorrow r x False
infer (SLetMut r (ERefMut x)) = letMutBorrow r x True
infer (SLetImm r (ECall f args)) = callAndBind r f args False
infer (SLetMut r (ECall f args)) = callAndBind r f args True

-- Here we handle creating an immutable variable.
-- The expression on the right is checked first, then the new variable is added as immutable, owned, and not borrowing anything.
infer (SLetImm x e) = E.infer e >>= \t ->
  modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))

-- Here we handle creating a mutable variable.
-- The expression on the right is checked first, then the new variable is added as mutable, owned, and not borrowing anything.
infer (SLetMut x e) = E.infer e >>= \t ->
  modify (over tcVars (insertTop x (VarInfo t True True 0 0 Nothing)))

-- Here we handle assigning an immutable borrow to an existing variable, like r = &x.
-- The variable r must already exist, must be mutable, and must have the right reference type.
-- The variable x must exist, still have its value, and must not already be mutably borrowed.
-- If r was borrowing something before, that old borrow is released first.
-- Then x gets one extra immutable borrow, and r is marked as borrowing x.
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

-- Here we handle assigning a mutable borrow to an existing variable, like r = &mut x.
-- The variable r must already exist, must be mutable, and must have the right mutable reference type.
-- The variable x must exist, must be mutable, and its value must not be moved.
-- x also cannot already be borrowed, because a mutable borrow must be the only borrow.
-- If r was borrowing something before, that old borrow is released first.
-- Then x gets one extra mutable borrow, and r is marked as borrowing x.
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

-- Here we handle assigning a new value to an existing variable, like x = e.
-- The variable x must exist and must be mutable.
-- Its current value cannot be borrowed, because borrowed values cannot be replaced.
-- The new expression must have the same type as x.
-- If x was previously a reference borrowing something, that old borrow is released.
-- After assignment, x owns its new value and is no longer marked as borrowing anything.
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

-- Here we handle assigning through a mutable reference, like *r = e. 
-- The variable r must exist and the reference itself must not be moved. 
-- r must be a mutable reference, because only mutable references allow writing. 
-- The new expression must have the same type as the value behind the reference.
infer (SDerefAssign r e) = do
  vars <- gets (view tcVars)
  case lookupStack r vars of
    Nothing -> throwError $ "Variable " ++ printTree r ++ " is not in scope"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Value of " ++ printTree r ++ " used after being moved"
      case varType vi of
        TRefMut t      -> E.check e t
        TRefMutLt _ t  -> E.check e t
        TRef _         -> throwError $
          printTree r ++ " is an immutable reference; cannot write through it"
        TRefLt _ _     -> throwError $
          printTree r ++ " is an immutable reference; cannot write through it"
        _              -> throwError $
          printTree r ++ " is not a mutable reference"

-- Here we handle changing one element of a list, like list[i] = e. 
-- The list must exist, must be mutable, and must not be moved. 
-- The index must be an integer, and the new value must have the same type as the list elements.
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

-- Here we handle adding a value to the end of a list, like list.push(e). 
-- The list must exist, must be mutable, and must not be moved. 
-- The added value must have the same type as the list elements.
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

-- Here we handle inserting a value into a list, like list.insert(i, e). 
-- The list must exist, must be mutable, and must not be moved. 
-- The index must be an integer, and the inserted value must have the same type as the list elements.
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

-- Here we handle removing a value from a list, like list.remove(i). 
-- The list must exist, must be mutable, and must not be moved. 
-- The index must be an integer.
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

-- Here we handle a block of statements. 
-- A block gets its own scope, so variables declared inside it should disappear after the block is checked.
infer (SBlock b) = checkBlock b

-- Here we handle an if-statement without an else branch. 
-- The condition must be a boolean. 
-- The body is checked as its own block, so variables declared inside it only exist inside that block.
infer (SIf cond body) = do
  E.check cond TBool
  checkBlock body

-- Here we handle an if-else statement. 
-- The condition must be a boolean. 
-- Both branches are checked as separate blocks, because each branch has its own local scope.
infer (SIfElse cond tbody fbody) = do
  E.check cond TBool
  checkBlock tbody
  checkBlock fbody

-- Here we handle a while loop. 
-- The condition must be a boolean. 
-- The loop body is checked as a block, so variables declared inside it do not escape outside the loop.
infer (SWhile cond body) = do
  E.check cond TBool
  checkBlock body

-- Here we handle declaring a normal function.
-- Normal functions are not allowed to return references, because there is no lifetime information that proves the reference would stay valid.
-- The function type is saved first, so the function can be called while checking.
-- Then the parameters are added in a new scope and the body is checked.
-- After the function body, borrows from this scope are released and the scope is removed.
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

-- Here we handle declaring a function with explicit lifetimes.
-- This kind of function is allowed to return references, but only if the return lifetime was declared in the function header.
-- The function type is saved, then the parameters are added in a new scope and the body is checked.
-- After the function body, borrows from this scope are released and the scope is removed.
infer (SFunLt f lts params retTy body) = do
  let ltNames = [lt | MkLifetime lt <- lts]
  case retTy of
    TRefLt lt _    -> unless (lt `elem` ltNames) $ throwError $
      "Function " ++ printTree f ++ " return type uses undeclared lifetime '" ++ printTree lt
    TRefMutLt lt _ -> unless (lt `elem` ltNames) $ throwError $
      "Function " ++ printTree f ++ " return type uses undeclared lifetime '" ++ printTree lt
    _ -> return ()
  modify (over tcFuns (Map.insert f (TFunLt ltNames params retTy)))
  modify (over tcVars push)
  mapM_ bindParam params
  checkBody retTy body
  releaseTopBorrows
  modify (over tcVars pop)

infer (SExpr e) = E.infer e >> return ()

-- Here we handle a spawn block. 
-- The block may use variables from outside, but only copyable values are allowed to be captured. 
-- This avoids sharing owned, non-copyable values across threads. 
-- After checking the captured variables, the spawn body is checked as a block.
infer (SSpawn body) = do
  let freeVs = mentionedBlock body
  vars <- gets (view tcVars)
  let checkCapture x = case lookupStack x vars of
        Nothing -> return ()
        Just vi -> unless (isCopyable (varType vi)) $ throwError $
          "Cannot capture non-Copy variable '" ++ printTree x ++ "' in spawn block"
  mapM_ checkCapture (Set.toList freeVs)
  checkBlock body

-- Here we handle a function call whose result is immediately saved into a variable, like let r = f(args). 
-- This is needed especially for lifetime functions, because returned references must be connected to the variable they borrow from. 
-- For normal functions, the result type is inferred and r is added normally. 
-- For lifetime functions, the arguments are checked, the returned borrow is resolved, and the borrow counters are updated if the result is a reference.
callAndBind :: Ident -> Ident -> [Exp] -> Bool -> Tc ()
callAndBind r f args isMut = do
  funs <- gets (view tcFuns)
  case Map.lookup f funs of
    Nothing -> throwError $ "Function " ++ show f ++ " is not defined"
    Just (TFun _ _) -> do
      t <- E.infer (ECall f args)
      modify (over tcVars (insertTop r (VarInfo t isMut True 0 0 Nothing)))
    Just (TFunLt lts params retTy) -> do
      when (length args /= length params) $ throwError $
        "Function " ++ show f ++ " expects " ++ show (length params) ++
        " argument(s) but got " ++ show (length args)
      mapM_ (\(e, p) -> E.check e (eraseLifetime (paramType p))) (zip args params)
      (boundType, mBorrowFrom) <- resolveReturnBorrow lts params args retTy
      case mBorrowFrom of
        Nothing -> modify (over tcVars (insertTop r (VarInfo boundType isMut True 0 0 Nothing)))
        Just z  -> do
          vars <- gets (view tcVars)
          case lookupStack z vars of
            Nothing  -> throwError $ "Variable " ++ printTree z ++ " is not in scope"
            Just zvi -> case boundType of
              TRef _ -> do
                when (varMutBorrows zvi > 0) $ throwError $
                  "Cannot borrow " ++ printTree z ++ ": already mutably borrowed"
                modify (over tcVars (updateStack z zvi { varBorrows = varBorrows zvi + 1 }))
                modify (over tcVars (insertTop r (VarInfo boundType isMut True 0 0 (Just z))))
              TRefMut _ -> do
                when (varBorrows zvi > 0) $ throwError $
                  "Cannot borrow " ++ printTree z ++ " as mutable: already borrowed"
                when (varMutBorrows zvi > 0) $ throwError $
                  "Cannot borrow " ++ printTree z ++ " as mutable: already mutably borrowed"
                unless (varMut zvi) $ throwError $
                  "Cannot borrow " ++ printTree z ++ " as mutable: variable is not mutable"
                modify (over tcVars (updateStack z zvi { varMutBorrows = varMutBorrows zvi + 1 }))
                modify (over tcVars (insertTop r (VarInfo boundType isMut True 0 0 (Just z))))
              _ -> throwError "Internal: resolveReturnBorrow returned non-reference type with borrow source"

-- Here we figure out what a lifetime-returning function call really returns. 
-- If the function returns a reference with lifetime a, this finds which argument has that same lifetime. 
-- The result is the normal reference type, together with the variable that is being borrowed from, if there is one.
resolveReturnBorrow :: [Ident] -> [Param] -> [Exp] -> Type -> Tc (Type, Maybe Ident)
resolveReturnBorrow lts params args retTy = case retTy of
  TRefLt lt inner -> do
    unless (lt `elem` lts) $ throwError $
      "Return type uses undeclared lifetime '" ++ printTree lt
    case findIndex (\p -> case paramType p of { TRefLt lt2 _ -> lt2 == lt; _ -> False }) params of
      Nothing -> throwError $ "Lifetime '" ++ printTree lt ++ " does not appear in any parameter"
      Just i  -> case args !! i of
        ERef z    -> return (TRef inner, Just z)
        ERefMut z -> return (TRef inner, Just z)
        _         -> throwError $ "Argument " ++ show (i + 1) ++
                       " must be a reference (&x or &mut x) for lifetime '" ++ printTree lt
  TRefMutLt lt inner -> do
    unless (lt `elem` lts) $ throwError $
      "Return type uses undeclared lifetime '" ++ printTree lt
    case findIndex (\p -> case paramType p of { TRefMutLt lt2 _ -> lt2 == lt; _ -> False }) params of
      Nothing -> throwError $ "Lifetime '" ++ printTree lt ++ " does not appear in any mutable parameter"
      Just i  -> case args !! i of
        ERefMut z -> return (TRefMut inner, Just z)
        _         -> throwError $ "Argument " ++ show (i + 1) ++
                       " must be a mutable reference (&mut x) for lifetime '" ++ printTree lt
  _ -> return (retTy, Nothing)

-- Here we check a block of statements. 
-- A new scope is opened before checking the statements. 
-- When the block ends, borrows created inside it are released, and variables declared inside the block are removed.
checkBlock :: Block -> Tc ()
checkBlock (Block stmts) = do
  modify (over tcVars push)
  checkStmtsNLL stmts
  releaseTopBorrows
  modify (over tcVars pop)

-- Here we check statements while using non-lexical lifetimes. 
-- After each statement, borrows that are not used anymore in the remaining statements are released early.
checkStmtsNLL :: [Stmt] -> Tc ()
checkStmtsNLL []       = return ()
checkStmtsNLL (s:rest) = do
  infer s
  releaseExpiredBorrows (mentionedVars rest)
  checkStmtsNLL rest

-- Here we check the body of a function. 
-- Void functions do not need a final return expression. 
-- Non-void functions must end with an expression of the declared return type. 
-- While checking the body, unused borrows are also released early.
checkBody :: Type -> Block -> Tc ()
checkBody TVoid (Block stmts) = checkStmtsNLL stmts
checkBody _     (Block [])    = throwError "Missing return expression in function body"
checkBody retTy (Block [SExpr e])  = E.check e retTy
checkBody retTy (Block (s : rest)) = do
  infer s
  releaseExpiredBorrows (mentionedVars rest)
  checkBody retTy (Block rest)

-- Here we add a function parameter to the current scope. 
-- Immutable parameters are added as immutable variables. 
-- Mutable parameters are added as mutable variables. 
-- In both cases, the parameter starts as owned and not borrowing anything.
bindParam :: Param -> Tc ()
bindParam (ParamImm x t) = modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))
bindParam (ParamMut  x t) = modify (over tcVars (insertTop x (VarInfo t True  True 0 0 Nothing)))

-- Here we handle creating an immutable borrow, like let r = &x.
-- The borrowed variable x must exist and must not be moved. 
-- x also cannot already have a mutable borrow, because mutable borrows do not allow any other borrow at the same time. 
-- If everything is valid, x gets one extra immutable borrow, and r is added as a reference that borrows from x.
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

-- Here we handle creating a mutable borrow, like let r = &mut x. 
-- The borrowed variable x must exist, must be mutable, and must not be moved. 
-- x cannot already have any borrow, because a mutable borrow must be exclusive. 
-- If everything is valid, x gets one extra mutable borrow, and r is added as a mutable reference that borrows from x.
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

-- Here we release the borrow stored in a variable. 
-- If the variable was not borrowing anything, nothing has to be done. 
-- If it was borrowing another variable, that variable's borrow counter is decreased again. 
-- Mutable references decrease the mutable borrow counter and normal references decrease the immutable borrow counter.
releaseVarBorrow :: VarInfo -> Tc ()
releaseVarBorrow vi = case varBorrowOf vi of
  Nothing -> return ()
  Just y  -> do
    vars <- gets (view tcVars)
    case lookupStack y vars of
      Nothing  -> return ()
      Just yvi -> case varType vi of
        TRefMut _    -> modify (over tcVars (updateStack y yvi { varMutBorrows = varMutBorrows yvi - 1 }))
        TRefMutLt _ _ -> modify (over tcVars (updateStack y yvi { varMutBorrows = varMutBorrows yvi - 1 }))
        _            -> modify (over tcVars (updateStack y yvi { varBorrows     = varBorrows     yvi - 1 }))

-- Here we release all borrows created in the top scope.
-- This is used when leaving a block or function body. 
-- First, variables in this scope that are references stop borrowing from their original variables. 
-- Then it checks that no variable from this scope is still borrowed, because dropping a borrowed value would leave a dangling reference.
releaseTopBorrows :: Tc ()
releaseTopBorrows = do
  vars <- gets (view tcVars)
  let top = topBindings vars
  mapM_ releaseBorrow (Map.toList top)
  vars2 <- gets (view tcVars)
  let top2 = topBindings vars2
  mapM_ checkNotBorrowed (Map.toList top2)
  where
    releaseBorrow (_, vi) = case varBorrowOf vi of
      Nothing -> return ()
      Just y  -> do
        vars <- gets (view tcVars)
        case lookupStack y vars of
          Nothing  -> return ()
          Just yvi -> case varType vi of
            TRefMut _    -> modify (over tcVars (updateStack y yvi { varMutBorrows = varMutBorrows yvi - 1 }))
            TRefMutLt _ _ -> modify (over tcVars (updateStack y yvi { varMutBorrows = varMutBorrows yvi - 1 }))
            _            -> modify (over tcVars (updateStack y yvi { varBorrows     = varBorrows     yvi - 1 }))
    checkNotBorrowed (x, vi) =
      when (varBorrows vi > 0 || varMutBorrows vi > 0) $ throwError $
        printTree x ++ " is dropped while still borrowed (borrow would dangle)"

-- Here we release borrows early using non-lexical lifetimes. 
-- live contains the variables that are still used later. 
-- If a reference variable is not used anymore, its borrow can end now instead of waiting until the end of the whole scope. 
-- After releasing the borrow, the variable is marked as no longer borrowing anything.
releaseExpiredBorrows :: Set.Set Ident -> Tc ()
releaseExpiredBorrows live = do
  vars <- gets (view tcVars)
  let expired = getConst $
        Map.traverseWithKey
          (\x vi -> Const $
            if x `Set.notMember` live && isJust (varBorrowOf vi)
            then [(x, vi)]
            else [])
          (topBindings vars)
  mapM_ releaseAndClear expired
  where
    releaseAndClear (x, vi) = do
      releaseVarBorrow vi
      modify (over tcVars (updateStack x (vi { varBorrowOf = Nothing })))

-- Here we collect all variables that are mentioned in a list of statements. 
-- This is used for non-lexical lifetimes, to know which borrows are still needed later and which ones can be released early.
mentionedVars :: [Stmt] -> Set.Set Ident
mentionedVars = foldMap mentionedStmt

-- Here we collect all variables that are used inside one statement.
-- This is needed for non-lexical lifetimes, because the checker needs to know which variables are still used later and which borrows can end early.
mentionedStmt :: Stmt -> Set.Set Ident
mentionedStmt (SLetImm _ e)         = mentionedExp e
mentionedStmt (SLetMut _ e)         = mentionedExp e
mentionedStmt (SAssign x e)         = Set.singleton x <> mentionedExp e
mentionedStmt (SDerefAssign r e)    = Set.singleton r <> mentionedExp e
mentionedStmt (SIndexAssign x i e)  = Set.singleton x <> mentionedExp i <> mentionedExp e
mentionedStmt (SPush x e)           = Set.singleton x <> mentionedExp e
mentionedStmt (SInsert x i e)       = Set.singleton x <> mentionedExp i <> mentionedExp e
mentionedStmt (SRemove x i)         = Set.singleton x <> mentionedExp i
mentionedStmt (SBlock b)            = mentionedBlock b
mentionedStmt (SIf e b)             = mentionedExp e <> mentionedBlock b
mentionedStmt (SIfElse e b1 b2)     = mentionedExp e <> mentionedBlock b1 <> mentionedBlock b2
mentionedStmt (SWhile e b)          = mentionedExp e <> mentionedBlock b
mentionedStmt (SFun _ _ _ b)        = mentionedBlock b
mentionedStmt (SFunLt _ _ _ _ b)   = mentionedBlock b
mentionedStmt (SSpawn b)            = mentionedBlock b
mentionedStmt (SExpr e)             = mentionedExp e

-- Here we collect all variables mentioned inside a block. 
-- A block is just a list of statements, so this reuses mentionedVars.
mentionedBlock :: Block -> Set.Set Ident
mentionedBlock (Block stmts) = mentionedVars stmts

-- Here we collect all variables that are used inside an expression. 
-- This is used for non-lexical lifetimes, to know which variables are still needed later. 
-- Expressions with subexpressions collect variables from all their parts. 
-- Expressions that do not use variables return an empty set.
mentionedExp :: Exp -> Set.Set Ident
mentionedExp (EVar x)         = Set.singleton x
mentionedExp (ERef x)         = Set.singleton x
mentionedExp (ERefMut x)      = Set.singleton x
mentionedExp (EIndex x e)     = Set.singleton x <> mentionedExp e
mentionedExp (EDeref e)       = mentionedExp e
mentionedExp (ENeg e)         = mentionedExp e
mentionedExp (ENot e)         = mentionedExp e
mentionedExp (EOk e)          = mentionedExp e
mentionedExp (EErr e)         = mentionedExp e
mentionedExp (EMul  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EDiv  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EAdd  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (ESub  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EAnd  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EOr   e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EEq   e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (ENeq  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (ELt   e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EGt   e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (ELeq  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EGeq  e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EPair e1 e2)    = mentionedExp e1 <> mentionedExp e2
mentionedExp (EIf e1 e2 e3)   = mentionedExp e1 <> mentionedExp e2 <> mentionedExp e3
mentionedExp (ELet _ e1 e2)   = mentionedExp e1 <> mentionedExp e2
mentionedExp (ECall f args)   = Set.singleton f <> foldMap mentionedExp args
mentionedExp (EList es)       = foldMap mentionedExp es
mentionedExp (EMatch e arms)  = mentionedExp e  <> foldMap mentionedArm arms
mentionedExp _                = Set.empty

-- Here we collect the variables used inside the body of a match arm.
-- The pattern itself is ignored here, because this function only checks which variables are used later for non-lexical lifetimes.
mentionedArm :: Arm -> Set.Set Ident
mentionedArm (MatchArm _ body) = mentionedExp body
