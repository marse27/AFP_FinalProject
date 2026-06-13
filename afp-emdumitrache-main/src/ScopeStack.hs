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
  , mergeWith
  ) where

import qualified Data.Map.Strict as Map
import Lang.Abs (Ident)

-- A ScopeStack stores variables in nested scopes. 
-- The first map is the current scope, and the maps after it are outer scopes.
newtype ScopeStack a = ScopeStack [Map.Map Ident a]
  deriving (Show, Eq)

-- Creates an empty scope stack with one global scope.
empty :: ScopeStack a
empty = ScopeStack [Map.empty]

-- Opens a new scope on top of the current ones. 
-- New variables will be inserted into this top scope.
push :: ScopeStack a -> ScopeStack a
push (ScopeStack fs) = ScopeStack (Map.empty : fs)

-- Removes the current top scope. 
-- If this would remove every scope, it keeps one empty global scope instead.
pop :: ScopeStack a -> ScopeStack a
pop (ScopeStack (_:fs@(_:_))) = ScopeStack fs
pop (ScopeStack _)             = ScopeStack [Map.empty]

-- Inserts or replaces a variable in the current top scope.
insertTop :: Ident -> a -> ScopeStack a -> ScopeStack a
insertTop x v (ScopeStack (f:fs)) = ScopeStack (Map.insert x v f : fs)
insertTop x v (ScopeStack [])     = ScopeStack [Map.singleton x v]

-- Looks for a variable starting from the current scope. 
-- If it is not found there, it continues searching in the outer scopes.
lookupStack :: Ident -> ScopeStack a -> Maybe a
lookupStack x (ScopeStack fs) = go fs
  where
    go []       = Nothing
    go (f:rest) = case Map.lookup x f of
      Just v  -> Just v
      Nothing -> go rest

-- Updates a variable, but skips bindings that match the skip function. 
-- This is useful when a name exists both as a reference and as a real value, and the update should affect the real value behind the reference instead.
updateSkipping :: (a -> Bool) -> Ident -> a -> ScopeStack a -> ScopeStack a
updateSkipping skip x v (ScopeStack fs) = ScopeStack (go fs)
  where
    go []     = []
    go (f:rest) = case Map.lookup x f of
      Just cur | skip cur -> f : go rest
      Just _              -> Map.insert x v f : rest
      Nothing             -> f : go rest

-- Returns only the bindings from the current top scope.
topBindings :: ScopeStack a -> Map.Map Ident a
topBindings (ScopeStack (f:_)) = f
topBindings (ScopeStack [])    = Map.empty

-- Applies a function to every binding in every scope. 
-- This is used when the checker needs to inspect or update all variables.
traverseWithKey :: Applicative f
                => (Ident -> a -> f a) -> ScopeStack a -> f (ScopeStack a)
traverseWithKey f (ScopeStack frames) =
  ScopeStack <$> traverse (Map.traverseWithKey f) frames

-- Merges two scope stacks frame-by-frame using the given combining function.
-- Both stacks must have the same structure (same number of frames, same keys).
-- Used to join the post-branch contexts of an if-else.
mergeWith :: (a -> a -> a) -> ScopeStack a -> ScopeStack a -> ScopeStack a
mergeWith f (ScopeStack fs1) (ScopeStack fs2) = ScopeStack (zipWith mergeFrame fs1 fs2)
  where mergeFrame m1 m2 = Map.intersectionWith f m1 m2

-- Updates the first matching variable found from inner to outer scopes.
-- This respects shadowing, because the closest variable is updated first.
updateStack :: Ident -> a -> ScopeStack a -> ScopeStack a
updateStack x v (ScopeStack fs) = ScopeStack (go fs)
  where
    go []       = []
    go (f:rest)
      | Map.member x f = Map.insert x v f : rest
      | otherwise       = f : go rest
