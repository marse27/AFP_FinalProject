-- | Typing and evaluation contexts, plus van Laarhoven lenses for their fields.
-- Lenses let callers update nested context fields without boilerplate record
-- syntax; they are the primary optics technique used throughout the checker.
module Context
  ( TcCtx (..)
  , EvalCtx (..)
  , VarInfo (..)
  , emptyTcCtx
  , emptyEvalCtx
  , tcVars, tcFuns
  , evalVars, evalFuns
  , Lens'
  , view, over, set
  ) where

import qualified Data.Map.Strict as Map
import Data.Functor.Const    (Const (..))
import Data.Functor.Identity (Identity (..))

import Lang.Abs   (Ident, Type)
import ScopeStack (ScopeStack)
import qualified ScopeStack as SS
import Value      (TClosure, Closure, Value)

-- Van Laarhoven lens type (RankNTypes is part of GHC2021).
type Lens' s a = forall f. Functor f => (a -> f a) -> s -> f s

-- | Read a field through a lens.
view :: Lens' s a -> s -> a
view l s = getConst (l Const s)

-- | Modify a field through a lens.
over :: Lens' s a -> (a -> a) -> s -> s
over l f s = runIdentity (l (Identity . f) s)

-- | Set a field through a lens.
set :: Lens' s a -> a -> s -> s
set l v = over l (const v)

-- | Per-variable information tracked by the type checker.
-- varOwned = False means the value was moved away (affine types only).
-- varBorrows counts active immutable borrows of this variable.
-- varMutBorrows counts active mutable borrows of this variable (max 1 by exclusivity).
-- varBorrowOf = Just x means this variable is a reference holding a borrow of x.
data VarInfo = VarInfo
  { varType       :: Type
  , varMut        :: Bool
  , varOwned      :: Bool
  , varBorrows    :: Int
  , varMutBorrows :: Int
  , varBorrowOf   :: Maybe Ident
  } deriving (Show, Eq)

-- | Context used by the type checker.
data TcCtx = TcCtx
  { _tcVars :: ScopeStack VarInfo
  , _tcFuns :: Map.Map Ident TClosure
  }

-- | Context used by the interpreter.
data EvalCtx = EvalCtx
  { _evalVars :: ScopeStack Value
  , _evalFuns :: Map.Map Ident Closure
  }

-- | Lens into the variable scope stack of a type-checker context.
tcVars :: Lens' TcCtx (ScopeStack VarInfo)
tcVars f ctx = (\v -> ctx { _tcVars = v }) <$> f (_tcVars ctx)

-- | Lens into the function-type map of a type-checker context.
tcFuns :: Lens' TcCtx (Map.Map Ident TClosure)
tcFuns f ctx = (\v -> ctx { _tcFuns = v }) <$> f (_tcFuns ctx)

-- | Lens into the variable scope stack of an interpreter context.
evalVars :: Lens' EvalCtx (ScopeStack Value)
evalVars f ctx = (\v -> ctx { _evalVars = v }) <$> f (_evalVars ctx)

-- | Lens into the function-closure map of an interpreter context.
evalFuns :: Lens' EvalCtx (Map.Map Ident Closure)
evalFuns f ctx = (\v -> ctx { _evalFuns = v }) <$> f (_evalFuns ctx)

-- | Initial type-checker context: one empty global scope, no functions.
emptyTcCtx :: TcCtx
emptyTcCtx = TcCtx SS.empty Map.empty

-- | Initial interpreter context: one empty global scope, no functions.
emptyEvalCtx :: EvalCtx
emptyEvalCtx = EvalCtx SS.empty Map.empty
