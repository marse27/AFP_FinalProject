module Interp.Stmt where
import Eval     (Eval)
import Lang.Abs (Stmt)
interp :: Stmt -> Eval ()
