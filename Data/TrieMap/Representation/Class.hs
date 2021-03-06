{-# LANGUAGE TypeFamilies #-}
module Data.TrieMap.Representation.Class where

import Control.Monad.ST
import Control.Monad.Primitive

import Data.Vector (Vector)
import Data.Vector.Fusion.Stream
import Data.TrieMap.Utils

-- | The @Repr@ type class denotes that a type can be decomposed to a representation
-- built out of pieces for which the 'TrieKey' class defines a generalized trie structure.
-- 
-- It is required that, if @('Repr' a, 'Eq' a)@, and @x, y :: a@, then @x '==' y@
-- if and only if @'toRep' x '==' 'toRep' y@.  It is typically the case that
-- @'compare' x y == 'compare' ('toRep' x) ('toRep' y)@, as well, but this is not
-- strictly required.  (It is, however, the case for all instances built into the package.)
-- 
-- As an additional note, the 'Key' modifier is used for \"bootstrapping\" 'Repr' instances,
-- allowing a type to be used in its own 'Repr' definition when wrapped in a 'Key' modifier.
class Repr a where
  type Rep a
  type RepStream a
  toRep :: a -> Rep a
  toRepStreamM :: MStream (ST s) a -> ST s (RepStream a)

-- | A default implementation of @'RepList' a@.
type DRepStream a = Vector (Rep a)

{-# INLINE toRepStream #-}
toRepStream :: Repr a => Stream a -> RepStream a
toRepStream strm = unsafeInlineST (toRepStreamM (liftStream strm))

{-# INLINE dToRepStreamM #-}
-- | A default implementation of 'toRepList'.
dToRepStreamM :: Repr a => MStream (ST s) a -> ST s (DRepStream a)
dToRepStreamM strm = unstreamM (fmap toRep strm)

-- | Uses the 'RepList' instance of @a@.  (This allows for efficient and automatic implementations of e.g. @Rep String@.)
instance Repr a => Repr [a] where
  type Rep [a] = RepStream a
  type RepStream [a] = Vector (RepStream a)
  toRep xs = toRepStream (fromList xs)
  toRepStreamM = dToRepStreamM