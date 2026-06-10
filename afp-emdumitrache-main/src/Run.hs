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

-- | Parse and type-check a program; returns its result type.
infertype :: String -> Either String Type
infertype input = do
  prog <- parse input
  case runTc emptyTcCtx (TC.infer prog) of
    Left err -> Left ("Type error: " ++ err)
    Right t  -> Right t

-- | Parse, type-check, and evaluate a program; returns its final value.
run :: String -> Either String Value
run input = do
  prog <- parse input
  case runTc emptyTcCtx (TC.infer prog) of
    Left err -> Left ("Type error: " ++ err)
    Right _  -> Right ()
  case runEval emptyEvalCtx (IP.interp prog) of
    Left err -> Left ("Runtime error: " ++ err)
    Right v  -> Right v
