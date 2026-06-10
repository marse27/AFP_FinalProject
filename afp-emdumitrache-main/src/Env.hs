-- | Thin alias over Data.Map for identifier-keyed environments.
-- Retained for compatibility; the main scoping mechanism is ScopeStack.
module Env where

import qualified Data.Map as Map

import Lang.Abs ( Ident )

-- | An environment mapping identifiers to values of type @a@.
type Env a = Map.Map Ident a

-- | Empty environment with no bindings.
empty :: Env a
empty = Map.empty

-- | Look up an identifier; returns Nothing if not present.
find :: Ident -> Env a -> Maybe a
find = Map.lookup

-- | Extend the environment with a new binding.
bind :: Ident -> a -> Env a -> Env a
bind = Map.insert
