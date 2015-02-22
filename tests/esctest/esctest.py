#!/usr/bin/python2.7
import esc
import escargs
import esccmd
import escio
import esclog
import esctypes
import escutil
import inspect
import os
import re
import tests
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
  esccmd.DECSCL(60 + esc.vtLevel, 1)

  escio.use8BitControls = False
  esccmd.DECSTR()
  esccmd.XTERM_WINOPS(esccmd.WINOP_RESIZE_CHARS, 25, 80)
  esccmd.DECRESET(esccmd.OPT_ALTBUF)  # Is this needed?
  esccmd.DECRESET(esccmd.OPT_ALTBUF_CURSOR)  # Is this needed?
  esccmd.DECRESET(esccmd.ALTBUF)  # Is this needed?
  esccmd.DECRESET(esccmd.DECLRMM)  # This can be removed when the bug revealed by test_DECSET_DECLRMM_ResetByDECSTR is fixed.
  esccmd.RM(esccmd.IRM)
  esccmd.RM(esccmd.LNM)
  # Technically, autowrap should be off by default (this is what the spec calls for).
  # However, xterm and iTerm2 turn it on by default. xterm has a comment that says:
  #   There are a couple of differences from real DEC VTxxx terminals (to avoid
  #   breaking applications which have come to rely on xterm doing
  #   this)...autowrap mode should be reset (instead it's reset to the resource
  #   default).
  esccmd.DECSET(esccmd.DECAWM)
  esccmd.DECRESET(esccmd.MoreFix)
  # Set and query title with utf-8
  esccmd.RM_Title(0, 1)
  esccmd.SM_Title(2, 3)
  esccmd.ED(2)

  # Pop the title stack just in case something got left on there
  for i in xrange(5):
    esccmd.XTERM_WINOPS(esccmd.WINOP_POP_TITLE,
                            esccmd.WINOP_PUSH_TITLE_ICON_AND_WINDOW)

  # Clear tab stops and reset them at 1, 9, ...
  esccmd.TBC(3)
  width = escutil.GetScreenSize().width()
  x = 1
  while x <= width:
    esccmd.CUP(esctypes.Point(x, 1))
    esccmd.HTS()
    x += 8

  esccmd.CUP(esctypes.Point(1, 1))
  esccmd.XTERM_WINOPS(esccmd.WINOP_DEICONIFY)
  # Reset all colors.
  esccmd.ResetColor()

  # Work around a bug in reset colors where dynamic colors do not get reset.
  esccmd.ChangeDynamicColor("10", "#000")
  esccmd.ChangeDynamicColor("11", "#ffffff")

def AttachSideChannel(name):
  if escargs.args.test_case_dir:
    path = os.path.join(escargs.args.test_case_dir, name + ".txt")
    escio.SetSideChannel(path)

def RemoveSideChannel():
  escio.SetSideChannel(None)

def CheckForKnownBug(name, method):
  return escutil.ReasonForKnownBugInMethod(method)

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

def MatchingNamesAndMethods():
  classes = []
  for category in [ tests.tests ]:
    classes.extend(category)

  for testClass in classes:
    try:
      testObject = testClass()
    except:
      esclog.LogError("Failed to create test class " + testClass.__name__)
      raise
    members = inspect.getmembers(testObject, predicate=inspect.ismethod)
    for name, method in members:
      full_name = testClass.__name__ + "." + name
      if (name.startswith("test_") and
          re.search(escargs.args.include, full_name)):
        yield full_name, method
      else:
        esclog.LogDebug("Skipping test %s" % full_name)

def PerformAction():
  if escargs.args.action == escargs.ACTION_RUN:
    RunTests()
  elif escargs.args.action == escargs.ACTION_LIST_KNOWN_BUGS:
    ListKnownBugs()

def ListKnownBugs():
  for name, method in MatchingNamesAndMethods():
    reason = CheckForKnownBug(name, method)
    if reason is not None:
      esclog.LogInfo("%s: %s" % (name, reason))

def RunTests():
  failed = 0
  passed = 0
  knownBugs = 0
  failures = []

  for name, method in MatchingNamesAndMethods():
    status = RunTest(name, method)
    if status is None:
      knownBugs += 1
    elif status:
      passed += 1
    else:
      failures.append(name)
      failed += 1
      if escargs.args.stop_on_failure:
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
    PerformAction()
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
      esccmd.CUP(esctypes.Point(1, 1))
      esccmd.CUD(999)
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
