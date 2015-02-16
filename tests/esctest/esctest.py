#!/usr/bin/python2.7
import c1tests
import csitests
import esc
import escargs
import escc1
import esccsi
import escio
import esclog
import esctypes
import escutil
import inspect
import os
import re
import singlechartests
import traceback

def init():
  global newline
  global logfile
  global log

  newline = "\r\n"

  parser = escargs.parser
  escargs.args = parser.parse_args()

  logfile = open(escargs.args.logfile, "w")
  log = ""

  esc.vtLevel = escargs.args.max_vt_level

  escio.Init()

def shutdown():
  escio.Shutdown()

def reset():
  esccsi.DECSCL(60 + esc.vtLevel, 1)

  escio.use8BitControls = False
  esccsi.DECSTR()
  esccsi.XTERM_WINOPS(esccsi.WINOP_RESIZE_CHARS, 25, 80)
  esccsi.DECRESET(esccsi.OPT_ALTBUF)  # Is this needed?
  esccsi.DECRESET(esccsi.OPT_ALTBUF_CURSOR)  # Is this needed?
  esccsi.DECRESET(esccsi.ALTBUF)  # Is this needed?
  esccsi.DECRESET(esccsi.DECLRMM)  # This can be removed when the bug revealed by test_DECSET_DECLRMM_ResetByDECSTR is fixed.
  esccsi.RM(esccsi.IRM)
  # Technically, autowrap should be off by default (this is what the spec calls for).
  # However, xterm and iTerm2 turn it on by default. xterm has a comment that says:
  #   There are a couple of differences from real DEC VTxxx terminals (to avoid
  #   breaking applications which have come to rely on xterm doing
  #   this)...autowrap mode should be reset (instead it's reset to the resource
  #   default).
  esccsi.DECSET(esccsi.DECAWM)
  esccsi.DECRESET(esccsi.MoreFix)
  # Set and query title with utf-8
  esccsi.RM_Title(0, 1)
  esccsi.SM_Title(2, 3)
  esccsi.ED(2)

  # Pop the title stack just in case something got left on there
  for i in xrange(5):
    esccsi.XTERM_WINOPS(esccsi.WINOP_POP_TITLE,
                            esccsi.WINOP_PUSH_TITLE_ICON_AND_WINDOW)

  # Clear tab stops and reset them at 1, 9, ...
  esccsi.TBC(3)
  width = escutil.GetScreenSize().width()
  x = 1
  while x <= width:
    esccsi.CUP(esctypes.Point(x, 1))
    escc1.HTS()
    x += 8

  esccsi.CUP(esctypes.Point(1, 1))
  esccsi.XTERM_WINOPS(esccsi.WINOP_DEICONIFY)

def AttachSideChannel(name):
  if escargs.args.test_case_dir:
    path = os.path.join(escargs.args.test_case_dir, name + ".txt")
    escio.SetSideChannel(path)

def RemoveSideChannel():
  escio.SetSideChannel(None)

def RunTest(class_name, name, method):
  ok = True
  esclog.LogInfo("Run test: " + class_name + "." + name)
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
  except esctypes.InsufficientVTLevel, e:
    RemoveSideChannel()
    esclog.LogInfo("Skipped because terminal lacks requisite capability: " +
                   str(e))
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
  classes = []

  for category in [ c1tests.tests, csitests.tests, singlechartests.tests ]:
    classes.extend(category)

  for testClass in classes:
    try:
      testObject = testClass()
    except:
      esclog.LogError("Failed to create test class " + testClass.__name__)
      raise
    tests = inspect.getmembers(testObject, predicate=inspect.ismethod)
    for name, method in tests:
      if name.startswith("test_") and (re.search(escargs.args.include, name) or
                                       re.search(escargs.args.include, testClass.__name__)):
        status = RunTest(testClass.__name__, name, method)
        if status is None:
          knownBugs += 1
        elif status:
          passed += 1
        else:
          failures.append(testClass.__name__ + "." + name)
          failed += 1
      else:
        esclog.LogDebug("Skipping test %s in class %s" % (
          name, testClass.__name__))
      if escargs.args.stop_on_failure and failed > 0:
        break
    if escargs.args.stop_on_failure and failed > 0:
      break

  if failed > 0:
    esclog.LogInfo(
        "*** %s passed, %s, %s FAILED ***" % (
          plural("test", passed),
          plural("known bug", knownBugs),
          plural("TEST", failed, caps=True)))
    esclog.LogInfo("Failing tests:\n" + "\n".join(failures))
  else:
    esclog.LogInfo(
        "*** %s passed, %s, %s failed ***" % (
          plural("test", passed),
          plural("known bug", knownBugs),
          plural("test", failed)))

def plural(word, count, caps=False):
  if count == 1:
    suffix = ""
  elif caps:
    suffix = "S"
  else:
    suffix = "s"

  return str(count) + " " + word + suffix

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
    if escargs.args.no_print_logs:
      # Hackily move the cursor to the bottom of the screen.
      esccsi.CUP(esctypes.Point(1, 1))
      esccsi.CUD(999)
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
