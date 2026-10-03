module Test.IntegrationEnvironment where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String (trim)
import Effect (Effect)
import Effect.Aff (runAff_, try)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Effect.Console as Console
import Effect.Exception (message)
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
  actual <- environment.runFile program
  trim actual `shouldEqual` "fixture output"
  environment.cleanupEnvironment
  where
  finish (Left err) = Console.error (message err) *> exit' 1
  finish (Right _) = log "environment contract passed"
  program = "module Test.Main where\n"
