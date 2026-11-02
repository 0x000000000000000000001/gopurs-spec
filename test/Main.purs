module Test.Main where

import Prelude

import Data.Array (fold)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Milliseconds(..), launchAff_)
import Effect.Class (liftEffect)
import Options.Applicative as Opt
import Record (merge)
import Test.Integration (integrationSpecs)
import Test.Spec.AssertionSpec (assertionSpec)
import Test.Spec.HoistSpec (hoistSpecSpec)
import Test.Spec.HookSpec (hookSpec)
import Test.Spec.ParallelSpec (parallelSpec)
import Test.Spec.PendingSpec (pendingSpec)
import Test.Spec.Reporter (specReporter)
import Test.Spec.Reporter.TeamCitySpec (teamcitySpec)
import Test.Spec.Runner.Node (runSpecAndExitProcess')
import Test.Spec.Runner.Node.Config as Config
import Test.Spec.RunnerSpec (runnerSpec)

main :: Effect Unit
main = launchAff_ do
  config <- liftEffect $
    Config.fromCommandLine' defaultConfig (Config.commandLineOptionParsers <> [debug, accept])
  integration <-
    integrationSpecs { debug: config.debug, accept: config.accept }
  liftEffect $
    runSpecAndExitProcess'
      { defaultConfig: config
      , parseCLIOptions: false
      }
      [specReporter] $
      pureSpecs *> integration
  where
    pureSpecs = do
      runnerSpec
      assertionSpec
      hookSpec
      hoistSpecSpec
      parallelSpec
      pendingSpec
      teamcitySpec

type Config = Config.TestRunConfig' (debug :: Boolean, accept :: Boolean)

defaultConfig :: Config
-- An integration case includes cold compilation as well as fixture execution.
-- Apply this finite default before parsing so --timeout and --no-timeout work.
defaultConfig = (Config.defaultConfig { timeout = Just $ Milliseconds 300000.0 })
  `merge` { debug: false, accept: false }

debug :: Config.OptionParser Config
debug = ado
  d <- Opt.switch $ fold
    [ Opt.long "debug"
    , Opt.help "Do not destroy temporary directory used for integration tests."
    ]

  in _ { debug = d }

accept :: Config.OptionParser Config
accept = ado
  a <- Opt.switch $ fold
    [ Opt.long "accept"
    , Opt.help "Accept all test outputs as new expected outputs."
    ]

  in _ { accept = a }
