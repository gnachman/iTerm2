#!/usr/bin/python2.7
import argparse
import esccsi
import csitests
import esclog
import escio
import esctypes
import inspect
import re
import traceback

def init():
  global newline
  global args
  global logfile
  global log

  escio.Init()
  newline = "\r\n"

  parser = argparse.ArgumentParser()
  parser.add_argument("--enable-xterm-checksum-bug",
                      help="Use buggy parameter order for DECRQCRA",
                      action="store_true")
  parser.add_argument("--include",
                      help="Regex for names of tests to run.",
                      default=".*")
  parser.add_argument("--expected-terminal",
                      help="Terminal in use. Modifies tests for known differences.",
                      choices=("iTerm2", "xterm"),
                      default="iTerm2")
  parser.add_argument("--no-print-logs",
                      help="Print logs after finishing?",
                      action="store_true")

  esclog.AddArguments(parser)
  args = parser.parse_args()
  esclog.v = args.v
  esclog.logfile = args.logfile
  esccsi.args = args

  logfile = open(args.logfile, "w")
  log = ""

def shutdown():
  escio.Shutdown()

def reset():
  esccsi.CSI_DECRESET(esccsi.DECLRMM)
  esccsi.CSI_DECSTBM()
  esccsi.CSI_DECRESET(esccsi.DECOM)
  esccsi.CSI_DECSCA(0)
  esccsi.CSI_ED(2)

def RunTest(name, method):
  ok = True
  esclog.LogInfo("Run test: " + name)
  try:
    reset()
    method()
    esclog.LogInfo("Passed.")
  except Exception, e:
    tb = traceback.format_exc()
    ok = False
    esclog.LogError("*** TEST %s FAILED:" % name)
    esclog.LogError(tb)
  esclog.LogInfo("")
  return ok

def RunTests():
  failed = 0
  passed = 0
  failures = []
  for testClass in csitests.tests:
    testObject = testClass(args)
    tests = inspect.getmembers(testObject, predicate=inspect.ismethod)
    for name, method in tests:
      if name.startswith("test_") and re.search(args.include, name):
        if RunTest(name, method):
          passed += 1
        else:
          failures.append(name)
          failed += 1
  if failed > 0:
    esclog.LogInfo("*** %d tests passed, %d TESTS FAILED ***" % (passed, failed))
    esclog.LogInfo("Failing tests: " + ",".join(failures))
  else:
    esclog.LogInfo("%d tests passed, %d tests failed." % (passed, failed))

def main():
  init()

  try:
    RunTests()
  except Exception, e:
    tb = traceback.format_exc()
    print tb.replace("\n", "\r\n")
    esclog.LogError("Failed with traceback:")
    esclog.LogError(tb)
  finally:
    if args.no_print_logs:
      # Hackily move the cursor to the bottom of the screen.
      esccsi.CSI_CUP(esctypes.Point(1, 1))
      esccsi.CSI_CUD(999)
    else:
      escio.WriteCSI(params=[ 2 ], final='J')
      escio.WriteCSI(params=[ 1, 1 ], final='H')
      print "\r\nLogs:\r\n"
      esclog.Print()

  shutdown()

main()
