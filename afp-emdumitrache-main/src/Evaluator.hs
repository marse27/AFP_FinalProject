module Evaluator (parse) where

import Lang.Par (myLexer, pProgram)
import Lang.Abs (Program)

-- Here we parse the source code text.
-- The lexer first turns the text into tokens, and the parser then builds the program from those tokens.
-- If parsing fails, an error message is returned.
parse :: String -> Either String Program
parse = pProgram . myLexer
