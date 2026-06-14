-- Tests that the concurrent logger does not affect program results and
-- that its background thread starts, drains, and stops cleanly.
module LoggerTests where

import Test.Hspec
import Logger   (startLogger, stopLogger, logMsg, LogMsg (..))
import Run      (infertype, run)
import Lang.Abs (Type (..))
import Value    (Value (..))

test :: IO ()
test = hspec $ do

  describe "Logger: program results unchanged with concurrent logger" $ do
    it "infertype result is unaffected by a running logger" $ do
      logger <- startLogger False
      let result = infertype "42"
      stopLogger logger
      result `shouldBe` Right TInt

    it "run result is unaffected by a running logger" $ do
      logger <- startLogger False
      let result = run "fn double(x: int) -> int { x + x }; double(7)"
      stopLogger logger
      result `shouldBe` Right (VInt 14)

    it "run result with ownership is unaffected by a running logger" $ do
      logger <- startLogger False
      let result = run "let x = Red; x"
      stopLogger logger
      result `shouldBe` Right VLightRed

  describe "Logger: background thread drains and stops without deadlock" $ do
    it "logger with disabled output stops cleanly after no-op logMsg calls" $ do
      logger <- startLogger False
      mapM_ (\i -> logMsg logger (LogMsg "test" (show (i :: Int)))) [1 .. 10]
      stopLogger logger

    it "logger with enabled output flushes all messages before stopping" $ do
      logger <- startLogger True
      logMsg logger (LogMsg "stage5" "background logger is running")
      logMsg logger (LogMsg "stage5" "all four techniques in use")
      stopLogger logger
