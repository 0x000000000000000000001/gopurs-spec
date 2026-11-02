module Test.IntegrationEnvironment where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String (trim)
import Effect (Effect)
import Effect.Aff (Milliseconds(..), delay, forkAff, killFiber, runAff_, try)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Effect.Console as Console
import Effect.Exception (error, message)
import Node.Encoding (Encoding(..))
import Node.FS.Aff as FS
import Node.OS (tmpdir)
import Node.Process (exit', lookupEnv)
import Test.Integration (prepareEnvironment)
import Test.Spec.Assertions (fail, shouldEqual)

-- The Node driver supplies a fresh template and fake external commands, while
-- this entry point exercises the actual native Aff/filesystem implementation.
main :: Effect Unit
main = runAff_ finish do
  environment <- liftEffect $ prepareEnvironment { debug: false }
  cancel <- liftEffect $ lookupEnv "SPEC_TEST_CANCEL"
  when (cancel == Just "1") do
    fiber <- forkAff $ environment.runFile program
    let
      awaitStarted remaining = do
        FS.access "cancel-started" >>= case _ of
          Nothing -> pure unit
          Just _ | remaining > 0 -> delay (Milliseconds 10.0) *> awaitStarted (remaining - 1)
          Just _ -> fail "Fake spago did not start"
    awaitStarted 200
    killFiber (error "diagnostic cancellation") fiber
    actual <- environment.runFile (program <> "-- second case\n")
    trim actual `shouldEqual` "fixture output"
    delay (Milliseconds 750.0)
    FS.access "cancel-late" >>= case _ of
      Nothing -> do
        evidence <- FS.readTextFile UTF8 "cancel-late"
        fail $ "Canceled child survived and observed the next case: " <> evidence
      Just _ -> pure unit
  retry <- liftEffect $ lookupEnv "SPEC_TEST_RETRY"
  when (retry == Just "1") do
    result <- try $ environment.runFile program
    case result of
      Right _ -> fail "Initialization with no spago.yaml unexpectedly succeeded"
      Left _ -> pure unit
    temporary <- liftEffect tmpdir
    FS.readdir temporary >>= (_ `shouldEqual` [])
    FS.writeTextFile UTF8 "integration-tests/env-template/spago.yaml"
      "workspace:\n  extraPackages:\n    spec:\n      path: SPEC_REPO_PATH\n"
  when (cancel /= Just "1") do
    actual <- environment.runFile program
    trim actual `shouldEqual` "fixture output"
  environment.cleanupEnvironment
  where
  finish (Left err) = Console.error (message err) *> exit' 1
  finish (Right _) = log "environment contract passed"
  program = "module Test.Main where\n"
