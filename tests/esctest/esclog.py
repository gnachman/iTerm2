#!/usr/bin/python2.7
import argparse

LOG_ERROR = 1
LOG_INFO = 2
LOG_DEBUG = 3
gLogFile = None
logfile = None
log = ""
v = LOG_INFO

def AddArguments(parser):
  parser.add_argument("--logfile",
                      help="Log file to write output to",
                      default="/tmp/esctest.log")
  parser.add_argument("--v",
                      help="Verbosity level. 1=errors, 2=errors and info, 3=debug, errors, and info",
                      default=2)

def LogInfo(fmt):
  Log(LOG_INFO, fmt)

def LogDebug(fmt):
  Log(LOG_DEBUG, fmt)

def LogError(fmt):
  Log(LOG_ERROR, fmt)

def Log(level, fmt):
  global log
  global gLogFile
  if v >= level:
    if gLogFile is None:
      gLogFile = open(logfile, "w")
    s = fmt + "\n"
    gLogFile.write(s)
    log += s

def Print():
  print log.replace("\n", "\r\n")
