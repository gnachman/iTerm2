#!/usr/bin/python2.7
import argparse
import escargs

LOG_ERROR = 1
LOG_INFO = 2
LOG_DEBUG = 3
gLogFile = None
log = ""

def LogInfo(fmt):
  Log(LOG_INFO, fmt)

def LogDebug(fmt):
  Log(LOG_DEBUG, fmt)

def LogError(fmt):
  Log(LOG_ERROR, fmt)

def Log(level, fmt):
  global log
  global gLogFile
  if escargs.args.v >= level:
    if gLogFile is None:
      gLogFile = open(escargs.args.logfile, "w")
    s = fmt + "\n"
    gLogFile.write(s)
    gLogFile.flush()
    log += s

def Print():
  print log.replace("\n", "\r\n")
