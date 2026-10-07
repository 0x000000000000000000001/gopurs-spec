module Test.Main where

import Prelude

import Effect (Effect)
import Test.Spec (describe, it, parallel, pending, pending', sequential)
import Test.Spec.Assertions (fail)
import Test.Spec.Reporter (specReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)

main :: Effect Unit
main = runSpecAndExitProcess [specReporter] do
  describe "g" do
    it "runs" $ pure unit
    pending' "g.3" $ fail "pending body ran"
  describe "p" $ describe "pp" $ describe "ppp" $
    pending "ppp.1"
  describe "a" $ parallel do
    -- Separate this suite from the adjacent pending-only parallel suite so
    -- the golden does not depend on the scheduling of their headings.
    sequential $ it "runs" $ pure unit
    describe "z" $ pending' "z.3" $ fail "pending body ran"
