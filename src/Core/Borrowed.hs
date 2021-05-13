-----------------------------------------------------------------------------
-- Copyright 2021 Microsoft Corporation, Daan Leijen
--
-- This is free software; you can redistribute it and/or modify it under the
-- terms of the Apache License, Version 2.0. A copy of the License can be
-- found in the file "license.txt" at the root of this distribution.
-----------------------------------------------------------------------------

module Core.Borrowed( -- Borrowed parameter information
                      Borrowed
                    , borrowedNew
                    , borrowedEmpty
                    , borrowedExtend 
                    , borrowedExtends
                    , borrowedLookup
                    , ppBorrowed

                    , extractBorrowDefs
                    , extractBorrowDef
                    ) where

import Lib.Trace
import Data.Maybe
import Common.Range
import Common.Failure
import qualified Data.List as L
import Lib.PPrint
import Common.Syntax( DefSort(..), ParamInfo(..) )
import qualified Common.NameMap as M
import Common.Name
import Common.ColorScheme
import Core.Core
import Type.Pretty
-- import qualified Core.CoreVar as CoreVar

import Lib.Trace



{--------------------------------------------------------------------------
  Initial
--------------------------------------------------------------------------}

-- | Environment mapping names to type schemes. Due to overloading
-- there may be multiple entries for the same qualified name
newtype Borrowed   = Borrowed (M.NameMap [ParamInfo])

type BorrowDef = (Name,[ParamInfo])

-- | The intial Borrowed
borrowedEmpty :: Borrowed
borrowedEmpty
  = Borrowed M.empty

borrowedNew :: [BorrowDef] -> Borrowed
borrowedNew xs
  = borrowedExtends xs borrowedEmpty

borrowedExtends :: [BorrowDef] -> Borrowed -> Borrowed
borrowedExtends xs borrowed
  = foldr borrowedExtend borrowed xs

borrowedExtend :: BorrowDef -> Borrowed -> Borrowed
borrowedExtend (name,pinfos) (Borrowed borrowed)
  = Borrowed (M.insert name pinfos borrowed)

borrowedLookup :: Name -> Borrowed -> Maybe [ParamInfo]
borrowedLookup name (Borrowed borrowed)
  = M.lookup name borrowed


{--------------------------------------------------------------------------
  Get borrow information from Core
--------------------------------------------------------------------------}
extractBorrowDefs ::  DefGroups -> [BorrowDef]
extractBorrowDefs dgs
  = concatMap extractDefGroup dgs

extractDefGroup (DefRec defs)
  = catMaybes (map (extractBorrowDef True) defs)
extractDefGroup (DefNonRec def)
  = maybeToList (extractBorrowDef False def)

extractBorrowDef :: Bool -> Def -> Maybe BorrowDef
extractBorrowDef isRec def
  = case defSort def of
      DefFun pinfos | not (null pinfos) -> Just (defName def,pinfos)
      _ -> Nothing

instance Show Borrowed where
 show = show . pretty

instance Pretty Borrowed where
 pretty g
   = ppBorrowed Type.Pretty.defaultEnv g


ppBorrowed :: Env -> Borrowed -> Doc
ppBorrowed env (Borrowed borrowed)
   = vcat [fill maxwidth (ppName env name) <+> tupled (map (text . show) pinfos)
       | (name,pinfos) <- M.toList borrowed]
   where
     maxwidth      = 12
