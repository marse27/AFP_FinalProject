module Run where

import Evaluator

import Lang.Abs ( Type
                , Program )
import TypeCheck.Prog ( infer )

import Value ( Value )
import Interp.Prog ( interp )

infertype :: String -> Result Type
infertype = evaluate (infer, "Type")

run :: String -> Result Value
run input = do
    _ <- infertype input
    evaluate (interp, "Runtime") input
