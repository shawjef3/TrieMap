{-# LANGUAGE TemplateHaskell, TypeFamilies, GADTs, ExistentialQuantification, CPP, UndecidableInstances #-}

module Tests (main) where

import Control.Monad
import Control.Applicative
import qualified Data.TrieMap as T
import qualified Data.Map as M
import Data.Ord
import Data.List (foldl', sortBy)
import Data.TrieMap.Representation
import Test.QuickCheck
import Prelude hiding (null, lookup)
import Data.ByteString (ByteString, pack)
import qualified Data.ByteString as BS
type Val = [Int]

main :: IO ()
main = quickCheckWith stdArgs{maxSuccess = 1000} (verify M.empty T.empty .&&. conjoin concretes)

data Key = A (ByteString, Int) | B Int ByteString | C [Bool] | D [Char] | E (Either String Double) deriving (Eq, Ord, Show)

data Key' = A' (ByteString, Int) | B' Int ByteString | C' [Bool] | D' [Char] | E' (Either String Double) deriving (Eq, Ord, Show)

hash :: Key -> Int
hash (A (bs, i)) = BS.foldl' (\ i w -> i * 31 + fromIntegral w) i bs
hash (B i bs)	= BS.foldl' (\ i w -> i * 61 + fromIntegral w) i bs
hash (C bs)	= length bs
hash (D cs)	= foldl' (\ i w -> i * 91 + fromEnum w) 0 cs
hash (E (Left cs))	= foldl' (\ i w -> i * 255 + fromEnum w) 0 cs
hash (E (Right i))	= fst (properFraction i)

instance Arbitrary Key where
	arbitrary = oneof [A <$> arbitrary,
				B <$> arbitrary <*> arbitrary,
				C <$> arbitrary,
				D <$> arbitrary,
				E <$> arbitrary]

instance Arbitrary Key' where
	arbitrary = oneof [A' <$> arbitrary,
				B' <$> arbitrary <*> arbitrary,
				C' <$> arbitrary,
				D' <$> arbitrary,
				E' <$> arbitrary]

instance Arbitrary ByteString where
	arbitrary = liftM pack arbitrary

instance Arbitrary Op where
	arbitrary = oneof [
		liftM Op (liftM2 Insert arbitrary arbitrary),
		return (Op Map),
		return (Op ToList),
		return (Op Size),
		liftM (Op . Lookup) arbitrary,
		liftM (Op . Delete) arbitrary,
		return (Op MinView),
		return (Op MaxView),
		return (Op MapMaybe),
		liftM Op (liftM Union recurse),
		liftM Op (liftM Isect recurse),
		liftM (Op . ElemAt) (arbitrary `suchThat` (>= 0)),
		liftM (Op . DeleteAt) (arbitrary `suchThat` (>= 0)),
		return (Op UpdateMin),
		return (Op UpdateMax)]
	shrink (Op (Insert k v)) = [Op (Insert k' v') | k' <- shrink k, v' <- shrink v]
	shrink (Op (Lookup k)) = map (Op . Lookup) (shrink k)
	shrink (Op (Delete k)) = map (Op . Delete) (shrink k)
	shrink (Op (Union ops)) = ops ++ map (Op . Union) (shrink ops)
	shrink _ = []

recurse :: Gen [Op]
recurse = sized (\ n -> resize (n `quot` 5) arbitrary)

data Op = forall r . Op (Operation r)

instance Show Op where
	show (Op (Insert k v)) = "Insert " ++ show k ++ " " ++ show v
	show (Op (Lookup k)) = "Lookup " ++ show k
	show (Op (Delete k)) = "Delete " ++ show k
	show (Op Map) = "Map"
	show (Op Size) = "Size"
	show (Op ToList) = "ToList"
	show (Op MinView) = "MinView"
	show (Op MaxView) = "MaxView"
	show (Op MapMaybe) = "MapMaybe"
	show (Op (Union ops)) = "Union " ++ show ops
	show (Op (DeleteAt i)) = "DeleteAt " ++ show i
	show (Op (ElemAt i)) = "ElemAt " ++ show i
	show (Op (Isect ops)) = "Isect " ++ show ops
	show (Op UpdateMax) = "UpdateMax"
	show (Op UpdateMin) = "UpdateMin"

data Operation r where
	Insert :: Key -> Val -> Operation ()
	Map :: Operation ()
	ToList :: Operation [(Key, Val)]
	Size :: Operation Int
	Lookup :: Key -> Operation (Maybe Val)
	Delete :: Key -> Operation ()
	MinView :: Operation (Maybe (Key, Val))
	MaxView :: Operation (Maybe (Key, Val))
	MapMaybe :: Operation ()
	Union :: [Op] -> Operation ()
	Isect :: [Op] -> Operation ()
	DeleteAt :: Int -> Operation ()
	ElemAt :: Int -> Operation (Maybe (Key, Val))
	UpdateMax :: Operation ()
	UpdateMin :: Operation ()

mapFunc :: Key -> Val -> Val
mapFunc ks xs = fromIntegral (hash ks):xs

mapMaybeFunc :: Key -> Val -> Maybe Val
mapMaybeFunc ks xs
	| even h	= Just (fromIntegral h:xs)
	where h = hash ks
mapMaybeFunc _ _ = Nothing

isectFunc :: Key -> Val -> Val -> Val
isectFunc ks xs ys = [fromIntegral $ hash ks] ++ xs ++ ys

generateMap :: M.Map Key Val -> [Op] -> M.Map Key Val
generateMap = foldl (\ mm (Op op) -> snd (operateMap mm op))

operateMap :: M.Map Key Val -> Operation r -> (r, M.Map Key Val)
operateMap m (Insert k v) = ((), M.insert k v m)
operateMap m (Lookup k) = (M.lookup k m, m)
operateMap m Map = ((), M.mapWithKey mapFunc m)
operateMap m ToList = (M.assocs m, m)
operateMap m Size = (M.size m, m)
operateMap m (Delete k) = ((), M.delete k m)
operateMap m MinView = case M.minViewWithKey m of
	Nothing	 -> (Nothing, m)
	Just ((k, v), m')	-> (Just (k, v), m')
operateMap m MaxView = case M.maxViewWithKey m of
	Nothing	-> (Nothing, m)
	Just (kv, m')	-> (Just kv, m')
operateMap m MapMaybe = ((), M.mapMaybeWithKey mapMaybeFunc m)
operateMap m (Union ops) =
	let m' = generateMap M.empty ops in ((), M.union m m')
operateMap m (DeleteAt i) = if M.null m then ((), m) else ((), M.deleteAt (i `mod` M.size m) m)
operateMap m (ElemAt i) = if M.null m then (Nothing, m) else (Just $ M.elemAt (i `mod` M.size m) m, m)
operateMap m (Isect ops) = ((), M.intersectionWithKey isectFunc m (generateMap M.empty ops))
operateMap m (UpdateMin) = ((), M.updateMinWithKey mapMaybeFunc m)
operateMap m (UpdateMax) = ((), M.updateMaxWithKey mapMaybeFunc m)

generateTMap :: T.TMap Key Val -> [Op] -> T.TMap Key Val
generateTMap = foldl (\ m (Op op) -> snd (operateTMap m op))

operateTMap :: T.TMap Key Val -> Operation r -> (r, T.TMap Key Val)
operateTMap m (Insert k v) = ((), T.insert k v m)
operateTMap m (Lookup k) = (T.lookup k m, m)
operateTMap m Map = ((), T.mapWithKey mapFunc m)
operateTMap m ToList = (T.assocs m, m)
operateTMap m Size = (T.size m, m)
operateTMap m (Delete k) = ((), T.delete k m)
operateTMap m MinView = case T.minViewWithKey m of
	Nothing	 -> (Nothing, m)
	Just ((k, v), m')	-> (Just (k, v), m')
operateTMap m MaxView = case T.maxViewWithKey m of
	Nothing	-> (Nothing, m)
	Just (kv, m')	-> (Just kv, m')
operateTMap m MapMaybe = ((), T.mapMaybeWithKey mapMaybeFunc m)
operateTMap m (Union ops) = ((), T.union m $ generateTMap T.empty ops)
operateTMap m (Isect ops) = ((), T.intersectionWithKey isectFunc m (generateTMap T.empty ops))
operateTMap m (DeleteAt i)
	| T.null m	= ((), m)
	| otherwise	= ((), T.deleteAt (i `mod` T.size m) m)
operateTMap m (ElemAt i)
	| T.null m	= (Nothing, m)
	| otherwise	= (Just $ T.elemAt (i `mod` T.size m) m, m)
operateTMap m UpdateMin = ((), T.updateMinWithKey mapMaybeFunc m)
operateTMap m UpdateMax = ((), T.updateMaxWithKey mapMaybeFunc m)

#define VERIFYOP(operation) verifyOp op@operation{} m tm = \
	case (operateMap m op, operateTMap tm op) of \
		{((r1, m'), (r2, tm'))	-> guard (r1 == r2 && M.assocs m' == T.assocs tm') >> return (m', tm');}

verifyOp :: Operation r -> M.Map Key Val -> T.TMap Key Val -> Maybe (M.Map Key Val, T.TMap Key Val)
VERIFYOP(Insert)
VERIFYOP(Lookup)
VERIFYOP(Map)
VERIFYOP(Size)
VERIFYOP(ToList)
VERIFYOP(Delete)
VERIFYOP(MinView)
VERIFYOP(MaxView)
VERIFYOP(MapMaybe)
VERIFYOP(Union)
VERIFYOP(DeleteAt)
VERIFYOP(ElemAt)
VERIFYOP(Isect)
VERIFYOP(UpdateMin)
VERIFYOP(UpdateMax)

verify :: M.Map Key Val -> T.TMap Key Val -> [Op] -> Bool
verify m tm (Op op:ops) = case verifyOp op m tm of
	Nothing	-> False
	Just (m', tm') -> verify m' tm' ops
verify _ _ [] = True

concretes :: [Property]
concretes = [
	printTestCase "extending by a single 0 makes a difference" 
	  (T.intersection (T.singleton (BS.pack [0]) "a") (T.singleton (BS.pack [0,0]) "b") == T.empty),
	printTestCase "comparisons are correct"
	  (let input = [(BS.pack [0], "a"), (BS.pack [0,0,0,0,0], "a")] in T.assocs (T.fromList input) == input),
	printTestCase "comparisons are correct"
	  (let input = [(BS.pack [0], "a"), (BS.pack [0,0,0,0,maxBound], "a")] in T.assocs (T.fromList input) == input),
	printTestCase "deleteAt works for OrdMap"
	  (let input = [(1.4 :: Double, 'a'), (-4.0, 'b')] in T.assocs (T.deleteAt 0 (T.fromList input)) == [(1.4, 'a')]),
	printTestCase "genOptRepr is consistent with equality" (\ a b -> ((a :: Key') == b) == (toRep a == toRep b))
	.&. 
	(printTestCase "fromDistinctAscList"
	  (\ input -> let sinput = sNub fst (input :: [(Key, Val)]) in 
	      T.assocs (T.fromDistinctAscList sinput) == sinput)
	.&.
	printTestCase "fromAscList"
	  (\ input -> let sinput = sortBy (comparing fst) (input :: [(Key, Val)]) in
	      T.assocs (T.fromAscListWith (++) sinput) == fromAscListTest sinput))
	]

fromAscListTest :: [(Key, Val)] -> [(Key, Val)]
fromAscListTest ((k1, v1):xs@((k2,v2):xs'))
  | k1 == k2	= fromAscListTest ((k1, v2 ++ v1):xs')
  | otherwise	= (k1, v1) : fromAscListTest xs
fromAscListTest xs = xs

sNub :: Ord b => (a -> b) -> [a] -> [a]
sNub f xs = nubber xs''
  where	xs' = [(x, f x) | x <- xs]
	xs'' = sortBy (comparing snd) xs'
	nubber ((x1, y1):xs@((_, y2):xs'))
	  | y1 == y2	= nubber ((x1, y1):xs')
	  | otherwise	= x1:nubber xs
	nubber [(x, _)] = [x]
	nubber [] = []

$(genRepr ''Key)
$(genOptRepr ''Key')