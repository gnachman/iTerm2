#!/usr/bin/python2.7
import argparse
import esccsi
import csitests
import esclog
import escio
import esctypes
import escutil
import inspect
import os
import re
import traceback

def init():
  global newline
  global args
  global logfile
  global log

  newline = "\r\n"

  parser = argparse.ArgumentParser()
  parser.add_argument("--disable-xterm-checksum-bug",
                      help="Don't use buggy parameter order for DECRQCRA",
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
  parser.add_argument("--test-case-dir",
                       help="Create files with test cases in the specified directory",
                       default=None)
  parser.add_argument("--stop-on-failure",
                      help="Stop running tests after a failure.",
                      action="store_true")

  esclog.AddArguments(parser)
  args = parser.parse_args()
  esclog.v = args.v
  esclog.logfile = args.logfile
  esccsi.args = args

  logfile = open(args.logfile, "w")
  log = ""

  escio.Init()

def shutdown():
  escio.Shutdown()

def reset():
  esccsi.CSI_DECRESET(esccsi.DECLRMM)
  esccsi.CSI_DECSTBM()
  esccsi.CSI_DECRESET(esccsi.DECOM)
  esccsi.CSI_DECSCA(0)
  esccsi.CSI_ED(2)

def AttachSideChannel(name):
  if args.test_case_dir:
    path = os.path.join(args.test_case_dir, name + ".txt")
    escio.SetSideChannel(path)

def RemoveSideChannel():
  escio.SetSideChannel(None)

def RunTest(name, method):
  ok = True
  esclog.LogInfo("Run test: " + name)
  try:
    reset()
    AttachSideChannel(name)
    method()
    RemoveSideChannel()
    escutil.AssertAssertionAsserted()
    esclog.LogInfo("Passed.")
  except esctypes.KnownBug, e:
    esclog.LogInfo("Fails as expected: " + str(e))
    tb = traceback.format_exc()
    lines = tb.split("\n")
    lines = map(lambda x: "KNOWN BUG: " + x, lines)
    esclog.LogInfo("\r\n".join(lines))
    ok = None
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
  knownBugs = 0
  failures = []
  for testClass in csitests.tests:
    testObject = testClass(args)
    tests = inspect.getmembers(testObject, predicate=inspect.ismethod)
    for name, method in tests:
      if name.startswith("test_") and re.search(args.include, name):
        status = RunTest(name, method)
        if status is None:
          knownBugs += 1
        elif status:
          passed += 1
        else:
          failures.append(name)
          failed += 1
      if args.stop_on_failure and failed > 0:
        break
    if args.stop_on_failure and failed > 0:
      break

  if failed > 0:
    esclog.LogInfo("*** %d tests passed, %d known bugs, %d TESTS FAILED ***" % (passed, knownBugs, failed))
    esclog.LogInfo("Failing tests: " + ",".join(failures))
  else:
    esclog.LogInfo("%d tests passed, %d known bugs, %d tests failed." % (passed, knownBugs, failed))

def main():
  init()

  try:
    RunTests()
  except Exception, e:
    reset()
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
      reset()
      print "\r\nLogs:\r\n"
      esclog.Print()

  shutdown()

main()
