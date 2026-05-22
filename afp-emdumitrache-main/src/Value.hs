module Value where

import Lang.Abs ( Exp
                , Ident
                , Type )
import Lang.Print ( Print( .. )
                  , doc
                  , concatD )

data Value
    = VInt Integer
    | VBool Bool
  deriving (Show, Eq)

instance Print Value where
  prt _ (VInt n) = doc (shows n)
  prt _ (VBool b) = doc (shows b)

data Closure = Fun Ident Exp
  deriving (Show, Eq)

instance Print Closure where
  prt _ (Fun x e) = concatD [prt 0 x, doc (showString "|->"), prt 0 e]

data TClosure = TFun Type Type
  deriving (Show, Eq)

instance Print TClosure where
  prt _ (TFun a b) = concatD [prt 0 a, doc (showString "->"), prt 0 b]
