{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE MultiWayIf, OverloadedStrings #-}

module Mud.StateHelpers ( addToInv
                        , findExit
                        , gecrToMesmc
                        , getArm
                        , getCloth
                        , getCoins
                        , getEnt
                        , getEntBothGramNos
                        , getEntBothGramNosInInv
                        , getEntNamesInInv
                        , getEntsCoinsByName
                        , getEntType
                        , getEq
                        , getEqMap
                        , getInv
                        , getInvCoins
                        , getMob
                        , getMobGender
                        , getMobHand
                        , getPCRm
                        , getPCRmId
                        , getPCRmInvCoins
                        , getRm
                        , getRmLinks
                        , getWpn
                        , hasCoins
                        , hasInv
                        , mkCoinsAmtList
                        , mkPlurFromBoth
                        , moveInv
                        , procGetEntsCoinsResPCInv
                        , procGetEntsCoinsResRm
                        , remFromInv
                        , sortInv ) where

import Mud.MiscDataTypes
import Mud.StateDataTypes
import Mud.TopLvlDefs
import Mud.Util hiding (blowUp, patternMatchFail)
import qualified Mud.Util as U (blowUp, patternMatchFail)

import Control.Applicative ((<$>), (<*>))
import Control.Lens (_1, at, ix)
import Control.Lens.Operators ((?=), (^.), (^?!))
import Control.Monad.State (gets)
import Data.Char (isDigit)
import Data.List (sortBy)
import Data.Monoid ((<>))
import Data.Text.Read (decimal)
import Data.Text.Strict.Lens (packed)
import qualified Data.Map.Lazy as M (elems)
import qualified Data.Text as T


blowUp :: T.Text -> T.Text -> [T.Text] -> a
blowUp = U.blowUp "Mud.StateHelpers"


patternMatchFail :: T.Text -> [T.Text] -> a
patternMatchFail = U.patternMatchFail "Mud.StateHelpers"


getEnt :: Id -> MudStack Ent
getEnt i = gets (^?!entTbl.ix i)


getEntType :: Ent -> MudStack Type
getEntType e = let i = e^.entId
               in gets (^?!typeTbl.ix i)


getEntsInInv :: Inv -> MudStack [Ent]
getEntsInInv = mapM getEnt


getEntNamesInInv :: Inv -> MudStack [T.Text]
getEntNamesInInv is = getEntsInInv is >>= \es ->
    return [ e^.name | e <- es ]


getEntSingsInInv :: Inv -> MudStack [T.Text]
getEntSingsInInv is = getEntsInInv is >>= \es ->
    return [ e^.sing | e <- es ]


getEntBothGramNos :: Ent -> BothGramNos
getEntBothGramNos e = (e^.sing, e^.plur)


getEntBothGramNosInInv :: Inv -> MudStack [BothGramNos]
getEntBothGramNosInInv is = map getEntBothGramNos <$> getEntsInInv is


mkPlurFromBoth :: BothGramNos -> Plur
mkPlurFromBoth (s, "") = s <> "s"
mkPlurFromBoth (_, p)  = p


-----


getEntsCoinsByName :: T.Text -> InvCoins -> MudStack GetEntsCoinsRes -- TODO: Impact of alphabetical case?
getEntsCoinsByName searchName ic@(is, c)
  | searchName == [allChar]^.packed = getEntsInInv is >>= \es ->
      return (Mult (length is) searchName (Just es) (Just c))
  | T.head searchName == allChar = getMultEntsCoins (maxBound :: Int) (T.tail searchName) ic
  | isDigit (T.head searchName) = let numText = T.takeWhile isDigit searchName
                                      numInt  = either (oops numText) (^._1) $ decimal numText
                                      rest    = T.drop (T.length numText) searchName
                                  in parse rest numInt
  | otherwise = getMultEntsCoins 1 searchName ic
  where
    oops numText = blowUp "getEntsCoinsByName" "unable to convert Text to Int" [ showText numText ]
    parse rest numInt
      | T.length rest < 2 = return (Sorry searchName)
      | otherwise = let delim = T.head rest
                        rest' = T.tail rest
                    in if | delim == amountChar -> getMultEntsCoins numInt rest' ic
                          | delim == indexChar  -> getIndexedEnt numInt rest' is
                          | otherwise           -> return (Sorry searchName)


getMultEntsCoins :: Amount -> T.Text -> InvCoins -> MudStack GetEntsCoinsRes
getMultEntsCoins a n (is, c)
  | a < 1 = return (Sorry n)
  | n `elem` allCoinNames = mkGecrForCoins a n c
  | otherwise = mkGecrForEnts a n is


-- TODO: In this function, special care must be taken to handle the case where amount == (maxBoun :: Int).
mkGecrForCoins :: Amount -> T.Text -> Coins -> MudStack GetEntsCoinsRes
mkGecrForCoins _ n _ = case n of
  "cp"    -> undefined
  "sp"    -> undefined
  "gp"    -> undefined
  "coin"  -> undefined
  "coins" -> undefined
  _       -> patternMatchFail "mkGecrForCoins" [n]


mkGecrForEnts :: Amount -> T.Text -> Inv -> MudStack GetEntsCoinsRes
mkGecrForEnts a n is = getEntNamesInInv is >>= maybe notFound found . findFullNameForAbbrev n
  where
    notFound = return (Mult a n Nothing Nothing)
    found fullName = getEntsInInv is >>= \es ->
        return (Mult a n (Just . takeMatchingEnts fullName $ es) Nothing)
    takeMatchingEnts fn = take a . filter (\e -> e^.name == fn)


getIndexedEnt :: Index -> T.Text -> Inv -> MudStack GetEntsCoinsRes
getIndexedEnt x n is
  | x < 1     = return (Sorry n)
  | otherwise = getEntNamesInInv is >>= maybe notFound found . findFullNameForAbbrev n
  where
    notFound = return (Indexed x n (Left ""))
    found fullName = filter (\e -> e^.name == fullName) <$> getEntsInInv is >>= \matches ->
        if length matches < x
          then let both = getEntBothGramNos . head $ matches
               in return (Indexed x n (Left . mkPlurFromBoth $ both))
          else return (Indexed x n (Right $ matches !! (x - 1)))


gecrToMesmc :: GetEntsCoinsRes -> MudStack (Maybe [Ent], Maybe Coins)
gecrToMesmc gecr = case gecr of
  (Mult    _ _ Nothing Nothing) -> return (Nothing,  Nothing)
  (Mult    _ _ mes mc)          -> return (mes, mc)
  (Indexed _ _ (Right e))       -> return (Just [e], Nothing)
  _                             -> return (Nothing,  Nothing)


procGetEntsCoinsResRm :: GetEntsCoinsRes -> MudStack (Maybe [Ent])
procGetEntsCoinsResRm gecr = case gecr of
  Sorry n                 -> output ("You don't see " <> aOrAn n <> " here.")             >> return Nothing
  (Mult 1 n Nothing _)    -> output ("You don't see " <> aOrAn n <> " here.")             >> return Nothing
  (Mult _ n Nothing _)    -> output ("You don't see any " <> n <> "s here.")              >> return Nothing
  (Mult _ _ (Just es) _)  -> return (Just es)
  (Indexed _ n (Left "")) -> output ("You don't see any " <> n <> "s here.")              >> return Nothing
  (Indexed x _ (Left p))  -> outputCon [ "You don't see ", showText x, " ", p, " here." ] >> return Nothing
  (Indexed _ _ (Right e)) -> return (Just [e])


procGetEntsCoinsResPCInv :: GetEntsCoinsRes -> MudStack (Maybe [Ent])
procGetEntsCoinsResPCInv gecr = case gecr of
  Sorry n                 -> output ("You don't have " <> aOrAn n <> ".")             >> return Nothing
  (Mult 1 n Nothing _)    -> output ("You don't have " <> aOrAn n <> ".")             >> return Nothing
  (Mult _ n Nothing _)    -> output ("You don't have any " <> n <> "s.")              >> return Nothing
  (Mult _ _ (Just es) _)  -> return (Just es)
  (Indexed _ n (Left "")) -> output ("You don't have any " <> n <> "s.")              >> return Nothing
  (Indexed x _ (Left p))  -> outputCon [ "You don't have ", showText x, " ", p, "." ] >> return Nothing
  (Indexed _ _ (Right e)) -> return (Just [e])


-----


getCloth :: Id -> MudStack Cloth
getCloth i = gets (^?!clothTbl.ix i)


-----


getWpn :: Id -> MudStack Wpn
getWpn i = gets (^?!wpnTbl.ix i)


-----


getArm :: Id -> MudStack Arm
getArm i = gets (^?!armTbl.ix i)


-----


getCoins :: Id -> MudStack Coins
getCoins i = gets (^?!coinsTbl.ix i)


mkCoinsAmtList :: Coins -> [Int]
mkCoinsAmtList (c, g, s) = [c, g, s]


hasCoins :: Id -> MudStack Bool
hasCoins i = not . all (== 0) . mkCoinsAmtList <$> getCoins i


-----


getInv :: Id -> MudStack Inv
getInv i = gets (^?!invTbl.ix i)


hasInv :: Id -> MudStack Bool
hasInv i = not . null <$> getInv i


getInvCoins :: Id -> MudStack InvCoins
getInvCoins i = (,) <$> getInv i <*> getCoins i


addToInv :: Inv -> Id -> MudStack ()
addToInv is ti = getInv ti >>= sortInv . (++ is) >>= (invTbl.at ti ?=)


remFromInv :: Inv -> Id -> MudStack ()
remFromInv is fi = getInv fi >>= \fis ->
    invTbl.at fi ?= deleteFirstOfEach is fis


moveInv :: Inv -> Id -> Id -> MudStack ()
moveInv [] _  _  = return ()
moveInv is fi ti = remFromInv is fi >> addToInv is ti


sortInv :: Inv -> MudStack Inv
sortInv is = (map (^._1) . sortBy nameThenSing) <$> zipped
  where
    nameThenSing (_, n, s) (_, n', s') = (n `compare` n') <> (s `compare` s')
    zipped = zip3 is <$> getEntNamesInInv is <*> getEntSingsInInv is


-----


getEqMap :: Id -> MudStack EqMap
getEqMap i = gets (^?!eqTbl.ix i)


getEq :: Id -> MudStack Inv
getEq i = M.elems <$> getEqMap i


-----


getMob :: Id -> MudStack Mob
getMob i = gets (^?!mobTbl.ix i)


getMobGender :: Id -> MudStack Gender
getMobGender i = (^.gender) <$> getMob i


getMobHand :: Id -> MudStack Hand
getMobHand i = (^.hand) <$> getMob i


-----


getRm :: Id -> MudStack Rm
getRm i = gets (^?!rmTbl.ix i)


getPCRmId :: MudStack Id
getPCRmId = gets (^.pc.rmId)


getPCRm :: MudStack Rm
getPCRm = getPCRmId >>= getRm


getPCRmInvCoins :: MudStack InvCoins
getPCRmInvCoins = getPCRmId >>= getInvCoins


getRmLinks :: Id -> MudStack [RmLink]
getRmLinks i = (^.rmLinks) <$> getRm i


findExit :: LinkName -> Id -> MudStack (Maybe Id)
findExit ln i = getRmLinks i >>= \rls ->
    case [ rl^.destId | rl <- rls, isValid rl ] of
      [] -> return Nothing
      is -> return (Just . head $ is)
  where
    isValid rl = ln `elem` stdLinkNames && ln == (rl^.linkName) || ln `notElem` stdLinkNames && ln `T.isInfixOf` (rl^.linkName)
