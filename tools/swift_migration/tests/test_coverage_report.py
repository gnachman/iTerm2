"""Tests for tools/swift_migration/coverage_report.py.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p test_coverage_report.py

The fixtures in fixtures/coverage_report are compiled and run in the test,
with `xcrun clang -fprofile-instr-generate -fcoverage-mapping`, and their
profiles merged with `xcrun llvm-profdata merge -sparse`, so every count
comes from the real toolchain. Lines are found by the "M:" markers in the
fixtures' comments. When xcrun, clang, llvm-profdata or llvm-cov is
missing, every test that needs them is skipped with a message saying so.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import coverage_report  # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures", "coverage_report")
TOOL = os.path.join(TOOLS, "coverage_report.py")


def toolchain_missing():
    """A message naming what is missing, or None."""
    if shutil.which("xcrun") is None:
        return "xcrun is not installed"
    for tool in ("clang", "llvm-profdata", "llvm-cov"):
        r = subprocess.run(["xcrun", "--find", tool], capture_output=True, text=True)
        if r.returncode != 0:
            return "xcrun cannot find %s" % tool
    return None


MISSING = toolchain_missing()
if MISSING:
    sys.stderr.write("test_coverage_report: skipping the compiled-fixture tests: %s\n" % MISSING)


def swift_missing():
    if MISSING:
        return MISSING
    r = subprocess.run(["xcrun", "--find", "swiftc"], capture_output=True, text=True)
    return None if r.returncode == 0 else "xcrun cannot find swiftc"


SWIFT_MISSING = swift_missing()


def marker_line(path, marker):
    with open(path) as f:
        for number, text in enumerate(f, 1):
            if "M:" + marker in text.split("//", 1)[-1].split():
                return number
    raise AssertionError("no marker %s in %s" % (marker, path))


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Built:
    """The fixtures compiled and run once for the whole module."""
    dir = None


def setUpModule():
    if MISSING:
        return
    d = tempfile.mkdtemp(prefix="coverage_report_test.")
    Built.dir = d
    src = os.path.join(d, "src")
    shutil.copytree(FIXTURES, src)
    Built.branches = os.path.join(src, "branches.c")
    Built.shapes = os.path.join(src, "shapes.m")
    Built.twice = os.path.join(src, "twice.c")
    flags = ["-fprofile-instr-generate", "-fcoverage-mapping", "-O0", "-w"]

    def build(out, sources, extra=()):
        r = run(["xcrun", "clang"] + flags + list(extra) + sources + ["-o", out])
        assert r.returncode == 0, r.stderr

    def profile(binary, profraw, args=()):
        env = dict(os.environ, LLVM_PROFILE_FILE=profraw)
        r = run([binary] + list(args), env=env)
        assert r.returncode == 0, r.stderr

    def merge(out, inputs):
        r = run(["xcrun", "llvm-profdata", "merge", "-sparse"] + inputs + ["-o", out])
        assert r.returncode == 0, r.stderr

    Built.cbin = os.path.join(d, "branches")
    build(Built.cbin, [Built.branches])
    Built.mbin = os.path.join(d, "shapes")
    build(Built.mbin, [Built.shapes], ["-fobjc-arc", "-framework", "Foundation"])
    Built.twice_a = os.path.join(d, "twice_a")
    build(Built.twice_a, [Built.twice])
    Built.twice_b = os.path.join(d, "twice_b")
    build(Built.twice_b, [Built.twice], ["-DVARIANT"])
    Built.twice_c = os.path.join(d, "twice_c")
    build(Built.twice_c, [Built.twice])
    Built.switches = os.path.join(src, "switches.c")
    Built.swbin = os.path.join(d, "switches")
    build(Built.swbin, [Built.switches])
    Built.blocks = os.path.join(src, "blocks.m")
    Built.bbin = os.path.join(d, "blocks")
    build(Built.bbin, [Built.blocks], ["-fobjc-arc", "-framework", "Foundation"])
    Built.lambdas = os.path.join(src, "lambdas.mm")
    Built.lbin = os.path.join(d, "lambdas")
    r = run(["xcrun", "clang++"] + flags + [Built.lambdas, "-o", Built.lbin])
    assert r.returncode == 0, r.stderr
    Built.foldmain = os.path.join(src, "foldmain.c")
    Built.foldbin = os.path.join(d, "foldmain")
    build(Built.foldbin, [Built.foldmain])
    Built.tubin = os.path.join(d, "tu")
    build(Built.tubin, [os.path.join(src, "tu1.c"), os.path.join(src, "tu2.c")])
    for binary, name in ((Built.swbin, "sw"), (Built.bbin, "b"), (Built.lbin, "l"), (Built.foldbin, "fold"),
                         (Built.tubin, "tu")):
        profile(binary, os.path.join(d, name + ".profraw"))
        prof = os.path.join(d, name + ".profdata")
        merge(prof, [os.path.join(d, name + ".profraw")])
        setattr(Built, name + "prof", prof)
    Built.swift = os.path.join(src, "constructs.swift")
    Built.elseif = os.path.join(src, "elseif.swift")
    Built.strings = os.path.join(src, "strings.swift")
    if not SWIFT_MISSING:
        # One compiler process at a time.
        for source, name in ((Built.swift, "s"), (Built.elseif, "e"), (Built.strings, "str")):
            binary = os.path.join(d, name + "bin")
            r = run(["xcrun", "swiftc", "-profile-generate", "-profile-coverage-mapping", "-Onone", source,
                     "-o", binary])
            assert r.returncode == 0, r.stderr
            profile(binary, os.path.join(d, name + ".profraw"))
            prof = os.path.join(d, name + ".profdata")
            merge(prof, [os.path.join(d, name + ".profraw")])
            setattr(Built, name + "bin", binary)
            setattr(Built, name + "prof", prof)

    profile(Built.cbin, os.path.join(d, "c.profraw"))
    profile(Built.cbin, os.path.join(d, "c_arg.profraw"), ["arg"])
    profile(Built.mbin, os.path.join(d, "m.profraw"))
    profile(Built.twice_a, os.path.join(d, "ta.profraw"))
    profile(Built.twice_b, os.path.join(d, "tb.profraw"))
    profile(Built.twice_c, os.path.join(d, "tc.profraw"))
    Built.cprof = os.path.join(d, "c.profdata")
    merge(Built.cprof, [os.path.join(d, "c.profraw")])
    Built.cprof_arg = os.path.join(d, "c_arg.profdata")
    merge(Built.cprof_arg, [os.path.join(d, "c_arg.profraw")])
    Built.mprof = os.path.join(d, "m.profdata")
    merge(Built.mprof, [os.path.join(d, "m.profraw")])
    Built.tprof = os.path.join(d, "t.profdata")
    merge(Built.tprof, [os.path.join(d, n) for n in ("ta.profraw", "tb.profraw")])
    Built.tprof_same = os.path.join(d, "t_same.profdata")
    merge(Built.tprof_same, [os.path.join(d, n) for n in ("ta.profraw", "tc.profraw")])
    # Make every source older than every binary, as after a real build.
    old = time.time() - 3600
    for name in os.listdir(src):
        os.utime(os.path.join(src, name), (old, old))


def tearDownModule():
    if Built.dir:
        shutil.rmtree(Built.dir, ignore_errors=True)


def report(*args):
    """Runs the tool; returns (status, stdout, stderr)."""
    r = run([sys.executable, "-B", TOOL] + list(args))
    return r.returncode, r.stdout, r.stderr


def function_json(spec, binary, profdata, *extra):
    status, out, err = report("function", spec, "--binary", binary, "--profdata", profdata,
                              "--no-codedb", "--json", *extra)
    try:
        data = json.loads(out)
    except ValueError:
        raise AssertionError("not JSON (status %d): %s\n%s" % (status, out, err))
    return status, data


def uncovered_outcomes(instance):
    """(line, column, outcome) for each unexercised branch outcome."""
    return sorted((b["line"], b["column"], o) for b in instance["branches"]
                  for o in b["unexercised"])


def uncovered_cases(instance):
    return sorted((c["line"], c["label"]) for c in instance["cases"] if c["taken"] == 0)


def uncovered_lines(instance):
    return [l["line"] for l in instance["lines"] if l["count"] == 0]


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class CFunctionTests(unittest.TestCase):

    def c(self, spec):
        return function_json(spec, Built.cbin, Built.cprof)

    def line(self, marker):
        return marker_line(Built.branches, marker)

    def test_if_else_with_one_side_never_taken(self):
        status, d = self.c("if_else")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(inst["count"], 1)
        self.assertEqual(uncovered_outcomes(inst), [(self.line("if"), 9, "false")])
        # llvm-cov counts the closing brace of the else with its body.
        self.assertEqual(uncovered_lines(inst), [self.line("else-body"), self.line("else-body") + 1])
        self.assertEqual(inst["cases"], [])

    def test_switch_with_a_case_never_hit_and_a_default(self):
        status, d = self.c("sw")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        cases = sorted((c["line"], c["label"], c["taken"]) for c in inst["cases"])
        self.assertEqual(cases, [(self.line("case1"), "case 1:", 1),
                                 (self.line("case2"), "case 2:", 0),
                                 (self.line("default"), "default:", 1)])
        self.assertEqual(uncovered_outcomes(inst), [])
        self.assertEqual(uncovered_lines(inst), [self.line("case2"), self.line("case2-body")])
        self.assertEqual(inst["summary"]["cases_covered"], 2)
        self.assertEqual(inst["summary"]["cases_total"], 3)

    def test_switch_without_default_reports_the_implicit_default(self):
        status, d = self.c("sw_no_default")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(uncovered_cases(inst), [(self.line("switch-nd"), "implicit default")])
        taken = sorted((c["line"], c["taken"]) for c in inst["cases"] if c["label"] != "implicit default")
        self.assertEqual(taken, [(self.line("nd-case1"), 1), (self.line("nd-case3"), 1)])

    def test_implicit_default_not_exercised_says_how_to_satisfy_it(self):
        status, out, err = report("function", "sw_no_default", "--binary", Built.cbin, "--profdata", Built.cprof,
                                  "--no-codedb")
        self.assertEqual(status, 1, out + err)
        lines = out.splitlines()
        k = [i for i, l in enumerate(lines) if "implicit default" in l and "NOT EXERCISED" in l]
        self.assertEqual(len(k), 1, out)
        self.assertEqual(lines[k[0] + 1].strip(),
                         "(control goes past the switch when no case matches: a test can pass a value no case "
                         "lists, by a cast when the cases list every enumerator; if no such value can reach it, "
                         "list it in the dossier with the reason, large-code.md section 2.1)")
        status, out, err = report("function", "sw", "--binary", Built.cbin, "--profdata", Built.cprof,
                                  "--no-codedb")
        self.assertNotIn("control goes past the switch", out)

    def test_short_circuit_right_side_never_runs(self):
        status, d = self.c("short_circuit")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        line = self.line("and")
        self.assertEqual(uncovered_outcomes(inst),
                         [(line, 9, "true"), (line, 14, "false"), (line, 14, "true")])
        right = [b for b in inst["branches"] if b["column"] == 14][0]
        self.assertEqual((right["true"], right["false"], right["text"]), (0, 0, "b"))
        self.assertEqual(uncovered_lines(inst), [self.line("and-body"), self.line("and-body") + 1])

    def test_loop_that_never_iterates(self):
        status, d = self.c("never_iterates")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(uncovered_outcomes(inst), [(self.line("for"), 21, "true")])
        self.assertIn(self.line("for-body"), uncovered_lines(inst))

    def test_folded_outcomes_are_not_required(self):
        status, d = self.c("forever")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        w = [b for b in inst["branches"] if b["line"] == self.line("while1")][0]
        self.assertTrue(w["false_folded"])
        self.assertFalse(w["true_folded"])
        self.assertEqual(w["unexercised"], [])
        line = self.line("or-folded")
        self.assertEqual(uncovered_outcomes(inst), [(line, 12, "false"), (line, 17, "false")])
        zero = [b for b in inst["branches"] if b["line"] == line and b["column"] == 17][0]
        self.assertTrue(zero["true_folded"])
        # llvm-cov counts outcomes that are not folded: while(1) true, the
        # if's two, x's two and the 0's false.
        self.assertEqual(inst["summary"]["branches_total"], 6)
        self.assertEqual(inst["summary"]["branches_covered"], 4)

    def test_function_never_called(self):
        status, d = self.c("never_called")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(inst["count"], 0)
        start = self.line("never-start")
        self.assertEqual(inst["start_line"], start)
        self.assertEqual(uncovered_lines(inst), list(range(start, start + 6)))
        self.assertEqual(uncovered_outcomes(inst),
                         [(self.line("never-if"), 9, "false"), (self.line("never-if"), 9, "true")])
        self.assertIn("never executed", d["verdict"])

    def test_macro_expanded_branch_is_placed_at_its_use(self):
        status, d = self.c("macro_branch")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(len(inst["branches"]), 1)
        b = inst["branches"][0]
        self.assertEqual(b["line"], self.line("macro-use"))
        self.assertEqual(b["unexercised"], ["false"])
        self.assertEqual(b["expansion"]["line"], self.line("macro-cond"))
        self.assertEqual(b["expansion"]["column"], 25)
        self.assertEqual(b["text"], "(x) > 0")

    def test_branches_in_an_ignored_logging_macro_are_set_aside(self):
        status, d = function_json("logged", Built.cbin, Built.cprof, "--ignore-macro", "LOGF")
        self.assertEqual(status, 0, d["verdict"])
        inst = d["instances"][0]
        # LOGF's if (gLog) and while (0) are set aside at both uses (LOUD
        # expands to LOGF). LOUD's own while (0) is not inside LOGF, so it
        # stays: folded true, false taken.
        self.assertEqual(uncovered_outcomes(inst), [])
        self.assertEqual([(b["line"], b["text"], b["true_folded"]) for b in inst["branches"]],
                         [(self.line("loud"), "0", True)])
        ignored = sorted((b["line"], b["macro"], b["text"]) for b in inst["ignored"])
        self.assertEqual(ignored, [(self.line("logf"), "LOGF", "0"), (self.line("logf"), "LOGF", "gLog"),
                                   (self.line("loud"), "LOGF", "0"), (self.line("loud"), "LOGF", "gLog")])

    def test_verdict_says_how_many_were_set_aside(self):
        status, d = function_json("logged", Built.cbin, Built.cprof, "--ignore-macro", "LOGF")
        self.assertEqual(d["verdict"], coverage_report.FULL_VERDICT
                         + " (4 set aside inside LOGF: listed under Set aside, not counted)")
        status, out, err = report("function", "logged", "--binary", Built.cbin, "--profdata", Built.cprof,
                                  "--no-codedb", "--ignore-macro", "LOGF")
        self.assertIn("(4 set aside inside LOGF", out.splitlines()[-1])
        status, d = function_json("logged", Built.cbin, Built.cprof)
        self.assertNotIn("set aside", d["verdict"])

    def test_logging_macro_branches_count_when_not_ignored(self):
        status, d = function_json("logged", Built.cbin, Built.cprof)
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(inst["ignored"], [])
        self.assertEqual(uncovered_outcomes(inst),
                         [(self.line("logf"), 5, "true"), (self.line("loud"), 5, "true")])

    def test_dlog_is_ignored_by_default(self):
        self.assertIn("DLog", coverage_report.DEFAULT_IGNORED_MACROS)

    def test_fully_covered_function(self):
        status, d = self.c("full")
        self.assertEqual(status, 0)
        self.assertEqual(d["verdict"], "every case label and every branch was exercised")
        s = d["instances"][0]["summary"]
        self.assertEqual((s["branches_covered"], s["branches_total"]), (2, 2))
        self.assertEqual(s["lines_covered"], s["lines_total"])

    def test_text_output_marks_uncovered_and_ends_with_verdict(self):
        status, out, err = report("function", "sw", "--binary", Built.cbin,
                                  "--profdata", Built.cprof, "--no-codedb")
        self.assertEqual(status, 1, err)
        lines = out.splitlines()
        body = [l for l in lines if l.lstrip().startswith(str(self.line("case2-body")) + " ")]
        self.assertEqual(len(body), 1)
        self.assertIn("<<<", body[0])
        self.assertIn("Summary: lines ", out)
        self.assertTrue(lines[-1].startswith("Verdict: "))
        self.assertIn("case 2: at line %d" % self.line("case2"), lines[-1])

    def test_file_line_spec_finds_the_enclosing_function(self):
        status, d = function_json("%s:%d" % (Built.branches, self.line("case2-body")),
                                  Built.cbin, Built.cprof)
        self.assertEqual(status, 1)
        self.assertEqual(d["instances"][0]["name"], "sw")

    def test_line_counts_agree_with_llvm_cov_show(self):
        r = run(["xcrun", "llvm-cov", "show", Built.cbin, "-instr-profile=" + Built.cprof,
                 "-use-color=false", "--", Built.branches])
        self.assertEqual(r.returncode, 0, r.stderr)
        shown = {}
        for text in r.stdout.splitlines():
            parts = text.split("|", 2)
            if len(parts) == 3 and parts[0].strip().isdigit():
                count = parts[1].strip()
                shown[int(parts[0])] = int(count) if count else None
        compared = 0
        for name in ("if_else", "sw", "sw_no_default", "short_circuit", "never_iterates", "forever",
                     "never_called", "macro_branch", "full"):
            status, d = self.c(name)
            for entry in d["instances"][0]["lines"]:
                self.assertEqual(entry["count"], shown[entry["line"]], "%s line %d" % (name, entry["line"]))
                compared += 1
        self.assertGreater(compared, 50)

    def test_unknown_function_is_incomplete(self):
        status, d = self.c("no_such_function")
        self.assertEqual(status, 3)
        self.assertEqual(d["instances"], [])
        self.assertTrue(any("not found" in p for p in d["problems"]))

    def test_source_newer_than_binary_is_incomplete(self):
        copy = os.path.join(Built.dir, "stale")
        os.makedirs(copy, exist_ok=True)
        src = os.path.join(copy, "branches.c")
        shutil.copy(Built.branches, src)
        binary = os.path.join(copy, "branches")
        r = run(["xcrun", "clang", "-fprofile-instr-generate", "-fcoverage-mapping", "-w", src, "-o", binary])
        self.assertEqual(r.returncode, 0, r.stderr)
        env = dict(os.environ, LLVM_PROFILE_FILE=os.path.join(copy, "p.profraw"))
        self.assertEqual(run([binary], env=env).returncode, 0)
        prof = os.path.join(copy, "p.profdata")
        run(["xcrun", "llvm-profdata", "merge", "-sparse", os.path.join(copy, "p.profraw"), "-o", prof])
        future = time.time() + 60
        os.utime(src, (future, future))
        status, d = function_json("full", binary, prof)
        self.assertEqual(status, 3)
        self.assertTrue(any("changed since" in p for p in d["problems"]), d["problems"])

    def test_profile_from_another_toolchain_is_an_error(self):
        bogus = os.path.join(Built.dir, "bogus.profdata")
        with open(bogus, "wb") as f:
            f.write(b"\xffnot a profile")
        status, out, err = report("function", "full", "--binary", Built.cbin, "--profdata", bogus,
                                  "--no-codedb")
        self.assertEqual(status, 2)
        self.assertIn("same toolchain", err)


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class ObjCFunctionTests(unittest.TestCase):

    def m(self, spec):
        return function_json(spec, Built.mbin, Built.mprof)

    def line(self, marker):
        return marker_line(Built.shapes, marker)

    def test_class_method(self):
        status, d = self.m("+[Shape kindFor:]")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(inst["name"], "+[Shape kindFor:]")
        self.assertEqual(uncovered_outcomes(inst), [(self.line("ternary"), 12, "false")])

    def test_block_body_is_part_of_its_method(self):
        status, d = self.m("-[Shape area:height:]")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(inst["start_line"], self.line("area-start"))
        self.assertEqual(inst["end_line"], self.line("area-end"))
        self.assertEqual(len(inst["includes"]), 1)
        self.assertIn("_block_invoke", inst["includes"][0])
        self.assertEqual(uncovered_outcomes(inst), [(self.line("block-if"), 13, "true")])
        self.assertEqual(uncovered_lines(inst), [self.line("block-zero"), self.line("block-zero") + 1])

    def test_category_method_by_its_full_name(self):
        status, d = self.m("-[Shape(Extra) extra:]")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual(inst["name"], "-[Shape(Extra) extra:]")
        self.assertEqual(uncovered_outcomes(inst), [(self.line("cat-while"), 12, "true")])

    def test_exact_name_wins_over_a_category(self):
        status, d = self.m("-[Shape extra:]")
        self.assertEqual(status, 1)
        self.assertEqual([i["name"] for i in d["instances"]], ["-[Shape extra:]"])
        self.assertEqual(d["instances"][0]["count"], 0)

    def test_category_method_found_without_the_category_name(self):
        status, d = self.m("-[Shape catOnly]")
        self.assertEqual(status, 0)
        self.assertEqual(d["instances"][0]["name"], "-[Shape(Extra) catOnly]")
        self.assertEqual(d["instances"][0]["start_line"], self.line("cat-only"))

    def test_branch_inside_an_sdk_macro_is_named_by_the_macro(self):
        # The SDK's MAX has a ?: inside; clang gives a branch with no width
        # at the macro's name, since system headers get no expansion regions.
        status, d = self.m("-[Shape(Extra) clamp:]")
        self.assertEqual(status, 1)
        b = d["instances"][0]["branches"]
        self.assertEqual([(x["line"], x["column"], x["text"], x["unexercised"]) for x in b],
                         [(self.line("sdk-max"), 12, "MAX(...)", ["true"])])

    def test_wrong_category_is_not_found(self):
        status, d = self.m("-[Shape(Nope) extra:]")
        self.assertEqual(status, 3)
        self.assertEqual(d["instances"], [])


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class SeveralBinariesTests(unittest.TestCase):

    def test_different_counts_in_two_binaries_are_reported_each_and_united(self):
        status, d = function_json("tw", Built.twice_a, Built.tprof, "--binary", Built.twice_b)
        self.assertEqual(status, 3)
        self.assertEqual(sorted(os.path.basename(i["binary"]) for i in d["instances"]),
                         ["twice_a", "twice_b"])
        line = marker_line(Built.twice, "tw-if")
        by_binary = {os.path.basename(i["binary"]): i for i in d["instances"]}
        self.assertEqual(uncovered_outcomes(by_binary["twice_a"]), [(line, 9, "false")])
        self.assertIn((line, 9, "true"), uncovered_outcomes(by_binary["twice_b"]))
        self.assertNotIn(line, [b[0] for b in d["union"]["unexercised"]])
        self.assertTrue(any("2 binaries" in p for p in d["problems"]), d["problems"])

    def test_identical_records_in_two_binaries_are_reported_once(self):
        status, d = function_json("tw", Built.twice_a, Built.tprof_same, "--binary", Built.twice_c)
        self.assertEqual(status, 1)
        self.assertEqual(len(d["instances"]), 1)
        self.assertEqual(sorted(os.path.basename(b) for b in d["instances"][0]["binaries"]),
                         ["twice_a", "twice_c"])
        self.assertTrue(any("cannot separate" in n for n in d["notes"]), d["notes"])


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class FileReportTests(unittest.TestCase):

    def test_functions_sorted_by_unexercised_branches(self):
        status, out, err = report("file", Built.branches, "--binary", Built.cbin,
                                  "--profdata", Built.cprof, "--no-codedb", "--json")
        self.assertEqual(status, 1, err)
        d = json.loads(out)
        names = [f["name"] for f in d["functions"]]
        self.assertEqual(names[0], "short_circuit")
        self.assertEqual(names[-1], "full")
        self.assertEqual(sorted(names), sorted(["if_else", "sw", "sw_no_default", "short_circuit",
                                                "never_iterates", "forever", "never_called",
                                                "macro_branch", "full", "logged", "main"]))
        keys = [f["unexercised_branches"] + f["unexercised_cases"] for f in d["functions"]]
        self.assertEqual(keys, sorted(keys, reverse=True))

    def test_text_form_has_one_row_per_function(self):
        status, out, err = report("file", Built.branches, "--binary", Built.cbin,
                                  "--profdata", Built.cprof, "--no-codedb")
        self.assertEqual(status, 1, err)
        self.assertIn("short_circuit", out.splitlines()[1])


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class RunDirectoryTests(unittest.TestCase):
    """A run directory as coverage_tests.sh lays it out."""

    @classmethod
    def setUpClass(cls):
        cls.run_dir = os.path.join(Built.dir, "run")
        os.makedirs(os.path.join(cls.run_dir, "classes"), exist_ok=True)
        st = os.stat(Built.cbin)
        with open(os.path.join(cls.run_dir, "binaries.txt"), "w") as f:
            f.write("%s\t%d\t%d\n" % (Built.cbin, st.st_size, int(st.st_mtime)))
        shutil.copy(Built.cprof, os.path.join(cls.run_dir, "coverage.profdata"))
        shutil.copy(Built.cprof, os.path.join(cls.run_dir, "classes", "PlainTests.profdata"))
        shutil.copy(Built.cprof_arg, os.path.join(cls.run_dir, "classes", "ArgTests.profdata"))
        with open(os.path.join(cls.run_dir, "per_class_route.txt"), "w") as f:
            f.write("per-class\n")

    def variant(self, name, route, launch=False):
        """A copy of the run directory whose per-class profiles came from
        route ("observer", "per-class" or None for not recorded)."""
        other = os.path.join(Built.dir, name)
        if os.path.isdir(other):
            shutil.rmtree(other)
        shutil.copytree(self.run_dir, other)
        os.unlink(os.path.join(other, "per_class_route.txt"))
        if route:
            with open(os.path.join(other, "per_class_route.txt"), "w") as f:
                f.write(route + "\n")
        if launch:
            shutil.copy(Built.cprof, os.path.join(other, "classes", "_launch.profdata"))
        return other

    def test_tests_for_on_an_observer_run_is_approximate(self):
        run_dir = self.variant("run_observer", "observer")
        status, out, err = report("tests-for", "never_called", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 3, err)
        d = json.loads(out)
        self.assertEqual(d["may_execute"], ["ArgTests"])
        self.assertNotIn("executing", d)
        self.assertFalse(d["exact"])
        self.assertIn(coverage_report.OBSERVER_CAVEAT, d["problems"])
        status, out, err = report("tests-for", "never_called", "--run", run_dir, "--no-codedb")
        self.assertEqual(status, 3)
        self.assertIn("per-class attribution from an observer run is approximate: work a class leaves running is "
                      "counted for the class that follows, and work the app's launch leaves running is counted for "
                      "whichever class is running when it happens; use --per-class for a per-class verdict", out)
        self.assertIn("  may execute ArgTests:", out)
        self.assertNotIn("  executes ", out)

    def test_tests_for_without_a_recorded_route_is_approximate(self):
        run_dir = self.variant("run_noroute", None)
        status, out, err = report("tests-for", "never_called", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 3, err)
        self.assertIn("may_execute", json.loads(out))

    def test_tests_for_on_a_per_class_run_is_exact(self):
        status, out, err = report("tests-for", "never_called", "--run", self.run_dir, "--no-codedb")
        self.assertEqual(status, 0, err)
        self.assertIn("  executes ArgTests:", out)
        self.assertNotIn("approximate", out)

    def test_launch_is_not_counted_as_a_class(self):
        run_dir = self.variant("run_launch", "per-class", launch=True)
        status, out, err = report("tests-for", Built.branches, "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)
        d = json.loads(out)
        self.assertEqual(d["executing"], ["ArgTests", "PlainTests"])
        self.assertNotIn("_launch", d["classes"])
        self.assertTrue(d["launch"]["executed"])
        status, out, err = report("tests-for", Built.branches, "--run", run_dir, "--no-codedb")
        self.assertIn("is executed by 2 of 2 test classes", out)
        self.assertIn("App launch, before the first class (_launch, not a class): executed", out)

    def test_function_from_a_run_directory(self):
        status, out, err = report("function", "full", "--run", self.run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)

    def test_run_whose_tests_failed_is_incomplete(self):
        run_dir = self.variant("run_failed", "per-class")
        with open(os.path.join(run_dir, "status.txt"), "w") as f:
            f.write("65\n")
        status, out, err = report("function", "full", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 3, err)
        problems = json.loads(out)["problems"]
        self.assertEqual(problems, ["the run's tests did not all pass (coverage_tests.sh exited with status 65): "
                                    "its coverage is that of a failing net"])
        status, out, err = report("tests-for", "never_called", "--run", run_dir, "--no-codedb")
        self.assertEqual(status, 3, err)
        self.assertIn("did not all pass", out)

    def test_run_that_never_finished_is_incomplete(self):
        run_dir = self.variant("run_started", "per-class")
        with open(os.path.join(run_dir, "status.txt"), "w") as f:
            f.write("started\n")
        status, out, err = report("function", "full", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 3, err)
        self.assertEqual(json.loads(out)["problems"],
                         ["the run's tests did not all pass (coverage_tests.sh exited with status started): its "
                          "coverage is that of a failing net"])

    def test_run_whose_tests_passed(self):
        run_dir = self.variant("run_passed", "per-class")
        with open(os.path.join(run_dir, "status.txt"), "w") as f:
            f.write("0\n")
        status, out, err = report("function", "full", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)
        self.assertEqual(json.loads(out)["notes"], [])

    def test_run_without_a_recorded_status_is_noted(self):
        status, out, err = report("function", "full", "--run", self.run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)
        self.assertTrue(any("does not record whether its tests passed" in n for n in json.loads(out)["notes"]))

    def test_changed_binary_is_refused(self):
        other = os.path.join(Built.dir, "run2")
        shutil.copytree(self.run_dir, other)
        with open(os.path.join(other, "binaries.txt"), "w") as f:
            f.write("%s\t1\t1\n" % Built.cbin)
        status, out, err = report("function", "full", "--run", other, "--no-codedb", "--json")
        self.assertEqual(status, 3)
        self.assertTrue(any("changed since" in p for p in json.loads(out)["problems"]))

    def test_tests_for_function(self):
        status, out, err = report("tests-for", "never_called", "--run", self.run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)
        d = json.loads(out)
        self.assertEqual(d["executing"], ["ArgTests"])
        self.assertEqual(d["not_executing"], ["PlainTests"])
        arg = d["classes"]["ArgTests"]
        line = marker_line(Built.branches, "never-if")
        self.assertEqual(arg["exercised_outcomes"], [[line, 9, "true"]])

    def test_tests_for_file(self):
        status, out, err = report("tests-for", Built.branches, "--run", self.run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)
        self.assertEqual(json.loads(out)["executing"], ["ArgTests", "PlainTests"])

    def test_tests_for_without_class_profiles(self):
        other = os.path.join(Built.dir, "run3")
        shutil.copytree(self.run_dir, other)
        shutil.rmtree(os.path.join(other, "classes"))
        status, out, err = report("tests-for", "full", "--run", other, "--no-codedb")
        self.assertEqual(status, 2)
        self.assertIn("--per-class", err)


def cases_of(instance):
    return sorted((c["line"], c["label"], c["taken"]) for c in instance["cases"])


def branch_counts(instance):
    return sorted((b["line"], b["column"], b["text"], b["true"], b["false"]) for b in instance["branches"])


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class SwitchConditionTests(unittest.TestCase):
    """The implicit default is the branch clang attaches to a switch with no
    default label, whose extent is the whole condition; a branch on an
    operand of ?:, && or || in the condition keeps both outcomes."""

    def s(self, spec):
        status, d = function_json(spec, Built.swbin, Built.swprof)
        return status, d["instances"][0]

    def line(self, marker):
        return marker_line(Built.switches, marker)

    def implicit(self, inst):
        return [c for c in inst["cases"] if c["label"] == "implicit default"]

    def test_ternary_condition_with_a_default_is_not_an_implicit_default(self):
        # The reviewer's sw5/a.c: y is never true.
        status, inst = self.s("d_tern")
        self.assertEqual(status, 1)
        self.assertEqual(self.implicit(inst), [])
        line = self.line("d-tern")
        self.assertEqual(branch_counts(inst), [(line, 13, "y", 0, 2)])
        self.assertEqual(uncovered_outcomes(inst), [(line, 13, "true")])

    def test_and_condition_with_a_default_keeps_both_operands(self):
        status, inst = self.s("d_and")
        self.assertEqual(status, 1)
        self.assertEqual(self.implicit(inst), [])
        line = self.line("d-and")
        self.assertEqual(branch_counts(inst), [(line, 13, "a", 0, 1), (line, 18, "b", 0, 0)])

    def test_or_condition_with_a_default_keeps_both_operands(self):
        status, inst = self.s("d_or")
        self.assertEqual(self.implicit(inst), [])
        line = self.line("d-or")
        self.assertEqual(branch_counts(inst), [(line, 13, "a", 1, 0), (line, 18, "b", 0, 0)])

    def test_plain_condition_with_a_default_has_no_implicit_default(self):
        status, inst = self.s("d_plain")
        self.assertEqual(self.implicit(inst), [])
        self.assertEqual(inst["branches"], [])

    def test_multiline_ternary_with_a_default(self):
        status, inst = self.s("d_multiline_tern")
        self.assertEqual(self.implicit(inst), [])
        line = self.line("d-mlt-cond")
        self.assertEqual(branch_counts(inst), [(line, 9, "y", 1, 0)])

    def test_plain_condition_without_default(self):
        status, inst = self.s("nd_plain")
        self.assertEqual(self.implicit(inst), [{"line": self.line("nd-plain"), "column": 5,
                                                "label": "implicit default", "taken": 1, "expansion": None}])
        self.assertEqual(inst["branches"], [])

    def test_ternary_condition_without_default(self):
        status, inst = self.s("nd_tern")
        self.assertEqual(status, 1)
        line = self.line("nd-tern")
        self.assertEqual([(c["line"], c["taken"]) for c in self.implicit(inst)], [(line, 0)])
        self.assertEqual(branch_counts(inst), [(line, 13, "y", 1, 0)])

    def test_and_condition_without_default(self):
        # clang instruments no condition that is a && or || expression, so
        # the export has no implicit-default branch for this switch: the
        # tool says so instead of passing over it.
        status, inst = self.s("nd_and")
        line = self.line("nd-and")
        self.assertEqual(self.implicit(inst), [])
        self.assertEqual(branch_counts(inst), [(line, 13, "a", 1, 1), (line, 18, "b", 1, 0)])
        self.assertEqual([(u["line"], u["construct"]) for u in inst["not_determinable"]],
                         [(line, "implicit default")])

    def test_or_condition_without_default(self):
        status, inst = self.s("nd_or")
        line = self.line("nd-or")
        self.assertEqual(self.implicit(inst), [])
        self.assertEqual(branch_counts(inst), [(line, 13, "a", 0, 1), (line, 18, "b", 0, 1)])
        self.assertEqual([(u["line"], u["construct"]) for u in inst["not_determinable"]],
                         [(line, "implicit default")])

    def test_and_condition_with_a_default_is_determinable(self):
        status, inst = self.s("d_and")
        self.assertEqual(inst["not_determinable"], [])

    def test_multiline_switch_implicit_default_is_labeled_at_the_switch(self):
        status, inst = self.s("nd_multiline")
        self.assertEqual(status, 1)
        self.assertEqual([(c["line"], c["taken"]) for c in self.implicit(inst)],
                         [(self.line("nd-ml-switch"), 0)])
        self.assertEqual(inst["branches"], [])

    def test_multiline_ternary_without_default(self):
        status, inst = self.s("nd_multiline_tern")
        self.assertEqual([(c["line"], c["taken"]) for c in self.implicit(inst)],
                         [(self.line("nd-mlt-switch"), 1)])
        self.assertEqual(branch_counts(inst), [(self.line("nd-mlt-cond"), 9, "y", 2, 0)])


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class BlockAndTryTests(unittest.TestCase):

    def b(self, spec, *extra):
        return function_json(spec, Built.bbin, Built.bprof, *extra)

    def line(self, marker):
        return marker_line(Built.blocks, marker)

    def regions(self, d):
        return [r["description"] for r in d["instances"][0]["unexercised_regions"]]

    def test_block_never_invoked_without_branches(self):
        status, d = self.b("b_never_plain")
        self.assertEqual(status, 1, d["verdict"])
        self.assertEqual(self.regions(d), ["block at line %d never invoked" % self.line("bnp")])
        self.assertIn("block at line %d never invoked" % self.line("bnp"), d["verdict"])

    def test_block_never_invoked_with_branches(self):
        status, d = self.b("b_never_branch")
        self.assertEqual(status, 1)
        self.assertEqual(self.regions(d), ["block at line %d never invoked" % self.line("bnb")])
        self.assertEqual(uncovered_outcomes(d["instances"][0]),
                         [(self.line("bnb-if"), 13, "false"), (self.line("bnb-if"), 13, "true")])

    def test_block_invoked(self):
        status, d = self.b("b_invoked")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(d["verdict"], coverage_report.FULL_VERDICT)

    def test_nested_block_never_invoked(self):
        status, d = self.b("b_nested")
        self.assertEqual(status, 1)
        self.assertEqual(self.regions(d), ["block at line %d never invoked" % self.line("bn-inner")])

    def test_block_passed_to_a_function_that_never_calls_it(self):
        status, d = self.b("b_passed")
        self.assertEqual(status, 1)
        self.assertEqual(self.regions(d), ["block at line %d never invoked" % self.line("bp")])

    def test_catch_body_is_not_determinable(self):
        status, d = self.b("t_try_plain")
        self.assertEqual(status, 3, d["verdict"])
        nd = d["instances"][0]["not_determinable"]
        self.assertEqual([(u["line"], u["construct"]) for u in nd], [(self.line("catch-plain"), "@catch")])
        self.assertIn("clang does not record whether a @catch body ran", nd[0]["reason"])
        self.assertNotEqual(d["verdict"], coverage_report.FULL_VERDICT)

    def test_accept_uncheckable_lists_them_and_exits_0(self):
        status, d = self.b("t_try_plain", "--accept-uncheckable")
        self.assertEqual(status, 0)
        self.assertTrue(d["verdict"].startswith("every checkable case label and branch was exercised; "
                                                "1 construct could not be checked"), d["verdict"])
        self.assertIn("line %d" % self.line("catch-plain"), d["verdict"])

    def test_accept_uncheckable_does_not_hide_a_miss(self):
        status, d = self.b("t_try", "--accept-uncheckable")
        self.assertEqual(status, 1)

    def test_branch_in_a_catch_body_has_its_false_outcome_not_determinable(self):
        status, d = self.b("t_try")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        b = [x for x in inst["branches"] if x["line"] == self.line("catch-if")][0]
        # clang says false 1: the catch body never ran.
        self.assertEqual((b["true"], b["false"], b["false_uncheckable"]), (0, 1, True))
        self.assertIn((self.line("catch-if"), "branch in @try/@catch"),
                      [(u["line"], u["construct"]) for u in inst["not_determinable"]])
        self.assertEqual(inst["summary"]["branches_covered"], 0)

    def test_brackets_in_an_inactive_preprocessor_block_are_not_code(self):
        # The } inside #if 0 would end the @try body early for a scan of the
        # text, losing the @catch; clang's skipped region says it is not
        # code. The catch-body branch was true once and never false, though
        # clang's subtraction says false 1.
        status, d = self.b("t_try_ifdef")
        self.assertEqual(status, 3, d["verdict"])
        nd = d["instances"][0]["not_determinable"]
        self.assertEqual([(u["line"], u["construct"]) for u in nd],
                         [(self.line("catch-ifdef"), "@catch"), (self.line("catch-ifdef-if"), "branch in @try/@catch")])

    def test_not_determinable_outcome_is_not_counted_as_missed(self):
        # The reviewer's p_finally_only: true never happened, false is not
        # determinable inside @try. One outcome counted, none covered.
        status, d = self.b("t_finally_only")
        self.assertEqual(status, 1)
        s = d["instances"][0]["summary"]
        self.assertEqual((s["branches_covered"], s["branches_total"], s["not_determinable"]), (0, 1, 1))
        status, out, err = report("function", "t_finally_only", "--binary", Built.bbin, "--profdata", Built.bprof,
                                  "--no-codedb")
        self.assertIn("branches 0/1 (outcomes)", out)
        self.assertIn("NOT EXERCISED: true", out)

    def test_tests_for_does_not_count_a_not_determinable_outcome(self):
        run_dir = os.path.join(Built.dir, "run_blocks")
        os.makedirs(os.path.join(run_dir, "classes"), exist_ok=True)
        st = os.stat(Built.bbin)
        with open(os.path.join(run_dir, "binaries.txt"), "w") as f:
            f.write("%s\t%d\t%d\n" % (Built.bbin, st.st_size, int(st.st_mtime)))
        shutil.copy(Built.bprof, os.path.join(run_dir, "coverage.profdata"))
        shutil.copy(Built.bprof, os.path.join(run_dir, "classes", "BlockTests.profdata"))
        with open(os.path.join(run_dir, "per_class_route.txt"), "w") as f:
            f.write("per-class\n")
        with open(os.path.join(run_dir, "status.txt"), "w") as f:
            f.write("0\n")
        status, out, err = report("tests-for", "t_finally_only", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 0, err)
        self.assertEqual(json.loads(out)["classes"]["BlockTests"]["exercised_outcomes"], [])

    def test_union_does_not_count_a_not_determinable_outcome_as_exercised(self):
        class Fake:
            branches = [{"line": 3, "column": 5, "true_folded": False, "false_folded": False,
                         "unexercised": [], "false_uncheckable": True}]
            derived, cases, regions, uncheckable, claimed = [], [], [], [], set()

            def executed(self):
                return True

            def unexercised_regions(self):
                return []
        u = coverage_report.union_of([Fake(), Fake()])
        self.assertEqual((u["branches_covered"], u["branches_total"]), (1, 1))

    def test_text_output_lists_not_determinable(self):
        status, out, err = report("function", "t_try_plain", "--binary", Built.bbin, "--profdata", Built.bprof,
                                  "--no-codedb")
        self.assertEqual(status, 3, err)
        self.assertIn("Not determinable (1):", out)
        self.assertIn("blocks.m:%d" % self.line("catch-plain"), out)
        self.assertTrue(out.splitlines()[-1].startswith("Verdict: incomplete: "))


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class LambdaTests(unittest.TestCase):

    def l(self, spec, *extra):
        return function_json(spec, Built.lbin, Built.lprof, *extra)

    def line(self, marker):
        return marker_line(Built.lambdas, marker)

    def test_lambda_never_called_has_no_record_and_is_not_determinable(self):
        status, d = self.l("l_mixed")
        self.assertEqual(status, 3, d["verdict"])
        nd = d["instances"][0]["not_determinable"]
        self.assertEqual([(u["line"], u["construct"]) for u in nd], [(self.line("l-never"), "lambda")])
        self.assertIn("no coverage record", nd[0]["reason"])

    def test_lambda_called(self):
        status, d = self.l("l_all_called")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(d["instances"][0]["not_determinable"], [])
        self.assertEqual(len(d["instances"][0]["includes"]), 1)

    def test_cxx_catch_never_taken_is_a_region_never_run(self):
        # C++ catch bodies get their own regions, so no special treatment.
        status, d = self.l("l_try")
        self.assertEqual(status, 1)
        inst = d["instances"][0]
        self.assertEqual([r["line"] for r in inst["unexercised_regions"]], [self.line("cxx-catch")])
        self.assertEqual(inst["not_determinable"], [])

    def test_lambda_detection_is_conservative(self):
        text = "x = a[i] {\n[obj msg] {\nauto f = [=](int y) mutable -> int { };\nauto g = [&x, y] { };\n"
        starts = [0] + [i + 1 for i, ch in enumerate(text) if ch == "\n"]
        found = coverage_report.find_lambdas(text, starts, 0, len(text))
        self.assertEqual([l for l, _ in found], [3, 4])


@unittest.skipIf(SWIFT_MISSING, "toolchain missing: %s" % SWIFT_MISSING)
class SwiftTests(unittest.TestCase):
    """Swift has no branch regions: outcomes are derived from region counts
    where both counts exist, and the rest is listed as not determinable.
    The validation table: the function, what its region counts show, what
    the tool reports."""

    def sw(self, name, *extra):
        status, d = function_json("%s:%d" % (Built.swift, self.def_line(name)), Built.sbin, Built.sprof, *extra)
        self.assertEqual(len(d["instances"]), 1, d)
        return status, d, d["instances"][0]

    def def_line(self, name):
        with open(Built.swift) as f:
            for n, text in enumerate(f, 1):
                if text.startswith("func %s(" % name):
                    return n + 1
        raise AssertionError(name)

    def line(self, marker):
        return marker_line(Built.swift, marker)

    def derived(self, inst):
        return [(x["line"], x["construct"], x["true"], x["false"], x["unexercised"])
                for x in inst["derived_conditions"]]

    def nd(self, inst):
        return [(u["line"], u["construct"]) for u in inst["not_determinable"]]

    def regions(self, inst):
        return [r["description"] for r in inst["unexercised_regions"]]

    def test_if_else_with_the_else_never_taken(self):
        # Regions: body 1, else body 0.
        status, d, inst = self.sw("ifElse")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("s-ifelse"), "if", 1, 0, ["false"])])

    def test_if_without_else_never_false(self):
        # Regions: condition 2, body 2: the condition was never false.
        status, d, inst = self.sw("ifNoElse")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("s-ifnoelse"), "if", 2, 0, ["false"])])
        self.assertIn("never false (derived from region counts)", d["verdict"])

    def test_if_without_else_both_outcomes(self):
        status, d, inst = self.sw("ifBoth")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(self.derived(inst), [(self.line("s-ifboth"), "if", 1, 1, [])])
        self.assertNotEqual(d["verdict"], coverage_report.FULL_VERDICT)
        self.assertTrue(d["verdict"].startswith(coverage_report.CHECKABLE_VERDICT))

    def test_guard_that_never_failed(self):
        # Regions: guard body 0, code after 1.
        status, d, inst = self.sw("guardNeverFails")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("s-guard"), "guard", 1, 0, ["false"])])
        self.assertIn("never failed", d["verdict"])

    def test_switch_with_every_case_hit(self):
        status, d, inst = self.sw("switchAll")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual([c["taken"] for c in inst["cases"]], [1, 1, 1])

    def test_switch_with_a_case_never_hit(self):
        status, d, inst = self.sw("switchSome")
        self.assertEqual(status, 1)
        self.assertEqual(uncovered_cases(inst), [(self.line("s-case2"), "case 2:")])

    def test_multi_pattern_case_and_where_clause_are_not_determinable(self):
        status, d, inst = self.sw("switchWhere")
        self.assertEqual(status, 3, d["verdict"])
        self.assertEqual(self.nd(inst), [(self.line("s-multi"), "case"), (self.line("s-where"), "case where")])

    def test_loop_that_never_iterates(self):
        status, d, inst = self.sw("loopNever")
        self.assertEqual(status, 1)
        self.assertEqual(self.regions(inst), ["region at line %d col 20" % (self.line("s-for-body") - 1)])

    def test_while_counts_derive_both_outcomes(self):
        # Regions: condition 5 (evaluations), body 3: true 3, false 2.
        status, d, inst = self.sw("whileCounts")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(self.derived(inst), [(self.line("s-while"), "while", 3, 2, [])])

    def test_while_left_only_by_break_is_never_false(self):
        status, d, inst = self.sw("whileBreak")
        self.assertEqual(status, 1)
        self.assertIn((self.line("s-while-break"), "while", 6, 0, ["false"]), self.derived(inst))

    def test_repeat_while(self):
        # Regions: body 3, condition 3, entered once: true 2, false 1.
        status, d, inst = self.sw("repeatOnce")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(self.derived(inst), [(self.line("s-repeat"), "repeat", 2, 1, [])])

    def test_and_with_the_right_side_never_evaluated(self):
        # Regions: condition 1, body 0; the right side's implicit closure 0.
        status, d, inst = self.sw("andRightNever")
        self.assertEqual(status, 1)
        line = self.line("s-and")
        self.assertEqual(self.derived(inst), [(line, "if", 0, 1, ["true"])])
        self.assertEqual(self.nd(inst), [(line, "&&")])
        self.assertEqual(self.regions(inst), ["implicit closure at line %d (an @autoclosure argument, or the "
                                              "right side of &&, || or ??) never evaluated" % line])

    def test_closure_never_called(self):
        status, d, inst = self.sw("closureNever")
        self.assertEqual(status, 1)
        self.assertEqual(self.regions(inst), ["closure at line %d never called" % self.line("s-closure")])

    def test_defer_has_no_condition(self):
        status, d, inst = self.sw("deferred")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual((self.derived(inst), self.nd(inst)), ([], []))

    def test_catch_never_taken(self):
        status, d, inst = self.sw("catchNever")
        self.assertEqual(status, 1)
        self.assertEqual(self.regions(inst), ["region at line %d col 13" % self.line("s-catch")])

    def test_early_return_never_taken(self):
        status, d, inst = self.sw("earlyReturn")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("s-early"), "if", 0, 1, ["true"])])

    def test_optional_chain_nil_coalescing_and_try_question_are_not_determinable(self):
        status, d, inst = self.sw("optionals")
        self.assertEqual(status, 1)
        opt, tryq = self.line("s-opt"), self.line("s-tryq")
        self.assertEqual(self.nd(inst), [(opt, "?."), (opt, "??"), (tryq, "try?"), (tryq, "??")])

    def test_multi_clause_condition(self):
        status, d, inst = self.sw("multiClause")
        self.assertEqual(status, 3, d["verdict"])
        self.assertEqual(self.nd(inst), [(self.line("s-multiclause"), "if")])
        self.assertIn("2 clauses", inst["not_determinable"][0]["reason"])

    def test_three_never_false_conditions_are_not_the_full_verdict(self):
        # The reviewer's case: every region ran, yet conditions were never
        # false. No Swift function ever gets the full verdict.
        for name in ("ifNoElse", "straight", "ifBoth", "switchAll"):
            status, d, inst = self.sw(name)
            self.assertNotEqual(d["verdict"], coverage_report.FULL_VERDICT, name)
            self.assertIn("swift_limit", inst)

    def test_straight_line_function(self):
        status, d, inst = self.sw("straight")
        self.assertEqual(status, 0)
        self.assertEqual(d["verdict"], coverage_report.CHECKABLE_VERDICT + "; 0 constructs could not be checked")

    def test_text_output_states_the_limit(self):
        status, out, err = report("function", "%s:%d" % (Built.swift, self.def_line("straight")), "--binary",
                                  Built.sbin, "--profdata", Built.sprof, "--no-codedb")
        self.assertEqual(status, 0, err)
        self.assertIn("Swift limit: Swift's coverage data has no branch regions", out)

    def test_accept_uncheckable(self):
        status, d, inst = self.sw("multiClause", "--accept-uncheckable")
        self.assertEqual(status, 0)
        self.assertIn("1 construct could not be checked", d["verdict"])


class SwiftFixture:
    """Helpers for a compiled Swift fixture: SOURCE, BIN and PROF name
    attributes of Built."""
    SOURCE = BIN = PROF = None

    def src(self):
        return getattr(Built, self.SOURCE)

    def sw(self, name, *extra):
        status, d = function_json("%s:%d" % (self.src(), self.def_line(name)), getattr(Built, self.BIN),
                                  getattr(Built, self.PROF), *extra)
        self.assertEqual(len(d["instances"]), 1, d)
        return status, d, d["instances"][0]

    def text(self, name, *extra):
        return report("function", "%s:%d" % (self.src(), self.def_line(name)), "--binary",
                      getattr(Built, self.BIN), "--profdata", getattr(Built, self.PROF), "--no-codedb", *extra)

    def def_line(self, name):
        with open(self.src()) as f:
            for n, text in enumerate(f, 1):
                if text.startswith("func %s(" % name):
                    return n + 1
        raise AssertionError(name)

    def line(self, marker):
        return marker_line(self.src(), marker)

    def line_of(self, needle):
        with open(self.src()) as f:
            for n, text in enumerate(f, 1):
                if needle in text:
                    return n
        raise AssertionError(needle)

    def derived(self, inst):
        return [(x["line"], x["construct"], x["true"], x["false"], x["unexercised"])
                for x in inst["derived_conditions"]]

    def nd(self, inst):
        return [(u["line"], u["construct"]) for u in inst["not_determinable"]]

    def nd_at(self, inst):
        return [(u["line"], u["column"], u["construct"]) for u in inst["not_determinable"]]

    def regions(self, inst):
        return [r["description"] for r in inst["unexercised_regions"]]


@unittest.skipIf(SWIFT_MISSING, "toolchain missing: %s" % SWIFT_MISSING)
class SwiftElseIfTests(SwiftFixture, unittest.TestCase):
    """Swift emits no region for an else that leads to else if let, else if
    var or else if case, nor at such a condition: the false count of the if
    before it is derived along the chain (the next condition's count, the
    final else's count, or evaluations minus the then count when the
    condition has no try), never from an enclosing region."""
    SOURCE, BIN, PROF = "elseif", "ebin", "eprof"

    def test_else_if_let_outer_never_false(self):
        # The reviewer's aElseIfLet: x > -100 is always true; the enclosing
        # region's count (2) is not the false count.
        status, d, inst = self.sw("elseIfLet")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("ei-let"), "if", 2, 0, ["false"]),
                                              (self.line("ei-let-nested"), "if", 0, 0, ["true", "false"])])

    def test_else_if_var(self):
        status, d, inst = self.sw("elseIfVar")
        self.assertEqual(status, 1)
        line = self.line("ei-var")
        self.assertEqual(self.derived(inst), [(line, "if", 1, 0, ["false"]),
                                              (line + 2, "if", 0, 0, ["true", "false"])])

    def test_else_if_case(self):
        status, d, inst = self.sw("elseIfCase")
        self.assertEqual(status, 1)
        line = self.line("ei-case")
        self.assertEqual(self.derived(inst), [(line, "if", 1, 0, ["false"]),
                                              (line, "if", 0, 0, ["true", "false"])])

    def test_else_if_let_with_a_final_else(self):
        status, d, inst = self.sw("elseIfLetElse")
        self.assertEqual(status, 0, d["verdict"])
        line = self.line("ei-let-else")
        self.assertEqual(self.derived(inst), [(line, "if", 1, 2, []), (line, "if", 1, 1, [])])

    def test_chain_of_pattern_conditions_without_a_final_else(self):
        status, d, inst = self.sw("chainNoElse")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("ch-1"), "if", 1, 2, []),
                                              (self.line("ch-2"), "if", 1, 1, []),
                                              (self.line("ch-3"), "if", 1, 0, ["false"])])

    def test_chain_ending_in_a_boolean_condition(self):
        status, d, inst = self.sw("chainBoolLast")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("cb-1"), "if", 1, 3, []),
                                              (self.line("cb-2"), "if", 1, 2, []),
                                              (self.line("cb-3"), "if", 1, 1, []),
                                              (self.line("cb-4"), "if", 1, 0, ["false"])])

    def test_then_body_that_throws(self):
        status, d, inst = self.sw("thenThrows")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("tt-1"), "if", 1, 1, []),
                                              (self.line("tt-2"), "if", 1, 0, ["false"])])

    def test_condition_with_try_before_an_else_if_let_is_not_determinable(self):
        # A throw in the condition is neither outcome, so evaluations minus
        # the then count is not the false count, and nothing else gives it.
        status, d, inst = self.sw("headTry")
        self.assertEqual(self.derived(inst), [])
        self.assertEqual(self.nd(inst), [(self.line("ht-1"), "if"), (self.line("ht-2"), "if")])
        self.assertNotEqual(status, 0)

    def test_several_clauses_mixing_boolean_and_pattern(self):
        status, d, inst = self.sw("mixedClauses")
        self.assertEqual(status, 3, d["verdict"])
        self.assertEqual(self.derived(inst), [(self.line("mc-1"), "if", 1, 2, []),
                                              (self.line("mc-2"), "if", 1, 1, [])])
        self.assertEqual(self.nd(inst), [(self.line("mc-1"), "if"), (self.line("mc-2"), "if")])

    def test_pattern_condition_first(self):
        status, d, inst = self.sw("patternFirst")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("pf-1"), "if", 1, 1, []),
                                              (self.line("pf-2"), "if", 1, 0, ["false"])])

    def test_mixed_with_a_plain_boolean_else_if(self):
        status, d, inst = self.sw("mixedBool")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("mb-1"), "if", 1, 2, []),
                                              (self.line("mb-2"), "if", 0, 2, ["true"]),
                                              (self.line("mb-3"), "if", 1, 1, [])])

    def test_inside_a_closure(self):
        status, d, inst = self.sw("inClosure")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("ic-1"), "if", 1, 1, []),
                                              (self.line("ic-2"), "if", 1, 0, ["false"])])

    def test_inside_a_guard_else(self):
        status, d, inst = self.sw("inGuardElse")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("ig-guard"), "guard", 1, 2, []),
                                              (self.line("ig-1"), "if", 1, 1, []),
                                              (self.line("ig-2"), "if", 1, 0, ["false"])])

    def test_then_body_that_does_not_exit(self):
        status, d, inst = self.sw("noExitThen")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("ne-1"), "if", 1, 1, []),
                                              (self.line("ne-2"), "if", 1, 0, ["false"])])

    def test_empty_bodies(self):
        status, d, inst = self.sw("emptyBodies")
        line = self.line("empty")
        self.assertEqual(self.derived(inst), [(line, "if", 1, 1, []), (line, "if", 1, 0, ["false"])])

    def test_if_with_try_in_its_condition_and_no_else_is_not_determinable(self):
        # The reviewer's aIfTry: one call threw, one was true; the condition
        # region's count minus the body's (1) is not a false count.
        status, d, inst = self.sw("ifTry")
        self.assertEqual(self.derived(inst), [])
        self.assertEqual(self.nd(inst), [(self.line("if-try"), "if")])

    def test_guard_with_try_uses_the_region_after_it(self):
        # One call threw in the condition, one failed: it never passed.
        status, d, inst = self.sw("guardTry")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("guard-try"), "guard", 0, 1, ["true"])])

    def test_guard_that_always_failed(self):
        status, d, inst = self.sw("guardAlwaysFails")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("guard-fails"), "guard", 0, 1, ["true"])])
        self.assertIn("never passed", d["verdict"])

    def test_guard_last_in_its_block(self):
        status, d, inst = self.sw("guardLast")
        self.assertEqual(status, 1)
        line = self.line("guard-last")
        self.assertEqual(self.derived(inst), [(line - 1, "if", 1, 0, ["false"]), (line, "guard", 0, 1, ["true"])])

    def test_while_with_try_in_its_condition_is_not_determinable(self):
        status, d, inst = self.sw("whileTry")
        self.assertEqual(self.derived(inst), [])
        self.assertEqual(self.nd(inst), [(self.line("while-try"), "while")])

    def test_repeat_with_try_in_its_condition_is_not_determinable(self):
        status, d, inst = self.sw("repeatTry")
        self.assertEqual(self.derived(inst), [])
        self.assertEqual(self.nd(inst), [(self.line("repeat-try") - 2, "repeat")])

    def test_condition_with_try_never_reached_has_neither_outcome(self):
        # With a try the false count is at most the times reached less the
        # body's count; that is 0 here, so it is known.
        status, d, inst = self.sw("nestedTryNeverReached")
        line = self.line("ntn")
        self.assertEqual(self.derived(inst), [(line, "if", 1, 0, ["false"]), (line, "if", 0, 0, ["true", "false"])])

    def test_while_with_try_whose_evaluations_were_all_true(self):
        status, d, inst = self.sw("whileTryAlwaysTrue")
        self.assertEqual(self.derived(inst), [(self.line("wtat"), "while", 2, 0, ["false"]),
                                              (self.line("wtat-if"), "if", 1, 1, [])])

    def test_repeat_whose_body_can_throw_is_not_determinable(self):
        # The region at the condition counts the iteration that threw as an
        # evaluation, so its count less the true count is too high.
        for name, marker in (("repeatThrowInIf", "rp-throw"), ("repeatTryLast", "rp-trylast"),
                             ("repeatTryMid", "rp-trymid"), ("repeatDoTry", "rp-do")):
            status, d, inst = self.sw(name)
            self.assertEqual([x for x in self.derived(inst) if x[1] == "repeat"], [], name)
            self.assertIn((self.line(marker), "repeat"), self.nd(inst), name)

    def test_repeat_with_a_throwing_closure_in_its_body_is_derived(self):
        status, d, inst = self.sw("repeatThrowingClosure")
        self.assertEqual(self.derived(inst), [(self.line("rp-closure"), "repeat", 2, 1, [])])

    def test_repeat_left_by_break(self):
        status, d, inst = self.sw("repeatBreak")
        line = self.line("rp-break")
        self.assertIn((line, "repeat", 1, 0, ["false"]), self.derived(inst))

    def test_condition_with_try_and_an_else(self):
        # One call true, one false, one threw: the else body's count is the
        # false count whatever threw.
        status, d, inst = self.sw("tryWithElse")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(self.derived(inst), [(self.line("twe"), "if", 1, 1, [])])


class SyntheticChainTests(unittest.TestCase):
    """_swift_if_chain on region lists made by hand, for what the compiler
    does not produce on demand."""

    def instance(self, source, regions, count=5):
        d = tempfile.mkdtemp(prefix="coverage_report_chain.")
        self.addCleanup(shutil.rmtree, d, True)
        path = os.path.join(d, "f.swift")
        with open(path, "w") as f:
            f.write(source)
        record = {"name": "f", "count": count, "filenames": [path], "branches": [],
                  "regions": [r + [0, 0, 0, 0] for r in regions]}
        return coverage_report.Instance("bin", record, [], None, {}, coverage_report.Sources())

    def test_inconsistent_counts_are_not_determinable(self):
        # Condition 5, body 3: false 2 by subtraction, but the else body says
        # 1. Neither is believed.
        inst = self.instance("func f(_ x: Int) -> Int {\n    if x > 0 { return 1 } else { return 2 }\n}\n",
                             [[1, 25, 3, 2, 5], [2, 8, 2, 13, 5], [2, 14, 2, 26, 3], [2, 32, 2, 44, 1]])
        self.assertEqual(inst.derived, [])
        self.assertEqual([(u["line"], u["construct"]) for u in inst.uncheckable], [(2, "if")])
        self.assertIn("inconsistent", inst.uncheckable[0]["reason"])

    def test_enclosing_count_disagreeing_with_the_condition_is_not_determinable(self):
        inst = self.instance("func f(_ x: Int) -> Int {\n    if x > 0 { return 1 }\n    return 0\n}\n",
                             [[1, 25, 4, 2, 5], [2, 8, 2, 13, 4], [2, 14, 2, 26, 3], [2, 26, 3, 13, 1]])
        self.assertEqual(inst.derived, [])
        self.assertIn("inconsistent", inst.uncheckable[0]["reason"])

    def test_outcomes_adding_up_to_more_than_evaluations_with_a_try(self):
        line = "    if try g() > 0 { return 1 } else { return 2 }"
        cond, body, other = line.index("try") + 1, line.index("{") + 1, line.rindex("{") + 1
        inst = self.instance("func f() throws -> Int {\n" + line + "\n}\n",
                             [[1, 24, 3, 2, 3], [2, cond, 2, body - 1, 3], [2, body, 2, body + 12, 2],
                              [2, other, 2, other + 12, 2]])
        self.assertEqual(inst.derived, [])
        self.assertIn("inconsistent", inst.uncheckable[0]["reason"])

    def test_repeat_disagreeing_with_the_region_after_it_is_not_determinable(self):
        source = "func f(_ n: Int) -> Int {\n    var i = 0\n    repeat {\n        i += 1\n    } while i < n\n" \
                 "    return i\n}\n"
        regions = [[1, 25, 7, 2, 1], [3, 12, 5, 6, 3], [5, 13, 5, 18, 3]]
        inst = self.instance(source, regions + [[5, 18, 6, 13, 1]], count=1)
        self.assertEqual([(d["construct"], d["true"], d["false"]) for d in inst.derived], [("repeat", 2, 1)])
        inst = self.instance(source, regions + [[5, 18, 6, 13, 5]], count=1)
        self.assertEqual(inst.derived, [])
        self.assertIn("disagree", inst.uncheckable[0]["reason"])

    def test_regions_starting_at_one_place_with_different_counts_are_not_used(self):
        inst = self.instance("func f(_ x: Int) -> Int {\n    if x > 0 { return 1 }\n    return 0\n}\n",
                             [[1, 25, 4, 2, 5], [2, 8, 2, 13, 5], [2, 14, 2, 26, 3], [2, 14, 2, 20, 2],
                              [2, 26, 3, 13, 2]])
        self.assertEqual(inst.derived, [])
        self.assertEqual([(u["line"], u["construct"]) for u in inst.uncheckable], [(2, "if")])


@unittest.skipIf(SWIFT_MISSING, "toolchain missing: %s" % SWIFT_MISSING)
class SwiftStringTests(SwiftFixture, unittest.TestCase):
    """Code inside string interpolations is code: its constructs are found at
    their true line and column. Text of string literals is not."""
    SOURCE, BIN, PROF = "strings", "strbin", "strprof"

    def test_nil_coalescing_in_an_interpolation(self):
        # The reviewer's g1: called only with nil.
        status, d, inst = self.sw("interpNilCoalescing")
        self.assertEqual(status, 3, d["verdict"])
        self.assertEqual(self.nd_at(inst), [(self.line("i-nc"), 20, "??")])

    def test_nested_parentheses(self):
        status, d, inst = self.sw("interpNestedParens")
        self.assertEqual(self.nd_at(inst), [(self.line("i-paren"), 20, "??")])

    def test_nested_string_with_its_own_interpolation(self):
        status, d, inst = self.sw("interpNestedString")
        self.assertEqual(self.nd_at(inst), [(self.line("i-nested"), 31, "??")])

    def test_optional_chain(self):
        status, d, inst = self.sw("interpChain")
        line = self.line("i-chain")
        self.assertEqual(self.nd_at(inst), [(line, 20, "?."), (line, 28, "??")])

    def test_and(self):
        status, d, inst = self.sw("interpAnd")
        self.assertEqual(self.nd_at(inst), [(self.line("i-and"), 19, "&&")])

    def test_multiline_string(self):
        status, d, inst = self.sw("interpMultiline")
        self.assertEqual(self.nd_at(inst), [(self.line_of("second \\(n ??"), 20, "??")])

    def test_raw_string(self):
        status, d, inst = self.sw("interpRaw")
        self.assertEqual(self.nd_at(inst), [(self.line("i-raw"), 23, "??")])

    def test_raw_string_with_two_delimiters(self):
        status, d, inst = self.sw("interpRaw2")
        self.assertEqual(self.nd_at(inst), [(self.line("i-raw2"), 23, "||")])

    def test_raw_string_ends_only_at_its_delimiter(self):
        # Quotes inside #"..."# do not end it; if they did, the """ left over
        # would open a multi-line string hiding the next function.
        status, d, inst = self.sw("rawQuote")
        self.assertEqual(self.nd_at(inst), [(self.line("rq"), 32, "??")])
        status, d, inst = self.sw("afterRawQuote")
        self.assertEqual(self.nd_at(inst), [(self.line("arq"), 15, "??")])

    def test_operators_in_literal_text_are_not_listed(self):
        status, d, inst = self.sw("literalOnly")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(inst["not_determinable"], [])

    def test_try_question_in_an_interpolation(self):
        status, d, inst = self.sw("interpTryQ")
        line = self.line("i-tryq")
        self.assertEqual(self.nd_at(inst), [(line, 18, "try?"), (line, 35, "??")])

    def test_closure_in_an_interpolation(self):
        status, d, inst = self.sw("interpClosure")
        self.assertEqual(status, 1)
        self.assertEqual(self.derived(inst), [(self.line("i-closure"), "guard", 1, 0, ["false"])])

    def test_lexer_forms(self):
        cases = [
            # Interpolation code kept, nested string's text blanked.
            (r'a "x\(b ?? "c")y" d', r'a "  (b ?? " ") " d'),
            # Nested parentheses.
            (r'"\((x))"', r'" ((x))"'),
            # Raw string: \( is text, \#( is an interpolation.
            (r'#"a \(b) \#(c ?? d)"#', r'#"         (c ?? d)"#'),
            # Two delimiters: \#( is text, \##( an interpolation.
            (r'##"\#(a) \##(b)"##', r'##"         (b)"##'),
            # An escaped backslash before ( is text.
            (r'"\\(a ?? b)"', r'"          "'),
            # Escaped quotes do not end the string.
            (r'"a \"b\" \(c)"', r'"         (c)"'),
            # Multi-line string, interpolation across lines.
            ('"""\nx \\(a\n ?? b)\n"""', '"""\n   (a\n ?? b)\n"""'),
            # Interpolation in a string inside an interpolation, with a
            # comment holding a ).
            (r'"\(f("\(g /* ) */ ?? h)"))"', r'" (f(" (g         ?? h)"))"'),
            # Extended regex literal: a quote in it starts no string.
            (r'let r = #/a"b/# ?? c', r'let r = #/   /# ?? c'),
        ]
        for text, want in cases:
            self.assertEqual(coverage_report.blank_code(text, True), want, text)

    def test_dlog_autoclosure_is_set_aside(self):
        status, d, inst = self.sw("dlogInterp")
        self.assertEqual(status, 0, d["verdict"])
        line = self.line("d-interp")
        self.assertEqual(sorted((b["line"], b["column"], b["macro"], b["kind"]) for b in inst["ignored"]),
                         [(line, 10, "DLog", "implicit closure"), (line, 21, "DLog", "??"),
                          (line, 24, "DLog", "implicit closure")])
        self.assertEqual(inst["not_determinable"], [])
        self.assertEqual(inst["unexercised_regions"], [])
        self.assertIn("3 set aside inside DLog", d["verdict"])

    def test_dlog_argument_with_a_real_closure(self):
        status, d, inst = self.sw("dlogClosure")
        self.assertEqual(status, 0, d["verdict"])
        line = self.line("d-closure")
        self.assertEqual(sorted((b["line"], b["column"], b["kind"]) for b in inst["ignored"]),
                         [(line, 10, "implicit closure"), (line, 27, "closure")])

    def test_multiline_dlog(self):
        status, d, inst = self.sw("dlogMultiline")
        self.assertEqual(status, 0, d["verdict"])
        self.assertEqual(len(inst["ignored"]), 3)

    def test_autoclosure_of_another_function_is_reported(self):
        status, d, inst = self.sw("notSetAside")
        self.assertEqual(status, 1)
        self.assertEqual(inst["ignored"], [])
        self.assertEqual(len(self.regions(inst)), 1)
        self.assertIn("implicit closure at line %d" % self.line("d-not"), self.regions(inst)[0])
        status, d, inst = self.sw("similarName")
        self.assertEqual(status, 1)
        self.assertEqual(inst["ignored"], [])

    def test_other_autoclosure_beside_a_dlog_is_reported(self):
        status, d, inst = self.sw("dlogAndOther")
        self.assertEqual(status, 1)
        line = self.line("d-other")
        self.assertEqual([(b["line"], b["kind"]) for b in inst["ignored"]], [(line - 1, "implicit closure")])
        self.assertEqual(len(self.regions(inst)), 1)
        self.assertIn("implicit closure at line %d" % line, self.regions(inst)[0])

    def test_closure_after_a_dlog_is_not_set_aside(self):
        status, d, inst = self.sw("dlogThenClosure")
        self.assertEqual(status, 1)
        line = self.line("d-after")
        self.assertEqual([(b["column"], b["kind"]) for b in inst["ignored"]], [(10, "implicit closure")])
        self.assertEqual(self.regions(inst), ["closure at line %d never called" % line])

    def test_no_default_ignores_reports_the_dlog_autoclosure(self):
        status, d, inst = self.sw("dlogInterp", "--no-default-ignores")
        self.assertEqual(status, 1)
        self.assertEqual(inst["ignored"], [])

    def test_text_lists_the_set_aside_autoclosures(self):
        status, out, err = self.text("dlogInterp")
        self.assertEqual(status, 0, out + err)
        self.assertIn("Set aside (inside set-aside macros and logging calls, not counted): 3\n", out)
        self.assertIn("  DLog: 3 items\n", out)
        self.assertIn("    line %d col 10: implicit closure, executed 0 times\n" % self.line("d-interp"), out)


@unittest.skipIf(MISSING, "toolchain missing: %s" % MISSING)
class SmallerFixesTests(unittest.TestCase):

    def test_fold_flags_are_keyed_by_file(self):
        # H()'s gFlag in fold.h is at the same line and column as the while
        # (0) of foldmain.c, whose true outcome is folded; gFlag's true
        # outcome never happened and must be reported.
        status, d = function_json("fold_macro", Built.foldbin, Built.foldprof)
        self.assertEqual(status, 1, d["verdict"])
        b = d["instances"][0]["branches"]
        self.assertEqual([(x["text"], x["true_folded"], x["unexercised"]) for x in b], [("gFlag", False, ["true"])])
        status, d = function_json("fold_loop", Built.foldbin, Built.foldprof)
        w = [x for x in d["instances"][0]["branches"] if x["line"] == marker_line(Built.foldmain, "while0")]
        self.assertEqual([(x["true_folded"], x["false_folded"]) for x in w], [(True, False)])

    def test_identical_instances_from_one_binary_are_named(self):
        status, d = function_json("inl_sign", Built.tubin, Built.tuprof)
        self.assertEqual(len(d["instances"]), 1)
        note = [n for n in d["notes"] if "inl_sign" in n]
        self.assertEqual(len(note), 1, d["notes"])
        self.assertIn("2 instances", note[0])
        self.assertIn("tu1.c:inl_sign", note[0])
        self.assertIn("tu2.c:inl_sign", note[0])
        self.assertNotIn("binaries", note[0])
        self.assertNotIn("sum", note[0])

    def test_changed_header_makes_the_report_stale_and_is_named(self):
        copy = os.path.join(Built.dir, "stale_header")
        os.makedirs(copy, exist_ok=True)
        for name in ("foldmain.c", "fold.h"):
            shutil.copy(os.path.join(FIXTURES, name), os.path.join(copy, name))
        src = os.path.realpath(os.path.join(copy, "foldmain.c"))
        hdr = os.path.realpath(os.path.join(copy, "fold.h"))
        binary = os.path.join(copy, "foldmain")
        r = run(["xcrun", "clang", "-fprofile-instr-generate", "-fcoverage-mapping", "-w", src, "-o", binary])
        self.assertEqual(r.returncode, 0, r.stderr)
        env = dict(os.environ, LLVM_PROFILE_FILE=os.path.join(copy, "p.profraw"))
        run([binary], env=env)
        run_dir = os.path.join(copy, "run")
        os.makedirs(run_dir)
        run(["xcrun", "llvm-profdata", "merge", "-sparse", os.path.join(copy, "p.profraw"), "-o",
             os.path.join(run_dir, "coverage.profdata")])
        st = os.stat(binary)
        with open(os.path.join(run_dir, "binaries.txt"), "w") as f:
            f.write("%s\t%d\t%d\n" % (binary, st.st_size, int(st.st_mtime)))
        import hashlib
        with open(os.path.join(run_dir, "sources.sha256"), "w") as f:
            for p in (src, hdr):
                with open(p, "rb") as g:
                    f.write("%s  %s\n" % (hashlib.sha256(g.read()).hexdigest(), p))
        status, out, err = report("function", "fold_macro", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 1, out + err)
        with open(hdr, "a") as f:
            f.write("// changed\n")
        status, out, err = report("function", "fold_macro", "--run", run_dir, "--no-codedb", "--json")
        self.assertEqual(status, 3, out + err)
        problems = json.loads(out)["problems"]
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("fold.h changed since the coverage build", problems[0])
        self.assertIn("contributes lines or macro definitions to fold_macro", problems[0])

    def test_set_aside_branches_are_listed_in_text(self):
        status, out, err = report("function", "logged", "--binary", Built.cbin, "--profdata", Built.cprof,
                                  "--no-codedb", "--ignore-macro", "LOGF")
        self.assertEqual(status, 0, out + err)
        self.assertIn("  LOGF: 4 branches\n", out)
        self.assertIn("    line %d col 5: gLog  true 0 false 1\n" % marker_line(Built.branches, "logf"), out)
        self.assertIn("    line %d col 5: 0  true folded false 1\n" % marker_line(Built.branches, "loud"), out)

    def test_set_aside_macro_is_the_same_option(self):
        a = function_json("logged", Built.cbin, Built.cprof, "--ignore-macro", "LOGF")
        b = function_json("logged", Built.cbin, Built.cprof, "--set-aside-macro", "LOGF")
        self.assertEqual(a, b)

    def test_set_aside_listing_shows_ten_per_macro_unless_verbose(self):
        import io

        class Fake:
            ignored = [{"line": i, "column": 1, "macro": "M", "text": "c", "true": 0, "false": 1} for i in range(12)]
        out = io.StringIO()
        coverage_report.print_set_aside(Fake, False, out)
        self.assertIn("  M: 12 branches\n", out.getvalue())
        self.assertEqual(out.getvalue().count("    line "), 10)
        self.assertIn("... and 2 more (--verbose lists them all)", out.getvalue())
        out = io.StringIO()
        coverage_report.print_set_aside(Fake, True, out)
        self.assertEqual(out.getvalue().count("    line "), 12)

    def test_help_tells_the_truth_about_set_aside_branches(self):
        doc = " ".join(coverage_report.__doc__.split())
        self.assertIn("they are listed, grouped by macro with a count per macro and each branch's location and "
                      "outcome counts", doc)
        self.assertIn("--set-aside-macro", doc)
        self.assertIn("--accept-uncheckable", doc)


class CoverageTestsScriptTests(unittest.TestCase):
    """coverage_tests.sh cannot be run here (it builds the app); these check
    its text: syntax, the latest link, result bundles, the route file and
    the help."""

    SCRIPT = os.path.join(TOOLS, "coverage_tests.sh")
    OBSERVER = os.path.join(os.path.dirname(os.path.dirname(TOOLS)), "ModernTests",
                            "iTermCoveragePerClassObserver.m")

    def text(self):
        with open(self.SCRIPT) as f:
            return f.read()

    def test_syntax(self):
        r = run(["bash", "-n", self.SCRIPT])
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_build_only_does_not_move_latest(self):
        text = self.text()
        self.assertEqual(text.count('ln -sfn "$RUN_DIR" "$BUILD_DIR/runs/latest"'), 1)
        link = text.index('ln -sfn "$RUN_DIR" "$BUILD_DIR/runs/latest"')
        self.assertGreater(link, text.index('if [ "$DO_TEST" = NO ]; then'))
        self.assertGreater(link, text.index('merge_profiles "$MERGE_FROM" "$RUN_DIR/coverage.profdata"'))

    def test_result_bundles_go_under_the_run_directory(self):
        text = self.text()
        self.assertIn('-resultBundlePath "$RUN_DIR/results/build.xcresult"', text)
        self.assertIn('bundle="$RUN_DIR/results/$(basename "$log" .log).xcresult"', text)
        self.assertIn('-resultBundlePath "$bundle"', text)

    def test_status_is_recorded_and_latest_moves_only_when_tests_passed(self):
        text = self.text()
        started = text.index('echo started > "$RUN_DIR/status.txt"')
        self.assertGreater(started, text.index('mkdir -p "$PROFRAW" "$RUN_DIR/results"'))
        self.assertLess(started, text.index("san_common_xcodebuild_args"))
        record = text.index('echo "$STATUS" > "$RUN_DIR/status.txt"')
        guard = text.index('if [ "$STATUS" -eq 0 ]; then\n    ln -sfn "$RUN_DIR" "$BUILD_DIR/runs/latest"')
        self.assertGreater(guard, record)
        self.assertGreater(record, text.index('merge_profiles "$MERGE_FROM" "$RUN_DIR/coverage.profdata"'))

    def test_route_is_recorded(self):
        text = self.text()
        self.assertIn('echo per-class > "$RUN_DIR/per_class_route.txt"', text)
        self.assertIn('echo observer > "$RUN_DIR/per_class_route.txt"', text)

    def help_text(self):
        """What --help prints: the header comment from line 2 to the first
        blank line, as the script's usage() takes it (running the script
        would source sanitizer_common.sh first)."""
        out = []
        for line in self.text().split("\n")[1:]:
            if line == "":
                break
            out.append(line[2:] if line.startswith("# ") else line[1:])
        return " ".join(" ".join(out).split())

    def test_help_and_observer_say_attribution_is_approximate(self):
        help_text = self.help_text()
        self.assertIn("Per-class attribution from an observer run is approximate", help_text)
        self.assertIn("use --per-class for a per-class verdict", help_text)
        self.assertIn("The latest link is not moved", help_text)
        with open(self.OBSERVER) as f:
            observer = " ".join(f.read().replace("//", " ").split())
        self.assertIn("Per-class attribution from an observer run is approximate", observer)
        self.assertIn("coverage_tests.sh --per-class", observer)
        launch = "work the app's launch leaves running"
        self.assertIn(launch, help_text)
        self.assertIn(launch, observer)


class LogTests(unittest.TestCase):
    """The log helpers coverage_tests.sh calls."""

    def write(self, text):
        fd, path = tempfile.mkstemp(suffix=".log")
        with os.fdopen(fd, "w") as f:
            f.write(text)
        self.addCleanup(os.unlink, path)
        return path

    PASSED = ("Test Case '-[A testOne]' started.\n"
              "Test Case '-[A testOne]' passed (0.001 seconds).\n")
    FAILED = ("Test Case '-[A testTwo]' started.\n"
              "Test Case '-[A testTwo]' failed (0.001 seconds).\n")

    def test_executed_counts_tests(self):
        status, out, _ = report("log-executed", self.write(self.PASSED + self.FAILED))
        self.assertEqual((status, out.strip()), (0, "2"))

    def test_executed_fails_on_empty_log(self):
        status, out, _ = report("log-executed", self.write("** TEST SUCCEEDED **\n"))
        self.assertEqual((status, out.strip()), (1, "0"))

    def test_status_from_log(self):
        self.assertEqual(report("log-status", self.write(self.PASSED))[1].strip(), "0")
        self.assertEqual(report("log-status", self.write(self.PASSED + self.FAILED))[1].strip(), "1")
        crashed = "Test Case '-[A testThree]' started.\n"
        self.assertEqual(report("log-status", self.write(self.PASSED + crashed))[1].strip(), "1")


class StreamTests(unittest.TestCase):
    """The streaming reader of llvm-cov export's functions array."""

    def test_reads_objects_across_chunk_boundaries(self):
        import io
        doc = {"data": [{"files": [{"filename": "a.c", "segments": [[1, 1, 0, True, True, False]]}],
                         "functions": [{"name": "f%d" % i, "regions": [[i, 1, i, 2, i, 0, 0, 0]],
                                        "filenames": ["x]{\"y"]} for i in range(50)],
                         "totals": {}}], "type": "llvm.coverage.json.export", "version": "3.0.1"}
        text = json.dumps(doc, separators=(",", ":"))
        files, functions = [], []
        coverage_report.stream_export(io.StringIO(text), files.append, functions.append, chunk=7)
        self.assertEqual([f["name"] for f in functions], ["f%d" % i for i in range(50)])
        self.assertEqual(files[0]["filename"], "a.c")


if __name__ == "__main__":
    unittest.main()
