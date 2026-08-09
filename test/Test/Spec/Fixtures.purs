module Test.Spec.Fixtures where

import Prelude

import Data.Identity (Identity)
import Test.Spec (SpecT(..), describe, it, class Example)
import Test.Spec.Tree (Item(..))
import Data.Bifunctor (bimap)
import Data.Foldable (any)
import Data.Newtype (un, over)
import Control.Monad.Writer (mapWriterT)

type Spec' a = SpecT Identity Unit Identity a

focus' :: forall m g i a. Monad m => SpecT g i m a -> SpecT g i m a
focus' = over SpecT $ mapWriterT $ map $ map \xs ->
  if any (any $ un Item >>> _.isFocused) xs
    then xs
    else map (bimap identity (\(Item r) -> Item r {isFocused = true})) xs

describeOnly' :: forall m g i a. Monad m => String -> SpecT g i m a -> SpecT g i m a
describeOnly' name spec = focus' (describe name spec)

itOnly' :: forall m t arg g. Monad m => Example t arg g => String -> t -> SpecT g arg m Unit
itOnly' name t = focus' (it name t)

successTest :: Spec' Unit
successTest =
  describe "a" do
    describe "b" do
      it "works" $ pure unit

sharedDescribeTest :: Spec' Unit
sharedDescribeTest =
  describe "a" do
    describe "b" do
      it "works" $ pure unit
    describe "c" do
      it "also works" $ pure unit

duplicatedDescribeTest :: Spec' Unit
duplicatedDescribeTest =
  describe "a" do
    describe "b" do
      describe "c" do
        it "first" $ pure unit
    describe "b" do
      describe "c" do
        it "second" $ pure unit

describeOnlyTest :: Spec' Unit
describeOnlyTest =
  describeOnly' "a" do
    describe "b" do
      it "works" $ pure unit
    describe "c" do
      it "also works" $ pure unit

describeOnlyNestedTest :: Spec' Unit
describeOnlyNestedTest =
  describe "a" do
    describeOnly' "b" do
      it "works" $ pure unit
    describe "c" do
      it "also works" $ pure unit

itOnlyTest :: Spec' Unit
itOnlyTest =
  describe "a" do
    describe "b" do
      itOnly' "works" $ pure unit
    describe "c" do
      it "also works" $ pure unit
