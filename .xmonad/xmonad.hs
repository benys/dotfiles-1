import XMonad
import XMonad.Core
import qualified XMonad.StackSet as W

import XMonad.Actions.CycleWS
import XMonad.Actions.GroupNavigation
import XMonad.Actions.Navigation2D
import XMonad.Actions.PhysicalScreens
import XMonad.Actions.TopicSpace
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.InsertPosition
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers
import XMonad.Hooks.WorkspaceHistory
import XMonad.Layout.Maximize
import XMonad.Layout.MultiToggle
import XMonad.Layout.MultiToggle.Instances
import XMonad.Layout.NoBorders
import XMonad.Layout.PerWorkspace
import XMonad.Layout.Reflect
import XMonad.Layout.Renamed
import XMonad.Layout.ResizableTile
import XMonad.Layout.Spacing
import XMonad.Layout.ThreeColumns
import qualified XMonad.Util.ExtensibleState as XS
import XMonad.Util.EZConfig
import XMonad.Util.Run
import XMonad.Util.SpawnOnce
import XMonad.Util.Timer
import XMonad.Util.Ungrab
import XMonad.Util.WorkspaceCompare

import System.Taffybar.Support.PagerHints

import Control.Monad
import Data.List
import Data.Map
import Data.Monoid
import System.Directory

-- Wrapper for TimerId so it can be stored in ExtensibleState
data PanelTimer = PanelTimer TimerId deriving Typeable
instance ExtensionClass PanelTimer where
    initialValue = PanelTimer 0

startupHook' = do
    spawn "feh --bg-scale --no-xinerama --no-fehbg ~/.wallpaper.png"
    spawnOnce "compton"
    spawnOnce "dunst"
    spawnOnce "taffybar"
    spawnOnce "qdbus org.kde.kded5 /modules/networkmanagement init && nmcli connection up umd-oitmr"

logHook' = switchTopicHook >> historyHook >> workspaceHistoryHook

layoutHook' = id
    . onWorkspace "windows" (noBorders Full)
    . mkToggle (single NBFULL)
    . avoidStruts
    . mkToggle (single FULL)
    . mkToggle (single REFLECTX)
    . mkToggle (single MIRROR)
    -- Window padding is roughly based on the *text* height of taffybar
    . renamed [CutWordsLeft 1] . spacingWithEdge 8
    . renamed [CutWordsLeft 1] . maximizeWithPadding 15
    . onWorkspace "mail" layoutHalfTall
    $ layoutGoldenTall ||| layoutHalfTall
  where
    layoutGoldenTall =
        renamed [Replace "GoldenTall"] $ ResizableTall 1 (3/100) (0.605) []
    layoutHalfTall =
        renamed [Replace "HalfTall"] $ ResizableTall 1 (3/100) (1/2) []


isDesktop      = isInProperty "_NET_WM_WINDOW_TYPE" "_NET_WM_WINDOW_TYPE_DESKTOP"
isDock         = isInProperty "_NET_WM_WINDOW_TYPE" "_NET_WM_WINDOW_TYPE_DOCK"
isOSD          = isInProperty "_NET_WM_WINDOW_TYPE" "_KDE_NET_WM_WINDOW_TYPE_ON_SCREEN_DISPLAY"
isNotification = isInProperty "_NET_WM_WINDOW_TYPE" "_NET_WM_WINDOW_TYPE_NOTIFICATION"

sendToBottom :: Window -> X ()
sendToBottom window = withDisplay $ \display ->
    io $ lowerWindow display window

raiseWindow' :: Window -> X ()
raiseWindow' window = withDisplay $ \display ->
    io $ raiseWindow display window

allWindowsByType :: Query Bool -> X [Window]
allWindowsByType query = withDisplay $ \display -> do
    (_, _, windows) <- asks theRoot >>= io . queryTree display
    filterM (runQuery query) windows

sendToJustAboveDesktop :: Window -> X ()
sendToJustAboveDesktop window = do
    sendToBottom window
    allWindowsByType isDesktop >>= mapM_ sendToBottom

doWindowAction :: (Window -> X ()) -> ManageHook
doWindowAction action = ask >>= liftX . action >> idHook

raiseAllNotifications :: X ()
raiseAllNotifications = allWindowsByType isNotification >>= mapM_ raiseWindow'

raiseAllNotificationsHook :: ManageHook
raiseAllNotificationsHook = liftX raiseAllNotifications >> idHook

raisePanelTemporarily :: X ()
raisePanelTemporarily = do
    allWindowsByType isDock >>= mapM_ raiseWindow'
    startTimer 2 >>= XS.put . PanelTimer

manageHook' = composeOne
    [ className =? "ksmserver"      -?> doIgnore
    , className =? "XLogo"          -?> doFloat
    , className =? "systemsettings" -?> doCenterFloat
    , isDesktop                     -?> doWindowAction sendToBottom
    , isDock                        -?> doWindowAction sendToJustAboveDesktop
    , isOSD                         -?> doCenterFloat
    , isDialog                      -?> doFloat
    , transience                    --- move to parent window
    , pure True                     -?> insertPosition Below Newer
    ] <+> raiseAllNotificationsHook

-- Based on https://stackoverflow.com/questions/11045239/can-xmonads-loghook-be-run-at-set-intervals-rather-than-in-merely-response-to/14297833
handleEventHook' event = do
    (PanelTimer timerId) <- XS.get
    handleTimer timerId event $ do
        allWindowsByType isDock >>= mapM_ sendToJustAboveDesktop
        return Nothing
    return (All True)

workspaces' = ["web", "ops", "dev", "music", "mail", "chat", "seven", "eight", "nine", "windows"]

topicConfig :: TopicConfig
topicConfig = def
    { defaultTopicAction = \topic -> return ()
    , topicActions = fromList $
        [ ("web"    , spawn "~/.xmonad/scripts/firefox-wait --new-window about:home && ~/.xmonad/scripts/firefox-wait twitter.com washingtonpost.com")
        , ("ops"    , (ask >>= spawn . terminal . config))
        , ("dev"    , (ask >>= spawn . terminal . config))
        , ("music"  , spawn "chromium --app=https://play.google.com/music/listen")
        , ("mail"   , spawn "~/.xmonad/scripts/firefox-wait --new-window https://mail.google.com/mail/u/0/#inbox && ~/.xmonad/scripts/firefox-wait --new-window https://mail.google.com/mail/u/1/#inbox")
        , ("chat"   , spawn "~/.xmonad/scripts/firefox-wait --new-window teams.webex.com")
        , ("windows", spawn "GDK_DPI_SCALE=1.0 GDK_SCALE=1 virt-viewer --full-screen --connect=qemu:///system --wait --reconnect -- osprey")
        ]
    }

switchTopicHook :: X ()
switchTopicHook = do
    currentWorkspace <- gets (W.tag . W.workspace . W.current . windowset)
    history <- workspaceHistory
    case history of
        (lastWorkspace:_) -> when (currentWorkspace /= lastWorkspace) $ switchTopic' currentWorkspace
        otherwise         -> switchTopic' currentWorkspace

switchTopic' :: Topic -> X ()
switchTopic' topic = do
    wins <- gets (W.integrate' . W.stack . W.workspace . W.current . windowset)
    when (Data.List.null wins) $ topicAction topicConfig topic

physicalScreens :: X [Maybe ScreenId]
physicalScreens = withWindowSet $ \windowSet -> do
    let numScreens = length $ W.screens windowSet
    mapM (\s -> getScreen def (P s)) [0..numScreens]

-- If this function seems weird, it's because it's intended to be dual to
--   getScreen :: PhysicalScreen -> X (Maybe ScreenId)
-- from XMonad.Actions.PhysicalScreens.
-- See: https://hackage.haskell.org/package/xmonad-contrib-0.13/docs/XMonad-Actions-PhysicalScreens.html
getPhysicalScreen :: ScreenId -> X (Maybe PhysicalScreen)
getPhysicalScreen sid = do
    pscreens <- physicalScreens
    return $ (Just sid) `elemIndex` pscreens >>= \s -> Just (P s)

rofi :: X String
rofi = withWindowSet $ \windowSet -> do
    let sid = W.screen (W.current windowSet)
    pscreen <- getPhysicalScreen sid
    return $ case pscreen of
                Just (P s) -> "rofi -m " ++ (show s)
                otherwise  -> "rofi"

spawnRofi :: String -> X ()
spawnRofi args = do
    cmd <- rofi
    spawn $ cmd ++ " " ++ args

reflectWith :: X () -> X ()
reflectWith swapFn = do
    sendMessage $ Toggle REFLECTX
    swapFn
    sendMessage $ Toggle REFLECTX

main = xmonad
    . docks
    . ewmh
    . pagerHints
    . withNavigation2DConfig def { defaultTiledNavigation = centerNavigation }
    $ def
    { modMask            = mod4Mask
    , terminal           = "urxvt"
    , startupHook        = startupHook'
    , logHook            = logHook'
    , layoutHook         = layoutHook'
    , manageHook         = manageHook'
    , handleEventHook    = handleEventHook'
    , workspaces         = workspaces'
    , borderWidth        = 3
    , focusedBorderColor = "#ab4642"
    , normalBorderColor  = "#b8b8b8"
    }
    `additionalKeysP`
    [ ("M-0"           , windows $ W.greedyView "windows")
    , ("M-="           , sendMessage $ IncMasterN 1)
    , ("M-S-="         , sendMessage $ IncMasterN 1)
    , ("M--"           , sendMessage $ IncMasterN (-1))
    , ("M-'"           , viewScreen def 0)
    , ("M-,"           , viewScreen def 1)
    , ("M-."           , viewScreen def 1)
    , ("M-S-'"         , sendToScreen def 0)
    , ("M-S-,"         , sendToScreen def 1)
    , ("M-S-."         , sendToScreen def 1)
    , ("M-f"           , sendMessage $ Toggle NBFULL)
    , ("M-S-f"         , sendMessage $ Toggle FULL)
    , ("M-r"           , sendMessage $ Toggle REFLECTX)
    , ("M-S-r"         , sendMessage $ Toggle MIRROR)
    , ("M-z"           , withFocused $ sendMessage . maximizeRestore)
    , ("M-h"           , windowGo L False)
    , ("M-l"           , windowGo R False)
    , ("M-j"           , windowGo D False)
    , ("M-k"           , windowGo U False)
    , ("M-S-h"         , sendMessage Shrink)
    , ("M-S-l"         , sendMessage Expand)
    , ("M-S-j"         , sendMessage MirrorShrink)
    , ("M-S-k"         , sendMessage MirrorExpand)
    , ("M-u"           , windows W.swapUp)
    , ("M-d"           , windows W.swapDown)
    , ("M-x"           , kill)
    , ("M-;"           , nextMatch History (return True))
    , ("M-a"           , toggleWS)
    , ("M-o"           , reflectWith swapPrevScreen)
    , ("M-e"           , reflectWith swapNextScreen)
    , ("M-S-o"         , swapPrevScreen)
    , ("M-S-e"         , swapNextScreen)
    , ("M-S-q"         , spawn "qdbus org.kde.ksmserver /KSMServer logout 1 0 1")
    , ("M-s"           , raisePanelTemporarily >> spawn "~/.xmonad/scripts/screensaver toggle")
    , ("M-<Escape>"    , unGrab >> spawn "~/.xmonad/scripts/screensaver reset; loginctl lock-session")
    , ("M-<Space>"     , spawn "qdbus org.mpris.MediaPlayer2.chrome /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause")
    , ("M-<Tab>"       , sendMessage NextLayout)
    , ("M-<Backspace>" , setLayout $ Layout layoutHook')
    , ("M1-<Tab>"      , windows W.focusDown)
    , ("M1-S-<Tab>"    , windows W.focusUp)
    , ("M-p"           , spawnRofi "-show drun")
    , ("M-w"           , spawnRofi "-show window")
    , ("M1-S-a"        , unGrab >> spawn "xdotool keyup alt+shift && ~/.xmonad/scripts/bw-type jtl/admin 3523ac3d-3fa3-4fa3-9638-a91a00f9a9a8")
    , ("M1-S-s"        , unGrab >> spawn "xdotool keyup alt+shift && ~/.xmonad/scripts/bw-type jtl/root 25d44246-0ed1-41e3-a0cc-a91a00f9a9a8")
    , ("M1-S-u"        , unGrab >> spawn "xdotool keyup alt+shift && ~/.xmonad/scripts/bw-type UMD e2ddb2b1-6f1a-4ca6-b388-a91a00f9a9a8")
    , ("M-S-d"         , spawn "pkill dunst; exec dunst")
    , ("<XF86AudioMicMute>"      , spawn "~/.xmonad/scripts/mic toggle-mute")
    , ("<XF86AudioMute>"         , raisePanelTemporarily >> spawn "~/.xmonad/scripts/volume toggle-mute")
    , ("<XF86AudioLowerVolume>"  , raisePanelTemporarily >> spawn "~/.xmonad/scripts/volume -1dB")
    , ("<XF86AudioRaiseVolume>"  , raisePanelTemporarily >> spawn "~/.xmonad/scripts/volume +1dB")
    , ("<XF86MonBrightnessDown>" , raisePanelTemporarily >> spawn "~/.xmonad/scripts/brightness decrease")
    , ("<XF86MonBrightnessUp>"   , raisePanelTemporarily >> spawn "~/.xmonad/scripts/brightness increase")
    ]
    `removeKeysP`
    [ "M-S-c"       -- close window
    , "M-S-<Space>" -- reset workspace to default layout
    , "M-S-<Tab>"   -- focus previous window
    , "M-S-/"       -- show help
    , "M-S-p"       -- launch gmrun
    ]

-- vim: filetype=haskell
