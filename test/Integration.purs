module Test.Integration where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (diff)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.String as S
import Data.String as Str
import Data.String.Regex (replace) as Regex
import Data.String.Regex.Flags (global) as Regex
import Data.String.Regex.Unsafe (unsafeRegex) as Regex
import Data.Traversable (for_, traverse_)
import Effect (Effect)
import Effect.Aff (Aff, Canceler(..), Milliseconds, generalBracket, makeAff, nonCanceler, try)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Effect.Exception (error)
import Effect.Now (now)
import Effect.Ref as Ref
import Node.Buffer as Buffer
import Node.ChildProcess as Proc
import Node.ChildProcess.Types as IO
import Node.Encoding (Encoding(..))
import Node.Errors.SystemError as SystemError
import Node.EventEmitter (on_)
import Node.FS.Aff as FS
import Node.FS.Constants as FSC
import Node.FS.Stats (isDirectory)


import Node.OS (tmpdir)
import Node.Process (cwd)
import Node.Stream as Stream
import Test.Spec (Spec, afterAll, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- Cancellation completes only after the child process group and its pipes close.
foreign import terminateAndWaitImpl :: Proc.ChildProcess -> Effect Boolean -> Effect Unit -> Effect Unit

-- | Reads the contents of `/integration-tests/cases` and turns each
-- | subdirectory into a test case. See `/integration-tests/cases/README` for
-- | more details.
integrationSpecs :: { debug :: Boolean, accept :: Boolean } -> Aff (Spec Unit)
integrationSpecs { debug, accept } = do
  { runFile, cleanupEnvironment } <- liftEffect $ prepareEnvironment { debug }
  cases <- FS.readdir "integration-tests/cases"

  pure $ afterAll (\_ -> cleanupEnvironment) $
    describe "Integration tests" do
      for_ cases \testName -> do
        let testDir = "integration-tests/cases/" <> testName
        it testName do
          program <- FS.readTextFile UTF8 $ testDir // "Main.purs"
          goldenOutput <- Str.trim <$> FS.readTextFile UTF8 (testDir // "output.txt")
          actualOutput <- Str.trim <$> runFile program
          if accept then do
            FS.writeTextFile UTF8 (testDir // "output.txt") actualOutput
            log $ "Accepted new output for test case: " <> testName
          else
            actualOutput `shouldEqual` goldenOutput

prepareEnvironment :: { debug :: Boolean } -> Effect { runFile :: String -> Aff String, cleanupEnvironment :: Aff Unit }
prepareEnvironment { debug } =
  Ref.new Nothing <#> \envDirVar ->
    { runFile: \program -> do
        dir <- ensureEnvironmentInitialized envDirVar
        ensureDirExists $ dir // "src"
        FS.writeTextFile UTF8 (dir // "src/Main.purs") program
        _out0 <- run "prepare:purescript" dir "spago" ["build", "-p", "integration-test"]
        thisDir <- liftEffect cwd
        gopursPath <- try (FS.stat (thisDir // "../gopurs/bin/gopurs")) >>= case _ of
          Right _ -> pure (thisDir // "../gopurs/bin/gopurs")
          Left _ -> try (FS.stat (thisDir // "gopurs/bin/gopurs")) >>= case _ of
            Right _ -> pure (thisDir // "gopurs/bin/gopurs")
            Left _ -> pure (thisDir // "bin/gopurs")
        _out1 <- run "prepare:gopurs" dir gopursPath ["--main", "Test.Main"]
        void $ run "prepare:go-mod-reset" (dir // "output") "rm" [ "-f", "go.mod" ]
        _out2 <- run "prepare:go-mod-init" (dir // "output") "go" [ "mod", "init", "gopurs/output" ]
        _out3 <- run "prepare:go-mod-tidy" (dir // "output") "go" [ "mod", "tidy" ]
        _out4 <- run "prepare:go-build" (dir // "output") "go" [ "build", "-o", "go_test_app", "./main" ]
        -- Failing spec cases intentionally exit 1; their output is checked below.
        res <- runWithExitCodes [0, 1] "runtime" (dir // "output") "env" [ "GOGC=1000", "./go_test_app" ]
        pure $ res
          -- Removing ESC characters (which are used for colors), because
          -- they're very inconvenient to include in the golden output files.
          # Regex.replace colorsRegex ""
          # S.replaceAll (S.Pattern spagoTestHeader) (S.Replacement "")

    , cleanupEnvironment:
        liftEffect (Ref.read envDirVar) >>= case _ of
          Just dir | debug -> do
            traceLog "Skipping environment cleanup due to debug=true flag"
            traceLog $ "Environment at: " <> dir
          Just dir -> do
            rmdirRec dir
            liftEffect $ Ref.write Nothing envDirVar
          Nothing ->
            pure unit
    }
  where
    colorsRegex = Regex.unsafeRegex "\x1B\\[[0-9;]+m" Regex.global

    traceLog
      | debug = log
      | otherwise = const $ pure unit

    ensureEnvironmentInitialized envDirVar =
      liftEffect (Ref.read envDirVar) >>= case _ of
        Just d ->
          pure d
        Nothing ->
          generalBracket
            (liftEffect tmpdir >>= \tmp -> FS.mkdtemp $ tmp // "purescript-spec-test-env")
            { failed: \_ dir -> discardEnvironment envDirVar dir
            , killed: \_ dir -> discardEnvironment envDirVar dir
            , completed: \_ _ -> pure unit
            }
            \dir -> do
              traceLog $ "Preparing environment in: " <> dir
              copyAllFiles { from: "integration-tests/env-template", to: dir }
              patchRepoPath $ dir // "spago.yaml"
              -- Publish only a complete environment. Spago and gopurs come
              -- from the caller's toolchain; the template is read-only.
              liftEffect $ Ref.write (Just dir) envDirVar
              pure dir

    discardEnvironment envDirVar dir = do
      liftEffect $ Ref.write Nothing envDirVar
      rmdirRec dir

    patchRepoPath file = do
      thisDir <- liftEffect cwd
      content <- FS.readTextFile UTF8 file
      let newContent = S.replaceAll (S.Pattern "SPEC_REPO_PATH") (S.Replacement thisDir) content
      FS.writeTextFile UTF8 file newContent

    copyAllFiles { from, to } = do
      ensureDirExists to
      files <- FS.readdir from
      for_ (Array.filter (\f -> not $ Array.elem f ["node_modules", "output"]) files) \f -> do
        stat <- FS.stat $ from // f
        if isDirectory stat then
          copyAllFiles { from: from // f, to: to // f }
        else
          FS.copyFile' (from // f) (to // f) FSC.copyFile_FICLONE

    run = runWithExitCodes [0]

    runWithExitCodes exitCodes phase cwd cmd args = do
      started <- liftEffect now
      log $ "[integration] start " <> phase <> " cwd=" <> cwd <> " command=" <> S.joinWith " " ([cmd] <> args)
      makeAff \cb -> do
        output <- Ref.new ""
        completed <- Ref.new false
        let finish result = do
              done <- Ref.read completed
              unless done do
                Ref.write true completed
                ended <- now
                log $ "[integration] end " <> phase <> " elapsedMs=" <> show (unwrap (ended `diff` started :: Milliseconds))
                  <> case result of
                    Right captured -> " success outputChars=" <> show (S.length captured)
                    Left err -> " failure: " <> show err
                cb result

        proc <- Proc.spawn' "env" (["PWD=" <> cwd, cmd] <> args) _ { cwd = Just cwd, detached = Just true, appendStdio = Just [IO.ignore, IO.pipe, IO.pipe] }

        for_ [Proc.stdout, Proc.stderr] \pipe ->
          pipe proc # on_ Stream.dataH \buf -> do
            str <- Buffer.toString UTF8 buf
            void $ output # Ref.modify (_ <> str)

        proc # on_ Proc.errorH \err -> finish $ Left $ SystemError.toError err
        proc # on_ Proc.closeH \exit -> do
          captured <- Ref.read output
          case exit of
            IO.Normally code | Array.elem code exitCodes -> finish $ Right captured
            _ -> finish $ Left $ error $
              "Command failed (" <> show exit <> "): "
                <> S.joinWith " " ([cmd] <> args) <> "\n" <> captured

        pure $ Canceler \_ -> do
          log $ "[integration] cancel " <> phase
          makeAff \canceled -> do
            terminateAndWaitImpl proc (Ref.read completed) (canceled (Right unit))
            pure nonCanceler
          log $ "[integration] canceled " <> phase <> "; child group and pipes closed"

    ensureDirExists dir =
      FS.access dir >>= case _ of
        Just _err -> FS.mkdir dir
        Nothing -> pure unit

    rmdirRec dir = do
      stat <- FS.stat dir
      if isDirectory stat then do
        FS.readdir dir >>= traverse_ \f -> rmdirRec $ dir // f
        FS.rmdir dir
      else
        FS.unlink dir

    spagoTestHeader =
      "purs compile: No files found using pattern: src/**/*.purs\n           Src   Lib   All\nWarnings     0     0     0\nErrors       0     0     0\n"

pathConcat :: String -> String -> String
pathConcat a b = a <> "/" <> b

infixl 5 pathConcat as //
