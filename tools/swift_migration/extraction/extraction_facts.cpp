// extraction_facts: facts from Clang's AST about a block of statements that is
// about to be extracted into a new function, or about a function and the calls
// to another function inside it.
//
// Part of the Objective-C to Swift migration (docs/swift-migration/large-code.md
// section 2.2). It is driven by extract_check.py, which formats the facts into a
// report with verdicts; this program only reports what the compiler knows and
// never decides whether an extraction is safe.
//
// Usage:
//   extraction_facts --main PATH [--contents FILE] --range FIRST LAST -- ARGS...
//   extraction_facts --main PATH [--contents FILE]
//                    (--function-at LINE | --function-named NAME)
//                    [--callee-named NAME] -- ARGS...
//
// NAME is a function's qualified name, or an Objective-C method written
// -[Class selector] or +[Class selector] (a category name in parentheses after
// the class is optional).
//   extraction_facts --version
//
// ARGS is a clang command line without the compiler (as in the code database's
// compile_commands.jsonl). PATH is the main file as the command names it.
// --contents parses FILE's bytes as if they were PATH (so that quoted includes
// and __FILE__ behave as for PATH); this is how the before and after versions
// of a commit are analyzed without writing them into the tree.
//
// Output: one JSON object on stdout. Exit 0 when clang ran (the object says how
// many errors it reported), 2 on a usage error or when no function contains the
// given lines.
//
// Everything is taken from the AST, the preprocessor's callbacks and the raw
// lexer over the main file; nothing is parsed by hand. Where a fact cannot be
// established it is reported as unknown with the reason, never guessed.

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/Attr.h"
#include "clang/AST/Decl.h"
#include "clang/AST/DeclCXX.h"
#include "clang/AST/DeclObjC.h"
#include "clang/AST/Expr.h"
#include "clang/AST/ExprCXX.h"
#include "clang/AST/ExprObjC.h"
#include "clang/AST/Mangle.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/AST/Stmt.h"
#include "clang/AST/StmtCXX.h"
#include "clang/AST/StmtObjC.h"
#include "clang/Basic/Builtins.h"
#include "clang/Basic/SourceManager.h"
#include "clang/Basic/Version.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "clang/Lex/Lexer.h"
#include "clang/Lex/MacroInfo.h"
#include "clang/Lex/PPCallbacks.h"
#include "clang/Lex/Preprocessor.h"
#include "clang/Tooling/Tooling.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <map>
#include <set>
#include <string>
#include <vector>

#ifndef EXTRACTION_LLVM_CLANG
#error "build.sh defines EXTRACTION_LLVM_CLANG, EXTRACTION_RESOURCE_DIR and EXTRACTION_DIGEST"
#endif

using namespace clang;

namespace {

// ---------------------------------------------------------------- JSON output

std::string jsonEscape(llvm::StringRef s) {
    std::string out;
    for (unsigned char c : s) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[8];
                snprintf(buf, sizeof buf, "\\u%04x", c);
                out += buf;
            } else {
                out += (char)c;
            }
        }
    }
    return out;
}

// A minimal JSON value builder: objects keep insertion order.
struct J {
    enum Kind { Null, Bool, Num, Str, Arr, Obj } kind = Null;
    bool b = false;
    long long n = 0;
    std::string s;
    std::vector<J> items;
    std::vector<std::pair<std::string, J>> fields;

    J() {}
    static J str(llvm::StringRef v) { J j; j.kind = Str; j.s = v.str(); return j; }
    static J num(long long v) { J j; j.kind = Num; j.n = v; return j; }
    static J boolean(bool v) { J j; j.kind = Bool; j.b = v; return j; }
    static J arr() { J j; j.kind = Arr; return j; }
    static J obj() { J j; j.kind = Obj; return j; }
    J &set(const std::string &k, J v) { fields.emplace_back(k, std::move(v)); return *this; }
    J &set(const std::string &k, const char *v) { return set(k, str(v)); }
    J &set(const std::string &k, const std::string &v) { return set(k, str(v)); }
    J &set(const std::string &k, llvm::StringRef v) { return set(k, str(v)); }
    J &set(const std::string &k, int v) { return set(k, num(v)); }
    J &set(const std::string &k, unsigned v) { return set(k, num(v)); }
    J &set(const std::string &k, long long v) { return set(k, num(v)); }
    J &set(const std::string &k, bool v) { return set(k, boolean(v)); }
    J &push(J v) { items.push_back(std::move(v)); return *this; }

    void write(std::string &o) const {
        switch (kind) {
        case Null: o += "null"; break;
        case Bool: o += b ? "true" : "false"; break;
        case Num: o += std::to_string(n); break;
        case Str: o += "\""; o += jsonEscape(s); o += "\""; break;
        case Arr:
            o += "[";
            for (size_t i = 0; i < items.size(); i++) {
                if (i) o += ",";
                items[i].write(o);
            }
            o += "]";
            break;
        case Obj:
            o += "{";
            for (size_t i = 0; i < fields.size(); i++) {
                if (i) o += ",";
                o += "\"" + jsonEscape(fields[i].first) + "\":";
                fields[i].second.write(o);
            }
            o += "}";
            break;
        }
    }
};

// ---------------------------------------------------------------- options

struct Options {
    std::string mainFile;
    std::string contents;
    int first = 0, last = 0;
    int functionAt = 0;
    std::string functionNamed;
    std::string calleeNamed;
    std::vector<std::string> args;
};

// ---------------------------------------------------------------- preprocessor facts

struct MacroUse {
    std::string name;
    unsigned begin = 0, end = 0;  // offsets of the invocation in the main file
    std::string defFile;
    unsigned defLine = 0;
    bool builtin = false;
    bool topLevel = true;     // the name token is written in the main file
    std::string via;          // for a nested use: the top-level macro it is inside
};

struct Skipped {
    unsigned begin, end;
};

struct Conditional {
    std::string kind;
    unsigned offset;
};

struct PPFacts {
    std::vector<MacroUse> macros;
    std::vector<Skipped> skipped;
    std::vector<Conditional> conditionals;
};

class Recorder : public PPCallbacks {
public:
    Recorder(SourceManager &sm, const LangOptions &lo, PPFacts &f) : sm_(sm), lo_(lo), f_(f) {}

    void MacroExpands(const Token &nameTok, const MacroDefinition &md, SourceRange range,
                      const MacroArgs *) override {
        SourceLocation loc = nameTok.getLocation();
        const MacroInfo *mi = md.getMacroInfo();
        MacroUse u;
        u.name = nameTok.getIdentifierInfo() ? nameTok.getIdentifierInfo()->getName().str() : "";
        u.builtin = mi && mi->isBuiltinMacro();
        if (loc.isFileID()) {
            if (sm_.getFileID(loc) != sm_.getMainFileID()) return;
            u.begin = sm_.getFileOffset(loc);
            SourceLocation e = range.getEnd();
            u.end = e.isFileID() && sm_.getFileID(e) == sm_.getMainFileID()
                        ? sm_.getFileOffset(e) + Lexer::MeasureTokenLength(e, sm_, lo_)
                        : u.begin + u.name.size();
        } else {
            // Only builtin macros (__LINE__ and the like) are recorded when
            // they expand inside another macro, because their value depends on
            // where the outer macro is used.
            if (!u.builtin) return;
            SourceLocation x = sm_.getExpansionLoc(loc);
            if (!x.isValid() || sm_.getFileID(x) != sm_.getMainFileID()) return;
            u.topLevel = false;
            u.begin = u.end = sm_.getFileOffset(x);
            SourceLocation l = loc;
            while (l.isMacroID()) {
                SourceLocation caller = sm_.getImmediateMacroCallerLoc(l);
                if (caller.isFileID()) {
                    u.via = Lexer::getImmediateMacroName(l, sm_, lo_).str();
                    break;
                }
                l = caller;
            }
        }
        if (mi && !u.builtin) {
            SourceLocation def = mi->getDefinitionLoc();
            if (def.isValid()) {
                PresumedLoc p = sm_.getPresumedLoc(sm_.getExpansionLoc(def), false);
                if (p.isValid()) {
                    u.defFile = p.getFilename();
                    u.defLine = p.getLine();
                }
            }
        }
        f_.macros.push_back(u);
    }

    void SourceRangeSkipped(SourceRange range, SourceLocation) override {
        SourceLocation b = range.getBegin(), e = range.getEnd();
        if (!b.isFileID() || !e.isFileID()) return;
        if (sm_.getFileID(b) != sm_.getMainFileID() || sm_.getFileID(e) != sm_.getMainFileID()) return;
        f_.skipped.push_back({sm_.getFileOffset(b), sm_.getFileOffset(e)});
    }

    void If(SourceLocation loc, SourceRange, ConditionValueKind) override { cond("#if", loc); }
    void Elif(SourceLocation loc, SourceRange, ConditionValueKind, SourceLocation) override { cond("#elif", loc); }
    void Ifdef(SourceLocation loc, const Token &, const MacroDefinition &) override { cond("#ifdef", loc); }
    void Ifndef(SourceLocation loc, const Token &, const MacroDefinition &) override { cond("#ifndef", loc); }
    void Else(SourceLocation loc, SourceLocation) override { cond("#else", loc); }
    void Endif(SourceLocation loc, SourceLocation) override { cond("#endif", loc); }

private:
    void cond(const char *kind, SourceLocation loc) {
        if (!loc.isFileID() || sm_.getFileID(loc) != sm_.getMainFileID()) return;
        f_.conditionals.push_back({kind, sm_.getFileOffset(loc)});
    }

    SourceManager &sm_;
    const LangOptions &lo_;
    PPFacts &f_;
};

// ---------------------------------------------------------------- analysis

const unsigned kNoOffset = ~0u;

struct Span {
    unsigned b = kNoOffset, e = kNoOffset;
    bool valid() const { return b != kNoOffset && e != kNoOffset; }
};

// A reference to a variable (or an ivar, or self).
struct Ref {
    const ValueDecl *decl = nullptr;
    unsigned off = 0;
    std::string use;     // read, write, read-write, address-taken, by-reference, unevaluated, unknown
    std::string why;     // details, e.g. the unknown parent kind
    bool inSel = false;
    const Stmt *closure = nullptr;   // innermost block or lambda (in the walked function) the reference is inside
    std::string capture;             // "", "block-copy", "block-byref", "lambda-copy", "lambda-byref"
    std::string through;             // for a pointer read: how the pointee is used (write, read-write, ...)
};

// A reference to a global, a file-scope static or a static data member.
struct GlobalRef {
    const VarDecl *decl;
    unsigned off;
    std::string use;
    bool inSel;
};

struct Exit {
    std::string kind;       // return, break, continue, goto, throw, rethrow, noreturn-call, co_return
    unsigned off = 0;
    std::string target;     // function, block, lambda, loop, switch, label, handler, none, program-end
    unsigned targetOff = kNoOffset;
    bool targetInside = false;
    bool inSel = false;
    std::string text;
    std::string value;       // return value text
    bool hasConst = false;
    long long constValue = 0;
    std::vector<std::pair<std::string, unsigned>> crossed;  // scope kind, offset
    std::vector<std::string> macros;   // macro chain the statement is spelled in
    bool spelledInMacroBody = false;
    std::string callee;
};

struct Scope {
    std::string kind;
    unsigned off;
    unsigned end;
};

struct Hazard {
    std::string kind;
    unsigned off;
    std::string detail;
};

struct SelfUse {
    std::string kind;   // self, _cmd, super, ivar, this
    std::string name;
    unsigned off;
    std::string use;
    bool inSel;
};

struct Positional {
    std::string kind;
    unsigned off;
    std::vector<std::string> macros;
};

struct DeclInfo {
    const VarDecl *vd;
    unsigned off;
    bool inSel;
    bool topLevelInSel;  // declared by a DeclStmt that is one of the selected statements
};

struct Entry {
    std::string kind;   // goto, case, default
    unsigned off;       // the label or case
    unsigned fromOff;   // the goto or switch
};

class Analyzer {
public:
    Analyzer(ASTContext &ctx, Preprocessor &pp, PPFacts &pf, unsigned errors)
        : ctx_(ctx), sm_(ctx.getSourceManager()), lo_(ctx.getLangOpts()), pp_(pp), pf_(pf), errors_(errors) {
        mainFID_ = sm_.getMainFileID();
        buf_ = sm_.getBufferData(mainFID_);
    }

    // ------------------------------------------------ locations

    unsigned offOf(SourceLocation loc) const {
        if (loc.isInvalid()) return kNoOffset;
        SourceLocation x = sm_.getExpansionLoc(loc);
        if (sm_.getFileID(x) != mainFID_) return kNoOffset;
        return sm_.getFileOffset(x);
    }

    Span spanOf(const Stmt *s) const {
        Span sp;
        if (!s) return sp;
        SourceRange r = s->getSourceRange();
        if (r.isInvalid()) return sp;
        CharSourceRange b = sm_.getExpansionRange(r.getBegin());
        CharSourceRange e = sm_.getExpansionRange(r.getEnd());
        if (sm_.getFileID(b.getBegin()) != mainFID_ || sm_.getFileID(e.getEnd()) != mainFID_) return sp;
        sp.b = sm_.getFileOffset(b.getBegin());
        SourceLocation end = e.getEnd();
        sp.e = sm_.getFileOffset(end) + (e.isTokenRange() ? Lexer::MeasureTokenLength(end, sm_, lo_) : 0);
        return sp;
    }

    Span spanOfDecl(const Decl *d) const {
        Span sp;
        SourceRange r = d->getSourceRange();
        if (r.isInvalid()) return sp;
        CharSourceRange b = sm_.getExpansionRange(r.getBegin());
        CharSourceRange e = sm_.getExpansionRange(r.getEnd());
        if (sm_.getFileID(b.getBegin()) != mainFID_ || sm_.getFileID(e.getEnd()) != mainFID_) return sp;
        sp.b = sm_.getFileOffset(b.getBegin());
        SourceLocation end = e.getEnd();
        sp.e = sm_.getFileOffset(end) + (e.isTokenRange() ? Lexer::MeasureTokenLength(end, sm_, lo_) : 0);
        return sp;
    }

    unsigned lineOf(unsigned off) const {
        if (off == kNoOffset) return 0;
        return sm_.getLineNumber(mainFID_, off);
    }

    unsigned lineStart(unsigned line) const {
        SourceLocation l = sm_.translateLineCol(mainFID_, line, 1);
        return sm_.getFileOffset(l);
    }

    // The offset just past the end of `line` (the start of the next line).
    unsigned lineEnd(unsigned line) const {
        unsigned s = lineStart(line);
        size_t nl = buf_.find('\n', s);
        return nl == llvm::StringRef::npos ? (unsigned)buf_.size() : (unsigned)nl + 1;
    }

    std::string textOf(Span sp, size_t max = 160) const {
        if (!sp.valid() || sp.e < sp.b || sp.e > buf_.size()) return "";
        std::string t = buf_.substr(sp.b, sp.e - sp.b).str();
        std::string out;
        bool space = false;
        for (char c : t) {
            if (c == '\n' || c == '\t' || c == '\r' || c == ' ') {
                space = true;
                continue;
            }
            if (space && !out.empty()) out += ' ';
            space = false;
            out += c;
        }
        if (out.size() > max) out = out.substr(0, max) + "...";
        return out;
    }

    std::vector<std::string> macroChain(SourceLocation loc, bool *inBody) const {
        std::vector<std::string> names;
        *inBody = false;
        SourceLocation l = loc;
        int guard = 0;
        while (l.isMacroID() && guard++ < 64) {
            if (!sm_.isMacroArgExpansion(l)) *inBody = true;
            names.push_back(Lexer::getImmediateMacroName(l, sm_, lo_).str());
            l = sm_.getImmediateMacroCallerLoc(l);
        }
        // An argument written in the main file is not hidden in a macro body.
        if (loc.isMacroID()) {
            SourceLocation sp = sm_.getSpellingLoc(loc);
            if (sp.isValid() && sm_.getFileID(sp) == mainFID_) {
                // Spelled in the main file: either in a macro argument (not hidden)
                // or in a #define in this file (hidden).
                unsigned o = sm_.getFileOffset(sp);
                *inBody = onDefineLine(o);
            } else {
                *inBody = true;
            }
        }
        std::reverse(names.begin(), names.end());
        // Deduplicate consecutive repeats (argument expansions report the same macro).
        std::vector<std::string> out;
        for (auto &n : names)
            if (out.empty() || out.back() != n) out.push_back(n);
        return out;
    }

    bool onDefineLine(unsigned off) const {
        // Is `off` inside a #define directive (including continuation lines)?
        size_t ls = buf_.rfind('\n', off == 0 ? 0 : off - 1);
        ls = ls == llvm::StringRef::npos ? 0 : ls + 1;
        // Walk back over continuation lines.
        while (ls >= 2 && buf_[ls - 2] == '\\') {
            size_t p = buf_.rfind('\n', ls - 2);
            ls = p == llvm::StringRef::npos ? 0 : p + 1;
            if (ls == 0) break;
        }
        llvm::StringRef line = buf_.substr(ls).ltrim(" \t");
        if (!line.starts_with("#")) return false;
        line = line.drop_front(1).ltrim(" \t");
        return line.starts_with("define");
    }

    std::string typeStr(QualType t) const {
        PrintingPolicy pp(lo_);
        pp.SuppressTagKeyword = false;
        return t.getAsString(pp);
    }

    static const char *lifetimeName(Qualifiers::ObjCLifetime l) {
        switch (l) {
        case Qualifiers::OCL_None: return "";
        case Qualifiers::OCL_ExplicitNone: return "__unsafe_unretained";
        case Qualifiers::OCL_Strong: return "__strong";
        case Qualifiers::OCL_Weak: return "__weak";
        case Qualifiers::OCL_Autoreleasing: return "__autoreleasing";
        }
        return "";
    }

    // Whether the ownership qualifier at the top of a type was written (an
    // AttributedType for objc_ownership in the type as written).
    static bool hasExplicitOwnership(TypeLoc tl) {
        while (!tl.isNull()) {
            if (auto at = tl.getAs<AttributedTypeLoc>()) {
                if (at.getAttrKind() == attr::ObjCOwnership) return true;
                tl = at.getModifiedLoc();
                continue;
            }
            if (auto pt = tl.getAs<ParenTypeLoc>()) {
                tl = pt.getInnerLoc();
                continue;
            }
            if (auto qt = tl.getAs<QualifiedTypeLoc>()) {
                tl = qt.getUnqualifiedLoc();
                continue;
            }
            if (auto mq = tl.getAs<MacroQualifiedTypeLoc>()) {
                tl = mq.getInnerLoc();
                continue;
            }
            return false;
        }
        return false;
    }

    static TypeLoc pointeeLoc(TypeLoc tl) {
        while (!tl.isNull()) {
            if (auto pt = tl.getAs<PointerTypeLoc>()) return pt.getPointeeLoc();
            if (auto rt = tl.getAs<ReferenceTypeLoc>()) return rt.getPointeeLoc();
            if (auto at = tl.getAs<AttributedTypeLoc>()) { tl = at.getModifiedLoc(); continue; }
            if (auto pr = tl.getAs<ParenTypeLoc>()) { tl = pr.getInnerLoc(); continue; }
            if (auto qt = tl.getAs<QualifiedTypeLoc>()) { tl = qt.getUnqualifiedLoc(); continue; }
            if (auto mq = tl.getAs<MacroQualifiedTypeLoc>()) { tl = mq.getInnerLoc(); continue; }
            return TypeLoc();
        }
        return TypeLoc();
    }

    J varType(const ValueDecl *vd) const {
        J t = J::obj();
        QualType q = vd->getType();
        t.set("type", typeStr(q));
        t.set("lifetime", lifetimeName(q.getObjCLifetime()));
        TypeLoc tl;
        if (const DeclaratorDecl *dd = dyn_cast<DeclaratorDecl>(vd))
            if (dd->getTypeSourceInfo()) tl = dd->getTypeSourceInfo()->getTypeLoc();
        t.set("lifetime_written", !tl.isNull() && hasExplicitOwnership(tl));
        QualType pointee;
        if (const PointerType *pt = q->getAs<PointerType>()) pointee = pt->getPointeeType();
        else if (const ReferenceType *rt = q->getAs<ReferenceType>()) pointee = rt->getPointeeType();
        t.set("is_pointer", !q.isNull() && q->isPointerType());
        t.set("is_reference", !q.isNull() && q->isReferenceType());
        t.set("is_object_pointer", !q.isNull() && (q->isObjCObjectPointerType() || q->isBlockPointerType()));
        if (!pointee.isNull()) {
            t.set("pointee_type", typeStr(pointee));
            t.set("pointee_lifetime", lifetimeName(pointee.getObjCLifetime()));
            TypeLoc pl = tl.isNull() ? TypeLoc() : pointeeLoc(tl);
            t.set("pointee_lifetime_written", !pl.isNull() && hasExplicitOwnership(pl));
            t.set("pointee_is_object_pointer", pointee->isObjCObjectPointerType() || pointee->isBlockPointerType());
            t.set("pointee_const", pointee.isConstQualified());
        }
        if (const VarDecl *v = dyn_cast<VarDecl>(vd)) {
            t.set("block_storage", v->hasAttr<BlocksAttr>());
            t.set("static_local", v->isStaticLocal());
            t.set("precise_lifetime", v->hasAttr<ObjCPreciseLifetimeAttr>());
            t.set("cleanup_attr", v->hasAttr<CleanupAttr>());
            bool dtor = false, copy = false;
            if (const CXXRecordDecl *rd = q->getAsCXXRecordDecl()) {
                if (rd->hasDefinition()) {
                    dtor = !rd->hasTrivialDestructor();
                    copy = !rd->hasTrivialCopyConstructor();
                }
            }
            t.set("nontrivial_destructor", dtor);
            t.set("nontrivial_copy", copy);
            t.set("vla", q->isVariableArrayType());
            t.set("va_list", isVaList(q));
        }
        return t;
    }

    // From the type's sugar, not its canonical type: on arm64 Darwin va_list
    // is char *, so a canonical comparison would call every char * a va_list.
    bool isVaList(QualType q) const {
        int guard = 0;
        while (!q.isNull() && guard++ < 32) {
            if (const TypedefType *tt = q->getAs<TypedefType>()) {
                std::string n = tt->getDecl()->getNameAsString();
                if (n == "va_list" || n == "__builtin_va_list" || n == "__darwin_va_list" || n == "__gnuc_va_list")
                    return true;
                QualType next = tt->getDecl()->getUnderlyingType();
                if (next == q) break;
                q = next;
                continue;
            }
            break;
        }
        return false;
    }

    // ------------------------------------------------ finding the function

    struct FnLike {
        const Decl *decl = nullptr;      // FunctionDecl or ObjCMethodDecl (outermost)
        const Stmt *body = nullptr;
        Span span;
    };

    class FnFinder : public RecursiveASTVisitor<FnFinder> {
    public:
        FnFinder(const Analyzer &a, unsigned b, unsigned e) : a_(a), b_(b), e_(e) {}
        bool VisitFunctionDecl(FunctionDecl *fd) {
            if (!fd->doesThisDeclarationHaveABody()) return true;
            consider(fd, fd->getBody());
            return true;
        }
        bool VisitObjCMethodDecl(ObjCMethodDecl *md) {
            if (!md->hasBody()) return true;
            consider(md, md->getBody());
            return true;
        }
        void consider(const Decl *d, const Stmt *body) {
            if (!body) return;
            Span s = a_.spanOf(body);
            if (!s.valid() || s.b > b_ || s.e < e_) return;
            // Prefer the innermost (a lambda's call operator is a FunctionDecl too,
            // but it is found through its LambdaExpr instead).
            if (const CXXMethodDecl *m = dyn_cast<CXXMethodDecl>(d))
                if (m->getParent()->isLambda()) return;
            if (!best.decl || (s.e - s.b) < (best.span.e - best.span.b)) {
                best.decl = d;
                best.body = body;
                best.span = s;
            }
        }
        FnLike best;
    private:
        const Analyzer &a_;
        unsigned b_, e_;
    };

    FnLike findFunction(unsigned b, unsigned e) {
        FnFinder f(*this, b, e);
        f.TraverseDecl(ctx_.getTranslationUnitDecl());
        return f.best;
    }

    std::string fnName(const Decl *d) const {
        if (const ObjCMethodDecl *m = dyn_cast<ObjCMethodDecl>(d)) {
            std::string cls;
            if (const ObjCInterfaceDecl *i = m->getClassInterface()) cls = i->getNameAsString();
            if (const ObjCCategoryImplDecl *c = dyn_cast<ObjCCategoryImplDecl>(m->getDeclContext()))
                cls += "(" + c->getNameAsString() + ")";
            return std::string(m->isInstanceMethod() ? "-" : "+") + "[" + cls + " " +
                   m->getSelector().getAsString() + "]";
        }
        if (const FunctionDecl *f = dyn_cast<FunctionDecl>(d)) return f->getQualifiedNameAsString();
        return "";
    }

    std::string irName(const Decl *d) const {
        std::unique_ptr<MangleContext> mc(ctx_.createMangleContext());
        std::string out;
        llvm::raw_string_ostream os(out);
        if (const ObjCMethodDecl *m = dyn_cast<ObjCMethodDecl>(d)) {
            mc->mangleObjCMethodName(m, os, /*includePrefixByte=*/false, /*includeCategoryNamespace=*/true);
        } else if (const FunctionDecl *f = dyn_cast<FunctionDecl>(d)) {
            if (isa<CXXConstructorDecl>(f) || isa<CXXDestructorDecl>(f)) return "";
            if (mc->shouldMangleDeclName(f)) mc->mangleName(GlobalDecl(f), os);
            else os << f->getNameAsString();
        }
        os.flush();
        return out;
    }

    J fnJson(const Decl *d, const Stmt *body) const {
        J f = J::obj();
        f.set("name", fnName(d));
        f.set("ir_name", irName(d));
        Span s = spanOfDecl(d);
        f.set("line", lineOf(s.b));
        f.set("end_line", lineOf(s.e == 0 ? 0 : s.e - 1));
        Span bs = spanOf(body);
        f.set("body_line", lineOf(bs.b));
        f.set("body_end_line", lineOf(bs.e == 0 ? 0 : bs.e - 1));
        f.set("arc", (bool)lo_.ObjCAutoRefCount);
        f.set("objc", (bool)lo_.ObjC);
        f.set("cplusplus", (bool)lo_.CPlusPlus);
        f.set("exceptions", (bool)lo_.Exceptions);
        f.set("cxx_exceptions", (bool)lo_.CXXExceptions);
        f.set("objc_exceptions", (bool)lo_.ObjCExceptions);
        QualType ret;
        if (const ObjCMethodDecl *m = dyn_cast<ObjCMethodDecl>(d)) {
            f.set("kind", "objc-method");
            f.set("instance", m->isInstanceMethod());
            f.set("selector", m->getSelector().getAsString());
            if (const ObjCInterfaceDecl *i = m->getClassInterface()) f.set("class", i->getNameAsString());
            f.set("direct", m->isDirectMethod());
            std::string category;
            if (const ObjCCategoryImplDecl *c = dyn_cast<ObjCCategoryImplDecl>(m->getDeclContext()))
                category = c->getNameAsString();
            else if (const ObjCCategoryDecl *c = dyn_cast<ObjCCategoryDecl>(m->getDeclContext()))
                category = c->getNameAsString();
            f.set("category", category);
            ret = m->getReturnType();
            J ps = J::arr();
            for (const ParmVarDecl *p : m->parameters()) ps.push(paramJson(p));
            f.set("params", ps);
        } else if (const FunctionDecl *fd = dyn_cast<FunctionDecl>(d)) {
            f.set("kind", isa<CXXMethodDecl>(fd) ? "cxx-method" : "function");
            f.set("static", fd->getStorageClass() == SC_Static);
            f.set("inline", fd->isInlineSpecified());
            f.set("always_inline", fd->hasAttr<AlwaysInlineAttr>());
            f.set("noinline", fd->hasAttr<NoInlineAttr>());
            const FunctionProtoType *fpt = fd->getType()->getAs<FunctionProtoType>();
            f.set("nothrow", fpt && fpt->isNothrow());
            f.set("variadic", fd->isVariadic());
            ret = fd->getReturnType();
            J ps = J::arr();
            for (const ParmVarDecl *p : fd->parameters()) ps.push(paramJson(p));
            f.set("params", ps);
        }
        f.set("return_type", typeStr(ret));
        f.set("returns_void", !ret.isNull() && ret->isVoidType());
        return f;
    }

    J paramJson(const ParmVarDecl *p) const {
        J j = varType(p);
        j.set("name", p->getNameAsString());
        j.set("line", lineOf(offOf(p->getLocation())));
        return j;
    }

    // ------------------------------------------------ the walk

    // Kinds of constructs that bind break and continue.
    static bool isLoop(const Stmt *s) {
        return isa<ForStmt>(s) || isa<WhileStmt>(s) || isa<DoStmt>(s) || isa<ObjCForCollectionStmt>(s) ||
               isa<CXXForRangeStmt>(s);
    }
    static bool isClosure(const Stmt *s) { return isa<BlockExpr>(s) || isa<LambdaExpr>(s); }

    static const char *scopeKind(const Stmt *s) {
        if (isa<ObjCAtTryStmt>(s)) return "@try";
        if (isa<ObjCAtCatchStmt>(s)) return "@catch";
        if (isa<ObjCAtFinallyStmt>(s)) return "@finally";
        if (isa<ObjCAtSynchronizedStmt>(s)) return "@synchronized";
        if (isa<ObjCAutoreleasePoolStmt>(s)) return "@autoreleasepool";
        if (isa<CXXTryStmt>(s)) return "try";
        if (isa<CXXCatchStmt>(s)) return "catch";
        if (isa<SwitchStmt>(s)) return "switch";
        if (isa<ForStmt>(s)) return "for";
        if (isa<WhileStmt>(s)) return "while";
        if (isa<DoStmt>(s)) return "do";
        if (isa<ObjCForCollectionStmt>(s)) return "for-in";
        if (isa<CXXForRangeStmt>(s)) return "range-for";
        if (isa<BlockExpr>(s)) return "block";
        if (isa<LambdaExpr>(s)) return "lambda";
        if (isa<StmtExpr>(s)) return "statement-expression";
        if (isa<IfStmt>(s)) return "if";
        return nullptr;
    }

    // Constructs an exit passes through that run code or change state on the
    // way out (cleanups): reported per exit.
    static bool isCleanupScope(const Stmt *s) {
        if (const ObjCAtTryStmt *t = dyn_cast<ObjCAtTryStmt>(s)) return t->getFinallyStmt() != nullptr;
        return isa<ObjCAtSynchronizedStmt>(s) || isa<ObjCAutoreleasePoolStmt>(s) || isa<ObjCAtFinallyStmt>(s) ||
               isa<CXXTryStmt>(s) || isa<ObjCAtTryStmt>(s) || isa<CXXCatchStmt>(s) || isa<ObjCAtCatchStmt>(s);
    }

    bool insideSel(Span s) const { return s.valid() && s.b >= unitsB_ && s.e <= unitsE_; }
    bool insideSel(unsigned off) const { return off != kNoOffset && off >= unitsB_ && off < unitsE_; }

    void walk(const Stmt *s) {
        if (!s) return;
        stack_.push_back(s);
        visit(s);
        if (const BlockExpr *be = dyn_cast<BlockExpr>(s)) {
            blocks_.push_back(be);
            walk(be->getBlockDecl()->getBody());
        } else if (const LambdaExpr *le = dyn_cast<LambdaExpr>(s)) {
            lambdas_.push_back(le);
            for (const Expr *init : le->capture_inits()) walk(init);
            walk(le->getBody());
        } else if (const PseudoObjectExpr *po = dyn_cast<PseudoObjectExpr>(s)) {
            walk(po->getSyntacticForm());
        } else if (const OpaqueValueExpr *ov = dyn_cast<OpaqueValueExpr>(s)) {
            if (ov->getSourceExpr() && seenOVE_.insert(ov).second) walk(ov->getSourceExpr());
        } else if (const DeclStmt *ds = dyn_cast<DeclStmt>(s)) {
            for (const Decl *d : ds->decls()) {
                const VarDecl *vd = dyn_cast<VarDecl>(d);
                if (!vd) continue;
                noteDecl(vd, ds);
                for (const Type *t = vd->getType().getTypePtrOrNull(); t;) {
                    if (const VariableArrayType *vat = dyn_cast<VariableArrayType>(t)) {
                        walk(vat->getSizeExpr());
                        t = vat->getElementType().getTypePtrOrNull();
                    } else {
                        break;
                    }
                }
                if (const Expr *init = vd->getInit()) {
                    initOf_[init] = vd;
                    walk(init);
                }
            }
        } else if (const CXXDefaultArgExpr *da = dyn_cast<CXXDefaultArgExpr>(s)) {
            scanSourceLoc(da->getExpr(), offOf(s->getBeginLoc()));
        } else if (const CXXDefaultInitExpr *di = dyn_cast<CXXDefaultInitExpr>(s)) {
            scanSourceLoc(di->getExpr(), offOf(s->getBeginLoc()));
        } else {
            for (const Stmt *c : s->children()) walk(c);
        }
        stack_.pop_back();
    }

    void scanSourceLoc(const Stmt *s, unsigned off) {
        if (!s) return;
        if (const SourceLocExpr *sl = dyn_cast<SourceLocExpr>(s)) {
            positional_.push_back({sl->getBuiltinStr().str() + " (in a default argument)", off, {}});
            return;
        }
        for (const Stmt *c : s->children()) scanSourceLoc(c, off);
    }

    void noteDecl(const VarDecl *vd, const DeclStmt *ds) {
        if (vd->isImplicit()) return;
        unsigned off = offOf(vd->getLocation());
        bool top = std::find(units_.begin(), units_.end(), (const Stmt *)ds) != units_.end();
        decls_.push_back({vd, off, insideSel(off), top});
    }

    // The innermost function-like construct (block, lambda) on the stack, or null for the function.
    const Stmt *innermostClosure(size_t from) const {
        for (size_t i = from; i-- > 0;)
            if (isClosure(stack_[i])) return stack_[i];
        return nullptr;
    }

    std::vector<std::string> crossedScopes(size_t from, size_t to, Exit &x) const {
        std::vector<std::string> v;
        for (size_t i = from; i-- > to + 1;) {
            const Stmt *s = stack_[i];
            if (isCleanupScope(s)) {
                // A try statement is crossed only when the exit is in its try body.
                x.crossed.push_back({scopeKind(s), spanOf(s).b});
            }
        }
        return v;
    }

    void exitInfo(Exit &x, const Stmt *s) {
        Span sp = spanOf(s);
        x.off = sp.b;
        x.inSel = insideSel(sp);
        x.text = textOf(sp);
        x.macros = macroChain(s->getBeginLoc(), &x.spelledInMacroBody);
    }

    void visit(const Stmt *s) {
        size_t depth = stack_.size() - 1;  // index of s

        if (const CompoundStmt *cs = dyn_cast<CompoundStmt>(s)) (void)cs;

        if (const char *k = scopeKind(s)) {
            if (!isa<IfStmt>(s)) {
                Span sp = spanOf(s);
                scopes_.push_back({k, sp.b, sp.e});
            }
        }

        if (const ReturnStmt *r = dyn_cast<ReturnStmt>(s)) {
            Exit x;
            x.kind = "return";
            exitInfo(x, s);
            size_t ci = depth;
            const Stmt *closure = nullptr;
            for (size_t i = depth; i-- > 0;)
                if (isClosure(stack_[i])) { closure = stack_[i]; ci = i; break; }
            if (closure) {
                x.target = isa<BlockExpr>(closure) ? "block" : "lambda";
                Span cs = spanOf(closure);
                x.targetOff = cs.b;
                x.targetInside = insideSel(cs);
                crossedScopes(depth, ci, x);
            } else {
                x.target = "function";
                x.targetInside = false;
                crossedScopes(depth, (size_t)-1, x);
            }
            if (const Expr *v = r->getRetValue()) {
                x.value = textOf(spanOf(v));
                Expr::EvalResult er;
                if (!v->isValueDependent() && v->EvaluateAsInt(er, ctx_)) {
                    x.hasConst = true;
                    x.constValue = er.Val.getInt().getExtValue();
                }
            }
            exits_.push_back(x);
        } else if (isa<CoreturnStmt>(s)) {
            Exit x;
            x.kind = "co_return";
            exitInfo(x, s);
            x.target = "function";
            exits_.push_back(x);
        } else if (isa<BreakStmt>(s) || isa<ContinueStmt>(s)) {
            bool brk = isa<BreakStmt>(s);
            Exit x;
            x.kind = brk ? "break" : "continue";
            exitInfo(x, s);
            for (size_t i = depth; i-- > 0;) {
                const Stmt *p = stack_[i];
                if (isClosure(p)) break;
                if (isLoop(p) || (brk && isa<SwitchStmt>(p))) {
                    x.target = isa<SwitchStmt>(p) ? "switch" : "loop";
                    Span ps = spanOf(p);
                    x.targetOff = ps.b;
                    x.targetInside = insideSel(ps);
                    crossedScopes(depth, i, x);
                    break;
                }
            }
            if (x.target.empty()) x.target = "none";
            exits_.push_back(x);
        } else if (const GotoStmt *g = dyn_cast<GotoStmt>(s)) {
            Exit x;
            x.kind = "goto";
            exitInfo(x, s);
            x.target = "label " + g->getLabel()->getNameAsString();
            if (const LabelStmt *ls = g->getLabel()->getStmt()) {
                Span lsp = spanOf(ls);
                x.targetOff = lsp.b;
                x.targetInside = insideSel(lsp);
            }
            exits_.push_back(x);
            gotos_.push_back(g);
        } else if (isa<IndirectGotoStmt>(s)) {
            Exit x;
            x.kind = "indirect-goto";
            exitInfo(x, s);
            x.target = "unknown";
            exits_.push_back(x);
            hazards_.push_back({"indirect-goto", spanOf(s).b, "goto * (computed goto): its target cannot be determined"});
        } else if (isa<AddrLabelExpr>(s)) {
            hazards_.push_back({"label-address", spanOf(s).b, "&&label (address of a label)"});
        } else if (const LabelStmt *ls = dyn_cast<LabelStmt>(s)) {
            labels_.push_back(ls);
        } else if (isa<SwitchCase>(s)) {
            // The switch it belongs to.
            for (size_t i = depth; i-- > 0;) {
                if (isClosure(stack_[i])) break;
                if (isa<SwitchStmt>(stack_[i])) {
                    cases_.push_back({s, stack_[i]});
                    break;
                }
            }
        } else if (isa<CXXThrowExpr>(s) || isa<ObjCAtThrowStmt>(s)) {
            bool rethrow = false;
            if (const CXXThrowExpr *t = dyn_cast<CXXThrowExpr>(s)) rethrow = !t->getSubExpr();
            if (const ObjCAtThrowStmt *t = dyn_cast<ObjCAtThrowStmt>(s)) rethrow = !t->getThrowExpr();
            Exit x;
            x.kind = rethrow ? "rethrow" : "throw";
            exitInfo(x, s);
            x.target = "propagates";
            for (size_t i = depth; i-- > 0;) {
                const Stmt *p = stack_[i];
                if (isClosure(p)) break;
                const Stmt *child = stack_[i + 1];
                if (rethrow && (isa<CXXCatchStmt>(p) || isa<ObjCAtCatchStmt>(p))) {
                    x.target = std::string("rethrows the exception of the ") + scopeKind(p);
                    Span ps = spanOf(p);
                    x.targetOff = ps.b;
                    x.targetInside = insideSel(ps);
                    break;
                }
                if (const CXXTryStmt *t = dyn_cast<CXXTryStmt>(p)) {
                    if (child == t->getTryBlock()) {
                        x.target = "may be caught by try";
                        Span ps = spanOf(p);
                        x.targetOff = ps.b;
                        x.targetInside = insideSel(ps);
                        break;
                    }
                }
                if (const ObjCAtTryStmt *t = dyn_cast<ObjCAtTryStmt>(p)) {
                    if (child == t->getTryBody()) {
                        x.target = "may be caught by @try";
                        Span ps = spanOf(p);
                        x.targetOff = ps.b;
                        x.targetInside = insideSel(ps);
                        break;
                    }
                }
            }
            crossedScopes(depth, (size_t)-1, x);
            exits_.push_back(x);
        } else if (const CallExpr *ce = dyn_cast<CallExpr>(s)) {
            visitCall(ce, depth);
        } else if (const ObjCMessageExpr *me = dyn_cast<ObjCMessageExpr>(s)) {
            if (me->getReceiverKind() == ObjCMessageExpr::SuperInstance ||
                me->getReceiverKind() == ObjCMessageExpr::SuperClass)
                selfUses_.push_back({"super", me->getSelector().getAsString(), spanOf(s).b, "message",
                                     insideSel(spanOf(s))});
            if (const ObjCMethodDecl *md = me->getMethodDecl()) {
                if (md->hasAttr<NoReturnAttr>()) {
                    Exit x;
                    x.kind = "noreturn-call";
                    exitInfo(x, s);
                    x.target = "never returns";
                    x.callee = md->getSelector().getAsString();
                    exits_.push_back(x);
                }
            }
        } else if (const ObjCPropertyRefExpr *pr = dyn_cast<ObjCPropertyRefExpr>(s)) {
            if (pr->isSuperReceiver())
                selfUses_.push_back({"super", "property", spanOf(s).b, "property", insideSel(spanOf(s))});
        } else if (isa<CXXThisExpr>(s)) {
            Span sp = spanOf(s);
            selfUses_.push_back({"this", cast<CXXThisExpr>(s)->isImplicit() ? "implicit" : "explicit", sp.b,
                                 classify(depth).first, insideSel(sp)});
        } else if (const ObjCIvarRefExpr *iv = dyn_cast<ObjCIvarRefExpr>(s)) {
            Span sp = spanOf(s);
            selfUses_.push_back({iv->isFreeIvar() ? "ivar" : "ivar-explicit-base", iv->getDecl()->getNameAsString(),
                                 sp.b, classify(depth).first, insideSel(sp)});
        } else if (const PredefinedExpr *pe = dyn_cast<PredefinedExpr>(s)) {
            bool body;
            positional_.push_back({pe->getIdentKindName().str(), spanOf(s).b, macroChain(s->getBeginLoc(), &body)});
        } else if (const SourceLocExpr *sl = dyn_cast<SourceLocExpr>(s)) {
            bool body;
            positional_.push_back({sl->getBuiltinStr().str(), spanOf(s).b, macroChain(s->getBeginLoc(), &body)});
        } else if (isa<VAArgExpr>(s)) {
            hazards_.push_back({"va_arg", spanOf(s).b, "va_arg reads the variadic arguments of the function it is in"});
        } else if (const MaterializeTemporaryExpr *mt = dyn_cast<MaterializeTemporaryExpr>(s)) {
            if (const ValueDecl *ext = mt->getExtendingDecl()) {
                if (const VarDecl *v = dyn_cast<VarDecl>(ext))
                    if (v->hasLocalStorage())
                        hazards_.push_back({"lifetime-extended-temporary", spanOf(s).b,
                                            "a temporary whose lifetime is extended to that of " + v->getNameAsString()});
            }
        } else if (isa<CompoundLiteralExpr>(s)) {
            visitCompoundLiteral(s, depth);
        } else if (const DeclRefExpr *dr = dyn_cast<DeclRefExpr>(s)) {
            visitDeclRef(dr, depth);
        }
    }

    // A compound literal at the top level of the range (not inside a nested
    // compound statement) lives to the end of the enclosing scope; its address
    // taken there dangles once a helper returns.
    void visitCompoundLiteral(const Stmt *s, size_t depth) {
        Span sp = spanOf(s);
        if (!insideSel(sp) || depth == 0) return;
        const Stmt *p = stack_[depth - 1];
        bool escapes = false;
        if (const UnaryOperator *uo = dyn_cast<UnaryOperator>(p)) escapes = uo->getOpcode() == UO_AddrOf;
        if (const ImplicitCastExpr *ic = dyn_cast<ImplicitCastExpr>(p)) escapes = ic->getCastKind() == CK_ArrayToPointerDecay;
        if (!escapes) return;
        for (size_t i = depth; i-- > 0;) {
            if (isa<CompoundStmt>(stack_[i]) || isClosure(stack_[i])) {
                if (stack_[i] == compound_)
                    hazards_.push_back({"block-local-address", sp.b, "the address of a compound literal at the top "
                                        "level of the range is taken here: if it is stored where it is used after "
                                        "the range, it dangles once the helper returns"});
                return;
            }
        }
    }

    void visitCall(const CallExpr *ce, size_t depth) {
        const FunctionDecl *fd = ce->getDirectCallee();
        bool noreturn = false;
        std::string name;
        if (fd) {
            name = fd->getNameAsString();
            noreturn = fd->isNoReturn();
        }
        if (!noreturn) {
            QualType ct = ce->getCallee()->getType();
            if (const PointerType *pt = ct->getAs<PointerType>()) ct = pt->getPointeeType();
            if (const FunctionType *ft = ct->getAs<FunctionType>()) noreturn = ft->getNoReturnAttr();
        }
        if (noreturn) {
            Exit x;
            x.kind = "noreturn-call";
            exitInfo(x, ce);
            x.target = "never returns";
            x.callee = name;
            exits_.push_back(x);
        }
        unsigned id = fd ? fd->getBuiltinID() : 0;
        Span sp = spanOf(ce);
        static const std::set<std::string> jmp = {"setjmp", "_setjmp", "sigsetjmp", "__sigsetjmp", "longjmp",
                                                  "_longjmp", "siglongjmp", "__builtin_setjmp", "__builtin_longjmp"};
        if (jmp.count(name)) hazards_.push_back({"setjmp-longjmp", sp.b, name + ": a jump buffer is valid only while the frame that called setjmp is live"});
        switch (id) {
        case Builtin::BI__builtin_alloca:
        case Builtin::BI__builtin_alloca_uninitialized:
        case Builtin::BI__builtin_alloca_with_align:
        case Builtin::BI__builtin_alloca_with_align_uninitialized:
        case Builtin::BIalloca:
            hazards_.push_back({"alloca", sp.b, name + ": the memory is freed when the function that called it returns"});
            break;
        case Builtin::BI__builtin_va_start:
        case Builtin::BI__builtin_c23_va_start:
        case Builtin::BI__va_start:
        case Builtin::BI__builtin_va_end:
        case Builtin::BI__builtin_va_copy:
        case Builtin::BIva_start:
        case Builtin::BIva_end:
        case Builtin::BIva_copy:
            hazards_.push_back({"va_list", sp.b, name + ": refers to the variadic arguments of the function it is in"});
            break;
        case Builtin::BI__builtin_frame_address:
        case Builtin::BI__builtin_return_address:
            hazards_.push_back({"frame-address", sp.b, name + ": its value is that of the function it is in"});
            break;
        default:
            break;
        }
        if (name == "alloca" && id == 0)
            hazards_.push_back({"alloca", sp.b, "alloca: the memory is freed when the function that called it returns"});
        (void)depth;
    }

    // The innermost block or lambda on the stack above index `i`, within the walked function.
    const Stmt *closureOf(size_t i) const { return innermostClosure(i); }

    void visitDeclRef(const DeclRefExpr *dr, size_t depth) {
        const ValueDecl *d = dr->getDecl();
        Span sp = spanOf(dr);
        if (isa<BindingDecl>(d)) {
            if (insideSel(sp))
                hazards_.push_back({"structured-binding", sp.b, "the structured binding " + d->getNameAsString() +
                                    " is not analyzed: how the block reads or writes it is unknown"});
            return;
        }
        const VarDecl *vd = dyn_cast<VarDecl>(d);
        if (!vd) return;
        if (vd->hasGlobalStorage() && !vd->isStaticLocal() && !isa<ImplicitParamDecl>(vd)) {
            globalRefs_.push_back({vd, sp.b, classify(depth).first, insideSel(sp)});
            return;
        }
        if (method_ && (vd == method_->getSelfDecl() || vd == method_->getCmdDecl())) {
            bool self = vd == method_->getSelfDecl();
            selfUses_.push_back({self ? "self" : "_cmd", self ? "self" : "_cmd", sp.b, classify(depth).first,
                                 insideSel(sp)});
            if (!self) return;
        }
        bool local = vd->isLocalVarDeclOrParm() || isa<ImplicitParamDecl>(vd);
        if (!local) return;
        if (method_ && vd == method_->getCmdDecl()) return;
        Ref r;
        r.decl = vd;
        r.off = sp.b == kNoOffset ? offOf(dr->getLocation()) : sp.b;
        auto c = classify(depth);
        r.use = c.first;
        r.why = c.second;
        r.inSel = insideSel(sp.valid() ? sp : Span{r.off, r.off + 1});
        if (r.use == "read") r.through = throughPointer(depth);
        if (r.inSel && r.use == "unevaluated" && vd->getType()->isConstantArrayType()) {
            unsigned dOff = offOf(vd->getLocation());
            size_t k = depth;
            while (k > 0 && isa<ParenExpr>(stack_[k - 1])) k--;
            if (!insideSel(dOff) && k > 0) {
                if (const UnaryExprOrTypeTraitExpr *ue = dyn_cast<UnaryExprOrTypeTraitExpr>(stack_[k - 1]))
                    if (ue->getKind() == UETT_SizeOf)
                        hazards_.push_back({"sizeof-array", r.off, "sizeof applied to the array " + vd->getNameAsString() +
                                            ", declared outside the range: passed to a helper it becomes a pointer and "
                                            "sizeof gives the size of the pointer"});
            }
        }
        if (r.inSel && (r.use == "address-taken" || r.use == "by-reference")) {
            for (const DeclInfo &di : decls_)
                if (di.vd == vd && di.topLevelInSel)
                    hazards_.push_back({"block-local-address", r.off, "the address of " + vd->getNameAsString() +
                                        ", declared in the range, is taken here: if it is stored where it is used "
                                        "after the range, it dangles once the helper returns (in the original it "
                                        "lived to the end of the enclosing scope)"});
        }
        const Stmt *cl = closureOf(depth);
        r.closure = cl;
        if (cl && declaredOutside(vd, cl)) {
            if (const BlockExpr *be = dyn_cast<BlockExpr>(cl)) {
                bool byref = vd->hasAttr<BlocksAttr>();
                for (const BlockDecl::Capture &cap : be->getBlockDecl()->captures())
                    if (cap.getVariable() == vd) byref = cap.isByRef();
                r.capture = byref ? "block-byref" : "block-copy";
            } else if (const LambdaExpr *le = dyn_cast<LambdaExpr>(cl)) {
                r.capture = "lambda-unknown";
                for (const LambdaCapture &cap : le->captures()) {
                    if (cap.capturesVariable() && cap.getCapturedVar() == vd)
                        r.capture = cap.getCaptureKind() == LCK_ByRef ? "lambda-byref" : "lambda-copy";
                }
            }
        }
        refs_.push_back(r);
    }

    bool declaredOutside(const VarDecl *vd, const Stmt *closure) const {
        Span cs = spanOf(closure);
        unsigned o = offOf(vd->getLocation());
        if (!cs.valid() || o == kNoOffset) return true;
        return o < cs.b || o >= cs.e;
    }

    static const Stmt *strip(const Stmt *s) { return s; }

    // For a pointer that is read at stack_[i]: how the object it points to is
    // used, when the read is the base of a dereference (*p, p->f, p[k]);
    // empty otherwise.
    std::string throughPointer(size_t i) const {
        size_t j = i;
        while (j > 0) {
            const Stmt *p = stack_[j - 1];
            if (isa<ParenExpr>(p)) { j--; continue; }
            if (const ImplicitCastExpr *ic = dyn_cast<ImplicitCastExpr>(p)) {
                if (ic->getCastKind() == CK_LValueToRValue || ic->getCastKind() == CK_NoOp) { j--; continue; }
            }
            break;
        }
        if (j == 0) return "";
        const Stmt *cur = stack_[j];
        const Stmt *p = stack_[j - 1];
        bool deref = false;
        if (const UnaryOperator *uo = dyn_cast<UnaryOperator>(p)) deref = uo->getOpcode() == UO_Deref;
        else if (const MemberExpr *me = dyn_cast<MemberExpr>(p)) deref = me->isArrow() && me->getBase() == cur;
        else if (const ArraySubscriptExpr *as = dyn_cast<ArraySubscriptExpr>(p)) deref = as->getBase() == cur;
        if (!deref) return "";
        return classify(j - 1).first;
    }

    // How the expression at stack_[i] (a DeclRefExpr, ivar reference or this) is used.
    std::pair<std::string, std::string> classify(size_t i) const {
        bool partial = false;
        size_t j = i;
        while (true) {
            if (j == 0) return {"unknown", "no parent"};
            const Stmt *cur = stack_[j];
            const Stmt *p = stack_[j - 1];
            if (isa<ParenExpr>(p) || isa<OpaqueValueExpr>(p) || isa<ConstantExpr>(p) || isa<FullExpr>(p)) {
                j--;
                continue;
            }
            if (const ImplicitCastExpr *ic = dyn_cast<ImplicitCastExpr>(p)) {
                switch (ic->getCastKind()) {
                case CK_NoOp:
                    j--;
                    continue;
                case CK_LValueToRValue:
                case CK_LValueToRValueBitCast:
                    return {partial ? "read" : "read", ""};
                case CK_ArrayToPointerDecay:
                    if (j >= 2) {
                        const Stmt *gp = stack_[j - 2];
                        if (const ArraySubscriptExpr *as = dyn_cast<ArraySubscriptExpr>(gp)) {
                            if (as->getBase()->IgnoreParens() == ic || as->getBase() == ic) {
                                partial = true;
                                j -= 2;
                                continue;
                            }
                        }
                    }
                    return {"address-taken", "array decays to a pointer"};
                default:
                    return {"unknown", std::string("implicit cast ") + ic->getCastKindName()};
                }
            }
            if (const ExtVectorElementExpr *ev = dyn_cast<ExtVectorElementExpr>(p)) {
                if (ev->getBase() == cur || ev->getBase()->IgnoreParens() == cur) {
                    partial = true;
                    j--;
                    continue;
                }
                return {"unknown", "vector element"};
            }
            if (const MemberExpr *me = dyn_cast<MemberExpr>(p)) {
                if (me->getBase() == cur || me->getBase()->IgnoreParenImpCasts() == cur) {
                    if (me->isArrow()) return {"read", ""};
                    if (const CXXMethodDecl *m = dyn_cast<CXXMethodDecl>(me->getMemberDecl())) {
                        if (m->isConst() || m->isStatic()) return {"read", "const member function"};
                        return {"read-write", "non-const member function " + m->getNameAsString()};
                    }
                    partial = true;
                    j--;
                    continue;
                }
                return {"unknown", "member expression"};
            }
            if (const ArraySubscriptExpr *as = dyn_cast<ArraySubscriptExpr>(p)) {
                if (as->getBase() == cur) {
                    partial = true;
                    j--;
                    continue;
                }
                return {"read", "array index"};
            }
            if (const BinaryOperator *bo = dyn_cast<BinaryOperator>(p)) {
                if (bo->getLHS() == cur || bo->getLHS()->IgnoreParens() == cur) {
                    if (bo->getOpcode() == BO_Assign) return {partial ? "read-write" : "write", partial ? "assignment to a part" : ""};
                    if (bo->isCompoundAssignmentOp()) return {"read-write", "compound assignment"};
                    if (bo->getOpcode() == BO_Comma) return {"unevaluated", "left operand of a comma, discarded"};
                }
                // The value assigned through a property setter or a subscript
                // (the left side is a pseudo-object) is read.
                if (bo->getOpcode() == BO_Assign && bo->getRHS() == cur &&
                    (isa<ObjCPropertyRefExpr>(bo->getLHS()->IgnoreParens()) ||
                     isa<ObjCSubscriptRefExpr>(bo->getLHS()->IgnoreParens())))
                    return {"read", "assigned through a property or subscript"};
                if (bo->getOpcode() == BO_Comma && bo->getRHS() == cur) {
                    j--;
                    continue;
                }
                return {"unknown", std::string("operand of ") + bo->getOpcodeStr().str()};
            }
            if (const UnaryOperator *uo = dyn_cast<UnaryOperator>(p)) {
                if (uo->isIncrementDecrementOp()) return {"read-write", "increment or decrement"};
                if (uo->getOpcode() == UO_AddrOf) return {"address-taken", "&"};
                if (uo->getOpcode() == UO_Real || uo->getOpcode() == UO_Imag || uo->getOpcode() == UO_Extension) {
                    j--;
                    continue;
                }
                return {"unknown", std::string("operand of unary ") + UnaryOperator::getOpcodeStr(uo->getOpcode()).str()};
            }
            if (isa<ConditionalOperator>(p)) {
                const ConditionalOperator *co = cast<ConditionalOperator>(p);
                if (co->getCond() == cur) return {"unknown", "condition"};
                j--;
                continue;
            }
            if (const CallExpr *ce = dyn_cast<CallExpr>(p)) {
                return classifyCallArg(ce, cur);
            }
            if (const CXXConstructExpr *cc = dyn_cast<CXXConstructExpr>(p)) {
                const CXXConstructorDecl *ctor = cc->getConstructor();
                for (unsigned k = 0; k < cc->getNumArgs(); k++) {
                    if (cc->getArg(k) == cur && ctor && k < ctor->getNumParams())
                        return refParam(ctor->getParamDecl(k)->getType(), "constructor argument");
                }
                return {"unknown", "constructor argument"};
            }
            if (isa<DeclStmt>(p)) {
                auto it = initOf_.find(dyn_cast<Expr>(cur));
                if (it != initOf_.end()) {
                    const VarDecl *v = it->second;
                    if (v->isImplicit() && j >= 2 && isa<CXXForRangeStmt>(stack_[j - 2]))
                        return {"read-write", "iterated by reference in a range-based for"};
                    if (v->getType()->isReferenceType()) {
                        QualType pt = v->getType()->getPointeeType();
                        if (pt.isConstQualified()) return {"read", "bound to a const reference"};
                        return {"by-reference", "bound to the reference " + v->getNameAsString()};
                    }
                }
                return {"unknown", "initializer"};
            }
            if (const ObjCForCollectionStmt *fc = dyn_cast<ObjCForCollectionStmt>(p)) {
                if (fc->getElement() == cur) return {"write", "element of for-in"};
                return {"unknown", "for-in"};
            }
            if (const GCCAsmStmt *as = dyn_cast<GCCAsmStmt>(p)) {
                for (unsigned k = 0; k < as->getNumOutputs(); k++)
                    if (as->getOutputExpr(k) == cur)
                        return {as->isOutputPlusConstraint(k) ? "read-write" : "write", "asm output"};
                return {"read-write", "asm operand"};
            }
            if (isa<UnaryExprOrTypeTraitExpr>(p) || isa<CXXTypeidExpr>(p) || isa<CXXNoexceptExpr>(p))
                return {"unevaluated", "sizeof or similar"};
            if (const CStyleCastExpr *cs = dyn_cast<CStyleCastExpr>(p)) {
                if (cs->getCastKind() == CK_ToVoid) return {"unevaluated", "cast to void"};
                if (cs->getCastKind() == CK_NoOp) {
                    j--;
                    continue;
                }
                return {"unknown", std::string("cast ") + cs->getCastKindName()};
            }
            if (const LambdaExpr *le = dyn_cast<LambdaExpr>(p)) {
                (void)le;
                return {"by-reference", "captured by reference by a lambda"};
            }
            if (isa<ReturnStmt>(p)) return {"by-reference", "returned as a reference"};
            if (isa<CXXDependentScopeMemberExpr>(p) || isa<UnresolvedMemberExpr>(p) || isa<CXXUnresolvedConstructExpr>(p))
                return {"unknown", "dependent expression in a template"};
            return {"unknown", std::string("used by ") + p->getStmtClassName()};
        }
    }

    std::pair<std::string, std::string> refParam(QualType t, const std::string &what) const {
        if (t->isReferenceType()) {
            QualType pt = t->getPointeeType();
            if (pt.isConstQualified() && !t->isRValueReferenceType()) return {"read", what + " by const reference"};
            if (t->isRValueReferenceType()) return {"read-write", what + " by rvalue reference (may be moved from)"};
            return {"by-reference", what + " by non-const reference"};
        }
        return {"read", what};
    }

    std::pair<std::string, std::string> classifyCallArg(const CallExpr *ce, const Stmt *cur) const {
        if (const CXXMemberCallExpr *mc = dyn_cast<CXXMemberCallExpr>(ce)) (void)mc;
        const FunctionDecl *fd = ce->getDirectCallee();
        if (const CXXOperatorCallExpr *oc = dyn_cast<CXXOperatorCallExpr>(ce)) {
            if (const CXXMethodDecl *m = dyn_cast_or_null<CXXMethodDecl>(fd)) {
                if (oc->getArg(0) == cur) {
                    if (m->isConst()) return {"read", "const operator"};
                    return {"read-write", "non-const operator " + m->getNameAsString()};
                }
                for (unsigned k = 1; k < oc->getNumArgs(); k++)
                    if (oc->getArg(k) == cur && k - 1 < m->getNumParams())
                        return refParam(m->getParamDecl(k - 1)->getType(), "operator argument");
            }
        }
        if (ce->getCallee() == cur) return {"read", "called"};
        if (!fd) return {"unknown", "argument of a call with no known callee"};
        for (unsigned k = 0; k < ce->getNumArgs(); k++) {
            if (ce->getArg(k) == cur) {
                if (k < fd->getNumParams()) return refParam(fd->getParamDecl(k)->getType(), "argument");
                return {"unknown", "variadic or builtin argument of " + fd->getNameAsString()};
            }
        }
        return {"unknown", "call"};
    }

    // ------------------------------------------------ selection

    // Raw tokens of the main file in [b, e), with directive lines and skipped
    // ranges left out.
    struct Tok {
        unsigned off, end;
        std::string text;
    };

    std::vector<Tok> rawTokens(unsigned b, unsigned e) const {
        std::vector<Tok> out;
        if (b >= buf_.size()) return out;
        Lexer lex(sm_.getLocForStartOfFile(mainFID_), lo_, buf_.begin(), buf_.begin() + b, buf_.end());
        Token t;
        bool inDirective = false;
        while (true) {
            lex.LexFromRawLexer(t);
            if (t.is(tok::eof)) break;
            unsigned o = sm_.getFileOffset(t.getLocation());
            if (o >= e) break;
            if (t.isAtStartOfLine()) inDirective = t.is(tok::hash);
            if (inDirective) continue;
            bool skipped = false;
            for (const Skipped &s : pf_.skipped)
                if (o >= s.begin && o < s.end) skipped = true;
            if (skipped) continue;
            out.push_back({o, o + t.getLength(), buf_.substr(o, t.getLength()).str()});
        }
        return out;
    }

    // The span of a statement, extended over a following ';'.
    Span extended(const Stmt *s) const {
        Span sp = spanOf(s);
        if (!sp.valid()) return sp;
        std::vector<Tok> next = rawTokens(sp.e, std::min<unsigned>(sp.e + 4096, buf_.size()));
        size_t k = 0;
        // Clang's range for "@throw;" (a rethrow) ends at the '@'.
        if (const ObjCAtThrowStmt *t = dyn_cast<ObjCAtThrowStmt>(s))
            if (!t->getThrowExpr() && k < next.size() && next[k].text == "throw") sp.e = next[k++].end;
        if (k < next.size() && next[k].text == ";") sp.e = next[k].end;
        return sp;
    }

    class CompoundFinder : public RecursiveASTVisitor<CompoundFinder> {
    public:
        bool VisitCompoundStmt(CompoundStmt *c) { compounds.push_back(c); return true; }
        bool VisitBlockExpr(BlockExpr *b) { closures.push_back(b); return true; }
        bool VisitLambdaExpr(LambdaExpr *l) { closures.push_back(l); return true; }
        bool shouldVisitLambdaBody() const { return true; }
        std::vector<const CompoundStmt *> compounds;
        std::vector<const Stmt *> closures;
    };

    bool selectUnits(const Stmt *child, unsigned selB, unsigned selE, std::string &why) {
        Span x = extended(child);
        if (!x.valid()) {
            why = "a statement at line " + std::to_string(lineOf(offOf(child->getBeginLoc()))) +
                  " is not written in the main file";
            return false;
        }
        if (x.e <= selB || x.b >= selE) return true;  // no overlap
        if (x.b >= selB && x.e <= selE) {
            units_.push_back(child);
            return true;
        }
        // A label (case, default or a goto label) before the range, with its
        // statement inside: the statement is the unit.
        if (const SwitchCase *sc = dyn_cast<SwitchCase>(child)) {
            if (offOf(sc->getKeywordLoc()) < selB) return selectUnits(sc->getSubStmt(), selB, selE, why);
        }
        if (const LabelStmt *ls = dyn_cast<LabelStmt>(child)) {
            if (offOf(ls->getIdentLoc()) < selB) return selectUnits(ls->getSubStmt(), selB, selE, why);
        }
        why = "the range covers part of the " + std::string(child->getStmtClassName()) + " at lines " +
              std::to_string(lineOf(x.b)) + "-" + std::to_string(lineOf(x.e - 1)) +
              " but not all of it";
        return false;
    }

    // ------------------------------------------------ range mode

    J runRange(unsigned first, unsigned last) {
        J out = J::obj();
        out.set("mode", "range");
        out.set("errors", errors_);
        unsigned nlines = sm_.getLineNumber(mainFID_, buf_.size() ? buf_.size() - 1 : 0);
        if (first < 1 || last < first || last > nlines) {
            out.set("error", "the range " + std::to_string(first) + "-" + std::to_string(last) +
                                 " is not within the file's " + std::to_string(nlines) + " lines");
            return out;
        }
        unsigned selB = lineStart(first), selE = lineEnd(last);
        std::vector<Tok> toks = rawTokens(selB, selE);
        J sel = J::obj();
        sel.set("first", first);
        sel.set("last", last);
        if (toks.empty()) {
            out.set("error", "the range holds no code (only comments, blank lines, directives or code that is not compiled)");
            addSkipped(out, selB, selE, kNoOffset, kNoOffset);
            return out;
        }
        FnLike fn = findFunction(toks.front().off, toks.back().end);
        if (!fn.decl) {
            out.set("error", "no function body contains lines " + std::to_string(first) + "-" + std::to_string(last));
            return out;
        }
        method_ = dyn_cast<ObjCMethodDecl>(fn.decl);
        CompoundFinder cf;
        cf.TraverseStmt(const_cast<Stmt *>(fn.body));
        const CompoundStmt *best = nullptr;
        unsigned bestSize = ~0u;
        for (const CompoundStmt *c : cf.compounds) {
            unsigned lb = offOf(c->getLBracLoc()), rb = offOf(c->getRBracLoc());
            if (lb == kNoOffset || rb == kNoOffset) continue;
            if (lb < toks.front().off && rb >= toks.back().end && rb - lb < bestSize) {
                best = c;
                bestSize = rb - lb;
            }
        }
        std::string why;
        bool aligned = best != nullptr;
        if (!best) why = "no compound statement contains the range";
        if (aligned) {
            for (const Stmt *c : best->body())
                if (!selectUnits(c, selB, selE, why)) {
                    aligned = false;
                    break;
                }
        }
        if (aligned && units_.empty()) {
            aligned = false;
            why = "the range contains no whole statement";
        }
        std::vector<J> noStmtMacros;
        if (aligned) {
            std::vector<Span> spans;
            for (const Stmt *u : units_) spans.push_back(extended(u));
            unitsB_ = spans.front().b;
            unitsE_ = spans.back().e;
            for (const Tok &t : toks) {
                bool ok = false;
                for (const Span &s : spans)
                    if (t.off >= s.b && t.end <= s.e) ok = true;
                if (!ok) {
                    // A macro invocation that expanded to no statement.
                    for (const MacroUse &m : pf_.macros)
                        if (m.topLevel && t.off >= m.begin && t.end <= m.end) ok = true;
                }
                if (!ok && t.text == ";") ok = true;  // an empty statement the AST folds away
                if (!ok) {
                    aligned = false;
                    why = "the token '" + t.text + "' at line " + std::to_string(lineOf(t.off)) +
                          " is not part of a whole statement inside the range";
                    break;
                }
            }
        }
        sel.set("aligned", aligned);
        if (!aligned) {
            sel.set("reason", why);
            out.set("selection", sel);
            out.set("function", fnJson(fn.decl, fn.body));
            addSkipped(out, selB, selE, kNoOffset, kNoOffset);
            return out;
        }
        // The innermost function-like construct containing the range.
        const Stmt *closure = nullptr;
        unsigned closureSize = ~0u;
        for (const Stmt *c : cf.closures) {
            Span s = spanOf(c);
            if (s.valid() && s.b <= unitsB_ && s.e >= unitsE_ && s.e - s.b < closureSize) {
                closure = c;
                closureSize = s.e - s.b;
            }
        }
        compound_ = best;
        walk(fn.body);

        J units = J::arr();
        for (const Stmt *u : units_) {
            Span s = extended(u);
            units.push(J::obj().set("kind", u->getStmtClassName()).set("line", lineOf(s.b)).set("end_line", lineOf(s.e - 1)));
        }
        sel.set("statements", units);
        sel.set("compound_line", lineOf(offOf(best->getLBracLoc())));
        sel.set("tail", isTail(best, units_.back(), fn.body, closure));
        // The statement after the range in the same compound statement.
        {
            const Stmt *after = nullptr;
            bool seen = false;
            for (const Stmt *c : best->body()) {
                if (seen) { after = c; break; }
                Span cs = spanOf(c);
                if (cs.valid() && cs.b <= spanOf(units_.back()).b && cs.e >= spanOf(units_.back()).e) seen = true;
            }
            if (after) {
                Span as = spanOf(after);
                sel.set("next", J::obj().set("kind", after->getStmtClassName()).set("line", lineOf(as.b))
                                    .set("text", textOf(as)));
            }
        }
        out.set("selection", sel);
        J fj = fnJson(fn.decl, fn.body);
        if (closure) {
            Span cs = spanOf(closure);
            fj.set("closure", J::obj().set("kind", isa<BlockExpr>(closure) ? "block" : "lambda").set("line", lineOf(cs.b)));
        }
        out.set("function", fj);

        Span fnSpan = closure ? spanOf(closure) : spanOf(fn.body);
        emitRangeFacts(out, fnSpan, closure);
        addSkipped(out, selB, selE, unitsE_, fnSpan.e);
        return out;
    }

    // Whether falling off the end of `last` (a child of `c`) ends the function.
    bool isTail(const CompoundStmt *c, const Stmt *last, const Stmt *body, const Stmt *closure) {
        if (c->body_back() != last) return false;
        const Stmt *node = c;
        const Stmt *top = closure ? (isa<BlockExpr>(closure) ? cast<BlockExpr>(closure)->getBlockDecl()->getBody()
                                                            : cast<LambdaExpr>(closure)->getBody())
                                  : body;
        // Walk up the parents of `node` using a fresh search from `top`.
        std::vector<const Stmt *> path;
        if (!findPath(top, node, path)) return false;
        for (size_t i = path.size() - 1; i > 0; i--) {
            const Stmt *child = path[i];
            const Stmt *parent = path[i - 1];
            if (const CompoundStmt *pc = dyn_cast<CompoundStmt>(parent)) {
                if (pc->body_back() != child) return false;
            } else if (isa<IfStmt>(parent) || isa<LabelStmt>(parent) || isa<AttributedStmt>(parent)) {
                if (const IfStmt *is = dyn_cast<IfStmt>(parent))
                    if (is->getCond() == child) return false;
            } else {
                return false;
            }
        }
        return true;
    }

    bool findPath(const Stmt *from, const Stmt *to, std::vector<const Stmt *> &path) {
        if (!from) return false;
        path.push_back(from);
        if (from == to) return true;
        for (const Stmt *c : from->children())
            if (findPath(c, to, path)) return true;
        path.pop_back();
        return false;
    }

    void addSkipped(J &out, unsigned selB, unsigned selE, unsigned afterB, unsigned afterE) {
        J in = J::arr(), after = J::arr();
        for (const Skipped &s : pf_.skipped) {
            unsigned sl = lineOf(s.begin), el = lineOf(s.end ? s.end - 1 : 0);
            if (s.begin < selE && s.end > selB) in.push(J::obj().set("first", sl).set("last", el));
            else if (afterB != kNoOffset && s.begin >= afterB && s.begin < afterE)
                after.push(J::obj().set("first", sl).set("last", el));
        }
        out.set("skipped_in_range", in);
        out.set("skipped_after_range", after);
        J conds = J::arr();
        for (const Conditional &c : pf_.conditionals)
            if (c.offset >= selB && c.offset < selE) conds.push(J::obj().set("kind", c.kind).set("line", lineOf(c.offset)));
        out.set("conditionals_in_range", conds);
    }

    J exitJson(const Exit &x) const {
        J j = J::obj();
        j.set("kind", x.kind);
        j.set("line", lineOf(x.off));
        j.set("text", x.text);
        j.set("target", x.target);
        if (x.targetOff != kNoOffset) j.set("target_line", lineOf(x.targetOff));
        j.set("target_inside", x.targetInside);
        if (!x.value.empty()) j.set("value", x.value);
        if (x.hasConst) j.set("const_value", x.constValue);
        if (!x.callee.empty()) j.set("callee", x.callee);
        J cr = J::arr();
        for (auto &c : x.crossed)
            cr.push(J::obj().set("kind", c.first).set("line", lineOf(c.second)).set("inside", insideSel(c.second)));
        j.set("crosses", cr);
        J m = J::arr();
        for (auto &n : x.macros) m.push(J::str(n));
        j.set("macros", m);
        j.set("in_macro_body", x.spelledInMacroBody);
        return j;
    }

    void emitRangeFacts(J &out, Span fnSpan, const Stmt *closure) {
        // Exits from inside the range.
        J exits = J::arr();
        for (const Exit &x : exits_)
            if (x.inSel) exits.push(exitJson(x));
        out.set("exits", exits);

        // Entries: a goto from outside to a label inside, a case or default of a
        // switch outside.
        J entries = J::arr();
        for (const GotoStmt *g : gotos_) {
            const LabelStmt *ls = g->getLabel()->getStmt();
            if (!ls) continue;
            Span gs = spanOf(g), lsp = spanOf(ls);
            if (!insideSel(gs) && insideSel(lsp))
                entries.push(J::obj().set("kind", "goto").set("line", lineOf(lsp.b)).set("from_line", lineOf(gs.b))
                                 .set("label", g->getLabel()->getNameAsString()));
        }
        for (auto &c : cases_) {
            Span cs = spanOf(c.first), ss = spanOf(c.second);
            if (insideSel(cs) && !insideSel(ss))
                entries.push(J::obj().set("kind", isa<CaseStmt>(c.first) ? "case" : "default").set("line", lineOf(cs.b))
                                 .set("from_line", lineOf(ss.b)));
        }
        out.set("entries", entries);

        // Scopes enclosing the range and inside it.
        J enclosing = J::arr(), inside = J::arr();
        for (const Scope &s : scopes_) {
            if (s.off <= unitsB_ && s.end >= unitsE_ && !(s.off >= unitsB_ && s.end <= unitsE_)) {
                if (s.off >= fnSpan.b || (closure == nullptr))
                    enclosing.push(J::obj().set("kind", s.kind).set("line", lineOf(s.off)));
                else
                    enclosing.push(J::obj().set("kind", s.kind).set("line", lineOf(s.off)).set("outside_function", true));
            } else if (s.off >= unitsB_ && s.end <= unitsE_) {
                inside.push(J::obj().set("kind", s.kind).set("line", lineOf(s.off)));
            }
        }
        out.set("scopes_enclosing", enclosing);
        out.set("scopes_inside", inside);

        // Variables declared outside the range and referenced inside it.
        std::map<const ValueDecl *, std::vector<const Ref *>> byVar;
        std::vector<const ValueDecl *> order;
        for (const Ref &r : refs_) {
            if (!r.inSel) continue;
            const VarDecl *vd = cast<VarDecl>(r.decl);
            unsigned dOff = offOf(vd->getLocation());
            if (insideSel(dOff)) continue;
            if (!byVar.count(r.decl)) order.push_back(r.decl);
            byVar[r.decl].push_back(&r);
        }
        // Loops enclosing the range (within the function-like construct): any
        // reference inside them may run after the range in a later iteration.
        std::vector<Span> loops;
        for (const Scope &s : scopes_) {
            bool loop = s.kind == "for" || s.kind == "while" || s.kind == "do" || s.kind == "for-in" ||
                        s.kind == "range-for";
            if (loop && s.off <= unitsB_ && s.end >= unitsE_ && s.off >= fnSpan.b && s.end <= fnSpan.e)
                loops.push_back({s.off, s.end});
        }
        // Backward gotos that jump from after the range to a label before it.
        std::vector<Span> backward;
        for (const GotoStmt *g : gotos_) {
            const LabelStmt *ls = g->getLabel()->getStmt();
            if (!ls) continue;
            unsigned go = spanOf(g).b, lo = spanOf(ls).b;
            if (go >= unitsE_ && lo < unitsB_ && lo >= fnSpan.b) backward.push_back({lo, unitsB_});
        }
        J vars = J::arr();
        for (const ValueDecl *d : order) {
            const VarDecl *vd = cast<VarDecl>(d);
            J v = varType(vd);
            v.set("name", vd->getNameAsString());
            unsigned dOff = offOf(vd->getLocation());
            v.set("decl_line", lineOf(dOff));
            const char *kind = "local";
            if (isa<ParmVarDecl>(vd)) kind = "parameter";
            else if (isa<ImplicitParamDecl>(vd)) kind = vd->getNameAsString() == "self" ? "self" : "implicit-parameter";
            else if (vd->isStaticLocal()) kind = "static-local";
            v.set("kind", kind);
            bool outsideFn = closure && (dOff == kNoOffset || dOff < fnSpan.b || dOff >= fnSpan.e);
            v.set("declared_outside_closure", outsideFn);
            J uses = J::arr();
            for (const Ref *r : byVar[d]) {
                J u = J::obj().set("line", lineOf(r->off)).set("use", r->use);
                if (!r->why.empty()) u.set("why", r->why);
                if (!r->through.empty()) u.set("through", r->through);
                if (!r->capture.empty()) {
                    u.set("capture", r->capture);
                    u.set("closure_line", lineOf(spanOf(r->closure).b));
                }
                uses.push(u);
            }
            v.set("uses", uses);
            v.set("first_use_overwrites", firstUseOverwrites(d));
            // Loops around the range that do not also contain the declaration
            // carry the variable from one iteration to the next.
            std::vector<Span> carrying;
            for (const Span &l : loops)
                if (dOff == kNoOffset || dOff < l.b || dOff >= l.e) carrying.push_back(l);
            if (!carrying.empty()) v.set("loop_carried_line", lineOf(carrying.back().b));
            // Later uses.
            J after = J::arr();
            for (const Ref &r : refs_) {
                if (r.decl != d || r.inSel) continue;
                if (r.off < fnSpan.b || r.off >= fnSpan.e) continue;
                std::string reason;
                if (r.off >= unitsE_) reason = "after";
                for (const Span &l : carrying)
                    if (reason.empty() && r.off >= l.b && r.off < l.e) reason = "loop";
                for (const Span &bk : backward)
                    if (reason.empty() && r.off >= bk.b && r.off < bk.e) reason = "backward-goto";
                if (reason.empty() && vd->hasAttr<BlocksAttr>() && r.closure) reason = "block";
                if (reason.empty()) continue;
                J u = J::obj().set("line", lineOf(r.off)).set("use", r.use).set("reason", reason);
                if (!r.why.empty()) u.set("why", r.why);
                after.push(u);
            }
            v.set("uses_after", after);
            J elsewhere = J::arr();
            for (const Ref &r : refs_)
                if (r.decl == d && !r.inSel && (r.use == "address-taken" || r.use == "by-reference"))
                    elsewhere.push(J::num(lineOf(r.off)));
            v.set("address_taken_outside_range", elsewhere);
            vars.push(v);
        }
        out.set("variables", vars);

        // Variables declared inside the range and used after it.
        J declared = J::arr();
        for (const DeclInfo &di : decls_) {
            if (!di.inSel) continue;
            J v = varType(di.vd);
            v.set("name", di.vd->getNameAsString());
            v.set("decl_line", lineOf(di.off));
            v.set("top_level", di.topLevelInSel);
            J after = J::arr();
            for (const Ref &r : refs_)
                if (r.decl == di.vd && !r.inSel && r.off >= unitsE_)
                    after.push(J::obj().set("line", lineOf(r.off)).set("use", r.use));
            v.set("uses_after", after);
            declared.push(v);
        }
        out.set("declared_inside", declared);

        // Globals, file-scope statics and static data members used in the range.
        std::map<const VarDecl *, std::vector<const GlobalRef *>> byGlobal;
        std::vector<const VarDecl *> gorder;
        for (const GlobalRef &g : globalRefs_) {
            if (!g.inSel) continue;
            if (!byGlobal.count(g.decl)) gorder.push_back(g.decl);
            byGlobal[g.decl].push_back(&g);
        }
        J globals = J::arr();
        for (const VarDecl *g : gorder) {
            J v = varType(g);
            v.set("name", g->getNameAsString());
            const char *kind = "global";
            if (g->isStaticDataMember()) kind = "static data member";
            else if (g->getStorageClass() == SC_Static) kind = "file static";
            else if (g->hasExternalStorage()) kind = "extern";
            v.set("kind", kind);
            PresumedLoc pl = sm_.getPresumedLoc(sm_.getExpansionLoc(g->getLocation()), false);
            v.set("decl_file", pl.isValid() ? pl.getFilename() : "");
            v.set("decl_line", pl.isValid() ? (int)pl.getLine() : 0);
            J uses = J::arr();
            for (const GlobalRef *r : byGlobal[g]) uses.push(J::obj().set("line", lineOf(r->off)).set("use", r->use));
            v.set("uses", uses);
            globals.push(v);
        }
        out.set("globals", globals);

        // self, _cmd, super, ivars, this.
        J selfs = J::arr();
        for (const SelfUse &s : selfUses_)
            if (s.inSel)
                selfs.push(J::obj().set("kind", s.kind).set("name", s.name).set("line", lineOf(s.off)).set("use", s.use));
        out.set("self_uses", selfs);

        // Values that depend on where the code is.
        J pos = J::arr();
        for (const Positional &p : positional_) {
            if (!insideSel(p.off)) continue;
            J m = J::arr();
            for (auto &n : p.macros) m.push(J::str(n));
            pos.push(J::obj().set("kind", p.kind).set("line", lineOf(p.off)).set("macros", m));
        }
        for (const MacroUse &m : pf_.macros) {
            if (!m.builtin || !insideSel(m.begin)) continue;
            J mm = J::arr();
            if (!m.via.empty()) mm.push(J::str(m.via));
            pos.push(J::obj().set("kind", m.name).set("line", lineOf(m.begin)).set("macros", mm));
        }
        out.set("positional", pos);

        // Macro expansions written in the range.
        J macros = J::arr();
        for (const MacroUse &m : pf_.macros) {
            if (!m.topLevel || m.builtin) continue;
            if (m.begin < unitsB_ || m.begin >= unitsE_) continue;
            macros.push(J::obj().set("name", m.name).set("line", lineOf(m.begin)).set("def_file", m.defFile)
                            .set("def_line", m.defLine));
        }
        out.set("macros", macros);

        // Hazards.
        J hz = J::arr();
        for (const Hazard &h : hazards_)
            if (insideSel(h.off)) hz.push(J::obj().set("kind", h.kind).set("line", lineOf(h.off)).set("detail", h.detail));
        out.set("hazards", hz);

        // Function-wide facts that make an answer incomplete.
        bool indirect = false;
        for (const Exit &x : exits_)
            if (x.kind == "indirect-goto" && x.off >= fnSpan.b && x.off < fnSpan.e) indirect = true;
        out.set("function_has_indirect_goto", indirect);
    }

    // Whether the first reference to `d` in the range is a plain assignment
    // `d = expr;` that is itself one of the selected statements, with no other
    // reference to `d` inside that statement: then the value `d` had before
    // the range is never read by it.
    bool firstUseOverwrites(const ValueDecl *d) const {
        const Ref *first = nullptr;
        for (const Ref &r : refs_)
            if (r.decl == d && r.inSel && (!first || r.off < first->off)) first = &r;
        if (!first || first->use != "write" || !first->capture.empty() || first->closure) return false;
        for (const Stmt *u : units_) {
            const Expr *e = dyn_cast<Expr>(u);
            if (!e) continue;
            const BinaryOperator *bo = dyn_cast<BinaryOperator>(e->IgnoreImplicit()->IgnoreParens());
            if (!bo || bo->getOpcode() != BO_Assign) continue;
            const DeclRefExpr *lhs = dyn_cast<DeclRefExpr>(bo->getLHS()->IgnoreParens());
            if (!lhs || lhs->getDecl() != d) continue;
            Span us = spanOf(u);
            if (spanOf(lhs).b != first->off) continue;
            for (const Ref &r : refs_)
                if (r.decl == d && &r != first && r.off >= us.b && r.off < us.e) return false;
            return true;
        }
        return false;
    }

    // ------------------------------------------------ function mode

    // A function's name without the category of an Objective-C method.
    static std::string withoutCategory(const std::string &n) {
        size_t lb = n.find('('), sp = n.find(' ');
        if (n.size() > 2 && (n[0] == '-' || n[0] == '+') && lb != std::string::npos && sp != std::string::npos && lb < sp) {
            size_t rb = n.find(')', lb);
            if (rb != std::string::npos && rb < sp) return n.substr(0, lb) + n.substr(rb + 1);
        }
        return n;
    }

    bool nameMatches(const Decl *d, const std::string &name) const {
        std::string n = fnName(d);
        return n == name || withoutCategory(n) == withoutCategory(name);
    }

    FnLike findNamed(const std::string &name) {
        struct Finder : RecursiveASTVisitor<Finder> {
            const Analyzer &a;
            const std::string &name;
            FnLike best;
            int count = 0;
            Finder(const Analyzer &a, const std::string &name) : a(a), name(name) {}
            void consider(const Decl *d, const Stmt *body) {
                if (!body || !a.nameMatches(d, name)) return;
                Span s = a.spanOf(body);
                if (!s.valid()) return;
                count++;
                best.decl = d;
                best.body = body;
                best.span = s;
            }
            bool VisitFunctionDecl(FunctionDecl *f) {
                if (f->doesThisDeclarationHaveABody()) consider(f, f->getBody());
                return true;
            }
            bool VisitObjCMethodDecl(ObjCMethodDecl *m) {
                if (m->hasBody()) consider(m, m->getBody());
                return true;
            }
        } f(*this, name);
        f.TraverseDecl(ctx_.getTranslationUnitDecl());
        if (f.count != 1) return FnLike();
        return f.best;
    }

    J runFunction(unsigned line, const std::string &named, const std::string &callee) {
        J out = J::obj();
        out.set("mode", "function");
        out.set("errors", errors_);
        FnLike fn;
        if (!named.empty()) {
            fn = findNamed(named);
            if (!fn.decl) {
                out.set("error", "no single function definition named " + named + " in the main file");
                return out;
            }
        } else {
            unsigned b = lineStart(line), e = lineEnd(line);
            std::vector<Tok> toks = rawTokens(b, e);
            unsigned tb = toks.empty() ? b : toks.front().off;
            unsigned te = toks.empty() ? b + 1 : toks.front().end;
            fn = findFunction(tb, te);
            if (!fn.decl) {
                out.set("error", "no function body contains line " + std::to_string(line));
                return out;
            }
        }
        method_ = dyn_cast<ObjCMethodDecl>(fn.decl);
        unitsB_ = unitsE_ = kNoOffset;
        walk(fn.body);
        J fj = fnJson(fn.decl, fn.body);
        J ex = J::arr();
        for (const Exit &x : exits_) ex.push(exitJson(x));
        fj.set("exits", ex);
        if (const CompoundStmt *cs = dyn_cast<CompoundStmt>(fn.body)) {
            if (!cs->body_empty()) {
                Span fs = spanOf(cs->body_front());
                fj.set("first_statement_line", lineOf(fs.b));
                J stmts = J::arr();
                for (const Stmt *st : cs->body()) {
                    Span ss = extended(st);
                    J o = J::obj().set("kind", st->getStmtClassName()).set("line", lineOf(ss.b))
                              .set("end_line", lineOf(ss.e ? ss.e - 1 : 0)).set("text", textOf(ss));
                    if (const ReturnStmt *rs = dyn_cast<ReturnStmt>(st)) {
                        if (const Expr *v = rs->getRetValue()) {
                            o.set("value", textOf(spanOf(v)));
                            Expr::EvalResult er;
                            if (!v->isValueDependent() && v->EvaluateAsInt(er, ctx_))
                                o.set("const_value", (long long)er.Val.getInt().getExtValue());
                        }
                    }
                    if (const DeclStmt *ds = dyn_cast<DeclStmt>(st)) {
                        J names = J::arr();
                        for (const Decl *d : ds->decls())
                            if (const VarDecl *vd = dyn_cast<VarDecl>(d)) names.push(J::str(vd->getNameAsString()));
                        o.set("declares", names);
                    }
                    stmts.push(o);
                }
                fj.set("statements", stmts);
                const Stmt *lastS = cs->body_back();
                Span ls = spanOf(lastS);
                J l = J::obj().set("kind", lastS->getStmtClassName()).set("line", lineOf(ls.b)).set("text", textOf(ls));
                l.set("end_line", lineOf(ls.e ? ls.e - 1 : 0));
                if (const ReturnStmt *r = dyn_cast<ReturnStmt>(lastS)) {
                    if (const Expr *v = r->getRetValue()) {
                        Expr::EvalResult er;
                        if (!v->isValueDependent() && v->EvaluateAsInt(er, ctx_))
                            l.set("const_value", (long long)er.Val.getInt().getExtValue());
                    }
                }
                fj.set("last_statement", l);
            }
        }
        // Parameter uses in the body.
        J puses = J::arr();
        for (const Ref &r : refs_) {
            if (!isa<ParmVarDecl>(r.decl)) continue;
            puses.push(J::obj().set("name", r.decl->getNameAsString()).set("line", lineOf(r.off)).set("use", r.use));
        }
        fj.set("param_uses", puses);
        fj.set("derefs", derefWrites(fn.body));
        out.set("function", fj);
        if (!callee.empty()) out.set("calls", callsTo(fn.body, callee));
        return out;
    }

    // Writes through a pointer parameter: *p = ..., p[i] = ..., p->f = ...
    J derefWrites(const Stmt *body) {
        J out = J::arr();
        std::vector<const Stmt *> path;
        derefWalk(body, path, out);
        return out;
    }

    void derefWalk(const Stmt *s, std::vector<const Stmt *> &path, J &out) {
        if (!s) return;
        if (const BinaryOperator *bo = dyn_cast<BinaryOperator>(s)) {
            if (bo->isAssignmentOp()) {
                const Expr *lhs = bo->getLHS()->IgnoreParens();
                const Expr *base = nullptr;
                if (const UnaryOperator *uo = dyn_cast<UnaryOperator>(lhs))
                    if (uo->getOpcode() == UO_Deref) base = uo->getSubExpr()->IgnoreParenImpCasts();
                if (const DeclRefExpr *dr = dyn_cast_or_null<DeclRefExpr>(base))
                    if (isa<ParmVarDecl>(dr->getDecl()))
                        out.push(J::obj().set("name", dr->getDecl()->getNameAsString()).set("line", lineOf(spanOf(s).b)));
            }
        }
        for (const Stmt *c : s->children()) derefWalk(c, path, out);
        if (const BlockExpr *be = dyn_cast<BlockExpr>(s)) derefWalk(be->getBlockDecl()->getBody(), path, out);
    }

    J stmtSummary(const Stmt *s) {
        J j = J::obj();
        if (!s) return j;
        Span sp = spanOf(s);
        j.set("kind", s->getStmtClassName()).set("line", lineOf(sp.b)).set("text", textOf(sp));
        const Stmt *only = s;
        if (const CompoundStmt *cs = dyn_cast<CompoundStmt>(s)) only = cs->size() == 1 ? cs->body_front() : nullptr;
        if (only) {
            if (const ReturnStmt *r = dyn_cast<ReturnStmt>(only)) {
                j.set("only", "return");
                if (r->getRetValue()) j.set("value", textOf(spanOf(r->getRetValue())));
            } else if (isa<BreakStmt>(only)) {
                j.set("only", "break");
            } else if (isa<ContinueStmt>(only)) {
                j.set("only", "continue");
            } else if (const GotoStmt *g = dyn_cast<GotoStmt>(only)) {
                j.set("only", "goto");
                j.set("label", g->getLabel()->getNameAsString());
            }
        }
        return j;
    }

    J callsTo(const Stmt *body, const std::string &callee) {
        J out = J::arr();
        std::vector<const Stmt *> path;
        callWalk(body, callee, path, out, body);
        return out;
    }

    bool isCallTo(const Stmt *s, const std::string &callee) const {
        if (const CallExpr *ce = dyn_cast<CallExpr>(s)) {
            if (const FunctionDecl *fd = ce->getDirectCallee()) return nameMatches(fd, callee);
        }
        if (const ObjCMessageExpr *me = dyn_cast<ObjCMessageExpr>(s)) {
            if (const ObjCMethodDecl *md = me->getMethodDecl()) return nameMatches(md, callee);
        }
        return false;
    }

    void callWalk(const Stmt *s, const std::string &calleeCanon, std::vector<const Stmt *> &path, J &out, const Stmt *body) {
        if (!s) return;
        path.push_back(s);
        if (isCallTo(s, calleeCanon)) out.push(callJson(path, body));
        if (const BlockExpr *be = dyn_cast<BlockExpr>(s)) callWalk(be->getBlockDecl()->getBody(), calleeCanon, path, out, body);
        else if (const PseudoObjectExpr *po = dyn_cast<PseudoObjectExpr>(s)) callWalk(po->getSyntacticForm(), calleeCanon, path, out, body);
        else if (const DeclStmt *ds = dyn_cast<DeclStmt>(s)) {
            for (const Decl *d : ds->decls())
                if (const VarDecl *vd = dyn_cast<VarDecl>(d))
                    if (vd->getInit()) {
                        initOf_[vd->getInit()] = vd;
                        callWalk(vd->getInit(), calleeCanon, path, out, body);
                    }
        } else
            for (const Stmt *c : s->children()) callWalk(c, calleeCanon, path, out, body);
        path.pop_back();
    }

    J argJson(const Expr *a) {
        J j = J::obj();
        j.set("text", textOf(spanOf(a)));
        const Expr *e = a->IgnoreParenImpCasts();
        if (const ObjCIndirectCopyRestoreExpr *ic = dyn_cast<ObjCIndirectCopyRestoreExpr>(e)) {
            j.set("writeback", true);
            e = ic->getSubExpr()->IgnoreParenImpCasts();
        }
        if (const UnaryOperator *uo = dyn_cast<UnaryOperator>(e)) {
            if (uo->getOpcode() == UO_AddrOf) {
                if (const DeclRefExpr *dr = dyn_cast<DeclRefExpr>(uo->getSubExpr()->IgnoreParens())) {
                    j.set("kind", "address-of");
                    j.set("var", dr->getDecl()->getNameAsString());
                    if (const VarDecl *vd = dyn_cast<VarDecl>(dr->getDecl())) j.set("var_type", varType(vd));
                    return j;
                }
            }
        }
        if (const DeclRefExpr *dr = dyn_cast<DeclRefExpr>(e)) {
            j.set("kind", "var");
            j.set("var", dr->getDecl()->getNameAsString());
            if (const VarDecl *vd = dyn_cast<VarDecl>(dr->getDecl())) j.set("var_type", varType(vd));
            return j;
        }
        j.set("kind", "other");
        return j;
    }

    J callJson(const std::vector<const Stmt *> &path, const Stmt *body) {
        const Stmt *call = path.back();
        J j = J::obj();
        Span cs = spanOf(call);
        j.set("line", lineOf(cs.b));
        j.set("text", textOf(cs));
        J args = J::arr();
        if (const CallExpr *ce = dyn_cast<CallExpr>(call)) {
            for (const Expr *a : ce->arguments()) args.push(argJson(a));
        } else if (const ObjCMessageExpr *me = dyn_cast<ObjCMessageExpr>(call)) {
            for (const Expr *a : me->arguments()) args.push(argJson(a));
            j.set("receiver", me->getReceiverKind() == ObjCMessageExpr::Instance
                                  ? textOf(spanOf(me->getInstanceReceiver()))
                                  : me->getReceiverKind() == ObjCMessageExpr::Class ? "class" : "super");
        }
        j.set("args", args);
        // Context.
        size_t i = path.size() - 1;
        bool negated = false;
        std::string compare;
        while (i > 0) {
            const Stmt *p = path[i - 1];
            if (isa<ImplicitCastExpr>(p) || isa<ParenExpr>(p) || isa<FullExpr>(p) || isa<ConstantExpr>(p)) {
                i--;
                continue;
            }
            if (const UnaryOperator *uo = dyn_cast<UnaryOperator>(p)) {
                if (uo->getOpcode() == UO_LNot) {
                    negated = !negated;
                    i--;
                    continue;
                }
            }
            if (const BinaryOperator *bo = dyn_cast<BinaryOperator>(p)) {
                if (bo->getOpcode() == BO_EQ || bo->getOpcode() == BO_NE) {
                    const Expr *other = bo->getLHS() == path[i] ? bo->getRHS() : bo->getLHS();
                    compare = std::string(bo->getOpcodeStr()) + " " + textOf(spanOf(other));
                    i--;
                    continue;
                }
            }
            break;
        }
        const Stmt *p = i > 0 ? path[i - 1] : nullptr;
        const Stmt *cur = path[i];
        std::string ctxKind = "other";
        if (const IfStmt *is = p ? dyn_cast<IfStmt>(p) : nullptr) {
            if (is->getCond() == cur) {
                ctxKind = "if-condition";
                j.set("then", stmtSummary(is->getThen()));
                if (is->getElse()) j.set("else", stmtSummary(is->getElse()));
            }
        } else if (const BinaryOperator *bo = p ? dyn_cast<BinaryOperator>(p) : nullptr) {
            if (bo->getOpcode() == BO_Assign && bo->getRHS() == cur) {
                ctxKind = "assigned";
                j.set("assigned_to", textOf(spanOf(bo->getLHS())));
            }
        } else if (p && isa<DeclStmt>(p)) {
            auto it = initOf_.find(dyn_cast<Expr>(cur));
            if (it != initOf_.end()) {
                ctxKind = "initializes";
                j.set("assigned_to", it->second->getNameAsString());
            }
        } else if (p && isa<ReturnStmt>(p)) {
            ctxKind = "returned";
        } else if (p && (isa<CompoundStmt>(p) || isa<SwitchCase>(p) || isa<LabelStmt>(p) || isa<AttributedStmt>(p))) {
            ctxKind = "discarded";
        }
        j.set("context", ctxKind);
        j.set("negated", negated);
        if (!compare.empty()) j.set("compare", compare);
        // The statement that holds the call, and what follows it.
        size_t si = path.size() - 1;
        while (si > 0 && !isa<CompoundStmt>(path[si - 1])) si--;
        if (si > 0) {
            const CompoundStmt *pc = cast<CompoundStmt>(path[si - 1]);
            const Stmt *stmt = path[si];
            const Stmt *next = nullptr;
            bool found = false;
            for (const Stmt *c : pc->body()) {
                if (found) { next = c; break; }
                if (c == stmt) found = true;
            }
            if (next) j.set("next", stmtSummary(next));
            bool inLoop = false;
            for (size_t k = 0; k < si; k++)
                if (isLoop(path[k]) || isa<SwitchStmt>(path[k])) inLoop = true;
            j.set("in_loop_or_switch", inLoop);
            // The statement's span starts after any case, default or goto
            // labels that carry it, so that it is the call statement itself.
            const Stmt *own = stmt;
            for (size_t k = si; k + 1 < path.size();) {
                const Stmt *sub = nullptr;
                if (const SwitchCase *sc = dyn_cast<SwitchCase>(own)) sub = sc->getSubStmt();
                else if (const LabelStmt *ls = dyn_cast<LabelStmt>(own)) sub = ls->getSubStmt();
                else if (const AttributedStmt *as = dyn_cast<AttributedStmt>(own)) sub = as->getSubStmt();
                if (!sub || path[k + 1] != sub) break;
                own = sub;
                k++;
            }
            Span ss = extended(own);
            j.set("stmt_line", lineOf(ss.b));
            j.set("stmt_end_line", lineOf(ss.e ? ss.e - 1 : 0));
            j.set("tail", isTail(pc, stmt, body, nullptr) && !inLoop);
        }
        return j;
    }

    // ------------------------------------------------ state

    ASTContext &ctx_;
    SourceManager &sm_;
    const LangOptions &lo_;
    Preprocessor &pp_;
    PPFacts &pf_;
    unsigned errors_;
    FileID mainFID_;
    llvm::StringRef buf_;

    const ObjCMethodDecl *method_ = nullptr;
    const CompoundStmt *compound_ = nullptr;
    std::vector<const Stmt *> units_;
    unsigned unitsB_ = kNoOffset, unitsE_ = kNoOffset;

    std::vector<const Stmt *> stack_;
    std::set<const OpaqueValueExpr *> seenOVE_;
    std::map<const Expr *, const VarDecl *> initOf_;
    std::vector<Ref> refs_;
    std::vector<GlobalRef> globalRefs_;
    std::vector<Exit> exits_;
    std::vector<Scope> scopes_;
    std::vector<Hazard> hazards_;
    std::vector<SelfUse> selfUses_;
    std::vector<Positional> positional_;
    std::vector<DeclInfo> decls_;
    std::vector<const GotoStmt *> gotos_;
    std::vector<const LabelStmt *> labels_;
    std::vector<std::pair<const Stmt *, const Stmt *>> cases_;
    std::vector<const BlockExpr *> blocks_;
    std::vector<const LambdaExpr *> lambdas_;
};

// ---------------------------------------------------------------- frontend glue

class CountingConsumer : public DiagnosticConsumer {
public:
    explicit CountingConsumer(DiagnosticOptions &opts) : printer_(llvm::errs(), opts) {}
    void BeginSourceFile(const LangOptions &lo, const Preprocessor *pp) override { printer_.BeginSourceFile(lo, pp); }
    void EndSourceFile() override { printer_.EndSourceFile(); }
    void HandleDiagnostic(DiagnosticsEngine::Level level, const Diagnostic &info) override {
        DiagnosticConsumer::HandleDiagnostic(level, info);
        if (level >= DiagnosticsEngine::Error) printer_.HandleDiagnostic(level, info);
    }

private:
    TextDiagnosticPrinter printer_;
};

class FactsConsumer : public ASTConsumer {
public:
    FactsConsumer(CompilerInstance &ci, const Options &o, PPFacts &pf, std::string &out)
        : ci_(ci), o_(o), pf_(pf), out_(out) {}
    void HandleTranslationUnit(ASTContext &ctx) override {
        unsigned errors = ci_.getDiagnostics().getClient()->getNumErrors();
        Analyzer a(ctx, ci_.getPreprocessor(), pf_, errors);
        J j = (o_.functionAt || !o_.functionNamed.empty())
                  ? a.runFunction(o_.functionAt, o_.functionNamed, o_.calleeNamed)
                  : a.runRange(o_.first, o_.last);
        j.set("tool", "extraction_facts");
        j.set("digest", EXTRACTION_DIGEST);
        j.set("main", o_.mainFile);
        const TargetInfo &ti = ctx.getTargetInfo();
        j.set("triple", ti.getTriple().str());
        out_.clear();
        j.write(out_);
    }

private:
    CompilerInstance &ci_;
    const Options &o_;
    PPFacts &pf_;
    std::string &out_;
};

class FactsAction : public ASTFrontendAction {
public:
    FactsAction(const Options &o, std::string &out) : o_(o), out_(out) {}
    std::unique_ptr<ASTConsumer> CreateASTConsumer(CompilerInstance &ci, StringRef) override {
        ci.getPreprocessor().addPPCallbacks(std::make_unique<Recorder>(ci.getSourceManager(), ci.getLangOpts(), pf_));
        return std::make_unique<FactsConsumer>(ci, o_, pf_, out_);
    }

private:
    const Options &o_;
    std::string &out_;
    PPFacts pf_;
};

int usage() {
    fprintf(stderr,
            "usage: extraction_facts --main PATH [--contents FILE] (--range FIRST LAST | --function-at LINE | "
            "--function-named NAME) [--callee-named NAME] -- ARGS...\n       extraction_facts --version\n");
    return 2;
}

}  // namespace

int main(int argc, char **argv) {
    if (argc == 2 && std::string(argv[1]) == "--version") {
        printf("extraction_facts %s %s\n", EXTRACTION_DIGEST, getClangFullVersion().c_str());
        return 0;
    }
    Options o;
    int i = 1;
    for (; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--") {
            i++;
            break;
        }
        if (a == "--range") {
            if (i + 2 >= argc) return usage();
            o.first = atoi(argv[++i]);
            o.last = atoi(argv[++i]);
            continue;
        }
        if (i + 1 >= argc) return usage();
        std::string v = argv[++i];
        if (a == "--main") o.mainFile = v;
        else if (a == "--contents") o.contents = v;
        else if (a == "--function-at") o.functionAt = atoi(v.c_str());
        else if (a == "--function-named") o.functionNamed = v;
        else if (a == "--callee-named") o.calleeNamed = v;
        else return usage();
    }
    for (; i < argc; i++) o.args.push_back(argv[i]);
    if (o.mainFile.empty() || o.args.empty() || (!o.functionAt && o.functionNamed.empty() && (o.first <= 0 || o.last <= 0))) return usage();

    std::vector<std::string> cmd;
    cmd.push_back(EXTRACTION_LLVM_CLANG);
    cmd.insert(cmd.end(), o.args.begin(), o.args.end());
    cmd.push_back("-fsyntax-only");
    cmd.push_back("-resource-dir");
    cmd.push_back(EXTRACTION_RESOURCE_DIR);

    DiagnosticOptions diagOpts;
    CountingConsumer diags(diagOpts);
    std::vector<std::string> overlays;
    for (size_t k = 0; k < o.args.size(); k++) {
        const std::string &a = o.args[k];
        if (a == "-ivfsoverlay" && k + 1 < o.args.size()) overlays.push_back(o.args[++k]);
        else if (a.rfind("-ivfsoverlay", 0) == 0 && a.size() > strlen("-ivfsoverlay"))
            overlays.push_back(a.substr(strlen("-ivfsoverlay")));
    }
    llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem> vfs = llvm::vfs::getRealFileSystem();
    if (!overlays.empty()) {
        DiagnosticsEngine overlayDiags(DiagnosticIDs::create(), diagOpts, &diags, /*ShouldOwnClient=*/false);
        vfs = createVFSFromOverlayFiles(overlays, overlayDiags, vfs);
    }
    if (!o.contents.empty()) {
        auto mb = llvm::MemoryBuffer::getFile(o.contents);
        if (!mb) {
            fprintf(stderr, "extraction_facts: cannot read %s\n", o.contents.c_str());
            return 2;
        }
        llvm::IntrusiveRefCntPtr<llvm::vfs::InMemoryFileSystem> mem(new llvm::vfs::InMemoryFileSystem);
        mem->addFile(o.mainFile, 0, llvm::MemoryBuffer::getMemBufferCopy((*mb)->getBuffer(), o.mainFile));
        llvm::IntrusiveRefCntPtr<llvm::vfs::OverlayFileSystem> ov(new llvm::vfs::OverlayFileSystem(vfs));
        ov->pushOverlay(mem);
        vfs = ov;
    }
    llvm::IntrusiveRefCntPtr<FileManager> files(new FileManager(FileSystemOptions(), vfs));
    std::string out;
    tooling::ToolInvocation invocation(cmd, std::make_unique<FactsAction>(o, out), files.get());
    invocation.setDiagnosticConsumer(&diags);
    bool ran = invocation.run();
    if (out.empty()) {
        fprintf(stderr, "extraction_facts: clang did not produce an AST for %s%s\n", o.mainFile.c_str(),
                ran ? "" : " (clang failed)");
        return 2;
    }
    printf("%s\n", out.c_str());
    return 0;
}
