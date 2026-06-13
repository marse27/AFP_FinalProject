-- | Thin alias over Data.Map for identifier-keyed environments.
-- Retained for compatibility; the main scoping mechanism is ScopeStack.
module Env where

import qualified Data.Map as Map

import Lang.Abs ( Ident )

-- This is a simple environment. 
-- It connects variable names to values.
type Env a = Map.Map Ident a

-- Creates an empty environment with no stored variables.
empty :: Env a
empty = Map.empty

-- Looks for a variable in the environment. 
-- If the variable exists, its value is returned. 
-- If it does not exist, the result is Nothing.
find :: Ident -> Env a -> Maybe a
find = Map.lookup

-- Adds a new variable and its value to the environment. 
-- If the variable already exists, its old value is replaced.
bind :: Ident -> a -> Env a -> Env a
bind = Map.insert
