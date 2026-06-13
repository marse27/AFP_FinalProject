-- Type inference and checking for expressions, running in the Tc monad.
-- Phase 1: EVar consumes ownership of affine (non-copyable) variables.
-- Phase 2A: EList infers list types; EIndex reads without consuming the list.
-- Phase 2C: EOk/EErr/EPair construct Result/pair types; EMatch pattern-matches with exhaustiveness checking.
-- Phase 3A: ERef creates an immutable borrow; EDeref reads through a reference.
-- Phase 3B: ERefMut creates a mutable borrow; EDeref also handles TRefMut as a place expression (no ownership transfer on dereference).
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
import Value      (TClosure (..), eraseLifetime, isCopyable, paramType)

-- Here we check that an expression has the type that is expected.
-- First the actual type of the expression is inferred.
-- If it is different from the expected type, an error is thrown.
check :: Exp -> Type -> Tc ()
check e expected = do
  actual <- infer e
  unless (expected == actual) $ throwError $
    "Expression " ++ printTree e ++
    " should be of type " ++ printTree expected ++
    " but has type " ++ printTree actual

-- Basic expressions and operators.
-- Values like numbers, booleans, and lights already have a known type.
-- Operators first check their inputs, then return the correct result type.
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
infer (EEq  e1 e2)    = do
  t <- infer e1
  check e2 t
  unless (t `elem` [TInt, TBool, TLight]) $
    throwError $ "Equality is only supported for int, bool, and Light, not " ++ printTree t
  return TBool
infer (ENeq e1 e2)    = do
  t <- infer e1
  check e2 t
  unless (t `elem` [TInt, TBool, TLight]) $
    throwError $ "Equality is only supported for int, bool, and Light, not " ++ printTree t
  return TBool
infer (ELt  e1 e2)    = comparison e1 e2
infer (EGt  e1 e2)    = comparison e1 e2
infer (ELeq e1 e2)    = comparison e1 e2
infer (EGeq e1 e2)    = comparison e1 e2

-- Here we handle an if-expression.
-- The condition must be a boolean.
-- The first branch gives the result type, and the else branch must have the same type.
infer (EIf c t f) = do
  check c TBool
  ty <- infer t
  check f ty
  return ty

-- Here we handle a local let-expression like let x = e in body.
-- First the value assigned to x is checked.
-- Then x is added in a new scope while the body is checked.
-- After the body is done, that scope is removed.
infer (ELet x e body) = do
  t <- infer e
  modify (over tcVars (insertTop x (VarInfo t False True 0 0 Nothing) . push))
  result <- infer body
  modify (over tcVars pop)
  return result

-- Here we handle using a variable like x.
-- We check that x exists and that its value was not already moved.
-- We also make sure the value is not borrowed, because borrowed values cannot be moved. If it is not copyable, this use moves it.
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

-- Here we handle calling a function like f(arg1, arg2).
-- We check that the function exists, that the number of arguments is correct, and that each argument has the type expected by the function parameter.
-- For lifetime-generic functions, returned references are only allowed when they are immediately stored with let, so their lifetime can be tracked safely.
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
    Just (TFunLt _ params retTy) -> do
      when (length args /= length params) $
        throwError $ "Function " ++ show f ++
          " expects " ++ show (length params) ++
          " argument(s) but got " ++ show (length args)
      mapM_ (\(e, p) -> check e (eraseLifetime (paramType p))) (zip args params)
      case retTy of
        TRefLt _ _    -> throwError $
          "Return value of lifetime-generic function " ++ show f ++
          " must be immediately bound: use 'let r = " ++ show f ++ "(...)'"
        TRefMutLt _ _ -> throwError $
          "Return value of lifetime-generic function " ++ show f ++
          " must be immediately bound: use 'let r = " ++ show f ++ "(...)'"
        _ -> return retTy

-- Empty lists are not allowed here because there is no first element from which the list type can be guessed.
infer (EList []) = throwError "Cannot infer type of empty list literal"

-- Here we handle a list with at least one element.
-- The first element decides the type of the list.
-- All other elements must have the same type, and the element type must be copyable.
infer (EList (e:es)) = do
  t <- infer e
  unless (isCopyable t) $
    throwError $ "List element type must be copyable, but got " ++ printTree t
  mapM_ (`check` t) es
  return (TList t)

-- Here we handle accessing an element from a list like list[0].
-- We check that the variable exists, that its value was not already moved, and that it is actually a list. The index must be an integer, and the result has the type of the list elements.
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

-- Here we handle creating Result values.
-- The type inside Ok(...) or Err(...) becomes the type stored in the Result.
infer (EOk e)  = TResult <$> infer e
infer (EErr e) = TResult <$> infer e

-- Here we handle creating a pair like (x, y).
-- The type of the pair is built from the types of its two values.
infer (EPair e1 e2) = TPair <$> infer e1 <*> infer e2

-- Here we handle creating an immutable borrow like &x.
-- We check that x exists and that its value was not already moved.
-- If it is valid, the result is a reference to the type of x.
infer (ERef x) = do
  vars <- gets (view tcVars)
  case lookupStack x vars of
    Nothing -> throwError $ "Variable " ++ printTree x ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": value has been moved"
      when (varMutBorrows vi > 0) $ throwError $
        "Cannot borrow " ++ printTree x ++ ": already mutably borrowed"
      return (TRef (varType vi))

-- Here we handle creating a mutable borrow like &mut x.
-- We check that x exists, that its value was not already moved, and that x was declared as mutable.
-- If it is valid, the result is a mutable reference to the type of x.
infer (ERefMut x) = do
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
      return (TRefMut (varType vi))

-- Here we handle dereferencing a reference variable like *r.
-- We check that r exists, that the reference itself was not already moved, and that r really has a reference type.
-- The result is the type of the value that the reference points to.
infer (EDeref (EVar r)) = do
  vars <- gets (view tcVars)
  case lookupStack r vars of
    Nothing -> throwError $ "Variable " ++ printTree r ++ " is not bound"
    Just vi -> do
      unless (varOwned vi) $ throwError $
        "Value of " ++ printTree r ++ " used after being moved"
      case varType vi of
        TRef inner      -> return inner
        TRefMut inner   -> return inner
        TRefLt _ inner  -> return inner
        TRefMutLt _ inner -> return inner
        t               -> throwError $ "Cannot dereference " ++ printTree r ++
                           " of type " ++ printTree t

-- Here we handle dereferencing any expression.
-- First the expression is checked to find its type.
-- It must be some kind of reference, otherwise there is nothing to dereference.
-- The result is the type stored inside the reference.
infer (EDeref e) = do
  t <- infer e
  case t of
    TRef inner      -> return inner
    TRefMut inner   -> return inner
    TRefLt _ inner  -> return inner
    TRefMutLt _ inner -> return inner
    _               -> throwError $ "Cannot dereference a value of type " ++ printTree t

-- Here we handle a match expression.
-- First the expression being matched is checked, so its type is known.
-- Then there must be at least one match arm, the patterns must cover all cases, and every arm must return the same type.
infer (EMatch e arms) = do
  scrutTy <- infer e
  case arms of
    [] -> throwError "Empty match expression"
    (first : rest) -> do
      checkExhaustive scrutTy (map getArmPat arms)
      t <- inferArm scrutTy first
      mapM_ (\arm -> checkArmType scrutTy arm t) rest
      return t

-- Gets only the pattern part from a match arm.
-- This is used when checking whether all needed patterns are covered.
getArmPat :: Arm -> Pat
getArmPat (MatchArm p _) = p

-- Here we check one match arm.
-- A new scope is opened because variables introduced by the pattern should only exist inside this arm.
-- After checking the arm body, that temporary scope is removed.
inferArm :: Type -> Arm -> Tc Type
inferArm scrutTy (MatchArm pat body) = do
  modify (over tcVars push)
  bindArmPat scrutTy pat
  t <- infer body
  modify (over tcVars pop)
  return t

-- Here we check that another match arm has the same type as the first arm that was already checked. 
-- This is needed because all branches of a match expression must return the same kind of value.
checkArmType :: Type -> Arm -> Type -> Tc ()
checkArmType scrutTy arm expected = do
  actual <- inferArm scrutTy arm
  unless (actual == expected) $ throwError $
    "Match arm has type " ++ printTree actual ++
    " but expected " ++ printTree expected

-- Here we handle the pattern of a match arm. 
-- The pattern must fit the type of the value being matched. 
-- If the pattern introduces variables, those variables are added to the current scope with the correct type.
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

-- Here we check that a match expression does not miss any case.
-- For Light, all three values must be covered: Red, Yellow, and Green.
-- For Result, both Ok and Err must be covered.
-- For Pair, one pair pattern is enough.
-- A wildcard pattern is always enough because it matches anything.
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

-- Checks if a pattern is a wildcard-like variable pattern. 
  -- This matches anything, so it can make a match expression complete.
isWild :: Pat -> Bool
isWild (PVar _) = True
isWild _        = False

-- Checks if a pattern is an Ok(...) pattern. 
-- This is used when checking that a Result match covers the Ok case.
isOkPat :: Pat -> Bool
isOkPat (POk _) = True
isOkPat _       = False

-- Checks if a pattern is an Err(...) pattern. 
-- This is used when checking that a Result match covers the Err case.
isErrPat :: Pat -> Bool
isErrPat (PErr _) = True
isErrPat _        = False

-- Checks if a pattern is a pair pattern like (x, y). 
-- For pairs, one pair pattern is enough to cover the match.
isPairPat :: Pat -> Bool
isPairPat (PPair _ _) = True
isPairPat _           = False

-- Here we check arithmetic expressions like +, -, *, and /. 
-- Both sides must be integers, and the result is also an integer.
arithmetic :: Exp -> Exp -> Tc Type
arithmetic e1 e2 = check e1 TInt >> check e2 TInt >> return TInt

-- Here we check boolean expressions like && and ||. 
-- Both sides must be booleans, and the result is also a boolean.
logic :: Exp -> Exp -> Tc Type
logic e1 e2 = check e1 TBool >> check e2 TBool >> return TBool

-- Here we check comparisons like <, >, <=, and >=. 
-- Both sides must be integers, and the result is a boolean.
comparison :: Exp -> Exp -> Tc Type
comparison e1 e2 = check e1 TInt >> check e2 TInt >> return TBool
