-- Copyright 2012-2021, Microsoft Research, Daan Leijen.
--
-- This is free software; you can redistribute it and/or modify it under the
-- terms of the Apache License, Version 2.0. A copy of the License can be
-- found in the LICENSE file at the root of this distribution.
-----------------------------------------------------------------------------
{-
    Definition of higher-ranked types and utility functions over them.
-}
-----------------------------------------------------------------------------
{-# LANGUAGE InstanceSigs #-}
module Type.Type (-- * Types
                    Type(..), Scheme, Sigma, Rho, Tau, Effect, InferType, Pred(..)
                  , Flavour(..)
                  , DataInfo(..), DataKind(..), ConInfo(..), SynInfo(..)
                  , dataInfoIsRec, dataInfoIsOpen, dataInfoIsLiteral
                  , conInfoSize, conInfoScanCount
                  , eqType, eqTypes, elemType
                  -- Predicates
                  , splitPredType, shallowSplitPreds, shallowSplitVars
                  , predType
                  -- ** Type atoms
                  , TypeVar(..), TypeCon(..), TypeSyn(..), SynonymRank
                  -- ** Accessors
                  , maxSynonymRank
                  , synonymRank, typeVarId, typeConName, typeSynName
                  , isBound, isSkolem, isMeta, isMonoType
                  -- ** Operations
                  , makeScheme
                  , quantifyType, qualifyType, applyType, tForall
                  , expandSyn
                  , canonicalForm, minimalForm
                  -- ** Standard types
                  , typeInt, typeBool, typeFun, typeVoid, typeInt32, typeEvIndex, typeSSizeT
                  , typeUnit, typeChar, typeString, typeFloat
                  , typeTuple, typeAny
                  , typeEv, isEvType, makeEvType, typeResumeContext
                  , effectExtend, effectExtends, effectEmpty, effectFixed, tconEffectExtend
                  , effectExtendNoDup, effectExtendNoDups
                  , extractEffectExtend
                  , extractOrderedEffect
                  , orderEffect, labelName, labelNameFull, labelNameEx
                  , isEffectEmpty, isEffectFixed, shallowEffectExtend, shallowExtractEffectExtend

                  , typeDivergent, typeTotal, typePartial, typePure
                  , typeList, typeVector, typeApp, typeRef --, typeNull
                  , typeOptional, typeMakeTuple
                  , typeCCtx, typeCCtxx, typeFieldAddr
                  , isOptional, makeOptionalType, unOptional
                  , typeReuse, typeLocal

                  , tconHandled, tconHandled1
                  -- , typeCps
                  , isEffectAsync, isAsyncFunction

                  -- , isDelay
                  -- ** Standard tests
                  , isTau, isRho, isTVar, isTCon
                  , tconTotal, tconList
                  , isTypeTotal
                  , isTypeBool, isTypeInt, isTypeString, isTypeChar
                  , isTypeUnit
                  , isTypeLocalVar
                  , isValueOperation, makeValueOperation

                  -- ** Trivial conversion
                  , IsType( toType)
                  -- ** Primitive
                  , isFun, splitFunType, splitFunScheme
                  , getTypeArities
                  , module Common.Name
                  ) where

import Lib.Trace
import Data.Maybe(isJust)
import Data.List( sortBy, find )

import Common.Name
import Common.NamePrim
import Common.Range
import Common.Id
import Common.Failure
import Common.Syntax
import Kind.Kind

{--------------------------------------------------------------------------
  Types
--------------------------------------------------------------------------}
-- | Types
data Type   = TForall  ![TypeVar] ![Pred] !Rho  -- ^ forall a b c. phi, psi => rho
                                             -- there is at least one variable
                                             -- every variable occurs at least once in rho
                                             -- variables and predicates are canonically ordered
                                             -- each predicate refers to at least one of the variables
                                             -- rho has kind *
            | TFun     ![(Name,Type)] !Effect !Type    -- ^ (x:a, y:b, z:c) -> m d
            | TCon     !TypeCon               -- ^ type constant (primitive, label, or newtype; not -> or =>)
            | TVar     !TypeVar               -- ^ type variable (cannot instantiate to -> or =>)
            | TApp     !Type ![Type]           -- ^ application of datatypes
            | TSyn     !TypeSyn ![Type] !Type   -- ^ type synonym indirection
                                             -- first [Type] list is the actual arguments
                                             -- final Type is the "real" type (expanded) (always has kind *)
            deriving (Show)

data Pred
  = PredSub !Type !Type
  | PredIFace !Name ![Type]
  deriving (Show)

-- | Various synonyms of types
type Scheme = Type
type Sigma  = Type    -- polymorphic type
type Tau    = Type    -- monomorphic type
type Rho    = Type    -- unqualified type
type Effect = Tau

-- | An inference type can contain type variables of flavour 'Meta' or 'Skolem'
type InferType = Type

-- | Type variables are variables in a type and contain an identifier and
-- kind. One can ask for the free type variables in a type, and substitute them with 'Tau' types.
data TypeVar = TypeVar{ typevarId :: !Id
                      , typevarKind :: !Kind
                      , typevarFlavour :: !Flavour
                      }
                      deriving (Show)

-- | The flavour of a type variable. Types in a "Type.Assumption" (Gamma) and inferred types in "Core.Core"
-- are always of the 'Bound' flavour. 'Meta' and 'Skolem' type variables only ever occur during type inference.
data Flavour = Meta | Skolem | Bound
             deriving (Eq, Ord, Show)

-- | Type constants have a name and a kind
data TypeCon = TypeCon{ typeconName :: !Name
                      , typeconKind :: !Kind
                      }
                      deriving (Show)

-- | Type synonyms have an identifier, kind, and rank (= partial ordering among type synonyms)
data TypeSyn = TypeSyn{ typesynName :: !Name
                      , typesynKind :: !Kind
                      , typesynRank :: !SynonymRank
                      , typesynInfo :: !(Maybe SynInfo)
                      }
                      deriving (Show)

-- | The rank of a type synonym gives a relative ordering among them. This is used
-- during unification to increase the chance of matching up type synonyms.
type SynonymRank = Int


maxSynonymRank :: Type -> SynonymRank
maxSynonymRank tp
  = case tp of
      TForall vars preds rho  -> maxSynonymRank rho
      TFun args eff tp        -> maxSynonymRanks (tp:eff:map snd args)
      TCon _                  -> 0
      TVar _                  -> 0
      TApp tp tps             -> maxSynonymRanks (tp:tps)
      TSyn syn args tp        -> max (synonymRank syn) (maxSynonymRanks (tp:args))

  where
    maxSynonymRanks tps
      = foldr max 0 (map maxSynonymRank tps)

{--------------------------------------------------------------------------
  Information about types

  Defined here to avoid circular dependencies
--------------------------------------------------------------------------}

-- | Data type information: name, kind, type arguments, and constructors
data DataInfo = DataInfo{ dataInfoSort    :: !DataKind
                        , dataInfoName    :: !Name
                        , dataInfoKind    :: !Kind
                        , dataInfoParams  :: ![TypeVar] {- ^ arguments -}
                        , dataInfoConstrs :: ![ConInfo]
                        , dataInfoRange   :: !Range
                        , dataInfoDef     :: !DataDef  -- value(raw,scan), normal, rec, open, linear
                        , dataInfoEffect  :: !DataEffect
                        , dataInfoVis     :: !Visibility
                        , dataInfoDoc     :: !String
                        }


dataInfoIsRec info
  = dataDefIsRec (dataInfoDef info)

dataInfoIsOpen info
  = dataDefIsOpen (dataInfoDef info)

dataInfoIsLiteral info
  = let name = dataInfoName info
    in (name == nameTpInt || name == nameTpChar || name == nameTpString || name == nameTpFloat)

-- | Constructor information: constructor name, name of the newtype, field types, and the full type of the constructor
data ConInfo = ConInfo{ conInfoName :: !Name
                      , conInfoTypeName :: !Name
                      -- , conInfoTypeSort :: Name
                      , conInfoForalls:: ![TypeVar] {- ^ quantifiers -}
                      , conInfoExists :: ![TypeVar] {- ^ existentials -}
                      , conInfoParams :: ![(Name,Type)] {- ^ field types -}
                      , conInfoType   :: !Scheme
                      , conInfoTypeSort :: !DataKind  -- ^ inductive, coinductive, retractive
                      , conInfoRange :: !Range
                      , conInfoParamRanges :: ![Range]
                      , conInfoParamVis    :: ![Visibility]
                      , conInfoSingleton :: !Bool -- ^ is this the only constructor of this type?
                      , conInfoOrderedParams :: ![(Name,Type)] -- ^ fields ordered by size
                      , conInfoValueRepr :: !ValueRepr
                      , conInfoVis :: !Visibility
                      , conInfoDoc :: !String
                      }

instance Show ConInfo where
  show info
    = show (conInfoName info)

-- return size and scan count for a constructor
conInfoSize :: Platform -> ConInfo -> Int
conInfoSize platform conInfo
  = valueReprSize platform (conInfoValueRepr conInfo)

conInfoScanCount :: ConInfo -> Int
conInfoScanCount conInfo
  = valueReprScanCount (conInfoValueRepr conInfo)

-- | A type synonym is quantified by type parameters
data SynInfo = SynInfo{ synInfoName :: Name
                      , synInfoKind  :: Kind
                      , synInfoParams ::  [TypeVar] {- ^ parameters -}
                      , synInfoType :: Type {- ^ result type -}
                      , synInfoRank :: SynonymRank
                      , synInfoRange :: Range
                      , synInfoVis :: Visibility
                      , synInfoDoc :: String
                      }
             deriving Show




{--------------------------------------------------------------------------
  Accessors
--------------------------------------------------------------------------}
-- | Return the 'Id' of a type variable
typeVarId :: TypeVar -> Id
typeVarId (TypeVar id kind _)  = id

typeConName :: TypeCon -> Name
typeConName (TypeCon name kind)      = name

typeSynName :: TypeSyn -> Name
typeSynName (TypeSyn name kind srank _) = name

-- | Return the relative /rank/ of a type synonym.
synonymRank :: TypeSyn -> SynonymRank
synonymRank (TypeSyn name kind srank _) = srank


-- | Is a type variable 'Bound'
isBound :: TypeVar -> Bool
isBound tv   = typevarFlavour tv == Bound

-- | Is a type variable 'Meta' (eg. unifiable)
isMeta :: TypeVar -> Bool
isMeta tv = typevarFlavour tv == Meta

-- | Is a type variable a 'Skolem' (eq. not unifiable)
isSkolem :: TypeVar -> Bool
isSkolem tv = typevarFlavour tv == Skolem

predType :: Pred -> Type
predType (PredSub t1 t2)      = typeFun [(newName "sub",t1)] typeTotal t2
predType (PredIFace name tps) = typeUnit --todo "Type.Operations.predType.PredIFace"

isMonoType :: Type -> Bool
isMonoType tp
  = case expandSyn tp of
      TForall{} -> False
      _         -> True


{--------------------------------------------------------------------------
  Equality
--------------------------------------------------------------------------}

instance Eq TypeVar where
  tv1 == tv2  = (typeVarId tv1 == typeVarId tv2) -- && (typevarFlavour tv1 == typevarFlavour tv2)

instance Ord TypeVar where
  -- tv1 <  tv2      = (typeVarId tv1 < typeVarId tv2) || (typeVarId tv)
  -- tv1 <= tv2      = (typeVarId tv1 <= typeVarId tv2)
  compare tv1 tv2 = case compare (typeVarId tv1) (typeVarId tv2) of
                      -- EQ   -> compare (typevarFlavour tv1) (typevarFlavour tv2)
                      ltgt -> ltgt



instance Eq TypeCon where
  tc1 == tc2      = (typeConName tc1 == typeConName tc2)

instance Ord TypeCon where
  tc1 <  tc2      = (typeConName tc1 < typeConName tc2)
  tc1 <= tc2      = (typeConName tc1 <= typeConName tc2)
  compare tc1 tc2 = compare (typeConName tc1) (typeConName tc2)


instance Eq TypeSyn where
  ts1 == ts2      = (typeSynName ts1 == typeSynName ts2)

instance Ord TypeSyn where
  ts1 <  ts2      = (typeSynName ts1 < typeSynName ts2)
  ts1 <= ts2      = (typeSynName ts1 <= typeSynName ts2)
  compare ts1 ts2 = compare (typeSynName ts1) (typeSynName ts2)

{--------------------------------------------------------------------------
  Split/add quantifiers
--------------------------------------------------------------------------}

-- | Split type into a list of universally quantified
-- type variables, a list of predicates, and a rho-type
splitPredType :: Type -> ([TypeVar], [Pred], Rho)
splitPredType tp
  = case tp of
      TForall vars preds rho      -> (vars, preds, rho)
      TSyn _ _  tp | mustSplit tp -> splitPredType tp
      otherwise                   -> ([], [], tp)
  where
    -- We must split a synonym if its expansion includes further quantifiers or predicates
    mustSplit :: Type -> Bool
    mustSplit tp
      = case tp of
          TForall _ _ _ -> True
          TSyn _ _ tp   -> mustSplit tp
          _             -> False

-- Find all quantified type variables, but do not expand synonyms
shallowSplitVars tp
  = case tp of
      TForall vars preds rho -> (vars, preds, rho)
      otherwise              -> ([], [], tp)

-- Find all predicates
shallowSplitPreds tp
  = case tp of
      TForall _ preds _ -> preds
      otherwise         -> []


expandSyn :: Type -> Type
expandSyn (TSyn syn args tp)
  = expandSyn tp
expandSyn tp
  = tp


-- | A type in canonical form has no type synonyms and expanded effect types.
canonicalForm :: Type -> Type
canonicalForm tp
  = case tp of
      TSyn syn args t       -> canonicalForm t
      TForall vars preds t  -> TForall vars preds (canonicalForm t)
      TApp t ts             -> TApp (canonicalForm t) (map canonicalForm ts)
      TFun args eff res     -> TFun [(name,canonicalForm t) | (name,t) <- args] (orderEffect (canonicalForm eff)) (canonicalForm res)
      _ -> tp


-- | A type in minimal form is in canonical form but also has no named function arguments
minimalForm :: Type -> Type
minimalForm tp
  = case tp of
      TSyn syn args t       -> canonicalForm t
      TForall vars preds t  -> TForall vars preds (canonicalForm t)
      TApp t ts             -> TApp (canonicalForm t) (map canonicalForm ts)
      TFun args eff res     -> TFun [(nameListNil,canonicalForm t) | (_,t) <- args] (orderEffect (canonicalForm eff)) (canonicalForm res)
      _ -> tp


-- | Create a type scheme from a list quantifiers.
makeScheme :: [TypeVar] -> Rho -> Scheme
makeScheme vars rho
  = case splitPredType rho of
      (vars0,preds,t) -> tForall (vars ++ vars0) preds t

quantifyType :: [TypeVar] -> Scheme -> Scheme
quantifyType vars tp
  = case splitPredType tp of
      (vars0,preds,rho) -> tForall (vars ++ vars0) preds rho

qualifyType :: [Pred] -> Scheme -> Scheme
qualifyType preds tp
  = case splitPredType tp of
      (vars,preds0,rho) -> tForall vars (preds ++ preds0) rho

tForall :: [TypeVar] -> [Pred] -> Rho -> Scheme
tForall [] [] rho  = rho
tForall vars preds rho = TForall vars preds rho


applyType tp1 tp2
  = case tp1 of
      TApp tp tps
        -> TApp tp (tps ++ [tp2])
      TSyn _ _ tp | mustSplit tp
        -> applyType tp tp2
      _ -> TApp tp1 [tp2]
  where
    mustSplit tp
      = case tp of
          TApp _ _    -> True
          TSyn _ _ tp -> mustSplit tp
          _           -> False


getTypeArities :: Type -> (Int,Int)
getTypeArities tp
  = case splitFunScheme tp of
      Just (tvars,_,pars,eff,res) -> (length tvars, length pars)
      Nothing -> (0,0)

splitFunScheme :: Scheme -> Maybe ([TypeVar],[Pred],[(Name,Tau)],Effect,Tau)
splitFunScheme tp
  = let (tvars, preds, rho) = splitPredType tp
    in case splitFunType rho of
         Just (pars,eff,res) -> Just (tvars,preds,pars,eff,res)
         Nothing             -> Nothing


{--------------------------------------------------------------------------
  Assertions
--------------------------------------------------------------------------}
-- | Is this a type variable?
isTVar :: Type -> Bool
isTVar tp
  = case tp of
      TVar tv     -> True
      TSyn _ _ t  -> isTVar t
      _           -> False

-- | Is this a type constant
isTCon :: Type -> Bool
isTCon tp
  = case tp of
      TCon c     -> True
      TSyn _ _ t -> isTCon t
      _          -> False

-- | Verify that a type is a rho type
-- (i.e., no outermost quantifiers)
isRho :: Type -> Bool
isRho tp
  = case tp of
      TForall _ _ _ -> False
      TSyn    _ _ t -> isRho t
      _             -> True

-- | Verify that a type is a tau type
-- (i.e., no quantifiers anywhere)
isTau :: Type -> Bool
isTau tp
  = case tp of
      TForall _ _ _  -> False
      TFun xs e r    -> all (isTau . snd) xs && isTau e && isTau r -- TODO e should always be tau
      TCon    _      -> True
      TVar    _      -> True
      TApp    a b    -> isTau a && all isTau b
      TSyn    _ ts t -> isTau t

-- | is this a function type
isFun :: Type -> Bool
isFun tp
  = case splitFunType tp of
      Nothing -> False
      Just (args,effect,res) -> True

-- | split a function type in its arguments, effect, and result type
splitFunType :: Type -> Maybe ([(Name,Type)],Type,Type)
splitFunType tp
  = case tp of
      TFun args effect result
        -> return (args, effect, result)
      TSyn _ _ t
        -> splitFunType t
      _ -> Nothing


{--------------------------------------------------------------------------
  Primitive types
--------------------------------------------------------------------------}

-- | Type of integers (@Int@)
typeInt :: Tau
typeInt
  = TCon tconInt

tconInt = (TypeCon nameTpInt (kindStar))
isTypeInt (TCon tc) = tc == tconInt
isTypeInt _         = False

typeInt32 :: Tau
typeInt32
  = TCon (TypeCon nameTpInt32 kindStar)

typeEvIndex :: Tau
typeEvIndex
  = TSyn (TypeSyn nameTpEvIndex kindStar 0 Nothing) [] typeSSizeT

typeSSizeT :: Tau
typeSSizeT
  = TCon (TypeCon nameTpSSizeT kindStar)

-- | Type of floats
typeFloat :: Tau
typeFloat
  = TCon (TypeCon nameTpFloat (kindStar))

-- | Type of characters
typeChar :: Tau
typeChar
  = TCon tconChar

tconChar = (TypeCon nameTpChar (kindStar))
isTypeChar (TCon tc) = tc == tconChar
isTypeChar _         = False



-- | Type of strings
typeString :: Tau
typeString
  = TCon tconString

tconString = (TypeCon nameTpString (kindStar))
isTypeString (TCon tc) = tc == tconString
isTypeString _         = False


typeResumeContext :: Tau -> Effect -> Effect -> Tau -> Tau
typeResumeContext b e e0 r
  = TApp (TCon tcon) [b,e,e0,r]
  where
    tcon = TypeCon nameTpResumeContext (kindFun kindStar (kindFun kindEffect (kindFun kindEffect (kindFun kindStar kindStar))))

typeRef :: Tau
typeRef
  = TCon (TypeCon nameTpRef (kindFun kindHeap (kindFun kindStar kindStar)))


tconLocalVar = TypeCon nameTpLocalVar (kindFun kindHeap (kindFun kindStar kindStar))

isTypeLocalVar :: Tau -> Bool
isTypeLocalVar tp =
  case expandSyn tp of
    TApp (TCon (TypeCon name _)) [_,_]  -> name == nameTpLocalVar
    _ -> False


isValueOperation tp
  = case splitPredType tp of
      -- (_,_,TSyn syn [_,_] _) -> typeSynName syn == nameTpValueOp
      (_,_,TApp (TCon (TypeCon name _)) [_,_]) -> name == nameTpValueOp
      _ -> False

makeValueOperation eff tp
  = TApp (TCon (TypeCon nameTpValueOp kind)) [eff,tp]
  where
    kind = kindFun kindEffect (kindFun kindStar kindStar)

orderEffect :: HasCallStack => Tau -> Tau
orderEffect tp
  = let (ls,tl) = extractOrderedEffect tp
    in foldr effectExtend tl ls




extractOrderedEffect :: Tau -> ([Tau],Tau)
extractOrderedEffect tp
  = let (labs,tl) = extractEffectExtend tp
        labss     = concatMap expand labs
        slabs     = (sortBy (\l1 l2 -> labelNameCompare (labelName l1) (labelName l2)) labss)
    in -- trace ("sorted: " ++ show (map labelName labss) ++ " to " ++ show (map labelName slabs)) $
       (slabs,tl)
  where
    expand l
      = let (ls,tl) = extractEffectExtend l
        in if (isEffectEmpty tl && not (null ls))
            then ls
            else [l]

labelName :: Tau -> Name
labelName tp
  = let (name,_,_) = (labelNameEx tp) in name

labelNameFull :: Tau -> Name
labelNameFull tp
  = let (name,i,_) = labelNameEx tp
    in postpend ("$" ++ show i) name



labelNameEx :: Tau -> (Name,Int,[Tau])
labelNameEx tp
  = case expandSyn tp of
      TCon tc -> (typeConName tc,0,[])
      TApp (TCon (TypeCon name _)) [htp] | (name == nameTpHandled || name == nameTpHandled1 || name == nameTpNHandled || name == nameTpNHandled1)
        -> labelNameEx htp -- use the handled effect name for handled<htp> types.
      TApp (TCon tc) targs@(TVar (TypeVar id kind Skolem) : _)  | isKindScope kind
        -> (typeConName tc, idNumber id, targs)
      TApp (TCon tc) targs  -> assertion ("non-expanded type synonym used as label") (typeConName tc /= nameEffectExtend) $
                               (typeConName tc,0,targs)
      _  -> failure "Type.Type.labelNameEx: label is not a constant"

typePartial :: Type
typePartial
  = TApp tconHandled [TCon (TypeCon nameTpPartial kindHandled)]

typeLocal :: Type
typeLocal
  = TCon (TypeCon nameTpLocal kindLocal)


-- typeCps :: Type
-- typeCps
--   = TApp tconHandled [TCon (TypeCon nameTpCps kindHandled)]

tconHandled :: Type
tconHandled = TCon $ TypeCon nameTpHandled kind
  where
    kind = kindFun kindHandled kindLabel

tconHandled1 :: Type
tconHandled1 = TCon $ TypeCon nameTpHandled1 kind
  where
    kind = kindFun kindHandled1 kindLabel


isAsyncFunction tp
  = let (_,_,rho) = splitPredType tp
    in case splitFunType rho of
         Just (_,eff,_) -> let (ls,_) = extractEffectExtend eff
                           in any isEffectAsync ls
         _ -> False

isEffectAsync tp
  = case expandSyn tp of
      TForall _ _ rho -> isEffectAsync rho
      TFun _ eff _    -> isEffectAsync eff
      TApp (TCon (TypeCon name _)) [t]
        | name == nameTpHandled -> isEffectAsync t
      TCon (TypeCon hxName _)
        -> hxName == nameTpAsync
      _ -> False

isEffectTyVar (TVar v) = isKindEffect $ typevarKind v
isEffectTyVar _        = False


effectEmpty :: Tau
effectEmpty
  = TCon (TypeCon nameEffectEmpty kindEffect)

isEffectEmpty :: HasCallStack => Tau -> Bool
isEffectEmpty tp
  = case expandSyn tp of
      TCon tc -> typeConName tc == nameEffectEmpty
      _       -> False


effectExtendNoDup :: HasCallStack => Tau -> Tau -> Tau
effectExtendNoDup label eff
  = let (ls,_) = extractEffectExtend label
    in if null ls
        then let (els,_) = extractEffectExtend eff
             in if isJust (find (\e -> eqType label e) els) --  (label `elem` els)
                 then eff
                 else appEffectExtend label eff
        else effectExtendNoDups ls eff

effectExtendNoDups :: HasCallStack => [Tau] -> Tau -> Tau
effectExtendNoDups labels eff
  = foldr effectExtendNoDup eff labels


effectExtend :: HasCallStack => Tau -> Tau -> Tau
effectExtend label eff
  = let (ls,tl) = extractEffectExtend label
    in if null ls
        then appEffectExtend label eff
        else effectExtends ls eff

tconEffectExtend :: TypeCon
tconEffectExtend
  = TypeCon nameEffectExtend (kindFun kindLabel (kindFun kindEffect kindEffect))

effectExtends :: HasCallStack => [Tau] -> Tau -> Tau
-- prevent over expansion of type syonyms here  (see also: Core.Parse.teffect)
effectExtends [lab@(TSyn (TypeSyn _ kind _ _) _ _)] eff  | isEffectEmpty eff && kind == kindEffect
  = lab
effectExtends labels eff
  = foldr effectExtend eff labels

effectFixed :: [Tau] -> Tau
effectFixed labels
  = effectExtends labels effectEmpty

isEffectFixed :: Tau -> Bool
isEffectFixed tp
  = isEffectEmpty (snd (extractEffectExtend tp))

extractEffectExtend :: HasCallStack => Tau -> ([Tau],Tau)
extractEffectExtend t
  = case expandSyn t of
      TApp (TCon tc) [l,e]  | typeConName tc == nameEffectExtend
        -> case extractEffectExtend e of
             (ls,tl) -> case extractLabel l of
                          ls0 -> (ls0 ++ ls, tl)
      _ -> ([],t)
  where
    extractLabel :: Tau -> [Tau]
    extractLabel l
      = -- trace ("extractLabel: " ++ show l) $
        case expandSyn l of
          TApp (TCon tc) [_,e] | typeConName tc == nameEffectExtend
            -> let (ls,tl) = extractEffectExtend l
               in assertion "label was not a fixed effect type alias" (isEffectFixed tl) $
                  ls
          _ -> [l]


shallowExtractEffectExtend :: Tau -> ([Tau],Tau)
shallowExtractEffectExtend t
  = case t of
      TApp (TCon tc) [l,e]  | typeConName tc == nameEffectExtend
        -> case shallowExtractEffectExtend e of
             (ls,tl) -> (l:ls, tl)
      _ -> ([],t)

shallowEffectExtend :: HasCallStack => Tau -> Tau -> Tau
shallowEffectExtend label eff
  -- We do not expand type synonyms in the label here by using the 'shallow' version of extract
  -- this means that type synonyms of kind E (ie. a fixed effect row) could stay around in
  -- the label (which should have kind X).
  -- We use this to keep type synonyms around longer -- but during unification we got to be
  -- careful to expand such synonyms
  = let (ls,tl) = shallowExtractEffectExtend label
    in if null ls
        then appEffectExtend label eff
        else effectExtends ls eff


appEffectExtend :: HasCallStack => Type -> Effect -> Effect
-- appEffectExtend label eff | isKindHandled (kindOf label)
--  =  TApp (TCon tconEffectExtend) [TApp tconHandled [label],eff]
appEffectExtend label eff
  = assertion ("label has not kind X: " ++ show (label,eff)) (hasKindLabel label)
    TApp (TCon tconEffectExtend) [label,eff]

  where
    hasKindLabel l
      = let k = kindOf (expandSyn l)
        in (k == kindLabel || k == kindEffect) -- || isKindHandled k || isKindHandled1 k)

kindOf :: HasCallStack => Tau -> Kind
kindOf tau
  = case tau of
      TForall _ _ tp -> kindOf tp
      TFun _ _ _     -> kindStar
      TVar v         -> typevarKind v
      TCon c         -> typeconKind c
      TSyn syn xs tp -> typesynKind syn
      TApp tp args   -> kindApply args (kindOf tp)
  where
    kindApply [] k   = k
    kindApply (_:rest) (KApp (KApp arr k1) k2)  = kindApply rest k2
    kindApply args  k  = failure ("Type.Type.kindOf: illegal kind in application? " ++ show (k) ++ " to " ++ show args
                              ++ "\n  " ++ show tau)


typeDivergent :: Tau
typeDivergent
  = single nameTpDiv

single :: Name -> Effect
single name
  = effectExtend (TCon (TypeCon name kindLabel)) effectEmpty

typeTotal :: Tau
typeTotal
  = effectEmpty -- TCon tconTotal

tconTotal :: TypeCon
tconTotal
  = TypeCon nameEffectEmpty kindEffect

isTypeTotal :: Tau -> Bool
isTypeTotal (TCon tc) = (tc == tconTotal)
isTypeTotal _         = False

{-
typePartial :: Tau
typePartial
  = single nameTpPartial
-}

typePure :: Tau
typePure
  = effectFixed [typePartial,typeDivergent]


-- | Type of boolean (@Bool@)
typeBool :: Tau
typeBool
  = TCon tconBool

tconBool
  = TypeCon nameTpBool (kindStar)

isTypeBool (TCon tc) = tc == tconBool
isTypeBool _         = False

isTypeUnit (TCon tc) = tc == tconUnit
isTypeUnit _         = False


-- | Type of ctail
typeCCtx :: Tau -> Tau
typeCCtx tp
  = TSyn tsynCCtx [tp] (TApp typeCCtxx [tp,tp])

tsynCCtx :: TypeSyn
tsynCCtx
  = TypeSyn nameTpCCtx (kindFun kindStar kindStar) 0 Nothing

typeCCtxx :: Tau
typeCCtxx
  = TCon tconCCtxx

tconCCtxx :: TypeCon
tconCCtxx
  = TypeCon nameTpCCtxx (kindFun kindStar (kindFun kindStar kindStar))

-- | Type of cfield
typeFieldAddr :: Tau
typeFieldAddr
  = TCon tconFieldAddr

tconFieldAddr :: TypeCon
tconFieldAddr
  = TypeCon nameTpFieldAddr (kindFun kindStar kindStar)

-- | Type of vectors (@[]@)
typeVector :: Tau
typeVector
  = TCon (TypeCon nameTpVector (kindFun kindStar kindStar))

-- | Type of lists (@[]@)
typeList :: Tau
typeList
  = TCon tconList

tconList :: TypeCon
tconList
  = TypeCon nameTpList (kindFun kindStar kindStar)

-- typeNull :: Tau -> Tau
-- typeNull tp
--   = typeApp (TCon (TypeCon nameTpNull kindStar)) [tp]

-- | Type of evidence.
typeEv :: Tau
typeEv = TCon tconEv

tconEv :: TypeCon
tconEv = TypeCon nameTpEv (kindFun kindStar kindStar)

isEvType :: Tau -> Bool
isEvType (TCon tc) = tc == tconEv
isEvType _         = False

makeEvType :: Type -> Type
makeEvType arg = typeApp typeEv [arg]

-- | Create a function type. Can have zero arguments.
typeFun :: [(Name,Tau)] -> Tau -> Tau -> Tau
typeFun args effect result
  = TFun args effect result

-- | Create an application
typeApp :: Tau -> [Tau] -> Tau
typeApp t []            = t
typeApp (TApp t ts0) ts = TApp t (ts0 ++ ts)
typeApp t ts            = TApp t ts

-- | Empty record
typeUnit :: Tau
typeUnit
  = TCon tconUnit

tconUnit
  = TypeCon nameTpUnit kindStar

typeVoid :: Tau
typeVoid
  = TCon (TypeCon nameTpVoid kindStar)

typeReuse :: Tau
typeReuse
   = TCon (TypeCon nameTpReuse kindStar)

typeAny :: Tau
typeAny
  = TCon (TypeCon (nameTpAny) kindStar)

typeMakeTuple :: [Tau] -> Tau
typeMakeTuple tps
  = case tps of
      [] -> typeUnit
      [tp] -> tp
      _    -> typeApp (typeTuple (length tps)) tps

typeTuple :: Int -> Tau
typeTuple n
  = TCon (TypeCon (nameTpTuple n) ({-kindArrowN n-} kindFunN (replicate n kindStar) kindStar))

typeOptional :: Tau
typeOptional
  = TCon tconOptional

tconOptional :: TypeCon
tconOptional
  = (TypeCon nameTpOptional (kindFun kindStar kindStar))

isOptional :: Type -> Bool
isOptional tp
  = case expandSyn tp of
      TApp (TCon tc) [t] -> tc == tconOptional
      _ -> False

makeOptionalType :: Type -> Type
makeOptionalType tp
  = TApp typeOptional [tp]

unOptional :: Type -> Type
unOptional tp
  = case expandSyn tp of
      TApp (TCon tc) [t] | tc == tconOptional -> t
      _ -> tp

-- | Remove type synonym indirections.
pruneSyn :: Rho -> Rho
pruneSyn rho
  = case rho of
      TSyn syn args t -> pruneSyn t
      TApp t1 ts      -> TApp (pruneSyn t1) (map pruneSyn ts)
      _               -> rho


{--------------------------------------------------------------------------
  Conversion between types
--------------------------------------------------------------------------}
class IsType a where
  -- | Trivial conversion to a kind quantified type scheme
  toType :: a -> Type

instance IsType Type where
  toType tp
    = tp

instance IsType TypeVar where
  toType v
    = TVar v

instance IsType TypeCon where
  toType con
    = TCon con


{--------------------------------------------------------------------------
  Equality between types
--------------------------------------------------------------------------}
-- instance Eq Type where
--  (==) = eqType

instance Eq Pred where
  (==) = matchPred

elemType :: Type -> [Type] -> Bool
elemType t ts
  = isJust (find (eqType t) ts)

eqType :: HasCallStack => Type -> Type -> Bool
eqType tp1 tp2
  = case (expandSyn tp1,expandSyn tp2) of
      (TForall vs1 ps1 t1, TForall vs2 ps2 t2)  -> (vs1==vs2 && matchPreds ps1 ps2 && eqType t1 t2)
      (TFun pars1 eff1 t1, TFun pars2 eff2 t2)  -> (eqTypes (map snd pars1) (map snd pars2) && matchEffect eff1 eff2 && eqType t1 t2)
      (TCon c1, TCon c2)                        -> c1 == c2
      (TVar v1, TVar v2)                        -> v1 == v2
      (TApp t1 ts1, TApp t2 ts2)                -> (eqType t1 t2 && eqTypes ts1 ts2)
      -- (TSyn syn1 ts1 t1, TSyn syn2 ts2 t2)      -> (syn1 == syn2 && eqTypes ts1 ts2 && eqType t1 t2)
      _ -> False

matchEffect :: HasCallStack => Effect -> Effect -> Bool
matchEffect eff1 eff2
  = eqType (orderEffect eff1) (orderEffect eff2)

eqTypes :: HasCallStack => [Type] -> [Type] -> Bool
eqTypes ts1 ts2
  = and (zipWith eqType ts1 ts2)

matchPreds ps1 ps2
  = and (zipWith matchPred ps1 ps2)

matchPred :: Pred -> Pred -> Bool
matchPred p1 p2
  = case (p1,p2) of
      (PredSub sub1 sup1, PredSub sub2 sup2)  -> (eqType sub1 sub2 && eqType sup1 sup2)
      (PredIFace n1 ts1, PredIFace n2 ts2)    -> (n1 == n2 && eqTypes ts1 ts2)
      _ -> False
