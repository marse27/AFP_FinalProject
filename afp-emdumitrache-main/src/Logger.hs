-- | Concurrent logging subsystem: a background thread drains a Chan of
-- structured log messages, printing them when logging is enabled.
-- Satisfies the group-of-2 concurrency technique requirement.
module Logger
  ( Logger
  , LogMsg (..)
  , startLogger
  , stopLogger
  , logMsg
  ) where

import Control.Concurrent      (forkIO)
import Control.Concurrent.Chan (Chan, newChan, readChan, writeChan)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Monad           (when)

-- | A structured log event tagged with a phase name.
data LogMsg = LogMsg
  { logPhase :: String
  , logText  :: String
  }

-- | A running logger handle: message channel, done-signal, and enabled flag.
data Logger = Logger
  { _chan    :: Chan (Maybe LogMsg)
  , _done    :: MVar ()
  , _enabled :: Bool
  }

-- | Fork a background drain thread. Messages print only when enabled is True.
startLogger :: Bool -> IO Logger
startLogger enabled = do
  ch   <- newChan
  done <- newEmptyMVar
  _    <- forkIO (drain ch done)
  return (Logger ch done enabled)

-- | Send the stop sentinel and block until the drain thread has flushed.
stopLogger :: Logger -> IO ()
stopLogger (Logger ch done _) = do
  writeChan ch Nothing
  takeMVar done

-- | Enqueue a log message (no-op when logging is disabled).
logMsg :: Logger -> LogMsg -> IO ()
logMsg (Logger ch _ enabled) msg =
  when enabled (writeChan ch (Just msg))

-- | Background thread body: print messages until the Nothing sentinel arrives.
drain :: Chan (Maybe LogMsg) -> MVar () -> IO ()
drain ch done = do
  msg <- readChan ch
  case msg of
    Nothing                  -> putMVar done ()
    Just (LogMsg phase text) -> do
      putStrLn $ "[" ++ phase ++ "] " ++ text
      drain ch done
