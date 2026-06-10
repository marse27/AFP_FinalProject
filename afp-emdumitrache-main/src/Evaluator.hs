-- | Parsing utility: converts AFP source text into a Program AST.
module Evaluator (parse) where

import Lang.Par (myLexer, pProgram)
import Lang.Abs (Program)

-- | Parse source text; return a parse-error string or the Program AST.
parse :: String -> Either String Program
parse = pProgram . myLexer
