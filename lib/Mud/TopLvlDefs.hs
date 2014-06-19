{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE OverloadedStrings #-}

module Mud.TopLvlDefs where

import Mud.StateDataTypes (Coins, LinkName)

import Control.Lens.Operators ((^.))
import Data.Text.Strict.Lens (unpacked)
import qualified Data.Text as T
import System.Environment (getEnv)
import System.IO.Unsafe (unsafePerformIO)


ver :: T.Text
ver = "0.1.0.0 (in development since 2013-10)"


mudDir :: FilePath
mudDir = let home = unsafePerformIO . getEnv $ "HOME"
         in home ++ "/CurryMUD/"^.unpacked


logDir, resDir, helpDir, titleDir, miscDir :: FilePath
logDir   = mudDir ++ "logs/"
resDir   = mudDir ++ "res/"
helpDir  = resDir ++ "help/"
titleDir = resDir ++ "titles/"
miscDir  = resDir ++ "misc/"


noOfTitles :: Int
noOfTitles = 37


wizChar, allChar, amountChar, indexChar, slotChar, rmChar, repChar, histChar, indentTagChar :: Char
wizChar       = ':'
allChar       = '\''
amountChar    = '/'
indexChar     = '.'
slotChar      = ':'
rmChar        = '-'
repChar       = ','
histChar      = '!'
indentTagChar = '`'


cols, minCols, maxCols :: Int -- TODO: Move to "Pla" data type?
cols    = minCols
minCols = 30
maxCols = 200


histSize :: Int
histSize = 25


stdLinkNames :: [LinkName]
stdLinkNames = ["n", "ne", "e", "se", "s", "sw", "w", "nw", "u", "d"]


noCoins :: Coins
noCoins = (0, 0, 0)
