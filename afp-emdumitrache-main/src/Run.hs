-- | Top-level entry points: parse, type-check, and evaluate AFP programs.
module Run (infertype, run) where

import Evaluator (parse)
import Context   (emptyTcCtx, emptyEvalCtx)
import Tc        (runTc)
import Eval      (runEval)
import Lang.Abs  (Type)
import Value     (Value)
import qualified TypeCheck.Prog as TC
import qualified Interp.Prog    as IP

-- Here we parse and type-check a program.
-- If parsing works, the program is checked from an empty type-checking context.
-- The result is either a type error or the final type of the program.
infertype :: String -> Either String Type
infertype input = do
  prog <- parse input
  case runTc emptyTcCtx (TC.infer prog) of
    Left err -> Left ("Type error: " ++ err)
    Right t  -> Right t

-- Here we parse, type-check, and then run a program.
-- The program is only evaluated if type checking succeeds.
-- This means invalid programs are rejected before the interpreter runs.
-- The result is either a type error, a runtime error, or the final value.
run :: String -> Either String Value
run input = do
  prog <- parse input
  case runTc emptyTcCtx (TC.infer prog) of
    Left err -> Left ("Type error: " ++ err)
    Right _  -> Right ()
  case runEval emptyEvalCtx (IP.interp prog) of
    Left err -> Left ("Runtime error: " ++ err)
    Right v  -> Right v
