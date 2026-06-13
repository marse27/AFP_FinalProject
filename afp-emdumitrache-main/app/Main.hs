module Main where

import Data.List          (isPrefixOf, partition)
import System.Environment (getArgs)
import System.IO          (hSetBuffering, stdout, BufferMode (NoBuffering))
import Lang.Print         (printTree)
import Logger             (Logger, LogMsg (..), startLogger, stopLogger, logMsg)
import Run                (run)

-- Here we run one program input.
-- The logger records when running starts and ends. 
-- The program is type-checked and evaluated through run. 
-- If something goes wrong, the error is printed. 
-- If it succeeds, the final value is printed.
eval :: Logger -> String -> IO ()
eval logger program = do
  logMsg logger (LogMsg "run" "start")
  putStrLn $ case run program of
    Left  err -> err
    Right val -> printTree val
  logMsg logger (LogMsg "run" "done")

-- This is the main entry point of the program. 
-- Command-line arguments are split into flags and files. 
-- If --log is given, logging is enabled. 
-- If no file is given, the program starts an interactive loop. 
-- If a file is given, that file is read and executed.
main :: IO ()
main = do
  args <- getArgs
  let (flags, files) = partition ("--" `isPrefixOf`) args
  let logEnabled = "--log" `elem` flags
  logger <- startLogger logEnabled
  case files of
    []           -> do
      hSetBuffering stdout NoBuffering
      loop logger
    (fileName:_) -> do
      program <- readFile fileName
      eval logger program
  stopLogger logger

-- Here we run the interactive mode. 
-- The user can type a program directly in the terminal. 
-- Typing :q stops the loop. 
-- Any other input is evaluated, and then the loop starts again.
loop :: Logger -> IO ()
loop logger = do
  putStr "Enter an expression (:q to quit): "
  input <- getLine
  case input of
    ":q" -> putStrLn "Goodbye!"
    prog -> eval logger prog >> loop logger
