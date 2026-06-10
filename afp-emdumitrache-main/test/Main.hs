module Main where

import qualified TypeCheckTests as TypeCheck ( test )
import qualified InterpTests    as Interp    ( test )
import qualified LoggerTests    as Logger    ( test )
import qualified BogusTests     as Bogus     ( test )

main :: IO ()
main = do
    TypeCheck.test
    Interp.test
    Logger.test
    Bogus.test
