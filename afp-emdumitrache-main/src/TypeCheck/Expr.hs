-- | Type inference and checking for expressions, running in the Tc monad.
-- Phase 1: EVar consumes ownership of affine (non-copyable) variables.
-- Phase 2A: EList infers list types; EIndex reads without consuming the list.
-- Phase 2C: EOk/EErr/EPair construct Result/pair types; EMatch pattern-matches
--           with exhaustiveness checking.
-- Phase 3A: ERef creates an immutable borrow; EDeref reads through a reference.
-- Phase 3B: ERefMut creates a mutable borrow; EDeref also handles TRefMut
--           as a place expression (no ownership transfer on dereference).
module TypeCheck.Expr (infer, check) where

import Control.Monad        (unless, when)
import Control.Monad.Except (throwError)
import Control.Monad.State  (gets, modify)

import qualified Data.Map.Strict as Map

import Lang.Abs   (Arm (..), Exp (..), Pat (..), Type (..))
import Lang.Print (printTree)

import Context    (VarInfo (..), tcVars, tcFuns, view, over)
import ScopeStack (lookupStack, insertTop, updateStack, push, pop)
import Tc         (Tc)
import Value      (TClosure (..), isCopyable, paramType)

-- | Check that an expression has exactly the expected type.
check :: Exp -> Type -> Tc ()
check e expected = do
  actual <- infer e
  unless (expected == actual) $ throwError $
    "Expression " ++ printTree e ++
    " should be of type " ++ printTree expected ++
    " but has type " ++ printTree actual

-- | Infer the type of an expression.
-- Reading an affine (non-copyable) variable transfers ownership and marks it
-- as unowned; re-reading it afterwards is a type error.
infer :: Exp -> Tc Type
infer (EInt _)        = return TInt
infer ETrue           = return TBool
infer EFalse          = return TBool
infer ELightRed       = return TLight
infer ELightYellow    = return TLight
infer ELightGreen     = return TLight
infer (ENeg e)        = check e TInt >> return TInt
infer (EMul e1 e2)    = arithmetic e1 e2
infer (EDiv e1 e2)    = arithmetic e1 e2
infer (EAdd e1 e2)    = arithmetic e1 e2
infer (ESub e1 e2)    = arithmetic e1 e2
infer (ENot e)        = check e TBool >> return TBool
infer (EAnd e1 e2)    = logic e1 e2
infer (EOr  e1 e2)    = logic e1 e2
infer (EEq  e1 e2)    = infer e1 >>= \t -> check e2 t >> return TBool
infer (ENeq e1 e2)    = infer e1 >>= \t -> check e2 t >> return TBool
infer (ELt  e1 e2)    = comparison e1 e2
infer (EGt  e1 e2)    = comparison e1 e2
infer (ELeq e1 e2)    = comparison e1 e2
infer (EGeq e1 e2)    = comparison e1 e2
infer (EIf c t f) = do
  check c TBool
  ty <- infer t
  check f ty
  return ty
infer (ELet x e body) = do
  t <- infer e
  modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing) . push))
  result <- infer body
  modify (over tcVars pop)
  return result
infer (EVar x) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ show x ++ " is not bound"
    Just vi  -> do
      let t = varType vi
      unless (isCopyable t || varOwned vi) $
        throwError $ "Value of " ++ printTree x ++ " used after being moved"
      when (not (isCopyable t) && (varBorrows vi > 0 || varMutBorrows vi > 0)) $
        throwError $ "Cannot move " ++ printTree x ++ ": value is borrowed"
      unless (isCopyable t) $
        modify (over tcVars (updateStack x vi { varOwned = False }))
      return t
infer (ECall f args) = do
  funs <- gets (view tcFuns)
  case Map.lookup f funs of
    Nothing -> throwError $ "Function " ++ show f ++ " is not defined"
    Just (TFun params retTy) -> do
      when (length args /= length params) $
        throwError $ "Function " ++ show f ++
          " expects " ++ show (length params) ++
          " argument(s) but got " ++ show (length args)
      mapM_ (\(e, p) -> check e (paramType p)) (zip args params)
      return retTy
infer (EList []) = throwError "Cannot infer type of empty list literal"
infer (EList (e:es)) = do
  t <- infer e
  unless (isCopyable t) $
    throwError $ "List element type must be copyable, but got " ++ printTree t
  mapM_ (`check` t) es
  return (TList t)
infer (EIndex x i) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $
        throwError $ "Value of " ++ printTree x ++ " used after being moved"
      case varType vi of
        TList elemT -> check i TInt >> return elemT
        t           -> throwError $ "Cannot index a value of type " ++ printTree t
infer (EOk e)  = TResult <$> infer e
infer (EErr e) = TResult <$> infer e
infer (EPair e1 e2) = TPair <$> infer e1 <*> infer e2
infer (ERef x) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      return (TRef (varType vi))
infer (ERefMut x) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      unless (varMut vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ " as mutable: variable is not mutable"
      return (TRefMut (varType vi))
-- | Dereference a reference. When the sub-expression is a plain variable
-- holding a TRef or TRefMut, we treat it as a place expression so the
-- reference is not consumed (TRefMut is non-Copy, but can be reused via deref).
infer (EDeref (EVar r)) = do
  vars <- gets (view tcVars)
  case lookupStack r vars of
    Nothing -> throwError $ "Variable " ++ printTree r ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Value of " ++ printTree r ++ " used after being moved"
      case varType vi of
        TRef inner    -> return inner
        TRefMut inner -> return inner
        t             -> throwError $ "Cannot dereference " ++ printTree r ++
                         " of type " ++ printTree t
infer (EDeref e) = do
  t <- infer e
  case t of
    TRef inner    -> return inner
    TRefMut inner -> return inner
    _             -> throwError $ "Cannot dereference a value of type " ++ printTree t
infer (EMatch e arms) = do
  scrutTy <- infer e
  case arms of
    [] -> throwError "Empty match expression"
    (first : rest) -> do
      checkExhaustive scrutTy (map getArmPat arms)
      t <- inferArm scrutTy first
      mapM_ (\arm -> checkArmType scrutTy arm t) rest
      return t

-- | Extract the pattern from a match arm.
getArmPat :: Arm -> Pat
getArmPat (MatchArm p _) = p

-- | Infer the result type of one match arm, binding pattern variables in scope.
inferArm :: Type -> Arm -> Tc Type
inferArm scrutTy (MatchArm pat body) = do
  modify (over tcVars push)
  bindArmPat scrutTy pat
  t <- infer body
  modify (over tcVars pop)
  return t

-- | Check that a match arm's body has the expected result type.
checkArmType :: Type -> Arm -> Type -> Tc ()
checkArmType scrutTy arm expected = do
  actual <- inferArm scrutTy arm
  unless (actual == expected) $ throwError $
    "Match arm has type " ++ printTree actual ++
    " but expected " ++ printTree expected

-- | Bind pattern variables into the current (innermost) scope.
-- Errors if the pattern is incompatible with the scrutinee type.
bindArmPat :: Type -> Pat -> Tc ()
bindArmPat TLight   PLightRed    = return ()
bindArmPat TLight   PLightYellow = return ()
bindArmPat TLight   PLightGreen  = return ()
bindArmPat (TResult t) (POk  x) = modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))
bindArmPat (TResult t) (PErr x) = modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing)))
bindArmPat (TPair t1 t2) (PPair x y) = do
  modify (over tcVars (insertTop x (VarInfo t1 False True 0 0 Nothing)))
  modify (over tcVars (insertTop y (VarInfo t2 False True 0 0 Nothing)))
bindArmPat scrutTy (PVar x) =
  modify (over tcVars (insertTop x (VarInfo scrutTy False True 0 0 Nothing)))
bindArmPat scrutTy _ =
  throwError $ "Pattern does not match type " ++ printTree scrutTy

-- | Check that the patterns cover all constructors of the scrutinee type.
checkExhaustive :: Type -> [Pat] -> Tc ()
checkExhaustive TLight pats
  | any isWild pats = return ()
  | PLightRed `elem` pats && PLightYellow `elem` pats && PLightGreen `elem` pats = return ()
  | otherwise = throwError
      "Non-exhaustive match on Light: must cover Red, Yellow, and Green"
checkExhaustive (TResult _) pats
  | any isWild pats = return ()
  | any isOkPat pats && any isErrPat pats = return ()
  | otherwise = throwError
      "Non-exhaustive match on Result: must cover Ok and Err"
checkExhaustive (TPair _ _) pats
  | any isWild pats = return ()
  | any isPairPat pats = return ()
  | otherwise = throwError
      "Non-exhaustive match on pair: must cover the pair constructor"
checkExhaustive t _ =
  throwError $ "Cannot match on type " ++ printTree t

isWild :: Pat -> Bool
isWild (PVar _) = True
isWild _        = False

isOkPat :: Pat -> Bool
isOkPat (POk _) = True
isOkPat _       = False

isErrPat :: Pat -> Bool
isErrPat (PErr _) = True
isErrPat _        = False

isPairPat :: Pat -> Bool
isPairPat (PPair _ _) = True
isPairPat _           = False

arithmetic :: Exp -> Exp -> Tc Type
arithmetic e1 e2 = check e1 TInt >> check e2 TInt >> return TInt

logic :: Exp -> Exp -> Tc Type
logic e1 e2 = check e1 TBool >> check e2 TBool >> return TBool

comparison :: Exp -> Exp -> Tc Type
comparison e1 e2 = check e1 TInt >> check e2 TInt >> return TBool
