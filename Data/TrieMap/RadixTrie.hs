{-# LANGUAGE BangPatterns, UnboxedTuples, TypeFamilies, MagicHash, FlexibleInstances #-}

module Data.TrieMap.RadixTrie () where

import Data.TrieMap.TrieKey
import Data.TrieMap.Sized

import Data.Functor
import Data.Foldable (Foldable(..))
import Control.Monad

import Data.Vector (Vector)
import qualified Data.Vector.Storable as S
import Data.Traversable
import Data.Word

import Data.TrieMap.RadixTrie.Edge
import Data.TrieMap.RadixTrie.Label

import Prelude hiding (length, and, zip, zipWith, foldr, foldl)

instance TrieKey k => Foldable (TrieMap (Vector k)) where
  foldMap f (Radix m) = foldMap (foldMap f) m
  foldr f z (Radix m) = foldl (foldr f) z m
  foldl f z (Radix m) = foldl (foldl f) z m

-- | @'TrieMap' ('Vector' k) a@ is a traditional radix trie.
instance TrieKey k => TrieKey (Vector k) where
	newtype TrieMap (Vector k) a = Radix (MEdge Vector k a)
	newtype Hole (Vector k) a = Hole (EdgeLoc Vector k a)
	
	emptyM = Radix Nothing
	singletonM ks a = Radix (Just (singletonEdge ks a))
	getSimpleM (Radix Nothing)	= Null
	getSimpleM (Radix (Just e))	= getSimpleEdge e
	sizeM (Radix m) = getSize m
	lookupM ks (Radix m) = m >>= lookupEdge ks

	fmapM f (Radix m) = Radix (mapEdge f <$> m)
	mapMaybeM f (Radix m) = Radix (m >>= mapMaybeEdge f)
	mapEitherM f (Radix e) = both Radix Radix (mapEitherMaybe (mapEitherEdge f)) e
	traverseM f (Radix m) = Radix <$> traverse (traverseEdge f) m

	unionM f (Radix m1) (Radix m2) = Radix (unionMaybe (unionEdge f) m1 m2)
	isectM f (Radix m1) (Radix m2) = Radix (isectMaybe (isectEdge f) m1 m2)
	diffM f (Radix m1) (Radix m2) = Radix (diffMaybe (diffEdge f) m1 m2)
	
	isSubmapM (<=) (Radix m1) (Radix m2) = subMaybe (isSubEdge (<=)) m1 m2

	singleHoleM ks = Hole (singleLoc ks)
	searchM ks (Radix (Just e)) = case searchEdge ks e root of
		(a, loc) -> (# a, Hole loc #)
	searchM ks _ = (# Nothing, singleHoleM ks #)
	indexM i (Radix (Just e)) = onThird Hole (indexEdge i e) root
	indexM _ (Radix Nothing) = indexFail ()

	clearM (Hole loc) = Radix (clearEdge loc)
	assignM a (Hole loc) = Radix (Just (assignEdge a loc))
	
	extractHoleM (Radix (Just e)) = fmap Hole <$> extractEdgeLoc e root
	extractHoleM _ = mzero
	
	beforeM (Hole loc) = Radix (beforeEdge Nothing loc)
	beforeWithM a (Hole loc) = Radix (beforeEdge (Just a) loc)
	afterM (Hole loc) = Radix (afterEdge Nothing loc)
	afterWithM a (Hole loc) = Radix (afterEdge (Just a) loc)
	
	unifyM ks1 a1 ks2 a2 = fmap (Radix . Just) (unifyEdge ks1 a1 ks2 a2)
	
	insertWithM f ks a (Radix (Just e)) = Radix (Just (insertEdge f ks a e))
	insertWithM _ ks a (Radix Nothing) = singletonM ks a

type WordVec = S.Vector Word

instance Foldable (TrieMap (S.Vector Word)) where
  foldMap f (WRadix m) = foldMap (foldMap f) m
  foldr f z (WRadix m) = foldl (foldr f) z m
  foldl f z (WRadix m) = foldl (foldl f) z m

-- | @'TrieMap' ('S.Vector' Word) a@ is a traditional radix trie specialized for word arrays.
instance TrieKey (S.Vector Word) where
	newtype TrieMap WordVec a = WRadix (MEdge S.Vector Word a)
	newtype Hole WordVec a = WHole (EdgeLoc S.Vector Word a)
	
	emptyM = WRadix Nothing
	singletonM ks a = WRadix (Just (singletonEdge ks a))
	getSimpleM (WRadix Nothing)	= Null
	getSimpleM (WRadix (Just e))	= getSimpleEdge e
	sizeM (WRadix m) = getSize m
	lookupM ks (WRadix m) = m >>= lookupEdge ks

	fmapM f (WRadix m) = WRadix (mapEdge f <$> m)
	mapMaybeM f (WRadix m) = WRadix (m >>= mapMaybeEdge f)
	mapEitherM f (WRadix e) = both WRadix WRadix (mapEitherMaybe (mapEitherEdge f)) e
	traverseM f (WRadix m) = WRadix <$> traverse (traverseEdge f) m

	unionM f (WRadix m1) (WRadix m2) = WRadix (unionMaybe (unionEdge f) m1 m2)
	isectM f (WRadix m1) (WRadix m2) = WRadix (isectMaybe (isectEdge f) m1 m2)
	diffM f (WRadix m1) (WRadix m2) = WRadix (diffMaybe (diffEdge f) m1 m2)
	
	isSubmapM (<=) (WRadix m1) (WRadix m2) = subMaybe (isSubEdge (<=)) m1 m2

	singleHoleM ks = WHole (singleLoc ks)
	searchM ks (WRadix (Just e)) = case searchEdge ks e root of
		(a, loc) -> (# a, WHole loc #)
	searchM ks _ = (# Nothing, singleHoleM ks #)
	indexM i (WRadix (Just e)) = case indexEdge i e root of
		(# i', a, loc #) -> (# i', a, WHole loc #)
	indexM _ (WRadix Nothing) = indexFail ()

	clearM (WHole loc) = WRadix (clearEdge loc)
	assignM a (WHole loc) = WRadix (Just (assignEdge a loc))
	
	extractHoleM (WRadix (Just e)) = do
		(a, loc) <- extractEdgeLoc e root
		return (a, WHole loc)
	extractHoleM _ = mzero

	beforeM (WHole loc) = WRadix (beforeEdge Nothing loc)
	beforeWithM a (WHole loc) = WRadix (beforeEdge (Just a) loc)
	afterM (WHole loc) = WRadix (afterEdge Nothing loc)
	afterWithM a (WHole loc) = WRadix (afterEdge (Just a) loc)
	
	unifyM ks1 a1 ks2 a2 = fmap (WRadix . Just) (unifyEdge ks1 a1 ks2 a2)