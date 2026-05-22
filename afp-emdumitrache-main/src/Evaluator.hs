module Evaluator where

import Env ( Env
           , empty )

import Lang.Abs ( Program )

import Lang.Par ( myLexer
                , pProgram )

type Result a = Either String a

throw :: String -> Result a
throw = Left

type Evaluator a b = Program -> (Env a, Env b) -> Result a

evaluate :: (Evaluator a b, String) -> String -> Result a
evaluate (eval, errDesc) input = do
    prog <- pProgram (myLexer input)
    case eval prog (empty, empty) of
        Left err -> throw $ errDesc ++ " error: " ++ err
        result -> result
