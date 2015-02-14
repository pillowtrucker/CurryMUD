{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE LambdaCase, MonadComprehensions, NamedFieldPuns, OverloadedStrings, PatternSynonyms, TransformListComp, ViewPatterns #-}

module Mud.Cmds.Admin (adminCmds) where

import Mud.ANSI
import Mud.Cmds.Util.Abbrev
import Mud.Cmds.Util.Misc
import Mud.Data.Misc
import Mud.Data.State.ActionParams.ActionParams
import Mud.Data.State.MsgQueue
import Mud.Data.State.State
import Mud.Data.State.Util.Get
import Mud.Data.State.Util.Misc
import Mud.Data.State.Util.Output
import Mud.Data.State.Util.Pla
import Mud.Data.State.Util.STM
import Mud.TopLvlDefs.Chars
import Mud.TopLvlDefs.FilePaths
import Mud.TopLvlDefs.Msgs
import Mud.Util.Misc hiding (patternMatchFail)
import Mud.Util.Padding
import Mud.Util.Quoting
import Mud.Util.Wrapping
import qualified Mud.Logging as L (logIOEx, logNotice, logPla, logPlaExec, logPlaExecArgs, massLogPla)
import qualified Mud.Util.Misc as U (patternMatchFail)

import Control.Applicative ((<$>), (<*>))
import Control.Arrow ((***))
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TMVar (putTMVar)
import Control.Concurrent.STM.TQueue (writeTQueue)
import Control.Exception (IOException)
import Control.Exception.Lifted (try)
import Control.Lens (_1, _2, _3, at, over)
import Control.Lens.Cons (cons)
import Control.Lens.Getter (view)
import Control.Lens.Operators ((&), (.~), (<>~), (?~), (^.))
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.IntMap.Lazy ((!))
import Data.List (delete)
import Data.Monoid ((<>))
import Data.Time (getCurrentTime, getZonedTime)
import Data.Time.Format (formatTime)
import GHC.Exts (sortWith)
import Prelude hiding (pi)
import System.Directory (doesFileExist)
import System.Locale (defaultTimeLocale)
import System.Process (readProcess)
import qualified Data.IntMap.Lazy as IM (IntMap, keys)
import qualified Data.Text as T
import qualified Data.Text.IO as T (putStrLn, readFile)


{-# ANN module ("HLint: ignore Use camelCase" :: String) #-}


-----


patternMatchFail :: T.Text -> [T.Text] -> a
patternMatchFail = U.patternMatchFail "Mud.Cmds.Admin"


-----


logIOEx :: T.Text -> IOException -> MudStack ()
logIOEx = L.logIOEx "Mud.Cmds.Admin"


logNotice :: T.Text -> T.Text -> MudStack ()
logNotice = L.logNotice "Mud.Cmds.Admin"


logPla :: T.Text -> Id -> T.Text -> MudStack ()
logPla = L.logPla "Mud.Cmds.Admin"


logPlaExec :: CmdName -> Id -> MudStack ()
logPlaExec = L.logPlaExec "Mud.Cmds.Admin"


logPlaExecArgs :: CmdName -> Args -> Id -> MudStack ()
logPlaExecArgs = L.logPlaExecArgs "Mud.Cmds.Admin"


massLogPla :: T.Text -> T.Text -> MudStack ()
massLogPla = L.massLogPla "Mud.Cmds.Admin"


-- ==================================================


adminCmds :: [Cmd]
adminCmds =
    [ mkAdminCmd "?"         adminDispCmdList "Display or search this command list."
    , mkAdminCmd "announce"  adminAnnounce    "Send a message to all players."
    , mkAdminCmd "boot"      adminBoot        "Boot a player, optionally with a custom message."
    , mkAdminCmd "bug"       adminBug         "Dump the bug log."
    , mkAdminCmd "date"      adminDate        "Display the current system date."
    , mkAdminCmd "peep"      adminPeep        "Start or stop peeping one or more players."
    , mkAdminCmd "print"     adminPrint       "Print a message to the server console."
    , mkAdminCmd "profanity" adminProfanity   "Dump the profanity log."
    , mkAdminCmd "shutdown"  adminShutdown    "Shut down CurryMUD, optionally with a custom message."
    , mkAdminCmd "tell"      adminTell        "Send a message to a player."
    , mkAdminCmd "time"      adminTime        "Display the current system time."
    , mkAdminCmd "typo"      adminTypo        "Dump the typo log."
    , mkAdminCmd "uptime"    adminUptime      "Display the system uptime."
    , mkAdminCmd "who"       adminWho         "Display or search a list of the players who are currently connected." ]


mkAdminCmd :: CmdName -> Action -> CmdDesc -> Cmd
mkAdminCmd (prefixAdminCmd -> cn) act cd = Cmd { cmdName = cn
                                               , cmdPriorityAbbrev = Nothing
                                               , cmdFullName       = cn
                                               , action            = act
                                               , cmdDesc           = cd }


prefixAdminCmd :: CmdName -> T.Text
prefixAdminCmd = prefixCmd adminCmdChar


-----


adminAnnounce :: Action
adminAnnounce p@AdviseNoArgs = advise p [ prefixAdminCmd "announce" ] advice
  where
    advice = T.concat [ "You must provide a message to send, as in "
                      , quoteColor
                      , dblQuote $ prefixAdminCmd "announce" <> " CurryMUD will be shutting down for maintenance in 30 \
                                                  \minutes"
                      , dfltColor
                      , "." ]
adminAnnounce (Msg i mq msg) = getEntSing i >>= \s -> do
    logPla    "adminAnnounce" i $       "announced "  <> dblQuote msg
    logNotice "adminAnnounce"   $ s <> " announced, " <> dblQuote msg
    ok mq
    massSend $ announceColor <> msg <> dfltColor
adminAnnounce p = patternMatchFail "adminAnnounce" [ showText p ]


-----


adminBoot :: Action
adminBoot p@AdviseNoArgs = advise p [ prefixAdminCmd "boot" ] "Please specify the full PC name of the player you wish \
                                                              \to boot, followed optionally by a custom message."
adminBoot (MsgWithTarget i mq cols target msg) = readTMVarInNWS msgQueueTblTMVar >>= \mqt@(IM.keys -> mqtKeys) ->
    getEntTbl >>= \et -> case [ k | k <- mqtKeys, (et ! k)^.sing == target ] of
      []      -> wrapSend mq cols $ "No PC by the name of " <> dblQuote target <> " is currently connected. (Note that \
                                    \you must specify the full PC name of the player you wish to boot.)"
      [bootI] | s <- (et ! i)^.sing -> if s == target
                then wrapSend mq cols "You can't boot yourself."
                else let bootMq = mqt ! bootI in do
                    ok mq
                    case msg of "" -> dfltMsg   bootI s bootMq
                                _  -> customMsg bootI s bootMq
      xs      -> patternMatchFail "adminBoot" [ showText xs ]
  where
    dfltMsg   bootI s bootMq = do
        logPla "adminBoot dfltMsg"   i     $ T.concat [ "booted ", target, " ", parensQuote "no message given", "." ]
        logPla "adminBoot dfltMsg"   bootI $ T.concat [ "booted by ", s,   " ", parensQuote "no message given", "." ]
        sendMsgBoot bootMq Nothing
    customMsg bootI s bootMq = do
        logPla "adminBoot customMsg" i     $ T.concat [ "booted ", target, "; message: ", dblQuote msg ]
        logPla "adminBoot customMsg" bootI $ T.concat [ "booted by ", s,   "; message: ", dblQuote msg ]
        sendMsgBoot bootMq . Just $ msg
adminBoot p = patternMatchFail "adminBoot" [ showText p ]


-----


adminBug :: Action
adminBug (NoArgs i mq cols) =
    logPlaExec (prefixAdminCmd "bug") i >> dumpLog mq cols bugLogFile ("bug", "bugs")
adminBug p = withoutArgs adminBug p


dumpLog :: MsgQueue -> Cols -> FilePath -> BothGramNos -> MudStack ()
dumpLog mq cols logFile (s, p) = send mq =<< helper
  where
    helper  = (try . liftIO $ readLog) >>= eitherRet handler
    readLog = mIf (doesFileExist logFile)
                  (return . multiWrapNl   cols . T.lines =<< T.readFile logFile)
                  (return . wrapUnlinesNl cols $ "No " <> p <> " have been logged.")
    handler e = do
        fileIOExHandler "dumpLog" e
        return . wrapUnlinesNl cols $ "Unfortunately, the " <> s <> " log could not be retrieved."


-----


adminDate :: Action
adminDate (NoArgs' i mq) = do
    logPlaExec (prefixAdminCmd "date") i
    send mq . nlnl . T.pack . formatTime defaultTimeLocale "%A %B %d" =<< liftIO getZonedTime
adminDate p = withoutArgs adminDate p


-----


adminDispCmdList :: Action
adminDispCmdList p@(LowerNub' i as) = logPlaExecArgs (prefixAdminCmd "?") as i >> dispCmdList adminCmds p
adminDispCmdList p                  = patternMatchFail "adminDispCmdList" [ showText p ]


-----


adminPeep :: Action
adminPeep p@AdviseNoArgs = advise p [ prefixAdminCmd "peep" ] "Please specify one or more PC names of the player(s) \
                                                              \you wish to start or stop peeping."
adminPeep (LowerNub i mq cols (map capitalize -> as)) = helper >>= \(msgs, logMsgs) -> do
    multiWrapSend mq cols msgs
    let (logMsgsSelf, logMsgsOthers) = unzip logMsgs
    logPla "adminPeep" i . (<> ".") . T.intercalate " / " $ logMsgsSelf
    forM_ logMsgsOthers $ uncurry (logPla "adminPeep")
  where
    helper = getEntTbl >>= \et -> onNWS plaTblTMVar $ \(ptTMVar, pt) ->
        let s                    = (et ! i)^.sing
            piss                 = mkPlaIdsSingsList et pt
            (pt', msgs, logMsgs) = foldr (peep s piss) (pt, [], []) as
        in putTMVar ptTMVar pt' >> return (msgs, logMsgs)
    peep s piss target a@(pt, _, _) =
        let notFound    = over _2 (cons sorry) a
            sorry       = "No player by the name of " <> dblQuote target <> " is currently connected."
            found match | (peepI, peepS) <- head . filter ((== match) . snd) $ piss
                        , thePeeper      <- pt ! i
                        , thePeeped      <- pt ! peepI = if peepI `notElem` thePeeper^.peeping
                          then let pt'     = pt & at i     ?~ over peeping (cons peepI) thePeeper
                                                & at peepI ?~ over peepers (cons i    ) thePeeped
                                   msg     = "You are now peeping " <> peepS <> "."
                                   logMsgs = [("started peeping " <> peepS, (peepI, s <> " started peeping."))]
                               in a & _1 .~ pt' & over _2 (cons msg) & _3 <>~ logMsgs
                          else let pt'     = pt & at i     ?~ over peeping (peepI `delete`) thePeeper
                                                & at peepI ?~ over peepers (i     `delete`) thePeeped
                                   msg     = "You are no longer peeping " <> peepS <> "."
                                   logMsgs = [("stopped peeping " <> peepS, (peepI, s <> " stopped peeping."))]
                               in a & _1 .~ pt' & over _2 (cons msg) & _3 <>~ logMsgs
        in maybe notFound found . findFullNameForAbbrev target . map snd $ piss
adminPeep p = patternMatchFail "adminPeep" [ showText p ]


-----


adminPrint :: Action
adminPrint p@AdviseNoArgs = advise p [ prefixAdminCmd "print" ] advice
  where
    advice = T.concat [ "You must provide a message to print to the server console, as in "
                      , quoteColor
                      , dblQuote $ prefixAdminCmd "print" <> " Is anybody home?"
                      , dfltColor
                      , "." ]
adminPrint (Msg i mq msg) = getEntSing i >>= \s -> do
    logPla    "adminPrint" i $       "printed "  <> dblQuote msg
    logNotice "adminPrint"   $ s <> " printed, " <> dblQuote msg
    liftIO . T.putStrLn . T.concat $ [ bracketQuote s, " ", printConsoleColor, msg, dfltColor ]
    ok mq
adminPrint p = patternMatchFail "adminPrint" [ showText p ]


-----


adminProfanity :: Action
adminProfanity (NoArgs i mq cols) =
    logPlaExec (prefixAdminCmd "profanity") i >> dumpLog mq cols profanityLogFile ("profanity", "profanities")
adminProfanity p = withoutArgs adminProfanity p


-----


adminShutdown :: Action
adminShutdown (NoArgs' i mq) = getEntSing i >>= \s -> do
    logPla "adminShutdown" i $ "initiating shutdown " <> parensQuote "no message given" <> "."
    massSend $ shutdownMsgColor <> dfltShutdownMsg <> dfltColor
    massLogPla "adminShutdown" $ T.concat [ "closing connection due to server shutdown initiated by "
                                          , s
                                          , " "
                                          , parensQuote "no message given"
                                          , "." ]
    logNotice  "adminShutdown" $ T.concat [ "server shutdown initiated by "
                                          , s
                                          , " "
                                          , parensQuote "no message given"
                                          , "." ]
    liftIO . atomically . writeTQueue mq $ Shutdown
adminShutdown (Msg i mq msg) = getEntSing i >>= \s -> do
    logPla "adminShutdown" i $ "initiating shutdown; message: " <> dblQuote msg
    massSend $ shutdownMsgColor <> msg <> dfltColor
    massLogPla "adminShutdown" . T.concat $ [ "closing connection due to server shutdown initiated by "
                                            , s
                                            , "; message: "
                                            , dblQuote msg ]
    logNotice  "adminShutdown" . T.concat $ [ "server shutdown initiated by ", s, "; message: ", dblQuote msg ]
    liftIO . atomically . writeTQueue mq $ Shutdown
adminShutdown p = patternMatchFail "adminShutdown" [ showText p ]


-----


adminTell :: Action
adminTell p@AdviseNoArgs = advise p [ prefixAdminCmd "tell" ] advice
  where
    advice = T.concat [ "Please specify the PC name of a player followed by a message, as in "
                      , quoteColor
                      , dblQuote $ prefixAdminCmd "tell" <> " taro thank you for reporting the bug you found"
                      , dfltColor
                      , "." ]
adminTell p@(AdviseOneArg a) = advise p [ prefixAdminCmd "tell" ] advice
  where
    advice = T.concat [ "Please also provide a message to send, as in "
                      , quoteColor
                      , dblQuote $ prefixAdminCmd "tell " <> a <> " thank you for reporting the bug you found"
                      , dfltColor
                      , "." ]
adminTell (MsgWithTarget i mq cols target msg) = do
    et        <- getEntTbl
    (mqt, pt) <- getMqtPt
    let (view sing -> s) = et ! i
        piss             = mkPlaIdsSingsList et pt
        notFound         = wrapSend mq cols $ "No player with the PC name of " <> dblQuote target <> " is currently \
                                              \logged in."
        found match | (tellI, tellS) <- head . filter ((== match) . snd) $ piss
                    , tellMq         <- mqt ! tellI
                    , p              <- pt ! tellI
                    , tellCols       <- p^.columns = do
                       logPla (prefixAdminCmd "tell") i  . T.concat $ [ "sent message to "
                                                                      , tellS
                                                                      , ": "
                                                                      , dblQuote msg ]
                       logPla (prefixAdminCmd "tell") tellI . T.concat $ [ "received message from "
                                                                         , s
                                                                         , ": "
                                                                         , dblQuote msg ]
                       wrapSend mq cols . T.concat $ [ "You send ", tellS, ": ", dblQuote msg ]
                       let targetMsg = T.concat [ bracketQuote s, " ", adminTellColor, msg, dfltColor ]
                       if getPlaFlag IsNotFirstAdminTell p
                         then wrapSend tellMq tellCols targetMsg
                         else multiWrapSend tellMq tellCols . (targetMsg :) =<< firstAdminTell tellI s
    maybe notFound found . findFullNameForAbbrev target . map snd $ piss
adminTell p = patternMatchFail "adminTell" [ showText p ]


firstAdminTell :: Id -> Sing -> MudStack [T.Text]
firstAdminTell i s = [ [ T.concat [ hintANSI
                       , "Hint:"
                       , noHintANSI
                       , " the above is a message from "
                       , s
                       , ", a CurryMUD administrator. To reply, type "
                       , quoteColor
                       , dblQuote $ "admin " <> s <> " msg"
                       , dfltColor
                       , ", where "
                       , quoteColor
                       , dblQuote "msg"
                       , dfltColor
                       , " is the message you want to send to "
                       , s
                       , "." ] ] | _ <- modifyPlaFlag i IsNotFirstAdminTell True ]

-----


adminTime :: Action
adminTime (NoArgs i mq cols) = do
    logPlaExec (prefixAdminCmd "time") i
    (ct, zt) <- liftIO $ (,) <$> formatThat `fmap` getCurrentTime <*> formatThat `fmap` getZonedTime
    multiWrapSend mq cols [ "At the tone, the time will be...", ct, zt ]
  where
    formatThat (T.words . showText -> wordy@(headLast -> (date, zone)))
      | time <- T.init . T.dropWhileEnd (/= '.') . head . tail $ wordy
      = T.concat [ zone, ": ", date, " ", time ]
adminTime p = withoutArgs adminTime p


-----


adminTypo :: Action
adminTypo (NoArgs i mq cols) =
    logPlaExec (prefixAdminCmd "typo") i >> dumpLog mq cols typoLogFile ("typo", "typos")
adminTypo p = withoutArgs adminTypo p


-----


adminUptime :: Action
adminUptime (NoArgs i mq cols) = do
    logPlaExec (prefixAdminCmd "uptime") i
    (try . send mq . nl =<< liftIO runUptime) >>= eitherRet handler
  where
    runUptime = T.pack <$> readProcess "uptime" [] ""
    handler e = logIOEx "adminUptime" e >> sendGenericErrorMsg mq cols
adminUptime p = withoutArgs adminUptime p


-----


adminWho :: Action
adminWho (NoArgs i mq cols)  = do
    logPlaExecArgs (prefixAdminCmd "who") [] i
    pager i mq . concatMap (wrapIndent 20 cols) =<< mkPlaListTxt <$> readWSTMVar <*> readTMVarInNWS plaTblTMVar
adminWho p@(ActionParams { plaId, args }) = do
    logPlaExecArgs (prefixAdminCmd "who") args plaId
    dispMatches p 20 =<< mkPlaListTxt <$> readWSTMVar <*> readTMVarInNWS plaTblTMVar


mkPlaListTxt :: WorldState -> IM.IntMap Pla -> [T.Text]
mkPlaListTxt ws pt =
    let pis         = [ pi | pi <- IM.keys pt, not . getPlaFlag IsAdmin $ (pt ! pi) ]
        (pis', pss) = unzip [ (pi, s) | pi <- pis, let s = view sing $ (ws^.entTbl) ! pi, then sortWith by s ]
        pias        = zip pis' . styleAbbrevs Don'tBracket $ pss
    in map helper pias ++ [ numOfPlayers pis <> " connected." ]
  where
    helper (pi, a) = let ((pp *** pp) -> (s, r)) = getSexRace pi ws
                     in T.concat [ pad 13 a, padOrTrunc 7 s, padOrTrunc 10 r ]
    numOfPlayers (length -> nop) | nop == 1  = "1 player"
                                 | otherwise = showText nop <> " players"
