#!/usr/bin/python2.7
import argparse
import csitests
import esc
import esccsi
import escio
import esclog
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
  parser.add_argument("--force",
                      help="If set, assertions won't stop execution",
                      action="store_true")

  esclog.AddArguments(parser)
  args = parser.parse_args()
  esclog.v = args.v
  esclog.logfile = args.logfile
  esccsi.args = args
  escutil.force = args.force

  logfile = open(args.logfile, "w")
  log = ""

  escio.Init()

def shutdown():
  escio.Shutdown()

def reset():
  esccsi.CSI_DECSTR()
  esccsi.CSI_DECRESET(esccsi.OPT_ALTBUF)  # Is this needed?
  esccsi.CSI_DECRESET(esccsi.OPT_ALTBUF_CURSOR)  # Is this needed?
  esccsi.CSI_DECRESET(esccsi.ALTBUF)  # Is this needed?
  esccsi.CSI_DECRESET(esccsi.DECLRMM)  # This can be removed when the bug revealed by test_DECSET_DECLRMM_ResetByDECSTR is fixed.
  esccsi.CSI_RM(esccsi.IRM)
  # Technically, autowrap should be off by default (this is what the spec calls for).
  # However, xterm and iTerm2 turn it on by default. xterm has a comment that says:
  #   There are a couple of differences from real DEC VTxxx terminals (to avoid
  #   breaking applications which have come to rely on xterm doing
  #   this)...autowrap mode should be reset (instead it's reset to the resource
  #   default).
  esccsi.CSI_DECSET(esccsi.DECAWM)
  esccsi.CSI_DECRESET(esccsi.MoreFix)
  esccsi.CSI_ED(2)

  # Clear tab stops and reset them at 1, 9, ...
  esccsi.CSI_TBC(3)
  width = escutil.GetScreenSize().width()
  x = 1
  while x <= width:
    esccsi.CSI_CUP(esctypes.Point(x, 1))
    escio.Write(esc.ESC + "H")
    x += 8

  esccsi.CSI_CUP(esctypes.Point(1, 1))

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
    RemoveSideChannel()
    esclog.LogInfo("Fails as expected: " + str(e))
    ok = None
  except Exception, e:
    RemoveSideChannel()
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
    tb = traceback.format_exc()
    try:
      reset()
    except:
      print "reset() failed with traceback:"
      print traceback.format_exc().replace("\n", "\r\n")

    print "RunTests failed:\r\n"
    print tb.replace("\n", "\r\n")
    esclog.LogError("Failed with traceback:")
    esclog.LogError(tb)
  finally:
    if args.no_print_logs:
      # Hackily move the cursor to the bottom of the screen.
      esccsi.CSI_CUP(esctypes.Point(1, 1))
      esccsi.CSI_CUD(999)
    else:
      try:
        reset()
      except:
        print "reset() failed with traceback:"
        print traceback.format_exc().replace("\n", "\r\n")

      print "\r\nLogs:\r\n"
      esclog.Print()

  shutdown()

main()
