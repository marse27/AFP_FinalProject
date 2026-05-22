module BogusTests where

import Test.Hspec
import Test.QuickCheck

test :: IO ()
test = hspec $ do
    describe "bogus tests you should change" $ do
        it "a property-based test with QuickCheck" $ do
            property $ \(x :: Int) -> x == x
        it "a test that should succeed" $ do
            True `shouldBe` (True || False)
