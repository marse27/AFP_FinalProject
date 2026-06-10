module Main where

import Data.List          (isPrefixOf, partition)
import System.Environment (getArgs)
import System.IO          (hSetBuffering, stdout, BufferMode (NoBuffering))
import Lang.Print         (printTree)
import Logger             (Logger, LogMsg (..), startLogger, stopLogger, logMsg)
import Run                (run)

-- | Type-check and evaluate a program, bracketed by log events.
eval :: Logger -> String -> IO ()
eval logger program = do
  logMsg logger (LogMsg "run" "start")
  putStrLn $ case run program of
    Left  err -> err
    Right val -> printTree val
  logMsg logger (LogMsg "run" "done")

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

loop :: Logger -> IO ()
loop logger = do
  putStr "Enter an expression (:q to quit): "
  input <- getLine
  case input of
    ":q" -> putStrLn "Goodbye!"
    prog -> eval logger prog >> loop logger
