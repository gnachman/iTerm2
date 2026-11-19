// Streaming reader of the Swift compiler's JSON AST dump, for the code
// database (tools/swift_migration/codedb).
//
// It runs the compiler itself (the command after --), reads the compiler's
// stdout through a pipe with RapidJSON's SAX parser, one JSON document per
// primary file, and writes, in one transaction for the whole module, to the
// SQLite database:
//
//   swift_unit       one row for the module
//   swift_input      the inputs codedb.py lists in --inputs (path, digest)
//   swift_ref        every reference from Swift to a declaration with an
//                    Objective-C USR: a Clang USR (c:objc(...)) or a Swift
//                    @objc declaration's (c:@M@Module@objc(...)), and every
//                    #selector, whatever it names
//   swift_objc_decl  Swift declarations visible to Objective-C, with their
//                    selectors (from the USR, from the compiler's @objc
//                    name, or derived from the Swift name)
//   swift_protocol   the requirements of the module's Swift protocols (not
//                    @objc), the members of their extensions, and every
//                    conformance of an Objective-C class to a Swift protocol
//                    declared in an extension, with the members it declares:
//                    the dump names a requirement that a call goes through,
//                    not the Objective-C method that witnesses it
//   swift_inactive   the #if clauses of each file that no node of the dump
//                    is in: the dump has nothing of an inactive clause, so
//                    the reader finds the clauses in the source text and
//                    keeps those that hold code and no node (inactive in
//                    this configuration, or holding nothing the compiler
//                    keeps); nested ones are inside the outermost recorded;
//                    a file whose clauses the lexer cannot determine (see
//                    findClauses) is recorded whole, with undetermined = 1
//
// Memory is bounded by the nesting depth of the tree and the size of the
// largest source file, never by the size of the dump. If the compiler fails,
// a document is truncated or malformed, a document is missing or not one of
// the module's files, or a source file changed while it was read, nothing is
// written (the transaction is rolled back) and the exit status is 1.
//
// Without --, it reads the dump from stdin (the tests do this with dumps
// captured from the compiler).
//
// Usage:
//   swift_refs --version
//   swift_refs --db DB --root ROOT --module M --target T --cmd-digest D
//              --file-list-digest D --files FILE --inputs FILE
//              --compiler-version FULL [--accept-compiler-version]
//              [--bare-slash-regex] [--stderr-file F] [--migration-scope DIR]... [-- COMMAND...]
//
// Exit status: 0 written; 1 failed (nothing written); 2 usage error.
// On success it prints one line to stdout:
//   swift_refs: documents N refs R decls D assertions A errors E unresolved U
//   underivable V skipped_documents K compiler_peak_kb C reader_peak_kb P
//   unknown_access X unknown_kinds Y undetermined_files Z
// then, when Y is not 0, a line that names them:
//   swift_refs: node kinds this reader does not know: KIND COUNT, ...
//
// Node kinds in none of dump_format.h's tables (handled or deliberately
// ignored) are counted, per module, in swift_unit.unknown_node_kinds: a new
// kind can carry references or change an access, which the reader would
// otherwise pass over in silence. A property reference whose use passes
// through a node the reader does not classify (see accessIn) has access
// "unknown", and the kind is counted in swift_unit.unknown_access_kinds.
//
// Every name of the dump format it depends on is in dump_format.h.

#include "dump_format.h"

#include <CommonCrypto/CommonDigest.h>
#include <rapidjson/error/en.h>
#include <rapidjson/filereadstream.h>
#include <rapidjson/reader.h>
#include <sqlite3.h>

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <map>
#include <memory>
#include <set>
#include <signal.h>
#include <spawn.h>
#include <string>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char **environ;

#ifndef SWIFT_REFS_DIGEST
#define SWIFT_REFS_DIGEST "unknown"
#endif

// The version of the Swift tables this reader writes; codedb.py's
// SWIFT_SCHEMA_VERSION must match.
static const int kSwiftSchemaVersion = 3;

using namespace rapidjson;

static bool isOneOf(const std::string &s, const char *const *list, size_t n) {
    for (size_t i = 0; i < n; ++i)
        if (s == list[i]) return true;
    return false;
}
#define IS_ONE_OF(s, arr) isOneOf((s), (arr), sizeof(arr) / sizeof((arr)[0]))

static std::string sha256Hex(const std::string &data) {
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.data(), (CC_LONG)data.size(), md);
    static const char *hex = "0123456789abcdef";
    std::string out;
    for (unsigned char c : md) {
        out += hex[c >> 4];
        out += hex[c & 15];
    }
    return out;
}

// --- USRs -------------------------------------------------------------------

// What an Objective-C-style USR names: c:objc(cs)Class(im)sel:,
// c:@M@Module@objc(pl)Proto(py)name, c:@CM@Module@objc(cs)Class(cpy)name.
struct ObjCUsr {
    bool ok = false;
    std::string containerKind;  // cs (class), pl (protocol), cy (category)
    std::string container;      // the class or protocol name
    std::string memberKind;     // im, cm, py, cpy, or empty for the container itself
    std::string member;         // the selector (im, cm) or property name (py, cpy)
};

static ObjCUsr parseObjCUsr(const std::string &usr) {
    ObjCUsr r;
    if (usr.compare(0, 2, "c:") != 0) return r;
    size_t p = usr.find("objc(");
    if (p == std::string::npos) return r;
    size_t q = usr.find(')', p);
    if (q == std::string::npos) return r;
    r.containerKind = usr.substr(p + 5, q - p - 5);
    size_t m = usr.find('(', q + 1);
    if (m == std::string::npos) {
        r.container = usr.substr(q + 1);
        r.ok = true;
        return r;
    }
    r.container = usr.substr(q + 1, m - q - 1);
    size_t e = usr.find(')', m);
    if (e == std::string::npos) return r;
    r.memberKind = usr.substr(m + 1, e - m - 1);
    r.member = usr.substr(e + 1);
    if (r.containerKind == "cy") {
        // c:objc(cy)Class@Category: the class is before the @.
        size_t at = r.container.find('@');
        if (at != std::string::npos) r.container = r.container.substr(0, at);
    }
    r.ok = true;
    return r;
}

static bool isMemberKind(const std::string &k) { return k == "im" || k == "cm" || k == "py" || k == "cpy"; }

// A mangled type whose values are references: a class (...C), optional or
// not, AnyObject (yXl), or an existential of an Objective-C protocol
// (..._p; the protocols of Objective-C-visible properties are class-bound).
// Writing through such a value (w.peer.count = 1) does not write it.
static bool isReferenceType(const std::string &mangled) {
    std::string s = mangled;
    if (s.compare(0, 2, "$s") == 0) s = s.substr(2);
    if (!s.empty() && s.back() == 'D') s.pop_back();
    while (s.size() >= 2 && s.compare(s.size() - 2, 2, "Sg") == 0) s.resize(s.size() - 2);
    auto endsWith = [&](const char *t) {
        size_t n = strlen(t);
        return s.size() >= n && s.compare(s.size() - n, n, t) == 0;
    };
    return endsWith("C") || endsWith("yXl") || endsWith("_p");
}

// A Swift USR of a member declared in a protocol (a requirement,
// s:3Fix8HasCountP5countSivp) or in an extension of a protocol
// (s:3Fix3ExtPAAE4extvSivp): a nominal type path whose last element is a
// protocol (P), followed by the member's name or an extension.
static bool isSwiftProtocolMember(const std::string &usr) {
    if (usr.compare(0, 2, "s:") != 0) return false;
    size_t i = 2;
    while (i < usr.size() && isdigit((unsigned char)usr[i])) {
        size_t n = 0;
        while (i < usr.size() && isdigit((unsigned char)usr[i])) n = n * 10 + (usr[i++] - '0');
        if (n == 0 || i + n > usr.size()) return false;
        bool discriminator = usr[i] == '_';
        i += n;
        // A private declaration's discriminator: 33_<hash>LL after its name.
        if (discriminator && usr.compare(i, 2, "LL") == 0) i += 2;
        if (i >= usr.size()) return false;
        char c = usr[i];
        if (c == 'P') {
            char d = i + 1 < usr.size() ? usr[i + 1] : '\0';
            return isdigit((unsigned char)d) || d == 'A' || (d == 's' && i + 2 < usr.size() && usr[i + 2] == 'E');
        }
        if (c == 'C' || c == 'V' || c == 'O') ++i;
        else if (!isdigit((unsigned char)c)) return false;
    }
    return false;
}

// The name of a Swift protocol from its USR (s:3Fix8HasCountP -> HasCount,
// s:s23CustomStringConvertibleP -> CustomStringConvertible, a private
// s:3Fix4Name33_<hash>LLP -> Name); otherwise the USR itself.
static std::string protocolNameFromUsr(const std::string &usr) {
    if (usr.compare(0, 2, "s:") != 0) return usr;
    size_t i = 2;
    if (i < usr.size() && usr[i] == 's') ++i;  // the standard library
    std::string last;
    while (i < usr.size() && isdigit((unsigned char)usr[i])) {
        size_t n = 0;
        while (i < usr.size() && isdigit((unsigned char)usr[i])) n = n * 10 + (usr[i++] - '0');
        if (n == 0 || i + n > usr.size()) return usr;
        if (usr[i] == '_' && usr.compare(i + n, 2, "LL") == 0) {
            i += n + 2;  // a private declaration's discriminator
            continue;
        }
        last = usr.substr(i, n);
        i += n;
        if (i < usr.size() && (usr[i] == 'C' || usr[i] == 'V' || usr[i] == 'O')) ++i;
    }
    return (i + 1 == usr.size() && usr[i] == 'P' && !last.empty()) ? last : usr;
}

// The USR of the protocol a mangled existential type names
// ($s3Fix3Ext_pD -> s:3Fix3ExtP), or "" when it is not one Swift protocol.
static std::string protocolUsrOfExistential(const std::string &mangled) {
    if (mangled.compare(0, 2, "$s") != 0 || mangled.compare(0, 4, "$sSo") == 0) return "";
    std::string s = mangled.substr(2);
    if (s.size() < 4 || s.compare(s.size() - 3, 3, "_pD") != 0) return "";
    return "s:" + s.substr(0, s.size() - 3) + "P";
}

// An imported Objective-C class type ($sSo8FXWidgetCD).
static bool isObjCClassType(const std::string &mangled) {
    return mangled.compare(0, 4, "$sSo") == 0 && mangled.size() > 6 &&
           mangled.compare(mangled.size() - 2, 2, "CD") == 0;
}

// The name of a type from its mangled form, for the common shapes
// ($sSo8FXWidgetCD -> FXWidget, $s3Fix8FXCallerCD -> FXCaller, AnyObject);
// otherwise the mangled string itself.
static std::string demangleTypeName(const std::string &mangled) {
    std::string s = mangled;
    if (s.compare(0, 2, "$s") == 0) s = s.substr(2);
    if (!s.empty() && s.back() == 'D') s.pop_back();
    if (s == "yXl") return "AnyObject";
    if (s.size() > 1 && s.back() == 'm') {
        // A metatype: the receiver of a class method.
        std::string inner = demangleTypeName("$s" + s.substr(0, s.size() - 1) + "D");
        return inner.compare(0, 2, "$s") == 0 ? mangled : inner + ".Type";
    }
    bool objc = false;
    if (s.compare(0, 2, "So") == 0) {
        objc = true;
        s = s.substr(2);
    }
    std::vector<std::string> ids;
    size_t i = 0;
    while (i < s.size() && isdigit((unsigned char)s[i])) {
        size_t n = 0;
        while (i < s.size() && isdigit((unsigned char)s[i])) n = n * 10 + (s[i++] - '0');
        if (n == 0 || i + n > s.size()) return mangled;
        ids.push_back(s.substr(i, n));
        i += n;
        // Skip a kind letter between nested identifiers (C class, V struct, O enum).
        if (i < s.size() && (s[i] == 'C' || s[i] == 'V' || s[i] == 'O' || s[i] == 'P') && i + 1 < s.size() &&
            isdigit((unsigned char)s[i + 1]))
            ++i;
    }
    if (ids.empty()) return mangled;
    std::string rest = s.substr(i);
    if (rest != "C" && rest != "V" && rest != "O" && rest != "_p" && rest != "a") return mangled;
    size_t first = objc ? 0 : 1;
    if (ids.size() <= first) return ids.back();
    std::string out;
    for (size_t k = first; k < ids.size(); ++k) out += (out.empty() ? "" : ".") + ids[k];
    return out;
}

// --- Selector derivation ------------------------------------------------------
//
// The rules by which Swift infers the Objective-C selector of an @objc
// declaration with no explicit name (the Swift compiler's
// AbstractFunctionDecl::getObjCSelector and its getter and setter forms).

static const char *const kPrepositions[] = {
    "above", "after", "along", "alongside", "as", "at", "before", "below", "by", "following", "for",
    "from", "given", "in", "including", "inside", "into", "matching", "of", "on", "passing",
    "preceding", "since", "to", "until", "using", "via", "when", "with", "within"};

// The first word of a camel-case identifier: "withLabel" -> "with",
// "URLString" -> "URL", "toX" -> "to".
static std::string firstWord(const std::string &s) {
    if (s.empty()) return s;
    size_t i = 1;
    if (isupper((unsigned char)s[0])) {
        // An acronym runs until the last capital before a lowercase letter.
        while (i < s.size() && isupper((unsigned char)s[i])) ++i;
        if (i < s.size() && i > 1 && islower((unsigned char)s[i])) --i;
        if (i == 1)
            while (i < s.size() && !isupper((unsigned char)s[i])) ++i;
        return s.substr(0, i);
    }
    while (i < s.size() && !isupper((unsigned char)s[i])) ++i;
    return s.substr(0, i);
}

static std::string lastWord(const std::string &s) {
    if (s.empty()) return s;
    size_t i = s.size() - 1;
    while (i > 0 && !isupper((unsigned char)s[i])) --i;
    // An acronym at the end: back up over its capitals.
    if (isupper((unsigned char)s[i]) && i + 1 == s.size())
        while (i > 0 && isupper((unsigned char)s[i - 1])) --i;
    return s.substr(i);
}

static bool isPreposition(const std::string &word) {
    std::string w;
    for (char c : word) w += (char)tolower((unsigned char)c);
    return IS_ONE_OF(w, kPrepositions);
}

static std::string sentenceCase(const std::string &s) {
    if (s.empty()) return s;
    std::string r = s;
    r[0] = (char)toupper((unsigned char)r[0]);
    return r;
}

// A method or initializer: base is the Swift base name ("init" for an
// initializer), labels the argument labels ("" for _).
static std::string deriveMethodSelector(const std::string &base, const std::vector<std::string> &labels,
                                        bool throws, bool async) {
    size_t pieces = labels.size() + (throws ? 1 : 0) + (async ? 1 : 0);
    if (pieces == 0) return base;
    if (pieces == 1 && labels.size() == 1 && labels[0].empty()) return base + ":";
    // The completion handler and the error come after the parameters; an
    // async function that throws has only the completion handler.
    std::vector<std::string> out;
    size_t arg = 0;
    size_t asyncIndex = async ? labels.size() : SIZE_MAX;
    size_t errorIndex = (throws && !async) ? labels.size() : SIZE_MAX;
    if (async && throws) pieces = labels.size() + 1;
    for (size_t piece = 0; piece < pieces; ++piece) {
        if (piece > 0) {
            if (piece == asyncIndex) out.push_back("completionHandler");
            else if (piece == errorIndex) out.push_back("error");
            else out.push_back(labels[arg++]);
            continue;
        }
        std::string first = base;
        if (piece == asyncIndex) {
            first += "WithCompletionHandler";
        } else if (piece == errorIndex) {
            first += "AndReturnError";
        } else if (!labels[arg].empty()) {
            const std::string &label = labels[arg++];
            if (!isPreposition(firstWord(label)) && !isPreposition(lastWord(base))) first += "With";
            first += sentenceCase(label);
        } else {
            ++arg;
        }
        out.push_back(first);
    }
    std::string sel;
    for (auto &p : out) sel += p + ":";
    return sel;
}

static std::string deriveGetter(const std::string &name) { return name; }
static std::string deriveSetter(const std::string &name) { return "set" + sentenceCase(name) + ":"; }

// --- Rows -------------------------------------------------------------------

struct Ref {
    std::string file;
    long line = 0, col = 0;
    std::string kind;
    std::string usr;
    std::string selector;  // empty: NULL
    std::string property;
    std::string className;
    std::string containerKind;
    bool isClassMember = false;
    std::string access;
    std::string selectorKind;
    bool implicit = false;
    std::string enclosingUsr, enclosingName;
    bool inClosure = false, inMacro = false;
    std::string receiverType;
    bool inScope = false;
    // The lvalue chain it is in accesses a part of it (see kLvalueChain).
    bool partOfLvalue = false;
    std::string valueType;  // the mangled type of the property's value
    // It is the base of a member declared in a protocol or a protocol
    // extension (see resolvePending).
    bool baseOfProtocolMember = false;
};

// A clause of a #if in the source text: its content is [start, end) in
// bytes, startLine..endLine in lines.
struct Clause {
    long start = 0, end = 0, startLine = 0, endLine = 0;
    bool active = false;   // a node of the dump starts inside it
    bool hasCode = false;  // a line in it is not blank or a // comment
};

// A row of swift_protocol.
struct ProtocolRow {
    std::string kind, protocolUsr, member, className, file;
    long line = 0;
};

struct Decl {
    std::string usr, selector, derived, source, swiftName, className, kind, file, access, overridesUsr,
        propertyUsr;
    long line = 0;
    bool isClassMember = false, isPrivate = false, derivedFlag = false, explicitName = false, isOverride = false,
         implicit = false, inScope = false;
};

// --- The handler ------------------------------------------------------------

struct Frame {
    bool object = false;
    std::string key;
    std::string kind;
    std::string usr;
    std::string declUsr;      // decl_usr of a decl_ref
    std::string baseName;     // base_name of a decl_ref, or name of a base_name node
    std::string type;
    std::string access;
    std::string selectorKind;
    std::string objcName;     // name of an objc_attr
    bool objcNameImplicit = false;
    bool isObjC = false, isStatic = false, implicit = false, isGet = false, isSet = false;
    bool hasForeignError = false, hasForeignAsync = false, isOverride = false, objcAttr = false;
    bool keypathObjC = false;
    long start = -1, end = -1;
    bool skip = false;
    bool inMacro = false;
    long macroStart = -1;
    // A reference node: the decl_ref child's USR and name.
    std::string refUsr, refName;
    // A declaration: its name and argument labels.
    std::string declName;
    std::vector<std::string> labels;
    std::string extendedType;
    std::string superclassType;  // of a class_decl, from its inheritance node
    std::string apiName;
    bool hasApiName = false;
    // dot_syntax_call_expr: the receiver's type, from its implicit argument.
    std::string receiverType;
    std::vector<Ref> pendingCall;  // refs waiting for the receiver type
    // Property refs waiting for the access of the lvalue chain they are in.
    std::vector<Ref> pendingAccess;
    // The keys of the arrays open in this object (an element object's key is
    // its array's key; arrays hold no frames of their own).
    std::vector<std::string> arrays;
    // normal_conformance: its protocol. extension_decl: the Swift protocols
    // it conforms to, and the names of the members it declares.
    std::string protocolUsr;
    std::vector<std::string> conformances, memberNames;
};

struct Options {
    std::string db, root, module, target, cmdDigest, fileListDigest, filesPath, inputsPath, compilerVersion,
        stderrFile;
    bool acceptCompilerVersion = false;
    // Bare regex literals (/.../) are enabled: --bare-slash-regex, or the
    // compiler command has -enable-bare-slash-regex, the upcoming feature
    // BareSlashRegexLiterals, or -swift-version 6.
    bool bareSlashRegex = false;
    std::vector<std::string> scopes;
    std::vector<std::string> command;
};

static bool startsWith(const std::string &s, const std::string &p) { return s.compare(0, p.size(), p) == 0; }

struct Handler : BaseReaderHandler<UTF8<>, Handler> {
    const Options &opt;
    std::vector<Frame> st;
    std::string key;
    std::string failure;  // set: stop and fail the module
    // The current document.
    std::string file;          // stored path
    bool fileRecorded = false; // inside the repository and not generated
    std::vector<long> nl;
    std::vector<Clause> clauses;  // the current document's #if clauses
    // The lexer could not account for a line beginning with #if in the
    // current document: its inactive regions are not determined.
    bool undetermined = false;
    const bool bareSlashRegex;
    long undeterminedFiles = 0;
    std::string text;          // the source, for its digest
    size_t textSize = 0;
    std::map<std::string, std::string> expectedDigest;  // stored path -> digest
    std::set<std::string> expected;                     // absolute paths
    std::set<std::string> seen;
    std::map<std::string, std::string> storedFor;       // absolute -> stored
    long documents = 0, skippedDocuments = 0, unresolved = 0;
    // Node kinds in none of dump_format.h's tables, and the parents (kind.key)
    // that left a property access unknown, with their counts.
    std::set<std::string> knownKinds;
    std::map<std::string, long> unknownKinds, unknownAccess;
    long unknownAccessRows = 0;
    std::string docMajor, docMinor, docFull;
    std::vector<Ref> refs;
    std::vector<Decl> decls;
    std::vector<ProtocolRow> protocolRows;
    sqlite3 *db = nullptr;
    sqlite3_stmt *refStmt = nullptr, *declStmt = nullptr, *inactiveStmt = nullptr, *protocolStmt = nullptr;
    long long unitId = 0;
    long refCount = 0, declCount = 0;

    explicit Handler(const Options &o) : opt(o), bareSlashRegex(o.bareSlashRegex) {
        for (const char *k : dump::kHandledKinds) knownKinds.insert(k);
        for (const char *k : dump::kTypeDecls) knownKinds.insert(k);
        for (const char *k : dump::kLvalueChain) knownKinds.insert(k);
        for (const char *k : dump::kLvalueIdentity) knownKinds.insert(k);
        for (const char *k : dump::kRvalueContexts) knownKinds.insert(k);
        for (const char *k : dump::kIgnoredKinds) knownKinds.insert(k);
    }

    bool fail(const std::string &why) {
        if (failure.empty()) failure = why;
        return false;
    }

    std::string stored(const std::string &abs) const {
        auto it = storedFor.find(abs);
        if (it != storedFor.end()) return it->second;
        return abs;
    }

    bool inScope(const std::string &path) const {
        for (auto &d : opt.scopes)
            if (startsWith(path, d)) return true;
        return false;
    }

    bool beginFile(const std::string &path) {
        file.clear();
        nl.clear();
        if (!expected.count(path)) return fail("document for a file that is not in the module's file list: " + path);
        if (seen.count(path)) return fail("two documents for " + path);
        seen.insert(path);
        file = stored(path);
        fileRecorded = !(file.empty() || file[0] == '/' || startsWith(file, "Build/"));
        // Read the source for its line starts, and check that it is the
        // content whose digest codedb.py recorded before the compiler ran.
        FILE *f = fopen(path.c_str(), "rb");
        if (!f) return fail("cannot read " + path);
        text.clear();
        char buf[1 << 16];
        size_t n;
        while ((n = fread(buf, 1, sizeof buf, f)) > 0) text.append(buf, n);
        fclose(f);
        for (size_t i = 0; i < text.size(); ++i)
            if (text[i] == '\n') nl.push_back((long)i);
        auto d = expectedDigest.find(file);
        if (d != expectedDigest.end() && d->second != sha256Hex(text))
            return fail("source file changed while the module was read: " + path);
        findClauses();
        textSize = text.size();
        text.clear();
        text.shrink_to_fit();
        return true;
    }

    // --- The #if clauses of the source text ----------------------------------
    //
    // A lexer finds the lines that begin in code (not inside a comment, a
    // string literal or a regex literal): a directive (#if, #elseif, #else,
    // #endif) is recognized only at the start of such a line. It knows line
    // comments, nested block comments, string literals with escapes and
    // interpolations (which hold code: strings, comments and parentheses),
    // multi-line and raw strings (#"..."#, #"""..."""#, any number of #),
    // extended regex literals (#/.../#) and, when the module enables them,
    // bare regex literals (/.../), whose start a lexer cannot always tell
    // from a division. A comment or multi-line string that opens on a line
    // after a bare slash is uncertain: if a line beginning with #if is inside
    // one, the lexer cannot account for it, and the file's inactive regions
    // are not determined (the whole file is recorded instead; see flush).

    // A context the lexer is in, innermost last.
    struct LexContext {
        enum Kind { Comment, String, Regex, Interpolation } kind;
        bool multiLine = false;
        int hashes = 0;   // of a raw string or extended regex
        int depth = 0;    // nesting of a comment; open parentheses of an interpolation
        bool uncertain = false;
    };

    static bool isIdentChar(char c) { return isalnum((unsigned char)c) || c == '_' || (unsigned char)c >= 0x80; }

    // A bare slash at i starts a regex literal: it is followed by a non-blank
    // character and a closing slash on the same line, and stands where an
    // operand starts (not after an identifier other than a keyword, a
    // literal, or a closing bracket). Returns the offset after the literal,
    // or 0.
    size_t bareRegexEnd(size_t i, size_t lineStart) const {
        static const char *const kKeywords[] = {"return", "case", "in", "where", "try", "await", "throw", "if",
                                                "guard", "while", "else", "repeat", "yield", "is", "as", "switch",
                                                "do", "for", "let", "var", "some", "any"};
        if (i + 1 >= text.size() || text[i + 1] == ' ' || text[i + 1] == '\t' || text[i + 1] == '\n') return 0;
        size_t j = i + 1;
        for (; j < text.size() && text[j] != '\n'; ++j) {
            if (text[j] == '\\') ++j;
            else if (text[j] == '/') break;
        }
        if (j >= text.size() || text[j] != '/') return 0;
        size_t p = i;
        while (p > lineStart && (text[p - 1] == ' ' || text[p - 1] == '\t')) --p;
        if (p > lineStart) {
            char c = text[p - 1];
            if (isIdentChar(c)) {
                size_t s = p - 1;
                while (s > lineStart && isIdentChar(text[s - 1])) --s;
                if (!IS_ONE_OF(text.substr(s, p - s), kKeywords)) return 0;
            } else if (c == ')' || c == ']' || c == '}' || c == '"') {
                return 0;
            } else if ((c == '!' || c == '?') && p - 1 > lineStart &&
                       (isIdentChar(text[p - 2]) || text[p - 2] == ')' || text[p - 2] == ']')) {
                return 0;  // a postfix ! or ?: x! / 2
            }
        }
        return j + 1;
    }

    // The number of # at i.
    int hashesAt(size_t i) const {
        int n = 0;
        while (i + n < text.size() && text[i + n] == '#') ++n;
        return n;
    }
    bool hashesFollow(size_t i, int n) const {
        if (i + n > text.size()) return false;
        for (int k = 0; k < n; ++k)
            if (text[i + k] != '#') return false;
        return true;
    }

    // Lexes one line, [pos, eol] (eol is its newline or the end), updating
    // the context stack.
    void lexLine(size_t pos, size_t eol, std::vector<LexContext> &stack) {
        bool sawBareSlash = false;
        auto uncertainHere = [&]() {
            if (sawBareSlash) return true;
            for (auto &c : stack)
                if (c.uncertain) return true;
            return false;
        };
        size_t i = pos;
        while (i <= eol && i < text.size()) {
            char c = text[i];
            if (c == '\n') {
                // A single-line string or regex does not go past its line
                // (unterminated: an error the compiler reports).
                while (!stack.empty() && !stack.back().multiLine &&
                       (stack.back().kind == LexContext::String || stack.back().kind == LexContext::Regex)) {
                    stack.pop_back();
                    // Inside it, an interpolation is closed with it.
                    while (!stack.empty() && stack.back().kind == LexContext::Interpolation) stack.pop_back();
                }
                return;
            }
            LexContext *top = stack.empty() ? nullptr : &stack.back();
            if (top && top->kind == LexContext::Comment) {
                if (text.compare(i, 2, "/*") == 0) {
                    ++top->depth;
                    i += 2;
                } else if (text.compare(i, 2, "*/") == 0) {
                    if (--top->depth == 0) stack.pop_back();
                    i += 2;
                } else {
                    ++i;
                }
                continue;
            }
            if (top && top->kind == LexContext::Regex) {
                if (c == '\\') {
                    i += 2;
                } else if (c == '/' && hashesFollow(i + 1, top->hashes)) {
                    i += 1 + top->hashes;
                    stack.pop_back();
                } else {
                    ++i;
                }
                continue;
            }
            if (top && top->kind == LexContext::String) {
                if (c == '\\' && hashesFollow(i + 1, top->hashes)) {
                    size_t k = i + 1 + top->hashes;
                    if (k < text.size() && text[k] == '(') {
                        LexContext in;
                        in.kind = LexContext::Interpolation;
                        in.uncertain = top->uncertain;
                        stack.push_back(in);
                        i = k + 1;
                    } else {
                        // An escaped character (not a newline: a multi-line
                        // string's \ at the end of a line joins the lines).
                        i = (k < text.size() && text[k] != '\n') ? k + 1 : k;
                    }
                } else if (c == '"' && top->multiLine && text.compare(i, 3, "\"\"\"") == 0 &&
                           hashesFollow(i + 3, top->hashes)) {
                    i += 3 + top->hashes;
                    stack.pop_back();
                } else if (c == '"' && !top->multiLine && hashesFollow(i + 1, top->hashes)) {
                    i += 1 + top->hashes;
                    stack.pop_back();
                } else {
                    ++i;
                }
                continue;
            }
            // Code: at the top level or in an interpolation.
            if (text.compare(i, 2, "//") == 0) {
                i = eol;  // to the newline
                continue;
            }
            if (text.compare(i, 2, "/*") == 0) {
                LexContext cm;
                cm.kind = LexContext::Comment;
                cm.depth = 1;
                cm.multiLine = true;
                cm.uncertain = uncertainHere();
                stack.push_back(cm);
                i += 2;
                continue;
            }
            if (c == '#' || c == '"') {
                int n = c == '#' ? hashesAt(i) : 0;
                size_t k = i + n;
                if (k < text.size() && text[k] == '"') {
                    LexContext s;
                    s.kind = LexContext::String;
                    s.hashes = n;
                    s.multiLine = text.compare(k, 3, "\"\"\"") == 0;
                    s.uncertain = uncertainHere();
                    stack.push_back(s);
                    i = k + (s.multiLine ? 3 : 1);
                    continue;
                }
                if (n > 0 && k < text.size() && text[k] == '/') {
                    // An extended regex literal; multi-line when #/ ends the line.
                    LexContext r;
                    r.kind = LexContext::Regex;
                    r.hashes = n;
                    r.multiLine = k + 1 < text.size() && text[k + 1] == '\n';
                    r.uncertain = uncertainHere();
                    stack.push_back(r);
                    i = k + 1;
                    continue;
                }
                i = k > i ? k : i + 1;
                continue;
            }
            if (c == '/' && bareSlashRegex) {
                sawBareSlash = true;
                size_t end = bareRegexEnd(i, pos);
                i = end ? end : i + 1;
                continue;
            }
            if (top && top->kind == LexContext::Interpolation) {
                if (c == '(') {
                    ++top->depth;
                } else if (c == ')') {
                    if (top->depth-- == 0) stack.pop_back();
                }
            }
            ++i;
        }
    }

    // The #if clauses of the source text, and whether they could be
    // determined (see above).
    void findClauses() {
        clauses.clear();
        undetermined = false;
        std::vector<size_t> open;  // indexes of the clauses being read, outermost first
        std::vector<LexContext> stack;
        long plainIfs = 0, directiveIfs = 0, accountedIfs = 0;
        size_t pos = 0;
        for (long line = 1; pos < text.size(); ++line) {
            size_t eol = text.find('\n', pos);
            if (eol == std::string::npos) eol = text.size();
            std::string l = text.substr(pos, eol - pos);
            size_t first = l.find_first_not_of(" \t\r");
            std::string t = first == std::string::npos ? "" : l.substr(first);
            auto word = [&](const char *w) {
                size_t n = strlen(w);
                return t.compare(0, n, w) == 0 && (t.size() == n || !(isalnum((unsigned char)t[n]) || t[n] == '_'));
            };
            long next = (long)eol + 1;
            bool inCode = stack.empty();
            bool inString = !inCode, inComment = false;
            // The cross-check: lines that begin with #if, by a plain scan;
            // the lexer's directives; and those inside a comment or string
            // whose start the lexer is sure of.
            if (word("#if")) {
                ++plainIfs;
                if (inCode) {
                    ++directiveIfs;
                } else {
                    bool sure = true;
                    for (auto &c : stack) sure = sure && !c.uncertain;
                    if (sure) ++accountedIfs;
                }
            }
            bool directive = inCode && !t.empty() && t[0] == '#';
            if (directive && word("#if")) {
                Clause c;
                c.start = next;
                c.startLine = line + 1;
                for (size_t i : open) clauses[i].hasCode = true;
                clauses.push_back(c);
                open.push_back(clauses.size() - 1);
            } else if (directive && (word("#elseif") || word("#else")) && !open.empty()) {
                Clause &c = clauses[open.back()];
                c.end = (long)pos;
                c.endLine = line - 1;
                Clause n;
                n.start = next;
                n.startLine = line + 1;
                clauses.push_back(n);
                open.back() = clauses.size() - 1;
            } else if (directive && word("#endif") && !open.empty()) {
                Clause &c = clauses[open.back()];
                c.end = (long)pos;
                c.endLine = line - 1;
                open.pop_back();
            } else if (!inString && !inComment && !t.empty() && t.compare(0, 2, "//") != 0) {
                for (size_t i : open) clauses[i].hasCode = true;
            }
            lexLine(pos, eol, stack);
            pos = eol + 1;
        }
        // A #if with no #endif (malformed source): its clause ends with the file.
        for (size_t i : open) {
            clauses[i].end = (long)text.size();
            clauses[i].endLine = (long)nl.size() + 1;
        }
        if (directiveIfs < plainIfs - accountedIfs) undetermined = true;
    }

    // A node of the dump starts at off: the clauses it is in are active.
    void markActive(long off) {
        for (auto &c : clauses)
            if (off >= c.start && off < c.end) c.active = true;
    }

    void lineCol(long off, long &line, long &col) const {
        auto it = std::lower_bound(nl.begin(), nl.end(), off);
        long idx = it - nl.begin();
        line = idx + 1;
        col = off - (idx ? nl[idx - 1] + 1 : 0) + 1;
    }

    // --- tree helpers -----------------------------------------------------

    static bool isDeclKind(const std::string &k) {
        return k == dump::kFuncDecl || k == dump::kAccessorDecl || k == dump::kConstructorDecl ||
               k == dump::kDestructorDecl || k == dump::kVarDecl || k == dump::kSubscriptDecl ||
               IS_ONE_OF(k, dump::kTypeDecls);
    }
    // A function the compiler makes of a body written in the source (a
    // defer block: "$defer"): neither written by the compiler nor a
    // declaration of its own.
    static bool isBodyClosure(const Frame &f) { return f.kind == dump::kFuncDecl && !f.declName.empty() && f.declName[0] == '$'; }
    static bool isFunctionLike(const std::string &k) {
        return k == dump::kFuncDecl || k == dump::kAccessorDecl || k == dump::kConstructorDecl ||
               k == dump::kDestructorDecl || k == dump::kVarDecl || k == dump::kSubscriptDecl;
    }

    std::string typeNameOf(const Frame &f) const {
        if (f.kind == dump::kExtensionDecl) return demangleTypeName(f.extendedType);
        ObjCUsr u = parseObjCUsr(f.usr);
        if (u.ok && u.memberKind.empty()) return u.container;
        return f.declName;
    }

    // The name of a function-like declaration, with its labels.
    static std::string functionName(const Frame &f) {
        if (f.kind == dump::kVarDecl || f.kind == dump::kSubscriptDecl) return f.kind == dump::kSubscriptDecl ? "subscript" : f.declName;
        std::string n = f.kind == dump::kConstructorDecl ? "init" : f.kind == dump::kDestructorDecl ? "deinit" : f.declName;
        n += "(";
        for (auto &l : f.labels) n += (l.empty() ? "_" : l) + ":";
        return n + ")";
    }

    // The enclosing declaration of the frame at index top (exclusive).
    void enclosing(size_t top, std::string &usr, std::string &name) const {
        usr.clear();
        name.clear();
        long fn = -1, ty = -1;
        for (long i = (long)top - 1; i >= 0; --i) {
            const Frame &f = st[(size_t)i];
            if (fn < 0 && isFunctionLike(f.kind) && f.kind != dump::kAccessorDecl && !isBodyClosure(f)) fn = i;
            if (fn < 0 && f.kind == dump::kAccessorDecl) {
                // Attribute to the property or subscript the accessor belongs to.
                continue;
            }
            if (ty < 0 && IS_ONE_OF(f.kind, dump::kTypeDecls)) ty = i;
            if (fn >= 0 && ty >= 0) break;
        }
        std::string typeName = ty >= 0 ? typeNameOf(st[(size_t)ty]) : "";
        if (fn >= 0) {
            usr = st[(size_t)fn].usr;
            name = (typeName.empty() ? "" : typeName + ".") + functionName(st[(size_t)fn]);
        } else if (ty >= 0) {
            usr = st[(size_t)ty].usr;
            name = typeName;
        }
    }

    bool inClosure(size_t top) const {
        for (size_t i = 0; i < top; ++i)
            if (st[i].kind == dump::kClosureExpr) return true;
        return false;
    }

    long offsetFor(const Frame &f, bool useEnd, size_t top) const {
        if (f.inMacro) return f.macroStart;
        long off = useEnd && f.end >= 0 ? f.end : f.start;
        for (long i = (long)top - 1; off < 0 && i >= 0; --i) off = st[(size_t)i].start;
        return off;
    }

    // --- SAX callbacks ----------------------------------------------------

    void push() {
        Frame f;
        f.object = true;
        if (key.empty() && !st.empty() && !st.back().arrays.empty()) key = st.back().arrays.back();
        f.key = key;
        if (!st.empty()) {
            const Frame &p = st.back();
            f.skip = p.skip || IS_ONE_OF(key, dump::kSkipKeys) ||
                     (p.kind == dump::kObjCSelectorExpr && key == dump::kKeySubExpr);
            f.inMacro = p.inMacro;
            f.macroStart = p.macroStart;
            if (key == dump::kKeyRewritten) {
                f.inMacro = true;
                f.macroStart = p.start;
            }
        }
        st.push_back(f);
        key.clear();
    }

    bool StartObject() {
        if (!failure.empty()) return false;
        push();
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
        Frame &f = st.back();
        if (key == dump::kKeyForeignError) f.hasForeignError = true;
        if (key == dump::kKeyForeignAsync) f.hasForeignAsync = true;
        return true;
    }
    bool String(const char *s, SizeType n, bool) {
        if (!failure.empty()) return false;
        Frame &f = st.back();
        if (!f.object) {
            key.clear();
            return true;
        }
        std::string v(s, n);
        if (key == dump::kKind) {
            f.kind = v;
            if (!f.skip && !knownKinds.count(v)) ++unknownKinds[v];
        } else if (key == dump::kUsr) {
            f.usr = v;
        } else if (key == dump::kDeclUsr) {
            f.declUsr = v;
        } else if (key == dump::kBaseNameField && f.kind == dump::kDeclRef) {
            f.baseName = v;
        } else if (key == dump::kName && f.kind == dump::kBaseName) {
            f.baseName = v;
        } else if (key == dump::kName && f.kind == dump::kObjCAttr) {
            f.objcName = v;
        } else if (key == dump::kType) {
            f.type = v;
        } else if (key == dump::kAccess) {
            f.access = v;
        } else if (key == dump::kSelectorKind && f.kind == dump::kObjCSelectorExpr) {
            f.selectorKind = v;
        } else if (key == dump::kApiName && f.kind == dump::kParameter) {
            f.apiName = v;
            f.hasApiName = true;
        } else if (key == dump::kExtendedType) {
            f.extendedType = v;
        } else if (key == dump::kSuperclassType) {
            f.superclassType = v;
        } else if (key == dump::kProtocolField && f.kind == dump::kNormalConformance) {
            f.protocolUsr = v;
        } else if (key == dump::kFilename && f.kind == dump::kSourceFile && st.size() == 1) {
            if (!beginFile(v)) return false;
        } else if (st.size() == 2 && st[1].key == dump::kKeyCompilerVersion) {
            if (key == dump::kMajor) docMajor = v;
            else if (key == dump::kMinor) docMinor = v;
            else if (key == dump::kFull) {
                docFull = v;
                if (!checkVersion()) return false;
            }
        }
        key.clear();
        return true;
    }
    bool checkVersion() {
        std::string mm = docMajor + "." + docMinor;
        if (!opt.compilerVersion.empty() && docFull != opt.compilerVersion)
            return fail("the dump is from \"" + docFull + "\", not the compiler codedb.py recorded (\"" +
                        opt.compilerVersion + "\")");
        if (mm != dump::kWrittenAgainst && !opt.acceptCompilerVersion)
            return fail("the dump is from Swift " + mm + "; this reader was written against the dump format of " +
                        std::string(dump::kWrittenAgainst) +
                        " (pass --accept-compiler-version to read it anyway; to check the reader against this "
                        "compiler, regenerate the fixture dump with tests/swift_fixture/make_dump.py and run "
                        "tests/test_codedb_swift.py)");
        return true;
    }
    bool Bool(bool b) {
        Frame &f = st.back();
        if (f.object) {
            if (key == dump::kObjCFlag) f.isObjC = b;
            else if (key == dump::kStatic) f.isStatic = b;
            else if (key == dump::kImplicit) f.implicit = b;
            else if (key == dump::kGet) f.isGet = b;
            else if (key == dump::kSet) f.isSet = b;
            else if (key == dump::kIsNameImplicit) f.objcNameImplicit = b;
            else if (key == dump::kKeyPathObjC && f.kind == dump::kKeyPathExpr) f.keypathObjC = b;
        }
        key.clear();
        return true;
    }
    bool num(long v) {
        Frame &f = st.back();
        if (f.object && f.key == dump::kRange && st.size() >= 2) {
            if (key == dump::kStart) {
                st[st.size() - 2].start = v;
                // Offsets in a macro's expansion are not offsets in the file.
                if (!st[st.size() - 2].inMacro && !clauses.empty()) markActive(v);
            }
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

    // --- references -------------------------------------------------------

    Ref makeRef(const Frame &f, const std::string &kind, const std::string &usr, bool useEnd) {
        Ref r;
        long off = offsetFor(f, useEnd, st.size());
        if (off >= 0) lineCol(off, r.line, r.col);
        r.file = file;
        r.kind = kind;
        r.usr = usr;
        ObjCUsr u = parseObjCUsr(usr);
        if (u.ok) {
            r.className = u.container;
            r.containerKind = u.containerKind == "cs" ? "class" : u.containerKind == "pl" ? "protocol"
                                                                                           : u.containerKind;
            r.isClassMember = u.memberKind == "cm" || u.memberKind == "cpy";
            if (u.memberKind == "im" || u.memberKind == "cm") r.selector = u.member;
            else if (u.memberKind == "py" || u.memberKind == "cpy") r.property = u.member;
        }
        // Written by the compiler: inside a declaration the compiler wrote (an
        // inherited initializer and its call of super.init).
        for (auto &a : st)
            if (isFunctionLike(a.kind) && a.implicit && !isBodyClosure(a)) r.implicit = true;
        enclosing(st.size(), r.enclosingUsr, r.enclosingName);
        r.inClosure = inClosure(st.size());
        r.inMacro = f.inMacro;
        r.inScope = inScope(file);
        return r;
    }

    void emit(Ref &r) {
        if (!fileRecorded) return;
        refs.push_back(std::move(r));
    }

    // Inside an accessor the compiler wrote for a stored property: its body
    // reads and writes the storage directly, and nothing in it is written
    // in the source.
    bool inImplicitAccessor() const {
        for (auto &f : st)
            if (f.kind == dump::kAccessorDecl && f.implicit) return true;
        return false;
    }

    // The access of a property reference (or of the lvalue chain holding
    // it) in the frame f, given its parent p: get, set, getset; "" when it
    // passes through an lvalue chain and the access is decided further up;
    // "unknown" when p is of a kind the reader does not classify, with
    // *cause set to KIND.KEY: such a node may write what it holds (as
    // abi_safe_conversion_expr does around an assignment's target), so the
    // reference may be read, written or both.
    static std::string accessIn(const Frame &f, const Frame &p, std::string *cause) {
        if (p.kind == dump::kLoadExpr) return "get";
        if (p.kind == dump::kAssignExpr && f.key == dump::kKeyDest) return "set";
        if (p.kind == dump::kAssignExpr && f.key == dump::kKeySrc) return "get";
        // The compiler puts the base of a subscript in an implicit inout_expr
        // whether the element is read or written (let e = w.names[0]): the
        // access is the subscript's, decided further up.
        if (p.kind == dump::kInOutExpr && p.implicit && p.key == dump::kKeyBase) return "";
        if (p.kind == dump::kInOutExpr) return "getset";
        // The existential a member is looked up on (w.delegate.ping()): read.
        // Only a mutating member writes it, and the existentials of the
        // properties recorded here are class-bound or Any, which have none.
        if (p.kind == dump::kOpenExistentialExpr && f.key == dump::kKeyExistentialValue) return "get";
        if ((IS_ONE_OF(p.kind, dump::kLvalueChain) || IS_ONE_OF(p.kind, dump::kLvalueIdentity)) &&
            (f.key == dump::kKeyBase || f.key == dump::kKeySubExpr || p.kind == dump::kTupleExpr))
            return "";
        // A node that takes only rvalues: what it holds can only be read.
        if (IS_ONE_OF(p.kind, dump::kRvalueContexts)) return "get";
        if (cause) *cause = p.kind + "." + f.key;
        return "unknown";
    }

    // Sets the access of a property reference and writes it.
    void settle(Ref &r, const std::string &access, const std::string &cause) {
        r.access = access;
        if (access == "unknown" && fileRecorded) {
            ++unknownAccess[cause];
            ++unknownAccessRows;
        }
        emit(r);
    }

    static std::string combine(const std::string &outer, bool part) {
        // A part of an lvalue that is written is read and written.
        if (part && outer == "set") return "getset";
        return outer;
    }

    void resolvePending(Frame &f) {
        // f has ended; settle the access of the property refs waiting in it.
        if (f.pendingAccess.empty()) return;
        if (st.empty()) {
            for (auto &r : f.pendingAccess) settle(r, "unknown", "(document)");
            f.pendingAccess.clear();
            return;
        }
        Frame &p = st.back();
        if (f.kind == dump::kMemberRefExpr || f.kind == dump::kDynamicMemberRefExpr ||
            f.kind == dump::kSubscriptExpr || f.kind == dump::kDynamicSubscriptExpr) {
            // A member of an object: its base is an object reference, which
            // is read whatever is done to the member (w.peer.count = 1
            // reads w.peer and writes count). The base is an object when
            // the member is an Objective-C one or the base's type is a
            // reference type.
            //
            // Except when the member is declared in a protocol or a protocol
            // extension: if the protocol is not class-bound, its setters and
            // mutating methods take the object reference inout, and the
            // compiler writes it back (w.peer!.extv = 1 calls setPeer:). The
            // dump does not say whether the protocol is class-bound, so such
            // a base is left to the access of the member: read when the
            // member is read, unknown when it is written.
            ObjCUsr member = parseObjCUsr(f.refUsr);
            bool objectMember = member.ok && isMemberKind(member.memberKind);
            bool protocolMember = !objectMember && isSwiftProtocolMember(f.refUsr);
            // The pointee of an unsafe pointer: what is done to it is done
            // to the memory the pointer points to; the pointer, the value
            // of the property, is read (w.csi.pointee.count = 2).
            bool pointee = f.refName == "pointee" && (startsWith(f.refUsr, "s:Sp") || startsWith(f.refUsr, "s:SP"));
            std::vector<Ref> rest;
            for (auto &r : f.pendingAccess) {
                if (pointee && (startsWith(r.valueType, "$sSp") || startsWith(r.valueType, "$sSP"))) {
                    settle(r, "get", "");
                } else if ((protocolMember || r.baseOfProtocolMember) && isReferenceType(r.valueType)) {
                    r.baseOfProtocolMember = true;
                    rest.push_back(std::move(r));
                } else if (objectMember || isReferenceType(r.valueType)) {
                    settle(r, "get", "");
                } else {
                    rest.push_back(std::move(r));
                }
            }
            f.pendingAccess.swap(rest);
        }
        if (IS_ONE_OF(f.kind, dump::kLvalueChain))
            for (auto &r : f.pendingAccess) r.partOfLvalue = true;
        std::string cause;
        std::string a = accessIn(f, p, &cause);
        if (a.empty()) {
            for (auto &r : f.pendingAccess) p.pendingAccess.push_back(std::move(r));
        } else {
            for (auto &r : f.pendingAccess) {
                std::string access = combine(a, r.partOfLvalue);
                if (r.baseOfProtocolMember && access != "get" && access != "unknown")
                    settle(r, "unknown", "write_through_protocol_member");
                else
                    settle(r, access, cause);
            }
        }
        f.pendingAccess.clear();
    }

    void referenceEnded(Frame &f) {
        const std::string &k = f.kind;
        if (inImplicitAccessor()) return;
        Frame *p = st.empty() ? nullptr : &st.back();
        if (k == dump::kObjCSelectorExpr) {
            if (f.refUsr.empty()) return;
            Ref r = makeRef(f, "selector-expr", f.refUsr, false);
            r.selectorKind = f.selectorKind.empty() ? dump::kSelectorMethod : f.selectorKind;
            emit(r);
            return;
        }
        if (k == dump::kKeyPathMember) {
            // A key path component; its position is the key path's.
            ObjCUsr u = parseObjCUsr(f.refUsr);
            if (!u.ok || !isMemberKind(u.memberKind)) return;
            Ref r = makeRef(f, "keypath", f.refUsr, false);
            if (f.type.empty()) {
                ++unresolved;
                return;
            }
            emit(r);
            return;
        }
        bool refKind = k == dump::kDeclRefExpr || k == dump::kMemberRefExpr || k == dump::kDynamicMemberRefExpr ||
                       k == dump::kOtherConstructorRefExpr || k == dump::kSubscriptExpr ||
                       k == dump::kDynamicSubscriptExpr;
        if (!refKind || f.refUsr.empty()) return;
        ObjCUsr u = parseObjCUsr(f.refUsr);
        if (!u.ok || !isMemberKind(u.memberKind)) return;
        if (f.type.empty()) {
            ++unresolved;
            return;
        }
        bool member = k == dump::kMemberRefExpr || k == dump::kDynamicMemberRefExpr;
        std::string kind;
        bool property = u.memberKind == "py" || u.memberKind == "cpy";
        if (k == dump::kDynamicMemberRefExpr || k == dump::kDynamicSubscriptExpr) kind = "dynamic";
        else if (property) kind = "property";
        else if (k == dump::kOtherConstructorRefExpr || f.refName == "init") kind = "init";
        else kind = "call";
        Ref r = makeRef(f, kind, f.refUsr, member);
        if (property) {
            r.valueType = f.type;
            // Settled when its context is known (see resolvePending).
            if (!p) {
                settle(r, "unknown", "(document)");
                return;
            }
            std::string cause;
            std::string a = accessIn(f, *p, &cause);
            if (a.empty()) p->pendingAccess.push_back(std::move(r));
            else settle(r, a, cause);
            return;
        }
        // The call whose receiver this is: the nearest dot_syntax_call_expr
        // or constructor_ref_call_expr reached through its fn, past
        // conversions (sub_expr).
        std::string childKey = f.key;
        for (long i = (long)st.size() - 1, steps = 0; i >= 0 && steps < 6; --i, ++steps) {
            Frame &a = st[(size_t)i];
            if ((a.kind == dump::kDotSyntaxCallExpr || a.kind == dump::kConstructorRefCallExpr) &&
                childKey == dump::kKeyFn) {
                a.pendingCall.push_back(std::move(r));
                return;
            }
            if (childKey != dump::kKeySubExpr) break;
            childKey = a.key;
        }
        emit(r);
    }

    // --- declarations -------------------------------------------------------

    void declarationEnded(Frame &f) {
        const std::string &k = f.kind;
        // A subscript is visible through its getter and setter only.
        if (!(k == dump::kFuncDecl || k == dump::kConstructorDecl || k == dump::kDestructorDecl ||
              k == dump::kVarDecl || k == dump::kAccessorDecl))
            return;
        if (f.usr.empty()) return;
        // The deinit the compiler declares for a class that has none adds no
        // -dealloc to it (the class's method list has none; the object's
        // stored properties are released by .cxx_destruct): not a
        // definition that a send of dealloc reaches.
        if (k == dump::kDestructorDecl && f.implicit) return;
        ObjCUsr u = parseObjCUsr(f.usr);
        bool objcUsr = u.ok && isMemberKind(u.memberKind);
        // A storage declaration of an accessor (var or subscript), if any.
        const Frame *storage = nullptr;
        if (k == dump::kAccessorDecl && st.size() >= 1) {
            const Frame &p = st.back();
            if ((p.kind == dump::kVarDecl || p.kind == dump::kSubscriptDecl)) storage = &p;
        }
        bool visible = objcUsr || f.isObjC || (storage && (storage->isObjC || parseObjCUsr(storage->usr).ok));
        if (!visible) return;
        if (k == dump::kAccessorDecl && !f.isGet && !f.isSet) return;  // _modify and others
        if (k == dump::kVarDecl && !st.empty() && !IS_ONE_OF(st.back().kind, dump::kTypeDecls)) return;
        if (!fileRecorded) return;
        Decl d;
        d.usr = f.usr;
        d.file = file;
        long off = f.start;
        if (off < 0 && storage) off = storage->start;
        for (long i = (long)st.size() - 1; off < 0 && i >= 0; --i) off = st[(size_t)i].start;
        long col = 0;
        if (off >= 0) lineCol(off, d.line, col);
        d.access = f.access.empty() && storage ? storage->access : f.access;
        d.isPrivate = d.access == "private" || d.access == "fileprivate";
        d.implicit = f.implicit;
        d.inScope = inScope(file);
        d.isOverride = f.isOverride || (storage && storage->isOverride);
        bool isStatic = f.isStatic || (storage && storage->isStatic);
        d.isClassMember = isStatic;
        // The class: from the USR, else the enclosing type.
        if (objcUsr) {
            d.className = u.container;
        } else {
            for (long i = (long)st.size() - 1; i >= 0; --i)
                if (IS_ONE_OF(st[(size_t)i].kind, dump::kTypeDecls)) {
                    d.className = typeNameOf(st[(size_t)i]);
                    break;
                }
        }
        if (k == dump::kVarDecl) {
            d.kind = "property";
            d.swiftName = f.declName;
            d.source = "usr";
            if (!objcUsr) d.source = "derived";
            decls.push_back(d);
            return;
        }
        std::string derived;
        bool derivable = true;
        if (k == dump::kAccessorDecl) {
            d.kind = f.isGet ? "getter" : "setter";
            d.propertyUsr = storage ? storage->usr : "";
            if (storage && storage->kind == dump::kSubscriptDecl) {
                // objectAtIndexedSubscript: or objectForKeyedSubscript:
                // depending on the index type, which is not derived here.
                d.swiftName = "subscript";
                derivable = false;
            } else if (storage) {
                d.swiftName = storage->declName + (f.isGet ? ".get" : ".set");
                std::string pname = storage->objcName.empty() ? storage->declName : storage->objcName;
                derived = f.isGet ? deriveGetter(storage->declName) : deriveSetter(storage->declName);
                if (!storage->objcName.empty() && !storage->objcNameImplicit) {
                    // @objc(name) on the property names its getter.
                    d.explicitName = true;
                    d.selector = f.isGet ? deriveGetter(pname) : deriveSetter(pname);
                    d.source = "explicit";
                }
            }
            if (!f.objcName.empty() && d.source.empty()) {
                d.selector = f.objcName;
                d.source = f.objcNameImplicit ? "objc_attr" : "explicit";
                d.explicitName = !f.objcNameImplicit;
            }
        } else {
            d.kind = k == dump::kConstructorDecl ? "init" : k == dump::kDestructorDecl ? "method" : "method";
            d.swiftName = functionName(f);
            if (k == dump::kDestructorDecl) {
                derived = "dealloc";
            } else {
                std::string base = k == dump::kConstructorDecl ? "init" : f.declName;
                derived = deriveMethodSelector(base, f.labels, f.hasForeignError, f.hasForeignAsync);
            }
            if (!f.objcName.empty()) {
                d.selector = f.objcName;
                d.source = f.objcNameImplicit ? "objc_attr" : "explicit";
                d.explicitName = !f.objcNameImplicit;
            }
        }
        d.derived = derivable ? derived : "";
        if (objcUsr) {
            // The USR carries the selector the compiler chose.
            d.selector = u.member;
            d.source = "usr";
            d.isClassMember = u.memberKind == "cm" || u.memberKind == "cpy";
        } else if (d.source.empty()) {
            if (derivable && !d.isOverride) {
                d.selector = derived;
                d.source = "derived";
                d.derivedFlag = true;
            } else {
                // An override takes the selector of what it overrides, which
                // the dump does not name.
                d.source = "underivable";
            }
        }
        if (d.isOverride && !st.empty()) d.overridesUsr = overriddenUsr(d);
        decls.push_back(d);
    }

    // The Objective-C method an override overrides, when the class's
    // superclass is an Objective-C class: c:objc(cs)Super(im)selector.
    std::string overriddenUsr(const Decl &d) const {
        if (d.selector.empty()) return "";
        for (long i = (long)st.size() - 1; i >= 0; --i) {
            const Frame &t = st[(size_t)i];
            if (t.kind == dump::kClassDecl) {
                const std::string &sup = t.superclassType;
                if (startsWith(sup, "$sSo")) {
                    std::string name = demangleTypeName(sup);
                    return "c:objc(cs)" + name + (d.isClassMember ? "(cm)" : "(im)") + d.selector;
                }
                return "";
            }
        }
        return "";
    }

    bool EndObject(SizeType) {
        Frame f = std::move(st.back());
        st.pop_back();
        if (!st.empty()) {
            Frame &p = st.back();
            // A decl_ref names what its parent refers to.
            if (f.kind == dump::kDeclRef && f.key == dump::kKeyDecl) {
                p.refUsr = f.declUsr;
                p.refName = f.baseName;
            }
            // base_name under the decl_name of a declaration: its name.
            if (f.kind == dump::kBaseName && f.key == dump::kBaseNameField && st.size() >= 2 &&
                p.kind == dump::kDeclName && p.key == dump::kKeyName && isDeclKind(st[st.size() - 2].kind))
                st[st.size() - 2].declName = f.baseName;
            // A parameter of a declaration: its argument label.
            if (f.kind == dump::kParameter && f.key == dump::kKeyParams && p.kind == dump::kParameterList &&
                p.key == dump::kKeyParams && st.size() >= 2 && isDeclKind(st[st.size() - 2].kind))
                st[st.size() - 2].labels.push_back(f.hasApiName ? f.apiName : "");
            // Attributes of a declaration.
            if (f.key == dump::kKeyAttrs) {
                if (f.kind == dump::kObjCAttr) {
                    p.objcAttr = true;
                    p.objcName = f.objcName;
                    p.objcNameImplicit = f.objcNameImplicit;
                } else if (f.kind == dump::kOverrideAttr) {
                    p.isOverride = true;
                }
            }
            if (f.key == dump::kKeyInherits && p.kind == dump::kClassDecl) p.superclassType = f.superclassType;
            // A conformance an extension declares.
            if (f.kind == dump::kNormalConformance && f.key == dump::kKeyConformances && p.kind == dump::kInheritance &&
                p.key == dump::kKeyInherits && st.size() >= 2 && st[st.size() - 2].kind == dump::kExtensionDecl &&
                startsWith(f.protocolUsr, "s:"))
                st[st.size() - 2].conformances.push_back(f.protocolUsr);
            if (f.key == dump::kKeyMembers && !f.skip && !f.implicit) protocolMemberEnded(f, p);
            // The receiver of a dot_syntax_call_expr: its implicit argument.
            if (f.key == dump::kKeyExpr && p.kind == dump::kArgument && st.size() >= 3 &&
                st[st.size() - 2].kind == dump::kArgumentList && st[st.size() - 2].key == dump::kKeyArgs &&
                (st[st.size() - 3].kind == dump::kDotSyntaxCallExpr ||
                 st[st.size() - 3].kind == dump::kConstructorRefCallExpr))
                st[st.size() - 3].receiverType = demangleTypeName(f.type);
        }
        if (!f.skip) {
            referenceEnded(f);
            declarationEnded(f);
        }
        if (f.kind == dump::kExtensionDecl && !f.skip && isObjCClassType(f.extendedType)) {
            for (auto &proto : f.conformances) {
                ProtocolRow row;
                row.kind = "conformance";
                row.protocolUsr = proto;
                row.className = demangleTypeName(f.extendedType);
                for (auto &m : f.memberNames) row.member += (row.member.empty() ? "" : " ") + m;
                addProtocolRow(row, f);
            }
        }
        if (f.kind == dump::kDotSyntaxCallExpr || f.kind == dump::kConstructorRefCallExpr) {
            for (auto &r : f.pendingCall) {
                r.receiverType = f.receiverType;
                emit(r);
            }
        }
        // Property refs whose receiver is the base of a member access.
        resolvePending(f);
        if (st.empty()) {
            if (!flush()) return false;
        }
        key.clear();
        return failure.empty();
    }

    void addProtocolRow(ProtocolRow &row, const Frame &f) {
        if (!fileRecorded) return;
        row.file = file;
        long off = f.start, col = 0;
        if (off >= 0) lineCol(off, row.line, col);
        protocolRows.push_back(std::move(row));
    }

    // A member declaration f of the type or extension p: a requirement of a
    // Swift protocol, a member of an extension of one, or a member of an
    // extension of an Objective-C class (which may declare conformances).
    void protocolMemberEnded(const Frame &f, Frame &p) {
        if (!(f.kind == dump::kFuncDecl || f.kind == dump::kVarDecl || f.kind == dump::kSubscriptDecl ||
              f.kind == dump::kConstructorDecl))
            return;
        std::string name = f.kind == dump::kSubscriptDecl ? "subscript" : f.kind == dump::kConstructorDecl ? "init"
                                                                                                          : f.declName;
        if (name.empty()) return;
        ProtocolRow row;
        row.member = name;
        if (p.kind == dump::kProtocolDecl && startsWith(p.usr, "s:")) {
            row.kind = "requirement";
            row.protocolUsr = p.usr;
            addProtocolRow(row, f);
        } else if (p.kind == dump::kExtensionDecl && !protocolUsrOfExistential(p.extendedType).empty()) {
            row.kind = "default";
            row.protocolUsr = protocolUsrOfExistential(p.extendedType);
            addProtocolRow(row, f);
        } else if (p.kind == dump::kExtensionDecl && isObjCClassType(p.extendedType)) {
            p.memberNames.push_back(name);
        }
    }

    // Writes the rows of the document that just ended.
    bool flush();
};

// --- SQLite -------------------------------------------------------------------

static bool exec(sqlite3 *db, const char *sql, std::string *err) {
    char *e = nullptr;
    if (sqlite3_exec(db, sql, nullptr, nullptr, &e) != SQLITE_OK) {
        if (err) *err = e ? e : "sqlite error";
        sqlite3_free(e);
        return false;
    }
    return true;
}

static void bindText(sqlite3_stmt *s, int i, const std::string &v, bool nullIfEmpty = true) {
    if (nullIfEmpty && v.empty()) sqlite3_bind_null(s, i);
    else sqlite3_bind_text(s, i, v.c_str(), (int)v.size(), SQLITE_TRANSIENT);
}

bool Handler::flush() {
    for (auto &r : refs) {
        sqlite3_stmt *s = refStmt;
        sqlite3_reset(s);
        sqlite3_clear_bindings(s);
        int i = 1;
        sqlite3_bind_int64(s, i++, unitId);
        bindText(s, i++, r.file, false);
        sqlite3_bind_int64(s, i++, r.line);
        sqlite3_bind_int64(s, i++, r.col);
        bindText(s, i++, r.kind, false);
        bindText(s, i++, r.usr, false);
        bindText(s, i++, r.selector);
        bindText(s, i++, r.property);
        bindText(s, i++, r.className);
        bindText(s, i++, r.containerKind);
        sqlite3_bind_int(s, i++, r.isClassMember);
        bindText(s, i++, r.access);
        bindText(s, i++, r.selectorKind);
        sqlite3_bind_int(s, i++, r.implicit);
        bindText(s, i++, r.enclosingUsr);
        bindText(s, i++, r.enclosingName);
        sqlite3_bind_int(s, i++, r.inClosure);
        sqlite3_bind_int(s, i++, r.inMacro);
        bindText(s, i++, r.receiverType);
        sqlite3_bind_int(s, i++, r.inScope);
        if (sqlite3_step(s) != SQLITE_DONE) return fail(std::string("sqlite: ") + sqlite3_errmsg(db));
        ++refCount;
    }
    refs.clear();
    for (auto &d : decls) {
        sqlite3_stmt *s = declStmt;
        sqlite3_reset(s);
        sqlite3_clear_bindings(s);
        int i = 1;
        sqlite3_bind_int64(s, i++, unitId);
        bindText(s, i++, d.usr, false);
        bindText(s, i++, d.selector);
        bindText(s, i++, d.derived);
        bindText(s, i++, d.source, false);
        bindText(s, i++, d.swiftName, false);
        bindText(s, i++, d.className);
        bindText(s, i++, d.kind, false);
        sqlite3_bind_int(s, i++, d.isClassMember);
        bindText(s, i++, d.file, false);
        sqlite3_bind_int64(s, i++, d.line);
        bindText(s, i++, d.access);
        sqlite3_bind_int(s, i++, d.isPrivate);
        sqlite3_bind_int(s, i++, d.derivedFlag);
        sqlite3_bind_int(s, i++, d.explicitName);
        sqlite3_bind_int(s, i++, d.isOverride);
        bindText(s, i++, d.overridesUsr);
        bindText(s, i++, d.propertyUsr);
        sqlite3_bind_int(s, i++, d.implicit);
        sqlite3_bind_int(s, i++, d.inScope);
        if (sqlite3_step(s) != SQLITE_DONE) return fail(std::string("sqlite: ") + sqlite3_errmsg(db));
        ++declCount;
    }
    decls.clear();
    for (auto &r : protocolRows) {
        sqlite3_stmt *s = protocolStmt;
        sqlite3_reset(s);
        sqlite3_clear_bindings(s);
        sqlite3_bind_int64(s, 1, unitId);
        bindText(s, 2, r.kind, false);
        bindText(s, 3, r.protocolUsr, false);
        bindText(s, 4, protocolNameFromUsr(r.protocolUsr), false);
        bindText(s, 5, r.member, r.kind != "conformance");
        bindText(s, 6, r.className);
        bindText(s, 7, r.file, false);
        sqlite3_bind_int64(s, 8, r.line);
        if (sqlite3_step(s) != SQLITE_DONE) return fail(std::string("sqlite: ") + sqlite3_errmsg(db));
    }
    protocolRows.clear();
    // The #if clauses no node is in, outermost only; or, when they could not
    // be determined, the whole file.
    if (fileRecorded && undetermined) {
        ++undeterminedFiles;
        long lines = (long)nl.size() + (nl.empty() || nl.back() + 1 < (long)textSize ? 1 : 0);
        sqlite3_stmt *s = inactiveStmt;
        sqlite3_reset(s);
        sqlite3_clear_bindings(s);
        sqlite3_bind_int64(s, 1, unitId);
        bindText(s, 2, file, false);
        sqlite3_bind_int64(s, 3, 1);
        sqlite3_bind_int64(s, 4, lines);
        sqlite3_bind_int(s, 5, 1);
        if (sqlite3_step(s) != SQLITE_DONE) return fail(std::string("sqlite: ") + sqlite3_errmsg(db));
        clauses.clear();
    }
    for (size_t i = 0; fileRecorded && i < clauses.size(); ++i) {
        const Clause &c = clauses[i];
        if (c.active || !c.hasCode || c.endLine < c.startLine) continue;
        bool nested = false;
        for (size_t j = 0; j < clauses.size() && !nested; ++j) {
            const Clause &o = clauses[j];
            nested = j != i && !o.active && o.hasCode && o.start <= c.start && c.end <= o.end;
        }
        if (nested) continue;
        sqlite3_stmt *s = inactiveStmt;
        sqlite3_reset(s);
        sqlite3_clear_bindings(s);
        sqlite3_bind_int64(s, 1, unitId);
        bindText(s, 2, file, false);
        sqlite3_bind_int64(s, 3, c.startLine);
        sqlite3_bind_int64(s, 4, c.endLine);
        sqlite3_bind_int(s, 5, 0);
        if (sqlite3_step(s) != SQLITE_DONE) return fail(std::string("sqlite: ") + sqlite3_errmsg(db));
    }
    clauses.clear();
    ++documents;
    if (!fileRecorded) ++skippedDocuments;
    return true;
}

// --- main ---------------------------------------------------------------------

static bool readLines(const std::string &path, std::vector<std::string> &out) {
    FILE *f = fopen(path.c_str(), "r");
    if (!f) return false;
    char *line = nullptr;
    size_t cap = 0;
    ssize_t n;
    while ((n = getline(&line, &cap, f)) > 0) {
        std::string s(line, (size_t)n);
        while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
        if (!s.empty()) out.push_back(s);
    }
    free(line);
    fclose(f);
    return true;
}

static void usage() {
    fprintf(stderr,
            "usage: swift_refs --db DB --root ROOT --module M --target T --cmd-digest D --file-list-digest D\n"
            "                  --files FILE --inputs FILE --compiler-version FULL [--accept-compiler-version]\n"
            "                  [--bare-slash-regex] [--stderr-file F] [--migration-scope DIR]... [-- COMMAND...]\n"
            "       swift_refs --version\n");
}

// Counts the lines of the compiler's stderr that report an assertion
// failure (with -Xllvm -assert-continue the compiler goes on) and errors.
static void countDiagnostics(const std::string &path, long &assertions, long &errors) {
    assertions = errors = 0;
    FILE *f = fopen(path.c_str(), "r");
    if (!f) return;
    char *line = nullptr;
    size_t cap = 0;
    while (getline(&line, &cap, f) > 0) {
        if (strncmp(line, "Assertion failed:", 17) == 0) ++assertions;
        else if (strstr(line, ": error: ")) ++errors;
    }
    free(line);
    fclose(f);
}

// "a 2, b 1": the counts, sorted by name.
static std::string countsText(const std::map<std::string, long> &counts) {
    std::string out;
    for (auto &kv : counts) out += (out.empty() ? "" : ", ") + kv.first + " " + std::to_string(kv.second);
    return out;
}

static std::string nowUtc() {
    char buf[32];
    time_t t = time(nullptr);
    struct tm tm;
    gmtime_r(&t, &tm);
    strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

int main(int argc, char **argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&](std::string &dst) {
            if (i + 1 >= argc) {
                usage();
                exit(2);
            }
            dst = argv[++i];
        };
        if (a == "--version") {
            printf("swift_refs %s %s\n", SWIFT_REFS_DIGEST, dump::kWrittenAgainst);
            return 0;
        } else if (a == "--db") next(o.db);
        else if (a == "--root") next(o.root);
        else if (a == "--module") next(o.module);
        else if (a == "--target") next(o.target);
        else if (a == "--cmd-digest") next(o.cmdDigest);
        else if (a == "--file-list-digest") next(o.fileListDigest);
        else if (a == "--files") next(o.filesPath);
        else if (a == "--inputs") next(o.inputsPath);
        else if (a == "--compiler-version") next(o.compilerVersion);
        else if (a == "--stderr-file") next(o.stderrFile);
        else if (a == "--accept-compiler-version") o.acceptCompilerVersion = true;
        else if (a == "--bare-slash-regex") o.bareSlashRegex = true;
        else if (a == "--migration-scope") {
            std::string d;
            next(d);
            o.scopes.push_back(d);
        } else if (a == "--") {
            for (++i; i < argc; ++i) o.command.push_back(argv[i]);
        } else {
            usage();
            return 2;
        }
    }
    for (size_t i = 0; i < o.command.size(); ++i) {
        const std::string &a = o.command[i];
        const std::string next = i + 1 < o.command.size() ? o.command[i + 1] : "";
        if (a == "-enable-bare-slash-regex" || (a == "-swift-version" && next == "6") ||
            (a == "-enable-upcoming-feature" && next == "BareSlashRegexLiterals"))
            o.bareSlashRegex = true;
    }
    if (o.db.empty() || o.root.empty() || o.module.empty() || o.target.empty() || o.filesPath.empty() ||
        o.inputsPath.empty() || o.cmdDigest.empty() || o.fileListDigest.empty()) {
        usage();
        return 2;
    }
    char rootReal[PATH_MAX];
    if (!realpath(o.root.c_str(), rootReal)) {
        fprintf(stderr, "swift_refs: cannot resolve %s\n", o.root.c_str());
        return 2;
    }
    std::string root = rootReal;

    Handler h(o);
    std::vector<std::string> files;
    if (!readLines(o.filesPath, files)) {
        fprintf(stderr, "swift_refs: cannot read %s\n", o.filesPath.c_str());
        return 2;
    }
    for (auto &f : files) {
        char real[PATH_MAX];
        std::string abs = realpath(f.c_str(), real) ? std::string(real) : f;
        h.expected.insert(f);
        std::string s = startsWith(abs, root + "/") ? abs.substr(root.size() + 1) : abs;
        h.storedFor[f] = s;
    }
    std::vector<std::pair<std::string, std::string>> inputs;
    {
        std::vector<std::string> lines;
        if (!readLines(o.inputsPath, lines)) {
            fprintf(stderr, "swift_refs: cannot read %s\n", o.inputsPath.c_str());
            return 2;
        }
        for (auto &l : lines) {
            // path TAB digest TAB kind
            size_t t1 = l.find('\t'), t2 = l.find('\t', t1 == std::string::npos ? t1 : t1 + 1);
            if (t1 == std::string::npos || t2 == std::string::npos) {
                fprintf(stderr, "swift_refs: bad line in %s: %s\n", o.inputsPath.c_str(), l.c_str());
                return 2;
            }
            std::string path = l.substr(0, t1), digest = l.substr(t1 + 1, t2 - t1 - 1);
            inputs.push_back({path, l.substr(t1 + 1)});
            h.expectedDigest[path] = digest;
        }
    }

    // Open the database and start the module's transaction.
    std::string err;
    if (sqlite3_open(o.db.c_str(), &h.db) != SQLITE_OK) {
        fprintf(stderr, "swift_refs: cannot open %s\n", o.db.c_str());
        return 1;
    }
    sqlite3_busy_timeout(h.db, 60000);
    bool ok = exec(h.db, "PRAGMA journal_mode=WAL;", &err) && exec(h.db, "BEGIN IMMEDIATE;", &err);
    if (ok) {
        sqlite3_stmt *s = nullptr;
        int version = -1;
        if (sqlite3_prepare_v2(h.db, "SELECT value FROM swift_meta WHERE key='schema_version'", -1, &s, nullptr) ==
                SQLITE_OK &&
            sqlite3_step(s) == SQLITE_ROW)
            version = atoi((const char *)sqlite3_column_text(s, 0));
        sqlite3_finalize(s);
        if (version != kSwiftSchemaVersion) {
            err = "the database's Swift tables have schema version " + std::to_string(version) +
                  ", this reader writes " + std::to_string(kSwiftSchemaVersion) + "; run codedb.py update";
            ok = false;
        }
    }
    auto prepare = [&](const char *sql) -> sqlite3_stmt * {
        sqlite3_stmt *s = nullptr;
        if (sqlite3_prepare_v2(h.db, sql, -1, &s, nullptr) != SQLITE_OK) {
            err = sqlite3_errmsg(h.db);
            ok = false;
        }
        return s;
    };
    if (ok) {
        // Replace the module's rows.
        sqlite3_stmt *s = prepare("SELECT id FROM swift_unit WHERE module=?");
        if (s) {
            sqlite3_bind_text(s, 1, o.module.c_str(), -1, SQLITE_TRANSIENT);
            if (sqlite3_step(s) == SQLITE_ROW) {
                long long old = sqlite3_column_int64(s, 0);
                for (const char *t :
                     {"swift_ref", "swift_objc_decl", "swift_input", "swift_inactive", "swift_protocol"}) {
                    std::string sql = std::string("DELETE FROM ") + t + " WHERE unit=" + std::to_string(old);
                    ok = ok && exec(h.db, sql.c_str(), &err);
                }
                std::string sql = "DELETE FROM swift_unit WHERE id=" + std::to_string(old);
                ok = ok && exec(h.db, sql.c_str(), &err);
            }
            sqlite3_finalize(s);
        }
    }
    std::string scopeText;
    for (auto &d : o.scopes) scopeText += (scopeText.empty() ? "" : ",") + d;
    if (ok) {
        sqlite3_stmt *s = prepare(
            "INSERT INTO swift_unit(module, target, cmd_digest, file_list_digest, compiler_version, reader_version, "
            "extracted_at, assertion_count, file_count, error_count, unresolved_count, underivable_count, "
            "migration_scope, unknown_node_kinds, unknown_access_kinds) VALUES(?,?,?,?,?,?,?,0,?,0,0,0,?,'','')");
        if (s) {
            sqlite3_bind_text(s, 1, o.module.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 2, o.target.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 3, o.cmdDigest.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 4, o.fileListDigest.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 5, o.compilerVersion.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 6, SWIFT_REFS_DIGEST, -1, SQLITE_TRANSIENT);
            std::string now = nowUtc();
            sqlite3_bind_text(s, 7, now.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(s, 8, (long long)files.size());
            sqlite3_bind_text(s, 9, scopeText.c_str(), -1, SQLITE_TRANSIENT);
            if (sqlite3_step(s) != SQLITE_DONE) {
                err = sqlite3_errmsg(h.db);
                ok = false;
            }
            sqlite3_finalize(s);
            h.unitId = sqlite3_last_insert_rowid(h.db);
        }
    }
    if (ok) {
        sqlite3_stmt *s = prepare("INSERT INTO swift_input(unit, path, digest, kind) VALUES(?,?,?,?)");
        for (auto &in : inputs) {
            if (!s) break;
            const std::string &rest = in.second;
            size_t t = rest.find('\t');
            sqlite3_reset(s);
            sqlite3_bind_int64(s, 1, h.unitId);
            sqlite3_bind_text(s, 2, in.first.c_str(), -1, SQLITE_TRANSIENT);
            std::string digest = rest.substr(0, t), kind = rest.substr(t + 1);
            sqlite3_bind_text(s, 3, digest.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 4, kind.c_str(), -1, SQLITE_TRANSIENT);
            if (sqlite3_step(s) != SQLITE_DONE) {
                err = sqlite3_errmsg(h.db);
                ok = false;
                break;
            }
        }
        if (s) sqlite3_finalize(s);
        h.refStmt = prepare(
            "INSERT INTO swift_ref(unit, file, line, col, kind, usr, selector, property, class_name, container_kind, "
            "is_class_method, access, selector_kind, implicit, enclosing_usr, enclosing_name, in_closure, in_macro, "
            "receiver_type, in_migration_scope) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
        h.declStmt = prepare(
            "INSERT INTO swift_objc_decl(unit, usr, selector, derived_selector, selector_source, swift_name, "
            "class_name, kind, is_class_member, file, line, access, is_private, selector_derived, explicit_name, "
            "is_override, overrides_usr, property_usr, implicit, in_migration_scope) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
        h.protocolStmt = prepare("INSERT INTO swift_protocol(unit, kind, protocol_usr, protocol_name, member, "
                                 "class_name, file, line) VALUES(?,?,?,?,?,?,?,?)");
        h.inactiveStmt = prepare("INSERT INTO swift_inactive(unit, file, start_line, end_line, undetermined) VALUES(?,?,?,?,?)");
    }
    if (!ok) {
        fprintf(stderr, "swift_refs: %s\n", err.c_str());
        exec(h.db, "ROLLBACK;", nullptr);
        sqlite3_close(h.db);
        return 1;
    }

    // Start the compiler, or read stdin.
    pid_t child = -1;
    int fd = 0;
    if (!o.command.empty()) {
        int pipefd[2];
        if (pipe(pipefd) != 0) {
            perror("swift_refs: pipe");
            return 1;
        }
        posix_spawn_file_actions_t fa;
        posix_spawn_file_actions_init(&fa);
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
        posix_spawn_file_actions_adddup2(&fa, pipefd[1], 1);
        if (!o.stderrFile.empty())
            posix_spawn_file_actions_addopen(&fa, 2, o.stderrFile.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        posix_spawn_file_actions_addclose(&fa, pipefd[0]);
        posix_spawn_file_actions_addclose(&fa, pipefd[1]);
        std::vector<char *> av;
        for (auto &a : o.command) av.push_back(const_cast<char *>(a.c_str()));
        av.push_back(nullptr);
        int rc = posix_spawn(&child, av[0], &fa, nullptr, av.data(), environ);
        posix_spawn_file_actions_destroy(&fa);
        close(pipefd[1]);
        if (rc != 0) {
            fprintf(stderr, "swift_refs: cannot run %s: %s\n", av[0], strerror(rc));
            exec(h.db, "ROLLBACK;", nullptr);
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
            if (!h.failure.empty()) parseError = h.failure;
            else
                parseError = "malformed or truncated dump at document " + std::to_string(h.documents + 1) +
                             ", byte " + std::to_string(pr.Offset()) + ": " + GetParseError_En(pr.Code());
            break;
        }
        h.st.clear();
    }
    long compilerPeakKb = 0;
    int status = 0;
    if (child > 0) {
        if (!parseError.empty()) kill(child, SIGKILL);
        // Drain what is left so that the compiler is not blocked on a full pipe.
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
    long assertions = 0, errors = 0;
    if (!o.stderrFile.empty()) countDiagnostics(o.stderrFile, assertions, errors);

    std::string why = parseError;
    if (why.empty() && status != 0)
        why = "the compiler exited with status " + std::to_string(status) +
              (o.stderrFile.empty() ? "" : " (its messages are in " + o.stderrFile + ")");
    if (why.empty() && (size_t)h.documents != files.size())
        why = "the dump has " + std::to_string(h.documents) + " documents; the module has " +
              std::to_string(files.size()) + " files";
    // Selectors of #selector expressions that name a Swift declaration by
    // its Swift USR (private and fileprivate @objc methods).
    long underivable = 0;
    if (why.empty()) {
        std::string sql =
            "UPDATE swift_ref SET selector = (SELECT d.selector FROM swift_objc_decl d WHERE d.unit = swift_ref.unit "
            "AND d.usr = swift_ref.usr AND d.selector IS NOT NULL LIMIT 1), class_name = coalesce(class_name, "
            "(SELECT d.class_name FROM swift_objc_decl d WHERE d.unit = swift_ref.unit AND d.usr = swift_ref.usr "
            "LIMIT 1)), is_class_method = coalesce((SELECT d.is_class_member FROM swift_objc_decl d WHERE d.unit = "
            "swift_ref.unit AND d.usr = swift_ref.usr LIMIT 1), is_class_method) "
            "WHERE unit = " + std::to_string(h.unitId) + " AND selector IS NULL AND kind = 'selector-expr'";
        if (!exec(h.db, sql.c_str(), &err)) why = "sqlite: " + err;
        sqlite3_stmt *s = nullptr;
        std::string q = "SELECT count(*) FROM swift_objc_decl WHERE unit = " + std::to_string(h.unitId) +
                        " AND selector IS NULL AND kind != 'property'";
        if (sqlite3_prepare_v2(h.db, q.c_str(), -1, &s, nullptr) == SQLITE_OK && sqlite3_step(s) == SQLITE_ROW)
            underivable = sqlite3_column_int64(s, 0);
        sqlite3_finalize(s);
    }
    std::string unknownKinds = countsText(h.unknownKinds), unknownAccess = countsText(h.unknownAccess);
    if (why.empty()) {
        std::string sql = "UPDATE swift_unit SET assertion_count=" + std::to_string(assertions) +
                          ", error_count=" + std::to_string(errors) + ", unresolved_count=" +
                          std::to_string(h.unresolved) + ", underivable_count=" + std::to_string(underivable) +
                          ", unknown_node_kinds=?, unknown_access_kinds=? WHERE id=" + std::to_string(h.unitId);
        sqlite3_stmt *s = nullptr;
        if (sqlite3_prepare_v2(h.db, sql.c_str(), -1, &s, nullptr) != SQLITE_OK) {
            why = std::string("sqlite: ") + sqlite3_errmsg(h.db);
        } else {
            bindText(s, 1, unknownKinds, false);
            bindText(s, 2, unknownAccess, false);
            if (sqlite3_step(s) != SQLITE_DONE) why = std::string("sqlite: ") + sqlite3_errmsg(h.db);
        }
        sqlite3_finalize(s);
    }
    sqlite3_finalize(h.refStmt);
    sqlite3_finalize(h.declStmt);
    sqlite3_finalize(h.inactiveStmt);
    sqlite3_finalize(h.protocolStmt);
    if (why.empty() && !exec(h.db, "COMMIT;", &err)) why = "sqlite: " + err;
    if (!why.empty()) {
        exec(h.db, "ROLLBACK;", nullptr);
        sqlite3_close(h.db);
        fprintf(stderr, "swift_refs: %s: nothing written for module %s\n", why.c_str(), o.module.c_str());
        return 1;
    }
    sqlite3_close(h.db);
    struct rusage self;
    getrusage(RUSAGE_SELF, &self);
    printf("swift_refs: documents %ld refs %ld decls %ld assertions %ld errors %ld unresolved %ld underivable %ld "
           "skipped_documents %ld compiler_peak_kb %ld reader_peak_kb %ld unknown_access %ld unknown_kinds %ld "
           "undetermined_files %ld\n",
           h.documents, h.refCount, h.declCount, assertions, errors, h.unresolved, underivable, h.skippedDocuments,
           compilerPeakKb, (long)(self.ru_maxrss / 1024), h.unknownAccessRows, (long)h.unknownKinds.size(),
           h.undeterminedFiles);
    if (!h.unknownKinds.empty()) printf("swift_refs: node kinds this reader does not know: %s\n", unknownKinds.c_str());
    if (!h.unknownAccess.empty())
        printf("swift_refs: property accesses left unknown, by the parent that is not classified: %s\n",
               unknownAccess.c_str());
    return 0;
}
