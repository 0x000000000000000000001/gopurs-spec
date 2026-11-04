module Test.Main where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, Milliseconds(..), launchAff_, never)
import Test.Spec (it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Config (defaultConfig)
import Test.Spec.Reporter (specReporter)
import Test.Spec.Runner (runSpecPure')

main :: Effect Unit
main = launchAff_ $ runSpecPure' config [specReporter] do
  it "passes quickly" $
    5 `shouldEqual` (3 + 2)

  it "times out" $
    -- Keep the test pending until the timeout cancels it. Racing two short
    -- delays can let the body finish first when the scheduler is busy.
    (never :: Aff Unit)

  it "shouldn't get to run" $
    2 `shouldEqual` 3

  where
    config = defaultConfig { failFast = true, timeout = Just $ Milliseconds 10.0, exit = false }
