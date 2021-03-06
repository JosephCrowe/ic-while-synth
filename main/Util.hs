{-# OPTIONS_GHC -fno-warn-orphans -fno-warn-deprecated-flags #-}
{-# LANGUAGE FlexibleInstances, UndecidableInstances, OverlappingInstances,
             TypeFamilies, MultiParamTypeClasses, FunctionalDependencies #-}

module Util where

import Control.Applicative
import Data.Maybe
import Data.Char
import Data.Monoid
import Data.List
import Data.Functor.Identity
import Data.Time.Clock

import Data.MonoTraversable

--------------------------------------------------------------------------------
-- Utilities for dealing with programming language syntax trees.

type Prec = Int

data OpInfo = OpInfo{  
    oPrec :: Prec,     -- Precedence
    oAscL :: Bool,     -- Left-associativity
    oAscR :: Bool }    -- Right-associativity

-- The class of types from which information about a particular operator can
-- be extracted with respect to a particular context.
class Operator a where
    type OpContext a
    opInfo :: OpContext a -> a -> OpInfo

--------------------------------------------------------------------------------
-- Type classes for overloading of various generic operators.

class Negation a where
    negation :: a -> a

class EqualsColon a b c | c -> a, c -> b where
    infixr 1 =:
    (=:) :: a -> b -> c

--------------------------------------------------------------------------------
-- Default implementation of Mono{Traversable,Foldable,FoldableEq,Functor}.

class MonoTraversableD mono where
    otraverseD :: Applicative f =>
        (Element mono -> f (Element mono)) -> mono -> f mono

instance MonoTraversableD mono => MonoTraversable mono where
    otraverse = otraverseD
    omapM act = unwrapMonad . otraverse (WrapMonad . act)

instance MonoTraversableD mono => MonoFoldable mono where
    ofoldMap f    = getConst . otraverseD (Const . f)
    ofoldr  f z t = appEndo (ofoldMap (Endo . f) t) z
    ofoldl' f     = ofoldlDefault $ \l r -> let l' = f l r in l' `seq` l'

    ofoldr1Ex f t
      = fromMaybe (error "ofoldr1Ex: empty") (ofoldr mf Nothing t)
      where mf l Nothing  = Just l
            mf l (Just r) = Just (f l r)

    ofoldl1Ex' f t
      = fromMaybe (error "ofoldlEx': empty") (ofoldlDefault mf Nothing t)
      where mf Nothing  r = Just r
            mf (Just l) r = l' `seq` Just l' where l' = f l r

instance (MonoTraversable mono, Eq (Element mono)) => MonoFoldableEq mono where
    oelem    = oany . (==)
    onotElem = oall . (/=)

ofoldlDefault :: MonoFoldable mono => (a -> Element mono -> a) -> a -> mono -> a
ofoldlDefault f z t = appEndo (getDual (ofoldMap (Dual . Endo . flip f) t)) z

instance MonoTraversableD mono => MonoFunctor mono where
    omap f = runIdentity . otraverse (Identity . f)

headMap :: (a -> a) -> [a] -> [a]
headMap f (x : xs) = f x : xs
headMap _ []       = []

--------------------------------------------------------------------------------
-- ANSI terminal control sequences.
ansiDarkRed, ansiDarkGreen, ansiDarkYellow, ansiClear :: String
ansiDarkRed    = "\27[31m"
ansiDarkGreen  = "\27[32m"
ansiDarkYellow = "\27[33m"
ansiClear      = "\27[0m"

--------------------------------------------------------------------------------
-- Miscellaneous utilities.

headUp, headLow :: String -> String
headUp  = headMap toUpper
headLow = headMap toLower

oxfordComma :: String -> [String] -> String
oxfordComma sep ws = case reverse ws of
    t : hs@(_:_:_) -> intercalate ", " (reverse hs) ++", "++ sep ++" "++ t
    [b, a]         -> a ++" "++ sep ++" "++ b
    _              -> concat ws

noOxfordComma :: String -> [String] -> String
noOxfordComma sep ws = case reverse ws of
    t : hs@(_:_) -> intercalate ", " (reverse hs) ++" "++ sep ++" "++ t
    _            -> concat ws

time :: IO a -> IO (a, NominalDiffTime)
time mx = do
    start <- getCurrentTime
    x <- mx
    end <- getCurrentTime
    return (x, end `diffUTCTime` start)
