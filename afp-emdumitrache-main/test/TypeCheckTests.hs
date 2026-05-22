module TypeCheckTests where

import Test.Hspec

import Run ( infertype )
import Lang.Abs ( Type(..) )

import Data.Either ( isLeft )

tcTest :: String -> Type -> Spec
tcTest input expected =
    it (input ++ " should type check to " ++ show expected) $ do
            infertype input `shouldBe` Right expected

tcErrorTest :: String -> Spec
tcErrorTest input =
    it (input ++ " should not type check") $ do
            infertype input `shouldSatisfy` isLeft

test :: IO ()
test = hspec $ do
    describe "typeChecker: good weather tests" $ do
        tcTest "let x = 2 in x + 3" TInt
        tcTest "True && False" TBool

        tcTest "val x = 3; x * x" TInt

        tcTest "fun isZero (x : int) = x == 0; res = isZero(42); res" TBool

    describe "typeChecker: bad weather tests" $ do
        tcErrorTest "let x = 2 in x + True"
        tcErrorTest "True && 3"
        tcErrorTest "fun increment (x : int) = x + 1; res = increment(True); res"
