// Streaming reader of the Swift compiler's JSON AST dump for the type-aware
// migration lints (tools/swift_migration/swift_ast_lints.py). It is a
// separate program from swift_refs.cpp, which fills the code database; it
// shares only the dump's names in dump_format.h.
//
// It runs the compiler itself (the command after --) and reads its stdout
// through a pipe, or reads stdin, with RapidJSON's SAX parser, one JSON
// document per primary file, and prints one line of facts per node the lints
// need, tab-separated, with byte offsets into the source file (the lints turn
// them into lines and columns, and decide what is a finding):
//
//   F  path                          a document begins (the file's path)
//   P  start  conversion  type  operand  flags
//                                    an implicit pointer conversion of an
//                                    argument: conversion is inout_to_pointer,
//                                    array_to_pointer or string_to_pointer;
//                                    type the pointer type (mangled); operand
//                                    the kind of the converted expression
//                                    (inout_expr for &x)
//   U  start  type  usr  name  flags an implicit force of an implicitly
//                                    unwrapped value (force_value_expr with
//                                    implicit_iuo_unwrap); start is the name
//                                    of the declaration (a member's name, a
//                                    called method's or function's name), or
//                                    the expression's start when there is
//                                    none: type the unwrapped
//                                    type; usr and name those of the
//                                    declaration the unwrapped expression
//                                    refers to (a property, a method or
//                                    function called, a variable), or "-"
//   A  start  operator  operand-type  argument-kinds  decl-usr  flags
//                                    a binary or prefix operator call (start:
//                                    the operator) whose operator is one of
//                                    kOperators; operand-type the type of its
//                                    first operand (inout for a compound
//                                    assignment); argument-kinds the kinds of
//                                    its operands, comma-separated
//   I  start  result-type  label  argument-type  argument-kind  count  flags
//                                    a call of an initializer (start: the
//                                    call) with its first argument's label
//                                    ("-" for none), type and kind, and the
//                                    number of arguments
//   E  path                          the document ended
//   S  key value ...                 the summary, last
//
// flags: "m" inside a macro expansion (start is then the macro's start in
// the file), "i" inside a declaration the compiler wrote (implicit), "-"
// for neither. A node without a source range is not reported.
//
// Memory is bounded by the nesting depth of the tree, never by the size of
// the dump: nothing of a node is kept after it ends. If the compiler fails,
// or a document is truncated or malformed, the exit status is 1 (facts
// already printed are then not to be trusted).
//
// Usage:
//   swift_ast_facts --version
//   swift_ast_facts [--accept-compiler-version] [--stderr-file F] [-- COMMAND...]
//
// Exit status: 0 read; 1 failed; 2 usage error. The summary line:
//   S documents N compiler_status C compiler_peak_kb K reader_peak_kb P
//     unranged U dump_bytes B
// (unranged: nodes of the kinds above that had no source range and were not
// reported; dump_bytes: the bytes of the dump read).

#include "dump_format.h"

#include <rapidjson/error/en.h>
#include <rapidjson/filereadstream.h>
#include <rapidjson/reader.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <string>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char **environ;

#ifndef SWIFT_AST_FACTS_DIGEST
#define SWIFT_AST_FACTS_DIGEST "unknown"
#endif

using namespace rapidjson;

// Names of the dump that only this reader uses (the shared ones are in
// dump_format.h). Read from the dumps of Swift 6.4 (dump::kWrittenAgainst).
namespace facts {
static const char *const kInoutToPointer = "inout_to_pointer";
static const char *const kArrayToPointer = "array_to_pointer";
static const char *const kStringToPointer = "string_to_pointer";
static const char *const kForceValueExpr = "force_value_expr";
static const char *const kImplicitIuoUnwrap = "implicit_iuo_unwrap";
static const char *const kBinaryExpr = "binary_expr";
static const char *const kPrefixUnaryExpr = "prefix_unary_expr";
static const char *const kCallExpr = "call_expr";
static const char *const kLabel = "label";
static const char *const kInit = "init";
// Nodes that refer to a declaration through their decl child.
static const char *const kReferenceKinds[] = {"declref_expr", "member_ref_expr", "dynamic_member_ref_expr",
                                              "subscript_expr", "dynamic_subscript_expr"};
// Reference nodes whose range ends with the member's name.
static const char *const kMemberKinds[] = {"member_ref_expr", "dynamic_member_ref_expr"};
// Function-like declarations: code inside one the compiler wrote is flagged.
static const char *const kFunctionLike[] = {"func_decl", "accessor_decl", "constructor_decl", "destructor_decl",
                                            "var_decl", "subscript_decl"};
// The operators of translation-rules.md section 1 and their compound
// assignments.
static const char *const kOperators[] = {"+", "-", "*", "<<", "+=", "-=", "*=", "<<="};
}  // namespace facts

static bool isOneOf(const std::string &s, const char *const *list, size_t n) {
    for (size_t i = 0; i < n; ++i)
        if (s == list[i]) return true;
    return false;
}
#define IS_ONE_OF(s, arr) isOneOf((s), (arr), sizeof(arr) / sizeof((arr)[0]))

static std::string field(const std::string &s) {
    if (s.empty()) return "-";
    std::string out = s;
    for (auto &c : out)
        if (c == '\t' || c == '\n' || c == '\r') c = ' ';
    return out;
}

struct Arg {
    std::string label, type, kind;
};

struct Frame {
    bool object = false;
    std::string key;
    std::string kind;
    std::string type;
    long start = -1, end = -1;  // end: the start of the node's last token
    bool implicit = false;
    bool iuoUnwrap = false;
    bool skip = false;
    bool inMacro = false;
    long macroStart = -1;
    bool inImplicitDecl = false;
    // decl_ref: its name and USR. A reference node: those of its decl child.
    std::string baseName, declUsr;
    bool hasDecl = false;
    // The declaration an expression refers to: its own decl (a reference
    // node), else that of its fn child (a call), else that of its sub_expr
    // child (a load, a paren, a conversion).
    std::string refName, refUsr;
    bool hasRef = false;
    long refPos = -1;  // where the declaration's name is written
    long fnRefPos = -1, subRefPos = -1;
    std::string fnRefName, fnRefUsr, subRefName, subRefUsr;
    bool hasFnRef = false, hasSubRef = false;
    std::string fnKind;  // the kind of the fn child
    long fnStart = -1;   // the start of the fn child (an operator's position)
    // argument: its label, and its expr child's type and kind.
    std::string label, argType, argKind;
    // argument_list: its arguments. A call or operator: those of its args child.
    std::vector<Arg> args;
    std::string subKind;  // the kind of the sub_expr child
    std::vector<std::string> arrays;
};

struct Handler : BaseReaderHandler<UTF8<>, Handler> {
    std::vector<Frame> st;
    std::string key;
    std::string failure;
    std::string file;
    bool acceptVersion = false;
    std::string docMajor, docMinor;
    long documents = 0, unranged = 0;

    bool fail(const std::string &why) {
        if (failure.empty()) failure = why;
        return false;
    }

    // --- output -------------------------------------------------------------

    long position(const Frame &f) const { return f.inMacro ? f.macroStart : f.start; }
    std::string flags(const Frame &f) const {
        std::string s;
        if (f.inMacro) s += "m";
        if (f.inImplicitDecl) s += "i";
        return s.empty() ? "-" : s;
    }

    // --- tree ---------------------------------------------------------------

    void push() {
        Frame f;
        f.object = true;
        if (key.empty() && !st.empty() && !st.back().arrays.empty()) key = st.back().arrays.back();
        f.key = key;
        if (!st.empty()) {
            const Frame &p = st.back();
            f.skip = p.skip || IS_ONE_OF(key, dump::kSkipKeys);
            f.inMacro = p.inMacro;
            f.macroStart = p.macroStart;
            if (key == dump::kKeyRewritten && !p.inMacro) {
                f.inMacro = true;
                f.macroStart = p.start;
            }
            f.inImplicitDecl = p.inImplicitDecl || (IS_ONE_OF(p.kind, facts::kFunctionLike) && p.implicit);
        }
        st.push_back(f);
        key.clear();
    }

    void finish(Frame &f) {
        // The declaration this expression refers to.
        if (f.hasDecl && IS_ONE_OF(f.kind, facts::kReferenceKinds)) {
            f.refName = f.baseName;
            f.refUsr = f.declUsr;
            f.hasRef = true;
            // A member reference ends with the member's name (base.name); a
            // declaration reference is the name; a subscript has no name.
            f.refPos = IS_ONE_OF(f.kind, facts::kMemberKinds) && f.end >= 0 ? f.end : f.start;
        } else if (f.hasFnRef) {
            f.refName = f.fnRefName;
            f.refUsr = f.fnRefUsr;
            f.refPos = f.fnRefPos;
            f.hasRef = true;
        } else if (f.hasSubRef) {
            f.refName = f.subRefName;
            f.refUsr = f.subRefUsr;
            f.refPos = f.subRefPos;
            f.hasRef = true;
        }
        if (f.skip) return;
        if (f.start < 0 && !f.inMacro) {
            if (f.kind == facts::kInoutToPointer || f.kind == facts::kArrayToPointer ||
                f.kind == facts::kStringToPointer || (f.kind == facts::kForceValueExpr && f.iuoUnwrap) ||
                f.kind == facts::kBinaryExpr || f.kind == facts::kPrefixUnaryExpr || f.kind == facts::kCallExpr)
                ++unranged;
            return;
        }
        if (f.kind == facts::kInoutToPointer || f.kind == facts::kArrayToPointer ||
            f.kind == facts::kStringToPointer) {
            printf("P\t%ld\t%s\t%s\t%s\t%s\n", position(f), f.kind.c_str(), field(f.type).c_str(),
                   field(f.subKind).c_str(), flags(f).c_str());
        } else if (f.kind == facts::kForceValueExpr && f.implicit && f.iuoUnwrap) {
            long at = f.inMacro ? f.macroStart : (f.hasSubRef && f.subRefPos >= 0 ? f.subRefPos : f.start);
            printf("U\t%ld\t%s\t%s\t%s\t%s\n", at, field(f.type).c_str(),
                   field(f.hasSubRef ? f.subRefUsr : "").c_str(), field(f.hasSubRef ? f.subRefName : "").c_str(),
                   flags(f).c_str());
        } else if ((f.kind == facts::kBinaryExpr || f.kind == facts::kPrefixUnaryExpr) && f.hasFnRef &&
                   IS_ONE_OF(f.fnRefName, facts::kOperators) && !f.args.empty()) {
            std::string kinds;
            for (auto &a : f.args) kinds += (kinds.empty() ? "" : ",") + field(a.kind);
            long at = f.inMacro ? f.macroStart : (f.fnStart >= 0 ? f.fnStart : f.start);
            printf("A\t%ld\t%s%s\t%s\t%s\t%s\t%s\n", at, f.kind == facts::kPrefixUnaryExpr ? "prefix" : "",
                   f.fnRefName.c_str(), field(f.args[0].type).c_str(), kinds.c_str(), field(f.fnRefUsr).c_str(),
                   flags(f).c_str());
        } else if (f.kind == facts::kCallExpr && f.fnKind == dump::kConstructorRefCallExpr && f.hasFnRef &&
                   f.fnRefName == facts::kInit) {
            const Arg none;
            const Arg &a = f.args.empty() ? none : f.args[0];
            printf("I\t%ld\t%s\t%s\t%s\t%s\t%zu\t%s\n", position(f), field(f.type).c_str(), field(a.label).c_str(),
                   field(a.type).c_str(), field(a.kind).c_str(), f.args.size(), flags(f).c_str());
        }
    }

    // Hand what the parent needs from a child that ended.
    void report(const Frame &f, Frame &p) {
        if (f.kind == dump::kDeclRef && f.key == dump::kKeyDecl) {
            p.baseName = f.baseName;
            p.declUsr = f.declUsr;
            p.hasDecl = true;
        }
        if (f.key == dump::kKeyFn) {
            p.fnKind = f.kind;
            p.fnStart = f.start;
            if (f.hasRef) {
                p.fnRefName = f.refName;
                p.fnRefUsr = f.refUsr;
                p.fnRefPos = f.refPos;
                p.hasFnRef = true;
            }
        }
        if (f.key == dump::kKeySubExpr) {
            p.subKind = f.kind;
            if (f.hasRef) {
                p.subRefName = f.refName;
                p.subRefUsr = f.refUsr;
                p.subRefPos = f.refPos;
                p.hasSubRef = true;
            }
        }
        if (f.key == dump::kKeyExpr && p.kind == dump::kArgument) {
            p.argType = f.type;
            p.argKind = f.kind;
        }
        if (f.kind == dump::kArgument && p.kind == dump::kArgumentList) {
            Arg a;
            a.label = f.label;
            a.type = f.argType;
            a.kind = f.argKind;
            p.args.push_back(a);
        }
        if (f.kind == dump::kArgumentList && f.key == dump::kKeyArgs) p.args = f.args;
    }

    // --- SAX callbacks ------------------------------------------------------

    bool StartObject() {
        if (!failure.empty()) return false;
        push();
        return true;
    }
    bool EndObject(SizeType) {
        if (st.empty()) return fail("unbalanced object");
        Frame f = std::move(st.back());
        st.pop_back();
        finish(f);
        if (!st.empty()) report(f, st.back());
        else if (!file.empty()) {
            printf("E\t%s\n", field(file).c_str());
            file.clear();
        }
        key.clear();
        return true;
    }
    bool StartArray() {
        if (!failure.empty()) return false;
        if (st.empty()) return fail("a document is an array, not a source_file object");
        if (key.empty() && !st.back().arrays.empty()) key = st.back().arrays.back();
        st.back().arrays.push_back(key);
        key.clear();
        return true;
    }
    bool EndArray(SizeType) {
        st.back().arrays.pop_back();
        key.clear();
        return true;
    }
    bool Key(const char *s, SizeType n, bool) {
        key.assign(s, n);
        return true;
    }
    bool String(const char *s, SizeType n, bool) {
        if (!failure.empty()) return false;
        Frame &f = st.back();
        if (!f.object) {
            key.clear();
            return true;
        }
        if (key == dump::kKind) {
            f.kind.assign(s, n);
        } else if (key == dump::kType) {
            f.type.assign(s, n);
        } else if (key == dump::kBaseNameField && f.kind == dump::kDeclRef) {
            f.baseName.assign(s, n);
        } else if (key == dump::kDeclUsr && f.kind == dump::kDeclRef) {
            f.declUsr.assign(s, n);
        } else if (key == facts::kLabel && f.kind == dump::kArgument) {
            f.label.assign(s, n);
        } else if (key == dump::kFilename && f.kind == dump::kSourceFile && st.size() == 1) {
            file.assign(s, n);
            ++documents;
            printf("F\t%s\n", field(file).c_str());
        } else if (st.size() == 2 && st[1].key == dump::kKeyCompilerVersion) {
            if (key == dump::kMajor) docMajor.assign(s, n);
            else if (key == dump::kMinor) {
                docMinor.assign(s, n);
                std::string mm = docMajor + "." + docMinor;
                if (mm != dump::kWrittenAgainst && !acceptVersion)
                    return fail("the dump is from Swift " + mm + "; this reader was written against the dump format "
                                "of " + std::string(dump::kWrittenAgainst) + " (pass --accept-compiler-version to "
                                "read it anyway)");
            }
        }
        key.clear();
        return true;
    }
    bool Bool(bool b) {
        Frame &f = st.back();
        if (f.object) {
            if (key == dump::kImplicit) f.implicit = b;
            else if (key == facts::kImplicitIuoUnwrap) f.iuoUnwrap = b;
        }
        key.clear();
        return true;
    }
    bool num(long v) {
        Frame &f = st.back();
        if (f.object && f.key == dump::kRange && st.size() >= 2) {
            if (key == dump::kStart) st[st.size() - 2].start = v;
            else if (key == dump::kEnd) st[st.size() - 2].end = v;
        }
        key.clear();
        return true;
    }
    bool Int(int v) { return num(v); }
    bool Uint(unsigned v) { return num(v); }
    bool Int64(int64_t v) { return num((long)v); }
    bool Uint64(uint64_t v) { return num((long)v); }
    bool Double(double) {
        key.clear();
        return true;
    }
    bool Null() {
        key.clear();
        return true;
    }
};

static int usage() {
    fprintf(stderr, "usage: swift_ast_facts --version | [--accept-compiler-version] [--stderr-file F] [-- COMMAND...]\n");
    return 2;
}

int main(int argc, char **argv) {
    Handler h;
    std::string stderrFile;
    std::vector<std::string> command;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--version") {
            printf("swift_ast_facts %s %s\n", SWIFT_AST_FACTS_DIGEST, dump::kWrittenAgainst);
            return 0;
        } else if (a == "--accept-compiler-version") {
            h.acceptVersion = true;
        } else if (a == "--stderr-file" && i + 1 < argc) {
            stderrFile = argv[++i];
        } else if (a == "--") {
            for (++i; i < argc; ++i) command.push_back(argv[i]);
        } else {
            return usage();
        }
    }
    pid_t child = -1;
    int fd = 0;
    if (!command.empty()) {
        int pipefd[2];
        if (pipe(pipefd) != 0) {
            perror("swift_ast_facts: pipe");
            return 1;
        }
        posix_spawn_file_actions_t fa;
        posix_spawn_file_actions_init(&fa);
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
        posix_spawn_file_actions_adddup2(&fa, pipefd[1], 1);
        if (!stderrFile.empty())
            posix_spawn_file_actions_addopen(&fa, 2, stderrFile.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        posix_spawn_file_actions_addclose(&fa, pipefd[0]);
        posix_spawn_file_actions_addclose(&fa, pipefd[1]);
        std::vector<char *> av;
        for (auto &a : command) av.push_back(const_cast<char *>(a.c_str()));
        av.push_back(nullptr);
        int rc = posix_spawn(&child, av[0], &fa, nullptr, av.data(), environ);
        posix_spawn_file_actions_destroy(&fa);
        close(pipefd[1]);
        if (rc != 0) {
            fprintf(stderr, "swift_ast_facts: cannot run %s: %s\n", av[0], strerror(rc));
            return 1;
        }
        fd = pipefd[0];
    }
    FILE *in = fd == 0 ? stdin : fdopen(fd, "rb");
    static char buf[1 << 16];
    FileReadStream is(in, buf, sizeof buf);
    Reader reader;
    std::string parseError;
    for (;;) {
        while (is.Peek() == ' ' || is.Peek() == '\n' || is.Peek() == '\r' || is.Peek() == '\t') is.Take();
        if (is.Peek() == '\0') break;
        ParseResult pr = reader.Parse<kParseStopWhenDoneFlag | kParseIterativeFlag>(is, h);
        if (!pr) {
            parseError = !h.failure.empty() ? h.failure
                                            : "malformed or truncated dump at document " +
                                                  std::to_string(h.documents) + ", byte " +
                                                  std::to_string(pr.Offset()) + ": " + GetParseError_En(pr.Code());
            break;
        }
        h.st.clear();
    }
    long compilerPeakKb = 0;
    int status = 0;
    if (child > 0) {
        if (!parseError.empty()) kill(child, SIGKILL);
        while (fread(buf, 1, sizeof buf, in) > 0) {
        }
        struct rusage ru;
        int ws = 0;
        while (wait4(child, &ws, 0, &ru) < 0 && errno == EINTR) {
        }
        compilerPeakKb = (long)(ru.ru_maxrss / 1024);
        status = WIFEXITED(ws) ? WEXITSTATUS(ws) : 128 + (WIFSIGNALED(ws) ? WTERMSIG(ws) : 0);
    }
    if (in != stdin) fclose(in);
    struct rusage self;
    getrusage(RUSAGE_SELF, &self);
    printf("S\tdocuments\t%ld\tcompiler_status\t%d\tcompiler_peak_kb\t%ld\treader_peak_kb\t%ld\tunranged\t%ld\t"
           "dump_bytes\t%zu\n",
           h.documents, status, compilerPeakKb, (long)(self.ru_maxrss / 1024), h.unranged, is.Tell());
    fflush(stdout);
    if (!parseError.empty()) {
        fprintf(stderr, "swift_ast_facts: %s\n", parseError.c_str());
        return 1;
    }
    if (status != 0) {
        fprintf(stderr, "swift_ast_facts: the compiler exited with status %d%s\n", status,
                stderrFile.empty() ? "" : (" (its messages are in " + stderrFile + ")").c_str());
        return 1;
    }
    return 0;
}
