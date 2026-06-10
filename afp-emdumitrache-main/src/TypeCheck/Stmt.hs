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

-- | Type-check a statement, updating the Tc context.
infer :: Stmt -> Tc ()
infer (SLetImm r (ERef    x)) = letBorrow    r x False
infer (SLetMut r (ERef    x)) = letBorrow    r x True
infer (SLetImm r (ERefMut x)) = letMutBorrow r x False
infer (SLetMut r (ERefMut x)) = letMutBorrow r x True
infer (SLetImm r (ECall f args)) = callAndBind r f args False
infer (SLetMut r (ECall f args)) = callAndBind r f args True
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
        TRefMut t      -> E.check e t
        TRefMutLt _ t  -> E.check e t
        TRef _         -> throwError $
          printTree r ++ " is an immutable reference; cannot write through it"
        TRefLt _ _     -> throwError $
          printTree r ++ " is an immutable reference; cannot write through it"
        _              -> throwError $
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
infer (SSpawn body) = do
  let freeVs = mentionedBlock body
  vars <- gets (view tcVars)
  let checkCapture x = case lookupStack x vars of
        Nothing -> return ()
        Just vi -> unless (isCopyable (varType vi)) $ throwError $
          "Cannot capture non-Copy variable '" ++ printTree x ++ "' in spawn block"
  mapM_ checkCapture (Set.toList freeVs)
  checkBlock body

-- | Handle 'let r = f(args)' where f may be a lifetime-generic function that
-- returns a reference. For plain TFun, delegates to E.infer. For TFunLt, resolves
-- which argument provides the return borrow and sets up borrow tracking on r.
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

-- | Given a lifetime-generic function's return type and call-site arguments,
-- find which argument provides the return borrow and return the erased type.
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

-- | Check all statements in a block in a fresh inner scope with NLL borrow release.
checkBlock :: Block -> Tc ()
checkBlock (Block stmts) = do
  modify (over tcVars push)
  checkStmtsNLL stmts
  releaseTopBorrows
  modify (over tcVars pop)

-- | Check a sequence of statements with NLL: after each statement, release
-- borrows for top-scope variables not mentioned in remaining statements.
checkStmtsNLL :: [Stmt] -> Tc ()
checkStmtsNLL []       = return ()
checkStmtsNLL (s:rest) = do
  infer s
  releaseExpiredBorrows (mentionedVars rest)
  checkStmtsNLL rest

-- | Check that a function body matches its declared return type, with NLL.
checkBody :: Type -> Block -> Tc ()
checkBody TVoid (Block stmts) = checkStmtsNLL stmts
checkBody _     (Block [])    = throwError "Missing return expression in function body"
checkBody retTy (Block [SExpr e])  = E.check e retTy
checkBody retTy (Block (s : rest)) = do
  infer s
  releaseExpiredBorrows (mentionedVars rest)
  checkBody retTy (Block rest)

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

-- | Release the borrow that vi holds (if any), decrementing the referent's counter.
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

-- | On scope exit: release remaining borrows, then check none of the variables
-- being dropped still has outstanding borrows from an outer scope.
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

-- | NLL: release borrows in the top scope for variables not in the live set.
-- Uses Map.traverseWithKey (a van Laarhoven Traversal over Map Ident VarInfo)
-- with the Const applicative as a structural fold — collecting expired borrows
-- without building intermediate maps or allocating extra closures.
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

-- ---------------------------------------------------------------------------
-- Free-variable analysis for NLL live-set computation
-- ---------------------------------------------------------------------------

-- | Collect all identifiers syntactically mentioned in a list of statements.
-- Conservative (over-approximates): mentions inside nested function bodies and
-- blocks are included, keeping borrows live as long as they syntactically appear.
mentionedVars :: [Stmt] -> Set.Set Ident
mentionedVars = foldMap mentionedStmt

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

mentionedBlock :: Block -> Set.Set Ident
mentionedBlock (Block stmts) = mentionedVars stmts

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

mentionedArm :: Arm -> Set.Set Ident
mentionedArm (MatchArm _ body) = mentionedExp body
