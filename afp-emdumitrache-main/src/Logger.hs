-- Concurrent logging subsystem: a background thread drains a Chan of structured log messages, printing them when logging is enabled.
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

-- This represents one log message. 
-- Each message has a phase, like "parse" or "type-check", and the actual text that should be printed.
data LogMsg = LogMsg
  { logPhase :: String
  , logText  :: String
  }

-- This stores everything needed by the logger. 
-- chan is where log messages are sent. 
-- done is used to know when the logger thread has finished. 
-- enabled decides whether messages should actually be printed.
data Logger = Logger
  { _chan    :: Chan (Maybe LogMsg)
  , _done    :: MVar ()
  , _enabled :: Bool
  }

-- Here we start the logger. 
-- A new channel is created for messages, and a background thread is started to read from that channel and print messages.
startLogger :: Bool -> IO Logger
startLogger enabled = do
  ch   <- newChan
  done <- newEmptyMVar
  _    <- forkIO (drain ch done)
  return (Logger ch done enabled)

-- Here we stop the logger. 
-- Nothing is sent through the channel as a signal that no more messages are coming. 
-- Then it waits until the logger thread confirms that it is done.
stopLogger :: Logger -> IO ()
stopLogger (Logger ch done _) = do
  writeChan ch Nothing
  takeMVar done

-- Here we send a log message to the logger.
-- If logging is disabled, nothing is sent.
logMsg :: Logger -> LogMsg -> IO ()
logMsg (Logger ch _ enabled) msg =
  when enabled (writeChan ch (Just msg))

-- This is the background loop that prints log messages. 
-- It keeps reading from the channel until it receives Nothing. 
-- When Nothing is received, it signals that the logger has finished.
drain :: Chan (Maybe LogMsg) -> MVar () -> IO ()
drain ch done = do
  msg <- readChan ch
  case msg of
    Nothing                  -> putMVar done ()
    Just (LogMsg phase text) -> do
      putStrLn $ "[" ++ phase ++ "] " ++ text
      drain ch done
