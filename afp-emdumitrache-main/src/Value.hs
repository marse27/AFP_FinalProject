-- Runtime values and closure representations for the AFP interpreter.
module Value where

import Data.List  (intercalate)
import Lang.Abs   (Block, Ident, Param (..), Type (..))
import Lang.Print (Print (..), doc, printTree)

data Value
    = VInt Integer
    | VBool Bool
    | VUnit
    | VLightRed
    | VLightYellow
    | VLightGreen
    | VList [Value]
    | VOk  Value
    | VErr Value
    | VPair Value Value
    | VRef    Ident
    | VRefMut Ident
  deriving (Show, Eq)

-- Here we define how runtime values are printed. 
-- This is only for displaying results in a readable way, not for evaluating or type-checking the program.
instance Print Value where
  prt _ (VInt n)       = doc (shows n)
  prt _ (VBool b)      = doc (shows b)
  prt _ VUnit          = doc (showString "()")
  prt _ VLightRed      = doc (showString "Red")
  prt _ VLightYellow   = doc (showString "Yellow")
  prt _ VLightGreen    = doc (showString "Green")
  prt _ (VList vs)     = doc (showString ("[" ++ intercalate ", " (map printTree vs) ++ "]"))
  prt _ (VOk v)        = doc (showString ("Ok(" ++ printTree v ++ ")"))
  prt _ (VErr v)       = doc (showString ("Err(" ++ printTree v ++ ")"))
  prt _ (VPair a b)    = doc (showString ("(" ++ printTree a ++ ", " ++ printTree b ++ ")"))
  prt _ (VRef x)       = doc (showString ("&"     ++ printTree x))
  prt _ (VRefMut x)   = doc (showString ("&mut " ++ printTree x))

-- Here we decide which types can be copied instead of moved. 
-- Integers, booleans, normal references, and unit values are copyable. 
-- Light values, lists, and mutable references are not copyable. 
-- Result and pair values are copyable only if the values inside them are copyable.
isCopyable :: Type -> Bool
isCopyable TLight         = False
isCopyable (TList _)      = False
isCopyable (TResult t)    = isCopyable t
isCopyable (TPair t u)    = isCopyable t && isCopyable u
isCopyable (TRef _)       = True
isCopyable (TRefLt _ _)   = True
isCopyable (TRefMut _)    = False
isCopyable (TRefMutLt _ _) = False
isCopyable _              = True

-- Here we remove explicit lifetime information from a reference type. 
-- This is useful when checking arguments, because the runtime reference type is just TRef or TRefMut.
eraseLifetime :: Type -> Type
eraseLifetime (TRefLt _ t)    = TRef t
eraseLifetime (TRefMutLt _ t) = TRefMut t
eraseLifetime t               = t

-- A runtime function closure stores the parameters and the function body. 
-- The body is saved here and executed later when the function is called.
data Closure = Fun [Param] Block

-- Closures are printed as a placeholder because showing the whole function body would not be useful as a runtime result.
instance Print Closure where
  prt _ _ = doc (showString "<closure>")

-- A type-level function closure stores the function's parameter types and return type for the type checker. 
-- TFun is for normal functions. 
-- TFunLt is for functions with explicit lifetimes.
data TClosure = TFun   [Param] Type
              | TFunLt [Ident] [Param] Type
  deriving (Show, Eq)

-- Function types are printed as a placeholder because they are internal type-checker information.
instance Print TClosure where
  prt _ _ = doc (showString "<fn-type>")

-- Gets the name of a function parameter. 
-- Mutable and immutable parameters both store their name in the same place.
paramIdent :: Param -> Ident
paramIdent (ParamImm x _) = x
paramIdent (ParamMut  x _) = x

-- Gets the type of a function parameter.
-- Mutable and immutable parameters both store their type in the same place.
paramType :: Param -> Type
paramType (ParamImm _ t) = t
paramType (ParamMut  _ t) = t
