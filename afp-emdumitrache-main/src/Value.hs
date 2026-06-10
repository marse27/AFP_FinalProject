-- | Runtime values and closure representations for the AFP interpreter.
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

-- | True if values of this type are implicitly copyable (read without consuming).
-- int and bool are Copy; Light, lists, Result, and pairs (with non-Copy components) are affine.
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

-- | Strip explicit lifetime annotations from reference types.
-- At call sites the caller's '&x' has type 'TRef T'; a parameter declared
-- '&'a T' (= 'TRefLt lt T') must accept it after erasure.
eraseLifetime :: Type -> Type
eraseLifetime (TRefLt _ t)    = TRef t
eraseLifetime (TRefMutLt _ t) = TRefMut t
eraseLifetime t               = t

-- | Multi-parameter function closure (params + body block).
data Closure = Fun [Param] Block

instance Print Closure where
  prt _ _ = doc (showString "<closure>")

-- | Multi-parameter function type closure (param list + return type).
-- TFunLt carries lifetime parameter names so the call site can resolve borrow sources.
data TClosure = TFun   [Param] Type
              | TFunLt [Ident] [Param] Type
  deriving (Show, Eq)

instance Print TClosure where
  prt _ _ = doc (showString "<fn-type>")

-- | Extract the declared identifier from a parameter.
paramIdent :: Param -> Ident
paramIdent (ParamImm x _) = x
paramIdent (ParamMut  x _) = x

-- | Extract the declared type from a parameter.
paramType :: Param -> Type
paramType (ParamImm _ t) = t
paramType (ParamMut  _ t) = t
