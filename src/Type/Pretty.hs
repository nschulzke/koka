-----------------------------------------------------------------------------
-- Copyright 2012-2021, Microsoft Research, Daan Leijen.
--
-- This is free software; you can redistribute it and/or modify it under the
-- terms of the Apache License, Version 2.0. A copy of the License can be
-- found in the LICENSE file at the root of this distribution.
-----------------------------------------------------------------------------
module Type.Pretty (-- * Pretty
                    ppType, ppScheme, ppTypeVar, ppDataInfo, ppSynInfo
                   ,prettyDataInfo, prettyConInfo, prettyDefFunType
                   ,ppSchemeEffect, ppDeclType, ppPred
                   ,niceTypeInitial, niceTypeExtend, niceTypeExtendVars
                   ,precTop, precArrow, precApp, precAtom, pparens
                   ,Env(..), defaultEnv
                   ,niceList, niceTypes, niceType, niceEnv
                   ,typeColon, niceTypeVars, ppName, ppParam
                   , canonical, minCanonical
                   , prettyComment, prettyRange, ppNamePlain
                   , keyword
                   ) where


import Data.Char( isSpace )
import qualified Data.Map as M
import Platform.Config( programName )
import Data.List( partition )
import Lib.PPrint
import Common.Name
import Common.NamePrim( isNameTpTuple, nameTpOptional, nameEffectExtend, nameTpTotal, nameEffectEmpty,
                        nameTpHandled, nameTpHandled1, nameTpNHandled, nameTpNHandled1, nameTpDelay, nameSystemCore, nameCoreTypes, nameTpUnit,
                        isSystemCoreName, shortenSystemCoreName, nameTpValueOp )
import Common.ColorScheme
import Common.IdNice
import Common.Syntax
import Kind.Kind
import Kind.Pretty
import Kind.ImportMap

import Type.Type
import Type.TypeVar
import Type.Kind

typeColon colors
  = color (colorSep colors) (text ":")


minCanonical tp
  = compress (show (minimalForm tp))

canonical tp
  = compress (show (canonicalForm tp))


compress cs
  = case cs of
      [] -> []
      (c:cc) ->
        if (c=='\n')
         then compress (dropWhile isSpace cc)
        else if (isSpace c)
         then ' ' : compress (dropWhile isSpace cc)
         else c : compress cc

{--------------------------------------------------------------------------

--------------------------------------------------------------------------}

niceType :: Env -> Type -> Doc
niceType env tp
  -- ppType env tp
  = head (niceTypes env [tp])

niceTypes :: Env -> [Type] -> [Doc]
niceTypes = niceList (\env tp -> color (colorType (colors env)) (ppType env tp))

niceList :: (HasTypeVar a) => (Env -> a -> Doc) -> Env -> [a] -> [Doc]
niceList printer env schemes
  = let env' =  niceEnv env (tvsList (ftv schemes))
    in map (printer env') schemes

niceEnv :: Env -> [TypeVar] -> Env
niceEnv env typevars
  = env{ nice = niceTypeExtendVars typevars (nice env) }

keyword :: Env -> String -> Doc
keyword env s
  = color (colorTypeKeyword (colors env)) (text s)

tab
  = id

{--------------------------------------------------------------------------
  Show
--------------------------------------------------------------------------}

instance Pretty Type where
  pretty  = ppType defaultEnv -- ppScheme defaultEnv

instance Pretty TypeVar where
  pretty  = ppTypeVar defaultEnv

instance Pretty TypeCon where
  pretty = ppTypeCon defaultEnv

instance Pretty TypeSyn where
  pretty = ppTypeSyn defaultEnv

{--------------------------------------------------------------------------
  Pretty print type schemes

  This is somewhat complicated as we want to expand type variables
  into type schemes when they (a) occur once, and (b) the variance
  of the type variable matches the bound. This makes type schemes
  much more readable than the plain mlF variant.

  Furthermore, we want to hide type schemes that are hidden under
  a type synonym (see test/correct/kind/poly3). So, we have to
  determine if variables are used uniquely, or if they are dead,
  where we do not look under type synonyms if the option
  "--expand-synonyms" is not given.

  Even more complications: we want to return a big map with single
  use and dead variables but that is only possible if no name-capture
  is possible. So, we run "uniquefy" before doing the analysis to make
  all bound variables unique relative to each other.
--------------------------------------------------------------------------}
type TvScheme = M.Map TypeVar (Prec -> Doc)

-- | Pretty print environment for types.
data Env     = Env{ showKinds      :: !Bool
                  , showIds        :: !Bool -- show id numbers
                  , showFlavours :: !Bool
                  , expandSynonyms :: !Bool
                  , colors  :: !ColorScheme
                  , nice    :: !Nice
                  , prec    :: !Prec
                  , ranked  :: !TvScheme
                  , context :: !Name  -- ^ module in which we pretty print
                  , importsMap :: !ImportMap -- ^ import aliases
                  , fullNames :: !Bool

                  -- should not really belong here. Contains link bases for documentation generation (see Syntax.Colorize)
                  , colorizing:: !Bool
                  , htmlBases :: ![(String,String)]
                  , htmlCss   :: !String
                  , htmlJs    :: !String

                  -- should not be here either: Signifies whether we output core for an interface or not
                  , coreIface :: !Bool
                  , coreShowTypes :: !Bool  -- show types in core output
                  -- , coreInlineMax :: !Int   -- max size for exported inline definition
                  , coreShowVis   :: !Bool -- show visibility?
                  , coreShowDef   :: !Bool -- show definition body

                  -- should not be here either: was the verbose flag set?
                  , verbose   :: !Int
                  }


-- | Default pretty print environment
defaultEnv :: Env
defaultEnv
  = Env False False
        True -- showFlavours
        False
        defaultColorScheme niceEmpty (precTop-1) M.empty (newName "Main") (importsEmpty)
        False -- fullNames
        False
        []
        ("styles/" ++ programName ++ ".css") -- [("System.","file://c:/users/daan/dev/koka/out/lib/")]
        ("scripts/" ++ programName ++ "-highlight.js")
        False -- coreIface
        False -- coreShowTypes
        -- 20    -- coreInlineMax
        True  -- coreShowVis
        False -- coreShowDef
        0     -- verbose


-- | Pretty print a type.
ppScheme :: Env -> Scheme -> Doc
ppScheme env scheme
  = niceType env scheme

ppSchemeEffect :: Env -> Scheme -> Doc
ppSchemeEffect env tp@(TFun [] effect result)
  = ppSchemeEffect env (TForall [] [] tp)
ppSchemeEffect env (TForall vars preds (TFun [] effect result))
  = color (colorType (colors env)) $
    let env' = env{ nice = niceTypeExtend vars (nice env), prec = precTop } in
    pparens (prec env) precQuant $ tab $
    (if null vars then empty else (keyword env' "forall" <.> angled (map (ppTypeVar env') vars) <.> dot <.> space))
    <.> (if null preds then empty else ((commaSep (map (ppPred env') preds)) <+> text "=> " ))
    <.> (if isTypeTotal effect then empty else (ppType env'{prec = precArrow-1} effect) <.> space)
    <.> ppType env' result
ppSchemeEffect env tp
  = niceType env tp


prettyDefFunType :: Env -> [ParamInfo] -> Scheme -> Doc
prettyDefFunType env pinfos tp
  = case ppDeclType env pinfos tp of
      (Just params,pre,post) -> pre <.> parens (commaSep (map ppParam params)) <+> text "->" <+> post
      (Nothing,pre,post) -> pre <+> text "()" <+> text "->" <+> post
  where
    ppParam (name,pinfo,tpDoc)
      = (case pinfo of Borrow -> text "^" <+> (if nameNil == name then text "_" else ppName env name) <+> text ": "
                       _      -> if nameNil == name then empty else ppName env name <+> text ": ")
        <.> tpDoc

ppDeclType :: Env -> [ParamInfo] -> Scheme -> (Maybe [(Name,ParamInfo,Doc)],Doc,Doc)
ppDeclType env pinfos tp
  = case tp of
      TForall vars preds rho
        -> let env' = niceEnv env vars
               (args,_,res) = ppDeclType env' pinfos rho
               pre  = if (null vars {- prec env == precTopTop-}) then empty
                        else (keyword env' "forall" <.> angled (map (ppTypeVar env') vars) <.> space)
           in (args, pre, res <.> ppPredicates env' preds)
      TFun params effect rho
        -> -- ppFun env (text ":") params eff rho
           let pparams = [(name, pinfo, ppType env tp) | ((name,tp),pinfo) <- zip params (pinfos ++ repeat Own)]
           in (Just pparams, empty, (if (isTypeTotal effect) then empty else (ppType env{prec=precArrow} effect <.> space)) <.> ppType env{prec=precArrow} rho)
      _ -> -- ppType env tp
           (Nothing, empty, ppType env tp)

{--------------------------------------------------------------------------
  Pretty printing of type information

  TODO: properly implement these
--------------------------------------------------------------------------}

instance Show DataInfo where
  show = show . pretty

instance Pretty DataInfo where
  pretty = ppDataInfo Type.Pretty.defaultEnv True False

ppDataInfo env showBody isExtend dataInfo
  = prettyDataInfo env showBody False isExtend dataInfo


commaSep = hsep . punctuate comma


prettyDataInfo env0 showBody publicOnly isExtend info@(DataInfo datakind name kind args cons range datadef dataEff vis doc)
  = if (publicOnly && isPrivate vis) then empty else
    (prettyComment env0 doc $
      (if publicOnly then empty else ppVis env0 vis) <.>
      let env = env0{ nice = niceTypeExtendVars (args) (nice env0) } in
      (if isExtend then keyword env "extend "
        else case datadef of
               DataDefRec     -> keyword env "recursive "
               DataDefOpen    -> keyword env "open "
               DataDefValue v -> keyword env ("value" ++ show v ++ " ")
               _ -> empty) <.>
      (case dataEff of
         DataNoEffect -> empty
         DataEffect named linear -> (if named then keyword env "named " else empty) <.>
                                    (if linear then keyword env "linear " else empty) <.> keyword env "effect ") <.>
      (case datakind of
         Inductive -> keyword env "type"
         CoInductive -> keyword env "co type"
         Retractive  -> keyword env "div type") <+>  -- this "div" means a retractive type or non-(co)inductive type
      -- ppVis env vis <+>
      ppName env name <.> pretty range <.>
      (if null args then empty else space <.> angled (map (ppTypeVar env) args)) <.>
      (if kind /= kindStar then text " ::" <+> ppKind (colors env) 0 kind else empty) <+>
      (if (showBody && not (null cons))
        then (text "{" <->
              indent 2 (vcat (map (prettyConInfo env publicOnly) cons)) <-> text "}")
        else empty))

prettyConInfo env0 publicOnly (ConInfo conName ntname foralls exists fields scheme sort range paramRanges paramVis singleton
                                      orderedFields vrepr vis doc)
  = if (publicOnly && isPrivate vis) then empty else
    (prettyComment env0 doc $
      (if publicOnly then empty else ppVis env0 vis) <.>
      keyword env0 "con" <+>
      ppName env0 conName <.> pretty range <.>
      (if null exists then empty else (angled (map (ppTypeVar env) exists))) <.>
      (if null fields
        then empty
        else parens (commaSep (map (ppField env) (zip paramVis fields)))) <.>
      (text (show vrepr))
      <+> text ":" <+> ppType env scheme <.> semi)
  where
    ppField env (fvis,(name,tp))
      = -- (if (fvis /= vis) then ppVis env fvis else empty) <.>
        (if isFieldName name then empty else (ppName env name <.> text ": ")) <.>
        ppType env tp
    env = env0{ nice = niceTypeExtend exists (nice env0) }


prettyComment env comment doc
  = if null comment then doc
    else let cmt = if last comment == '\n' then init comment else comment
         in color (colorComment (colors env)) (text cmt) <-> doc


ppVis env vis
  = case vis of
      Private -> empty -- keyword env "private "
      Public  -> keyword env "pub "

{--------------------------------------------------------------------------
  Synonym Info
--------------------------------------------------------------------------}


instance Pretty SynInfo where
  pretty info = ppSynInfo Type.Pretty.defaultEnv False False True info

ppSynInfo env isLocal publicOnly showBody (SynInfo name kind params scheme rank range vis doc)
    = if (publicOnly && isPrivate vis) then empty else
      (prettyComment env doc $
        (if isLocal
          then keyword env "local alias"
          else (ppVis env vis) <.> keyword env "alias") <+>
        ppName env name <.> prettyRange env range <.> -- <+> (ppSynInfo env True synInfo)
        let docs = niceTypes env (map TVar params ++ [scheme])
        in (if null params then empty else angled (init docs))
         <.> (if kind /= kindStar then text " ::" <+> ppKind (colors env) precTop kind else empty)
         <+> (if not showBody then empty else keyword env "=" <+> last docs))
         <+> text "=" <+> pretty rank


prettyRange env range
  = if coreIface env then pretty range else empty


{--------------------------------------------------------------------------
  Pretty printing
--------------------------------------------------------------------------}

-- | Precedence
type Prec = Int

precTop,precQuant,precArrow,precApp :: Prec
precTopTop = -1  -- most outer level: used to suppress 'forall'
precTop   = 0
precQuant = 1
precArrow = 2
precApp   = 3
precAtom  = 4
precPred  = 5

pparens :: Prec -> Prec -> Doc -> Doc
pparens context prec doc
  | context >= prec = parens doc
  | otherwise       = doc


ppType :: Env -> Type -> Doc
ppType env tp
  = color (colorType (colors env)) $
    case tp of
      TForall vars preds t
        -> let env' = env{ nice = niceTypeExtend vars (nice env), prec = precTop } in
           pparens (prec env) precQuant $ tab $
               (if (null vars {- prec env == precTopTop-}) then empty
                  else (keyword env' "forall" <.> angled (map (ppTypeVar env') vars) <.> space))
            <.> ppType env' t
            <.> ppPredicates env' preds

      TFun args effect result
        -> ppFun env (text "->") args effect result

      TVar tv@(TypeVar id kind Bound)
                    -> case M.lookup tv (ranked env) of
                         Nothing -> ppTypeVar env tv -- nicePretty (nice env) id
                         Just f  -> f (prec env)
      TVar tv       -> ppTypeVar env tv
      TCon cv       -> --if (typeConName cv == nameEffectEmpty && not (coreIface env))
                       --
                       --  then ppNamePlain env nameTpTotal
                      --  else
                        ppTypeCon env cv
      TApp (TCon con) [_,_] | typeConName con == nameEffectExtend
                    -> let (ls,tl) = shallowExtractEffectExtend tp
                           tldoc   = if (matchType tl effectEmpty)
                                      then empty
                                      else text "|" <.> ppType env{prec=precTop} tl
                       in color (colorEffect (colors env)) $
                          case ls of
                            --[]  | tl == effectEmpty && not (coreIface env) -> ppNamePlain env nameTpTotal
                            [l] | matchType tl effectEmpty && not (coreIface env) -> ppType env{prec=precAtom} l
                            _   -> text "<" <.> hcat (punctuate comma (map (ppType env{prec=precTop}) ls)) <.> tldoc <.> text ">"

      TApp (TCon con) [eff,res]
                    | typeConName con == nameTpValueOp && not (coreIface env)
                    -> text "->" <+> ppType env eff <+> ppType env res
                    | typeConName con == nameTpDelay
                    -> text "$" <+>
                       (if (isTypeTotal eff) then empty else (ppType env{prec = precArrow} eff <.> space)) <.>
                       ppType env{prec=precArrow} res

      TApp (TCon con) [arg]
                    | typeConName con == nameTpOptional && not (coreIface env)
                    -> text "?" <+> ppType env{prec=precAtom} arg
                    | (typeConName con == nameTpHandled || typeConName con == nameTpHandled1 ||
                       typeConName con == nameTpNHandled || typeConName con == nameTpNHandled1) && not (coreIface env)
                    -> ppType env arg
      TApp (TCon (TypeCon name _)) args | isNameTpTuple (name)
                    -> parens (commaSep (map (ppType env{prec = precTop}) args))
      TApp f args   -> pparens (prec env) precApp $
                       ppType env{ prec = precAtom } f <.>
                       (case args of
                          [] -> empty
                          (arg:rest)
                            -> (if null rest then colorByKind env (getKind arg) id else id) $
                               angled (map (ppType env{ prec = precTop }) args))
      TSyn syn args tp
                    -> ppSynonym env syn args (ppType env{ prec = precTop } tp)

ppPredicates env preds
  = (if null preds then empty else (keyword env " with") <+> (align (hcat (map (ppPred env) preds))))

ppFun env arrow args effect result
  = pparens (prec env) precArrow $
    parens (hsep (punctuate comma (map (ppParam env{prec = precTop}) args))) <+>
    (if (isTypeTotal effect) then arrow else (arrow <+> ppType env{prec = precArrow} effect)) <+>
    ppType env{prec=precArrow} result

ppParam :: Env -> (Name,Type) -> Doc
ppParam env (name,tp)
  = (if (nameIsNil name || isFieldName name || isWildcard name || isHiddenName name)
      then empty
      else color (colorParameter (colors env)) (ppNamePlain env (unqualify name)) <.> text " : ")
    <.> ppType env tp


ppName :: Env -> Name -> Doc
ppName env name
  = color (colorSource (colors env)) $
    ppNamePlain env name

ppTypeName :: Env -> Name -> Doc
ppTypeName env name
  = color (colorType (colors env)) $ ppNamePlain env name

ppNamePlain :: Env -> Name -> Doc
ppNamePlain env name | isImplicitParamName name
  = text "?" <.> ppNamePlain env (fromImplicitParamName name)

ppNamePlain env name
  = prettyName (colors env) $
    if (fullNames env || isModuleName name)
     then name
     else if (context env == qualifier name)
            then unqualify name
            else if (isSystemCoreName name && not (coreIface env))
                   then shortenSystemCoreName name
                   else importsAlias name (importsMap env)

---------------------------------------------------------------------------
-- Predicates
---------------------------------------------------------------------------

ppPred :: Env -> Pred -> Doc
ppPred env pred
  = pparens (prec env) precPred $
    case pred of
      PredSub tp1 tp2
        -> ppType (env{prec = precPred}) tp1 <+> text "<=" <+> ppType (env{prec=precPred}) tp2
      PredIFace name args
        -> ppTypeName env name <.> angled (map (ppType env{prec=precTop}) args)



ppSynonym :: Env -> TypeSyn -> [Tau] -> Doc -> Doc
ppSynonym env (TypeSyn name kind rank _) args tpdoc
  = (if (expandSynonyms env)
      then parens
      else if (null args)
       then id
       else pparens (prec env) precApp) $
    ppType env{prec=precTop} (TApp (TCon (TypeCon name kind)) args) <.>
    if (expandSynonyms env) then text " == " <.> pretty rank <+> tpdoc else empty

ppTypeVar :: Env -> TypeVar -> Doc
ppTypeVar env (TypeVar id kind flavour)
    = colorByKindDef env kind colorTypeVar $
      wrapKind (showKinds env) env kind $
      let flav = case flavour of
                    Meta   -> text "_"
                    Skolem -> if (coreIface env) then text "__" else text "$"
                    _      -> empty in
      (if showFlavours env then flav else empty) <.>
         -- text (show id)
         nicePretty (nice env) id <.> (if (showIds env) then text ("=" ++ show id) else empty)

ppTypeCon :: Env -> TypeCon -> Doc
ppTypeCon env (TypeCon name kind)
    = colorByKindDef env kind colorTypeCon $
      --(if name == nameEffectEmpty then id else)
      (wrapKind (showKinds env) env kind) $
      if name == nameTpUnit then text "()" else ppNamePlain env name

ppTypeSyn :: Env -> TypeSyn -> Doc
ppTypeSyn env (TypeSyn name kind rank _)
    = colorByKindDef env kind colorTypeCon $
      wrapKind (showKinds env) env kind (ppNamePlain env name)


colorByKindDef env kind defcolor doc
  = colorByKind env kind (color (defcolor (colors env))) doc

colorByKind env kind defcolor doc
  = case colorForKind env kind of
      Just c  -> color c doc
      Nothing -> defcolor doc


colorForKind env kind
  = if (kind == kindEffect || kind == kindLabel || kind == kindFun kindHeap kindLabel)
     then Just (colorEffect (colors env))
    else if (kind == kindHeap || kind == kindScope)
     then Just (colorEffect (colors env))
     else Nothing

wrapKind :: Bool -> Env -> Kind -> Doc -> Doc
wrapKind showKinds env kind doc
  = if (showKinds && kind /= kindStar )
    then color (colorKind (colors env)) $
         parens (color (colorType (colors env)) doc <+> text "::" <+>
                 ppKind (colors env) precTop kind)
    else doc

niceTypeInitial :: [TypeVar] -> Nice
niceTypeInitial ts
  = niceTypeExtendVars ts niceEmpty

niceTypeExtend :: [TypeVar] -> Nice -> Nice
niceTypeExtend tvars nice
  = niceTypeExtendVars tvars nice

niceTypeExtendVars ts nice
  = let (es,ws) = partition (\(TypeVar id kind flavour) -> kind == kindEffect) ts
        (hs,vs) = partition (\(TypeVar id kind flavour) -> kind == kindHeap) ws
        (ss,us) = partition (\(TypeVar id kind flavour) -> kind == kindScope) vs
        nice1   = niceExtend (map typeVarId us) niceTypeVars nice
        nice2   = niceExtend (map typeVarId es) niceEffectVars nice1
        nice3   = niceExtend (map typeVarId hs) niceHeapVars nice2
        nice4   = niceExtend (map typeVarId ss) niceScopeVars nice3
    in nice4

niceTypeVars :: [String]
niceTypeVars
  = [ [x]              | x <- letters ] ++
    [ ([x] ++ show i)  | i <- [1..], x <- letters]
  where
    letters = ['a'..'d']

niceEffectVars :: [String]
niceEffectVars
  = [ "e" ] ++
    [ (['e'] ++ show i)  | i <- [1..]]

niceHeapVars :: [String]
niceHeapVars
  = [ "h" ] ++
    [ (['h'] ++ show i)  | i <- [1..]]

niceScopeVars :: [String]
niceScopeVars
  = [ "s" ] ++
    [ (['s'] ++ show i)  | i <- [1..]]
