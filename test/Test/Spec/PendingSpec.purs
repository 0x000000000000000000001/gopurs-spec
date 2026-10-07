module Test.Spec.PendingSpec (pendingSpec) where

import Prelude

import Data.Array as Array
import Data.Bifunctor (bimap)
import Data.Either (Either(..))
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Data.String (joinWith)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Effect.Aff (forkAff, joinFiber)
import Effect.Aff.AVar as AVar
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Pipes (await, yield)
import Test.Spec (Spec, Tree(..), after_, before_, describe, it, parallel, pending, pending', sequential)
import Test.Spec.Assertions (fail, shouldEqual)
import Test.Spec.Result (Result(..))
import Test.Spec.Runner (Config, Reporter, defaultConfig, evalSpecT)
import Test.Spec.Runner.Event as Event
import Test.Spec.Summary (Summary(..), successful, summarize)
import Test.Spec.Tree (TestLocator, parentSuiteName)

config :: Config
config = defaultConfig { exit = false, timeout = Just (Milliseconds 2000.0) }

pendingSpec :: Spec Unit
pendingSpec = describe "Pending execution contracts" do
  it "keeps pending paths and events, without running bodies or per-test hooks" do
    calls <- liftEffect $ Ref.new []
    events <- liftEffect $ Ref.new []
    let record label = liftEffect $ Ref.modify_ (_ <> [label]) calls
    results <- un Identity $ evalSpecT config [capture events] $
      before_ (record "before") $ after_ (record "after") do
        describe "g" do
          it "runs" $ record "body"
          pending' "g.3" $ record "pending body" *> fail "pending body ran"
        describe "p" $ describe "pp" $ describe "ppp" $
          pending "ppp.1"
        describe "a" $ parallel do
          it "runs" $ record "body"
          describe "z" $ pending' "z.3" $ record "pending body" *> fail "pending body ran"
    observedCalls <- liftEffect $ Ref.read calls
    observedCalls `shouldEqual` ["before", "body", "after", "before", "body", "after"]
    (map (bimap (const unit) passed) results) `shouldEqual`
      [ Node (Left "g") [Leaf "runs" (Just true), Leaf "g.3" Nothing]
      , Node (Left "p") [Node (Left "pp") [Node (Left "ppp") [Leaf "ppp.1" Nothing]]]
      , Node (Left "a") [Leaf "runs" (Just true), Node (Left "z") [Leaf "z.3" Nothing]]
      ]
    (un Count $ summarize results) `shouldEqual` { passed: 2, failed: 0, pending: 3 }
    successful results `shouldEqual` true
    observed <- liftEffect $ Ref.read events
    (Array.sort $ Array.mapMaybe pendingPath observed) `shouldEqual` ["a/z/z.3", "g/g.3", "p/pp/ppp/ppp.1"]
    (Array.sort $ Array.mapMaybe startedPath observed) `shouldEqual` ["a/runs", "g/runs"]
    (Array.sort $ Array.mapMaybe finishedPath observed) `shouldEqual` ["a/runs", "g/runs"]
    (Array.mapMaybe (case _ of
      Event.Start count -> Just count
      _ -> Nothing) observed) `shouldEqual` [5]
    (Array.length $ Array.filter (case _ of
      Event.End _ -> true
      _ -> false) observed) `shouldEqual` 1

  it "runs parallel peers across a pending leaf using a rendezvous" do
    first <- AVar.empty
    second <- AVar.empty
    results <- un Identity $ evalSpecT config [] $ parallel do
      it "first" $ AVar.put unit first *> AVar.take second
      pending "between peers"
      it "second" $ AVar.put unit second *> AVar.take first
    (un Count $ summarize results) `shouldEqual` { passed: 2, failed: 0, pending: 1 }
    successful results `shouldEqual` true

  it "preserves sequential ordering inside a parallel group with pending leaves" do
    started <- AVar.empty
    release <- AVar.empty
    calls <- liftEffect $ Ref.new []
    events <- liftEffect $ Ref.new []
    let record label = liftEffect $ Ref.modify_ (_ <> [label]) calls
    coordinator <- forkAff $ AVar.take started *> AVar.put unit release
    results <- un Identity $ evalSpecT config [capture events] $ parallel $ describe "ordered" $ sequential do
      it "first" do
        record "first starts"
        AVar.put unit started
        AVar.take release
        record "first ends"
      pending "between sequential tests"
      it "second" do
        seen <- liftEffect $ Ref.read calls
        seen `shouldEqual` ["first starts", "first ends"]
        record "second"
    joinFiber coordinator
    observed <- liftEffect $ Ref.read calls
    observed `shouldEqual` ["first starts", "first ends", "second"]
    observedEvents <- liftEffect $ Ref.read events
    -- Check the execution mode as well as the body order, so a fast parallel
    -- schedule cannot accidentally satisfy this sequential contract.
    (Array.mapMaybe (case _ of
      Event.Test execution loc -> Just (show execution <> ":" <> pathName loc)
      _ -> Nothing) observedEvents) `shouldEqual` ["Sequential:ordered/first", "Sequential:ordered/second"]
    (un Count $ summarize results) `shouldEqual` { passed: 2, failed: 0, pending: 1 }
    successful results `shouldEqual` true

passed :: Result -> Boolean
passed (Success _ _) = true
passed (Failure _) = false

pathName :: TestLocator -> String
pathName (path /\ name) = joinWith "/" (parentSuiteName path <> [name])

pendingPath :: Event.Event -> Maybe String
pendingPath (Event.Pending loc) = Just (pathName loc)
pendingPath _ = Nothing

startedPath :: Event.Event -> Maybe String
startedPath (Event.Test _ loc) = Just (pathName loc)
startedPath _ = Nothing

finishedPath :: Event.Event -> Maybe String
finishedPath (Event.TestEnd loc _) = Just (pathName loc)
finishedPath _ = Nothing

capture :: Ref.Ref (Array Event.Event) -> Reporter
capture ref = do
  event <- await
  liftEffect $ Ref.modify_ (_ <> [event]) ref
  yield event
  case event of
    Event.End results -> pure results
    _ -> capture ref
