-- | Persistent, immutable stack of scope frames threaded through the type
-- checker and interpreter. Each frame is a Map from Ident to a value.
-- Push / pop are O(1); lookup searches from innermost scope outward.
module ScopeStack
  ( ScopeStack
  , empty
  , push
  , pop
  , insertTop
  , lookupStack
  , updateStack
  , topBindings
  , updateSkipping
  , traverseWithKey
  ) where

import qualified Data.Map.Strict as Map
import Lang.Abs (Ident)

-- | Stack of scope frames; head is the innermost (most recently opened) scope.
newtype ScopeStack a = ScopeStack [Map.Map Ident a]
  deriving (Show, Eq)

-- | One global scope, initially empty.
empty :: ScopeStack a
empty = ScopeStack [Map.empty]

-- | Open a new inner scope (call on block / function-body entry).
push :: ScopeStack a -> ScopeStack a
push (ScopeStack fs) = ScopeStack (Map.empty : fs)

-- | Close the innermost scope, discarding its bindings (call on block exit).
pop :: ScopeStack a -> ScopeStack a
pop (ScopeStack (_:fs@(_:_))) = ScopeStack fs
pop (ScopeStack _)             = ScopeStack [Map.empty]

-- | Bind a name in the innermost scope (shadows any outer binding).
insertTop :: Ident -> a -> ScopeStack a -> ScopeStack a
insertTop x v (ScopeStack (f:fs)) = ScopeStack (Map.insert x v f : fs)
insertTop x v (ScopeStack [])     = ScopeStack [Map.singleton x v]

-- | Search for a name from the innermost scope outward.
lookupStack :: Ident -> ScopeStack a -> Maybe a
lookupStack x (ScopeStack fs) = go fs
  where
    go []       = Nothing
    go (f:rest) = case Map.lookup x f of
      Just v  -> Just v
      Nothing -> go rest

-- | Update the first occurrence of a name where the current value does NOT
-- satisfy the skip predicate. Used for deref-assign to skip reference bindings
-- (VRef/VRefMut) and find the owned value.
updateSkipping :: (a -> Bool) -> Ident -> a -> ScopeStack a -> ScopeStack a
updateSkipping skip x v (ScopeStack fs) = ScopeStack (go fs)
  where
    go []     = []
    go (f:rest) = case Map.lookup x f of
      Just cur | skip cur -> f : go rest
      Just _              -> Map.insert x v f : rest
      Nothing             -> f : go rest

-- | Return the bindings in the innermost scope.
topBindings :: ScopeStack a -> Map.Map Ident a
topBindings (ScopeStack (f:_)) = f
topBindings (ScopeStack [])    = Map.empty

-- | Van Laarhoven Traversal over all (key, value) pairs across all scope frames.
-- With Const applicative, acts as a structural fold; with Identity, maps uniformly.
-- Visits frames from innermost to outermost; each (k, v) pair visited once per frame.
traverseWithKey :: Applicative f
                => (Ident -> a -> f a) -> ScopeStack a -> f (ScopeStack a)
traverseWithKey f (ScopeStack frames) =
  ScopeStack <$> traverse (Map.traverseWithKey f) frames

-- | Update the first occurrence of a name (innermost scope first).
updateStack :: Ident -> a -> ScopeStack a -> ScopeStack a
updateStack x v (ScopeStack fs) = ScopeStack (go fs)
  where
    go []       = []
    go (f:rest)
      | Map.member x f = Map.insert x v f : rest
      | otherwise       = f : go rest
