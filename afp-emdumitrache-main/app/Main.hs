module Main where

import Run ( run )
import System.Environment ( getArgs )
import System.IO ( hSetBuffering
                 , stdout
                 , BufferMode(NoBuffering) )
import Lang.Print ( printTree )

eval :: String -> IO ()
eval program = putStrLn $
    case run program of
        Left  err -> err
        Right val -> printTree val

main :: IO ()
main = do
    -- Read command-line arguments
    args <- getArgs
    case args of
        -- If no argument is provided, use standard input with Haskeline
        [] -> do
            hSetBuffering stdout NoBuffering
            loop
        -- If a file is provided, read the file and interpret it
        (fileName:_) -> do
            program <- readFile fileName
            eval program
    where
        loop :: IO ()
        loop = do
            putStr "Enter an expression (:q to quit): "
            input <- getLine
            case input of
                ":q" -> putStrLn "Goodbye!"
                prog -> do
                    eval prog
                    loop
