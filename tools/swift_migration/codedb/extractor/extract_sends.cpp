// Code database extractor: translation units, their inputs, Objective-C
// message sends, method and property declarations, @selector expressions,
// reflective calls, ivars, statics and globals and the references to them,
// from one compile command into SQLite.
//
// Built against upstream LLVM (see build.sh), not Xcode's toolchain.
//
// Usage:
//   extract_sends --db DB --root REPO --target TARGET --main FILE
//                 [--sdk-path P] [--sdk-version V]
//                 [--configuration C] [--arch A]
//                 [--migration-scope DIR]...
//                 -- <clang arguments, including FILE>
//   extract_sends --version
//   extract_sends --reflective-table
//
// The clang arguments are run with -fsyntax-only added; nothing is written
// except the database. cmd_digest is SHA-256 of the arguments after `--`
// other than -fmodules-cache-path=, joined with NUL bytes. Any -ivfsoverlay files in the arguments are applied.
//
// `extract_sends --version` prints "extract_sends <digest> <clang version>",
// where <digest> is the digest of the extractor's sources that build.sh bakes
// in (codedb.py computes the same digest from the sources). It is stored in
// tu.extractor_version, so any change to the extractor makes every unit stale.
// `extract_sends --reflective-table` prints the table of recognized reflective
// calls (reflective_table.h), one tab-separated line per entry.
//
// Paths: every file is stored under its canonical path (symlinks resolved, a
// VFS overlay's virtual path replaced by the real file), relative to the
// repository root when inside it and absolute otherwise.
//
// Scope: a row is recorded if the file it is written in (see below) is inside
// the repository, wherever it is there (submodules/ and all of ThirdParty/
// included). Rows written in files outside the repository (the SDK, the
// compiler's resource headers, Homebrew) are not recorded, and neither are
// method and property rows in files under Build/ (headers the Swift compiler
// generates). Each row's in_migration_scope is 1 when that file is under one
// of the directories given with --migration-scope (relative to the
// repository, ending in '/'; codedb.py passes its MIGRATION_SCOPE_DIRS) and 0
// otherwise. The list is stored in tu.migration_scope, joined with commas.
//
// Unevaluated operands: a send, @selector expression or reflective call that
// appears only in an operand that is not evaluated is not recorded: the
// operands of sizeof, alignof and the other type traits (unless their type is
// variably modified), __typeof__/typeof (same exception), @encode, decltype
// and noexcept. A macro like MAX that names its argument in __typeof__ as well
// as in the expression therefore records one send. The operand of
// __builtin_choose_expr that is not chosen, and the controlling expression
// and the associations that are not selected of _Generic, are unevaluated
// operands too (the compiler emits only the chosen one); the state tables
// record references in them with the access unevaluated, as in sizeof.
//
// Both forms: the AST keeps two forms of some nodes, and the default
// traversal visits only one. An initializer list's syntactic form keeps a
// designator's value as written ({.c = x.rect}: an unconverted property
// reference, with no message send), its semantic form the converted
// expression; a variable-length array's size is written in the type location
// and converted in the type (char buf[s.length]). Both forms of each are
// traversed. A node the forms share is reached twice, and every recorder
// keys on the node: send (and the reflective rows of a send), selector_ref,
// reflective calls of functions, ivar_ref, static_ref, c_static, the
// containers and macro_ast_fact (node and fact) each record a node once, so
// two distinct nodes (two sends in one macro expansion) stay two rows, and
// one node reached through both forms is one. What only the syntactic form
// holds is still recorded where it is converted there (an initializer that a
// later designator overrides, which the compiler does not evaluate).
// Templates in Objective-C++: a send is recorded in the template as written
// and in each instantiation. A default argument and a default member
// initializer are recorded once, where they are written; the compiler
// evaluates them at each call or constructor that uses them.
//
// Constant conditions: a send, ivar_ref or static_ref row in code the
// compiler certainly does not emit at -O0 because a condition folds to a
// constant has in_constant_false_branch 1, with constant_condition_file and
// constant_condition_line of the condition. The mark exists to explain a
// send the database has and the object does not, so it must never be set on
// emitted code; the rule is deliberately narrower than what the compiler
// drops. A condition folds as CodeGen's ConstantFoldsToSimpleInteger folds
// it (Expr::EvaluateAsInt: an integer constant expression, or a
// const-qualified variable with a constant initializer, as in
// const BOOL debug = NO; no side effects; no label in the condition).
// Marked:
//   - the arm an if skips when its condition folds, unless that arm holds a
//     label or a case or default of an enclosing switch (CodeGen's
//     ContainsLabel; it then emits the arm);
//   - the operand that c ? x : y skips, and the right operand of 0 && x and
//     1 || x, when the operator is a scalar prvalue (or, in C++, a glvalue)
//     that is not part of a branch condition, and the skipped operand holds
//     no label. Part of a branch condition: the condition of an if, while,
//     do or for, the condition of a conditional operator, the left operand
//     of && or ||, and what EmitBranchOnBoolExpr reaches from those through
//     !, && and ||, both operands of a conditional operator and (more widely
//     than CodeGen) any cast; there CodeGen emits both operands.
// Not marked, although the compiler may drop them: an aggregate or complex
// conditional (CodeGen emits both operands), GNU a ?: b, the operands of a
// conditional inside a branch condition, a folded condition's own operands,
// loops (the compiler emits the body of while (0)), and code after a return
// (see "Unreachable code").
// test_codedb_completeness.py ConstantFormsTest checks every form against an
// object file. An ivar_ref or static_ref row stands for every reference at
// its place with its access (a macro argument expanded twice); it is marked
// only if every one of them is.
//
// Unreachable code: a send row has in_unreachable_code 1 when its message
// expression is placed only in blocks of its function's control-flow graph
// (Clang's CFG, built with every statement as an element and without
// pruning trivially false edges) that no path from the entry reaches. The
// function is the innermost function, method, block or lambda whose body
// holds the send. A path ends at return, break, continue, goto, @throw and
// throw, and at a call CodeGen emits as noreturn: a callee with the noreturn
// attribute, _Noreturn or [[noreturn]] (or of a noreturn function type), or
// __builtin_unreachable. The graph also ends a path at __builtin_assume(0),
// [[assume(0)]], __builtin_trap, __builtin_debugtrap and a call of an
// analyzer_noreturn function, after which CodeGen still emits the code that
// follows at -O0; there the edge the graph keeps to that code is followed
// (endsPathForCodeGen). A path also does not take
// the arm that the constant-condition rule above skips for an if, or for a
// conditional operator (the arm CodeGen does not emit), so the code after
// if (!(NO)) { noreturn(); } (ITAssertWithMessage(NO, ...)) and after
// NO ? ... : noreturn() (assert(NO)) is unreachable. An edge the graph keeps
// but calls unreachable (the default of a switch over an enum that lists
// every enumerator) is followed, because CodeGen emits it. The mark reflects
// the unit's own configuration (tu.configuration): the preprocessor decided
// what the body is (ITDebugAssert is assert in Development and a cast to
// void in Deployment), so a send marked in one configuration can be live in
// another. Like the constant-condition mark it exists to explain a send the
// database has and the object does not; it has been checked against the
// compiler only for the forms of the test fixtures. It is deliberately
// narrower than
// what the compiler drops: a send not placed in any block of the graph, the
// body of a block or lambda written in unreachable code, the code after
// while (1) without a break (the graph keeps the loop's exit), and the
// skipped operand of && and || are not marked. Bodies in a dependent
// context (a template pattern) are not analyzed; an instantiation is.
// test_codedb_completeness.py UnreachableCodeTest checks the forms against
// an object file. Only send rows carry the mark.
//
// function_ref: for each function defined in the repository with internal
// linkage or declared inline (the functions whose code the object holds
// once, once per inlined call, or not at all), the evaluated references to
// it (a call, or taking its address) per enclosing function or method
// (enclosing_name as for a send; '' at file scope). References in a template
// are left out; each instantiation counts. The cross-check bounds the call
// sites that an always_inline function adds to the object with it.
//
// Inputs: every file the unit read, with its SHA-256: the files in the unit's
// own source locations (SDK module maps and headers it reads itself
// included), and the input files of every module it imported (module maps
// and headers), read from the module files. Inputs of modules under the SDK
// (--sdk-path, or the -isysroot argument) or under clang's resource directory
// are not recorded: an SDK header read only through a compiled module is
// covered by the SDK path, version and build version.
//
// Where a row is recorded, and its macro_role, are decided by one token: for
// a send, the first token of its selector; for a method, the first token of
// its selector (for an accessor the compiler declares or synthesizes, the
// property's name or the @synthesize); for a property, its name; for an
// @selector expression, the first token inside the parentheses; for a call
// of a C function, the function's name; for a reflective message, the first
// token of its selector, as for the send:
//   - written directly in a file: macro_role NULL; file, line and col are that
//     token's position.
//   - spelled in a macro argument (however deeply the argument is passed on to
//     other macros): macro_role 'argument'; file, line and col are where the
//     developer wrote the token in the argument.
//   - spelled in a macro's replacement text: macro_role 'body'; file, line and
//     col are where the developer wrote the name of that macro, followed back
//     through macro arguments to a file (for a macro used directly in a file,
//     the outermost expansion site).
//   - made by token pasting (spelled in scratch space): macro_role 'pasted';
//     file, line and col are the outermost expansion site.
// For every row in a macro, macro_name, macro_file and macro_line describe
// the outermost macro, and expansion_line and expansion_col give the position
// of its name. The receiver and brackets do not affect any of this: in
// `#define BLOCK(x) [self x]`, BLOCK(foo) is an 'argument' send of foo.
//
// Declarations in headers: the methods and properties declared in an
// @interface, class extension, category or protocol are recorded once per
// target, content and view of the file that holds the container, by the first
// unit of that target that reads the file with that view (decl_source records
// the claim). A unit's view of a file is a digest of the language it is
// parsed as (C, Objective-C, C++ or Objective-C++) and the ranges of the file
// its preprocessor skipped (inactive #if branches), so a unit that defines a
// macro another unit does not, and that therefore sees other declarations,
// records its own rows. It is stored in tu_input.view. A view does not see
// macros that expand differently without skipping a branch. Rows of
// implementations (methods, synthesized accessors, @synthesize and @dynamic)
// are recorded by every unit, as sends are.
//
// Declarations read through a module: a repository file that a unit reads
// only through a Clang module (its declarations are deserialized from the
// module file, so they are not top-level declarations of the unit) has its
// containers (methods, properties, ivars, objc_class and objc_adoption) and
// variables recorded as a header's are, once per target and content, by the
// unit that holds its decl_source claim with via_module 1 and view ''.
// Function bodies in such a file are not traversed; the unit that walks the
// file counts them in tu.module_bodies_skipped (update warns when any is not
// zero). A unit claims such a file
// only when it walked the module's declarations; it walks them when one of
// those files has no claim yet.
//
// Classes and the SDK: objc_class has a row for every @interface in the
// repository (its superclass), objc_adoption one for every protocol an
// @interface, category, class extension or protocol lists (container_kind
// interface, category, extension or protocol), recorded as declarations.
// sdk_method, sdk_class and sdk_adoption hold the declarations outside the
// repository, from every header a unit parses or imports through a module:
// sdk_method one row per method and per property getter and setter (the
// getter= and setter= names; no setter for readonly) of a class, protocol or
// category (container Class(Category), Class() for an extension), with the
// framework (the last X.framework in the header's path, else its directory),
// is_optional (an @optional protocol method or property) and is_action (the
// result type is written IBAction); sdk_class the superclass of each class;
// sdk_adoption the protocols each lists. They are claimed per module and
// configuration: the key is the declaration's top-level module (or
// "textual:" and the header's path for a header that is not in a module; a
// declaration read both ways has a row under each key), then the OS and
// deployment target and, for an Objective-C++ unit, objc++
// ("AppKit macosx13.0", "AppKit macosx15.0 objc++"), because a header can
// declare different things under each (availability #if, __cplusplus). A
// declaration every configuration sees has a row under each key (the queries
// list it once); the cost is a walk per module and configuration that units
// load, not per module. The first unit that loads a
// module whose key no other unit holds in sdk_claim walks the module's
// declarations and records them; tu_module lists the keys every unit loads,
// so that a key nobody holds (its unit was removed) is found. Walking means
// deserializing every module the unit loaded, so a unit whose keys are all
// held does not walk.
//
// Overrides: for every method row, objc_method_override has one row per
// method Clang's overridden-methods query returns for it (superclass methods,
// and protocol requirements of the class, its categories and extensions; a
// method the query returns more than once, as a requirement inherited through
// two protocols, has one row), with where that method is declared, whether
// that is outside the repository, and whether the code that owns the
// declaration is parsed into this database (owner_parsed): 1 when this unit
// reads the declaring file itself as source (a main file or a header it
// includes textually), 0 when the file is outside the repository, is read
// only through a compiled module, lies inside a .framework bundle (a prebuilt
// framework, whose sources are not parsed), or is a header the Swift compiler
// generates (named *-Swift.h; it declares Swift code). A method declared in a
// category or class extension is judged also by the class that it extends
// (overridden_class): when that class's @interface is in a file whose owner is
// not parsed by the same rule, or is in a source file (not a header) and the
// unit has no @implementation of the class (a private SDK class the
// repository declares itself), owner_parsed is 0 (overridden_class_parsed 0),
// wherever the category is. A category in the repository on an SDK class can
// redeclare a private method of the class, which the SDK calls.
//
// State: objc_ivar, c_static, ivar_ref and static_ref.
//   objc_ivar has a row for every ivar of a class in the repository: those
//   declared in an @interface, a class extension or an @implementation
//   (container_kind), and those the compiler synthesizes for a property
//   (container_kind implementation, synthesized_by 'explicit' for a written
//   @synthesize, 'automatic' otherwise, with property_name). Ivars of an
//   @interface or class extension are declarations, recorded once per target,
//   content and view as methods are; the others are recorded by every unit
//   that has the @implementation. A unit's view includes whether it is
//   compiled with ARC, because ARC changes the types (an id ivar is __strong
//   id under ARC and id without it): a header read by units of both kinds has
//   a row from each, and a query reports a CONFLICT when they disagree.
//   access is the ivar's access control as the compiler resolves it
//   (private, protected, package, public).
//   c_static has a row for every variable with static storage declared in the
//   repository: kind file-static, local-static (with the enclosing function
//   or method), global (a definition, tentative or not), extern (a
//   declaration that is not a definition) and static-member. Those in a
//   header (not a .m, .mm, .c or C++ source file) are recorded once per
//   target, content and view; the others by every unit. A global's extern
//   declaration and its definition share the usr. is_const: the variable
//   (for an array, its elements) is const; pointee_const: for a C pointer, 1
//   when every level it points through is const, 0 when not, NULL for
//   anything else (objects included: an Objective-C type does not say
//   whether the object is immutable). init_kind: none (no initializer, or
//   only the zero initialization the compiler adds), literal (a string,
//   Objective-C string, number, character, boolean or null literal), constant
//   (another constant initializer), runtime (C++ dynamic initialization).
//   thread_local: _Thread_local, __thread or thread_local.
//   The type columns (TYPE_COLUMNS): type as written and canonical_type, as
//   the compiler prints them (with ARC's inferred ownership); type_class:
//   bit-field (bit_width), atomic, array, object (object_class: the class,
//   id or Class, and object_protocols), block, selector, c-pointer (C
//   pointers, references, member pointers), struct, union, cxx-object (a C++
//   class that is not C-like) with record_name and record_has_objects (a
//   field, nested or in an array, is an object or block pointer), vector (a
//   SIMD vector such as vector_float4), scalar, or other. ownership: for an object or block pointer (for an array, its
//   elements), under ARC strong, weak, unsafe_unretained or autoreleasing;
//   without ARC, weak only where the unit honors __weak (-fobjc-weak),
//   unsafe_unretained where written, and manual otherwise; none for the rest.
//   ownership_written: the qualifier when it is spelled in the declaration or
//   a typedef it uses (NULL when ARC infers it; without ARC the compiler drops
//   every qualifier but __weak, so none is recorded). arc: the unit's mode.
//   import_facts: facts about the type, read from its canonical QualType,
//   that decide what Swift can import (codedb.py's importability; the
//   rules there were checked with swiftc): words separated by one space,
//   sorted. A word without a prefix is about the type itself, or about a
//   record it holds by value; "in-" before a word means a part of it: a
//   pointee, an array or vector element, a field, or a block's or function's
//   result or a parameter. The words: atomic, variable-array,
//   incomplete-array, int128, long-double, float16 (half or _Float16),
//   unusual-builtin (a builtin type other than void, bool, the char, short,
//   int, long and long long types, float, double, id, Class, SEL and those
//   above; or _BitInt), complex, enum-plain, enum-ns (enum_extensibility, as
//   NS_ENUM makes), enum-options (flag_enum, as NS_OPTIONS makes),
//   vector-elements-N with vector-element-NAME (the element's builtin type
//   as the compiler names it, or other), function-pointer, function,
//   variadic-function, unprototyped-function, opaque-pointee (a pointer to
//   an incomplete struct or union), cf-bridged (a pointer to a struct with
//   objc_bridge, objc_bridge_mutable or objc_bridge_related, as
//   CF_BRIDGED_TYPE declares CGContextRef), cxx-reference, member-pointer,
//   incomplete-record, cxx-record (not C-like), cxx-template (a class
//   template specialization), union, bit-field-member, array-member (a
//   constant-size array field), flexible-array-member, object-pointee (a
//   pointer to an object or block pointer), array-pointee (a pointer to a
//   constant-size array), nsobject-qualified (NSObject<P> *), protocol-key
//   (an NSSet element or NSDictionary key of type id<P>), kindof, type-args with
//   generic-bridged, generic-repository or generic-sdk (see
//   objectImportFacts), type-in-main-file, cf-type-ref, va-list, lock-type
//   (see sugarFacts), objc-imp (the SDK's IMP, variadic where Swift reads
//   the SDK), os-object (a dispatch or os object, NSObject<OS_...> *),
//   forward-declared-class and forward-declared-protocol (no definition in
//   this unit), object-member-OWNERSHIP (an object or block
//   field, directly or in a record or array held by value: strong, weak,
//   unsafe_unretained, autoreleasing, or unqualified in a unit without
//   ARC), dependent-type, other-type and too-deep (parts nested more than 8
//   deep are not read).
//   objc_ivar.type_encoding: the ivar's type encoding as the compiler emits
//   it in the class's ivar list (ASTContext::getObjCEncodingForType with the
//   ivar, so structures carry their field names), which is what the runtime
//   reports for the ivar.
//   ivar_ref has a row for every ObjCIvarRefExpr naming an ivar declared in
//   the repository (kind direct), and one for the ivar access of each
//   accessor the compiler synthesizes (kind synthesized-getter, a read, or
//   synthesized-setter, a write, at the accessor as objc_method records it;
//   base_kind self). static_ref has a row for every DeclRefExpr naming a
//   c_static variable. Both are recorded at the name's token, with the
//   location rules above, and the enclosing method or function, its class
//   (enclosing_class, NULL outside a method), whether the reference is in a
//   block and in a block passed to dispatch_once (in_once_block), and in the
//   body of a C++ lambda (in_lambda: how the lambda captures the variable the
//   ivar is reached through, "self by reference", "self by copy",
//   "init-capture", or "not captured", which is every static; NULL outside a
//   lambda). References in the argument of __builtin_object_size are not
//   recorded (it is not evaluated; the SDK's fortified memcpy, memmove and
//   memset pass their destination to it a second time), and a reference at
//   the same place with the same access is recorded once.
//   access: write (the left side of =, or of a C++ operator=), rmw (of a
//   compound assignment, ++ or --, or a C++ operator for them), address (&x,
//   or x bound to a local non-const lvalue reference), byref (&x as an
//   argument of a call or message, or x bound to a non-const lvalue
//   reference parameter; an array that decays to a pointer to non-const when
//   it is passed, returned, assigned or used in pointer arithmetic),
//   synchronized (the operand of @synchronized, through statement expressions
//   such as ITNonnilLock's: their result expression and the initializer of a
//   local declared in them), once-token (&x as dispatch_once's predicate),
//   unevaluated (in an operand that is not evaluated: sizeof, typeof,
//   decltype and the others above), read otherwise (&x or an array passed as
//   a pointer to const included). partial: the access is to a member reached with '.' or an
//   element of an array of the ivar or variable (_rect.origin.x = 0 is a
//   partial write of _rect); a member reached through '->' or an element
//   through a pointer is a read of the pointer. base_kind (ivar_ref):
//   implicit-self (_x), self (self->_x), parameter, weak-strong-local (a
//   local initialized from a __weak variable, the strong half of the
//   weak-strong dance), local, other. retain_hint (ivar_ref): retain,
//   release, autorelease or copy when the ivar receives that message (or
//   CFRetain, CFRelease, CFAutorelease), assigned-owned when it is assigned
//   the result of retain, copy, mutableCopy, new, alloc or init of alloc;
//   NULL otherwise. sync_lock (ivar_ref and static_ref): the lock of the
//   innermost @synchronized body the reference is lexically in ("ivar USR",
//   "self", "class NAME", "class of self", "static USR", or "other SOURCE");
//   lock and unlock function pairs are not recognized.
//   objc_impl has a row for every @implementation (category NULL) and
//   category @implementation in the repository, with arc, the mode of the
//   unit that compiles it: the mode that governs the class's own code.
//   A send of a property's accessor reaches
//   its ivar through objc_method.property_usr and the synthesize row of
//   objc_property, whose ivar_usr is objc_ivar.usr.
//
// Macros and conditional compilation: macro_def, macro_undef, macro_ast_fact,
// macro_expansion, macro_use_count, pp_condition and pp_skipped, from the
// preprocessor's callbacks (MacroDefined, MacroUndefined, MacroExpands, If,
// Elif, Ifdef, Ifndef, Elifdef, Elifndef, Else, Endif, SourceRangeSkipped).
// Rows of a file in the repository (not under Build/) are recorded once per
// target, content and view of that file, by the unit that holds its claim in
// decl_source (as a header's declarations are), and carry that view; a view
// does not see a macro that expands differently without skipping a branch.
// Every unit records its own rows for its main file.
//   macro_def: every macro defined in a repository file: kind (object or
//   function), params (comma-separated; "..." for __VA_ARGS__, "name..." for
//   a GNU named variadic parameter), variadic, body (the replacement tokens
//   as the preprocessor spells them, separated by one space where the source
//   has any; at most 1,000 bytes, body_truncated 1 beyond), body_digest
//   (SHA-256, 16 hex digits, of kind, params and the whole body: the identity
//   of a definition), previous_def ("file:line" of the definition this one
//   replaced in the unit, without an #undef between), and file, line and col
//   of its name. A definition inside a skipped range is not recorded (the
//   preprocessor does not read it). facts are words from the replacement
//   tokens, separated by spaces, with details in fact_detail (JSON, word to
//   list): send (a '[' that does not follow an operand, holding a selector
//   piece or a receiver and a unary selector), selector (@selector), self,
//   cmd (_cmd), file-line (__FILE__, __LINE__, __func__, __FUNCTION__,
//   __PRETTY_FUNCTION__, __FILE_NAME__), stringify (# of a parameter), paste
//   (##), statement-expression ("({"), control-flow-keyword (return, break,
//   continue or goto anywhere in the body), return and goto outside a block or a
//   function body the macro defines, break and continue outside a loop (or,
//   for break, a switch) the macro opens, synchronized, autoreleasepool, try
//   (@synchronized, @autoreleasepool, @try), block (^ then { or a parameter
//   list and {), static, method-definition ('-' or '+' then '(' at the start
//   of the body or after ';' or '}'), class-definition (@interface,
//   @implementation, @protocol), method-family-attribute
//   (objc_method_family, ns_returns_retained and the others in
//   methodFamilyAttributes()), type-parameter (a parameter used as a cast, a
//   declaration's type, or the operand of sizeof, alignof or @encode),
//   multiple-evaluation and unevaluated-parameter (a parameter written more
//   than once, or never, outside # and ##; a count of the text: a use the
//   code skips at run time, as DLog's when logging is off, is not seen), and
//   uses-macro (a name in the body that is a repository macro defined when
//   this one is). These are read from tokens, so they are facts about the
//   text and can be wrong where the text is ambiguous (a type-parameter that
//   is an expression in parentheses).
//   macro_undef: every #undef in a repository file, with the definition it
//   removed.
//   macro_ast_fact: facts from the AST of this unit's expansions of each
//   repository macro (name, def_file, def_line), attributed to the macro
//   whose replacement text spells the token (a pasted token is followed to
//   the ## that made it): send (detail the selector, with " [argument]" when
//   the selector comes from an argument and " [pasted]" when the macro pasted
//   it), selector, self ("written", or "implicit (an ivar access)"), cmd,
//   ivar (its name), block, method (the method, as a definition or
//   declaration, when the macro writes its '-' or '+'), names-method (the
//   macro spells only its selector), class (the macro writes the @interface,
//   @implementation or @protocol), names-class (it spells only the name),
//   declaration (a variable, function, typedef or tag
//   the macro declares outside any compound statement that the same
//   expansion opens: its name is visible to the code around the use), and
//   expands (a repository macro expanded in its replacement text, one
//   level). count is how many nodes; at most 20 details per macro and fact,
//   the rest counted in one row "(N more)".
//   macro_expansion: every expansion of a repository macro whose site is in a
//   repository file. nesting: none (its name is written in a file), argument
//   (written in a file, in the arguments of another expansion), or body
//   (made by another macro's replacement text; parent_name is that macro
//   when it is a repository macro). file, line and col are where the name is
//   written (for body, the outermost expansion's site); outer_name,
//   outer_line and outer_col are the outermost expansion's name and site.
//   The join to a send, selector_ref, ivar_ref, static_ref or reflective_call
//   row that has a macro_role is: row.file = file AND row.expansion_line =
//   outer_line AND row.expansion_col = outer_col (row.macro_name is then
//   outer_name). args: the unexpanded argument texts, a JSON list, each at
//   most 120 bytes (args_truncated). in_condition: in an #if or #elif.
//   enclosing_usr and enclosing_name: the innermost function or method
//   definition (or file-scope variable with an initializer) whose range
//   strictly contains the site (a declaration that begins with the macro is
//   made by it, not around it). An argument the macro never substitutes, or
//   only stringifies or pastes, is not expanded and has no rows.
//   macro_use_count: the expansions of each macro defined outside the
//   repository (the SDK, the compiler's predefines and command line, as
//   def_file "<built-in>" with def_line 0) whose name is written in a
//   repository file, counted per file. A send in such a macro is a send row
//   with that macro_name.
//   pp_condition: every #if, #ifdef, #ifndef, #elif, #elifdef, #elifndef and
//   #else in a repository file that the unit reads: condition (the text
//   after the keyword to the end of the directive, comments removed; for
//   #ifdef and #ifndef the macro), chain_line (the line of the #if that opens
//   its chain), value (true, false or not-evaluated: an #elif after a taken
//   branch; a directive reached more than once lists each value, joined with
//   commas), include_guard. A directive inside a skipped range has no row.
//   pp_skipped: every range the preprocessor skipped in a repository file:
//   start_line (the directive that begins it) and end_line (the directive
//   that ends it), both directive lines included, and the directive,
//   condition and chain_line of the directive that begins it.
//   Include guards: a file's first conditional directive, with only comments
//   before it, that is #ifndef X or #if !defined(X), whose next directive is
//   #define X, and whose #endif has only comments after it, has
//   include_guard 1, and so does a range it skips (include_guard of the
//   chain's #if). #pragma once makes no directive and no range: a second
//   inclusion is not read.
//
// Exit status: 0 extracted cleanly; 3 recorded, but the unit had errors (the
// diagnostics are printed); 2 usage or database error (nothing recorded, and
// rows from an earlier extraction of the unit are left as they were).

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/DeclObjC.h"
#include "clang/AST/ExprCXX.h"
#include "clang/AST/ExprObjC.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Analysis/CFG.h"
#include "clang/Basic/Builtins.h"
#include "clang/Basic/DiagnosticOptions.h"
#include "clang/Basic/SourceManager.h"
#include "clang/Basic/Version.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/CompilerInvocation.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Frontend/TextDiagnosticPrinter.h"
#include "clang/Index/USRGeneration.h"
#include "clang/Lex/Lexer.h"
#include "clang/Lex/MacroArgs.h"
#include "clang/Lex/MacroInfo.h"
#include "clang/Lex/PPCallbacks.h"
#include "clang/Lex/Preprocessor.h"
#include "clang/Serialization/ASTReader.h"
#include "clang/Serialization/ModuleFile.h"
#include "clang/Tooling/Tooling.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/raw_ostream.h"

#include <CommonCrypto/CommonDigest.h>
#include <sqlite3.h>

#include <algorithm>
#include <cstring>
#include <functional>
#include <ctime>
#include <limits.h>
#include <map>
#include <optional>
#include <set>
#include <stdlib.h>
#include <string>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "reflective_table.h"

#ifndef CODEDB_LLVM_CLANG
#error "build.sh defines CODEDB_LLVM_CLANG (path of upstream clang), CODEDB_RESOURCE_DIR and CODEDB_EXTRACTOR_DIGEST"
#endif

using namespace clang;

// PRAGMA user_version of the database. codedb.py's SCHEMA_VERSION must match.
static const int kSchemaVersion = 13;

// The location columns every row table shares (see the top of this file).
#define LOCATION_COLUMNS                                                                                    \
    "  file TEXT NOT NULL,"                                                                                 \
    "  line INTEGER NOT NULL,"                                                                              \
    "  col INTEGER NOT NULL,"                                                                               \
    "  macro_name TEXT,"                                                                                    \
    "  macro_file TEXT,"                                                                                    \
    "  macro_line INTEGER,"                                                                                 \
    "  macro_role TEXT,"                                                                                    \
    "  expansion_line INTEGER,"                                                                             \
    "  expansion_col INTEGER,"                                                                              \
    "  in_migration_scope INTEGER NOT NULL"

// Whether a row is in code the compiler does not emit because a condition
// folds to a constant (see "Constant conditions" at the top of this file),
// and where that condition is written.
#define CONSTANT_FALSE_COLUMNS                                                                              \
    "  in_constant_false_branch INTEGER NOT NULL DEFAULT 0,"                                                \
    "  constant_condition_file TEXT,"                                                                       \
    "  constant_condition_line INTEGER"

// The facts about a type that objc_ivar and c_static share (see "State"
// at the top of this file).
#define TYPE_COLUMNS                                                                                        \
    "  type TEXT NOT NULL,"                                                                                 \
    "  canonical_type TEXT NOT NULL,"                                                                       \
    "  type_class TEXT NOT NULL,"                                                                           \
    "  object_class TEXT,"                                                                                  \
    "  object_protocols TEXT,"                                                                              \
    "  record_name TEXT,"                                                                                   \
    "  record_has_objects INTEGER,"                                                                         \
    "  ownership_written TEXT,"                                                                             \
    "  ownership TEXT NOT NULL,"                                                                            \
    "  arc INTEGER NOT NULL,"                                                                               \
    "  import_facts TEXT NOT NULL,"

// The schema. The driver and the query helper read it; only the extractor
// creates it (the driver adds tu_failure).
static const char *kSchema =
    "CREATE TABLE IF NOT EXISTS tu("
    "  id INTEGER PRIMARY KEY,"
    "  target TEXT NOT NULL,"
    "  main_file TEXT NOT NULL,"
    "  cmd_digest TEXT NOT NULL,"
    "  extracted_at TEXT NOT NULL,"
    "  clang_version TEXT NOT NULL,"
    "  diagnostics_errors INTEGER NOT NULL,"
    "  sdk_path TEXT,"
    "  sdk_version TEXT,"
    "  configuration TEXT,"
    "  arch TEXT,"
    "  extractor_version TEXT NOT NULL,"
    "  arguments TEXT NOT NULL,"
    "  migration_scope TEXT NOT NULL,"
    "  module_bodies_skipped INTEGER NOT NULL DEFAULT 0,"
    "  UNIQUE(target, main_file));"
    // view: for a file in the repository that the unit reads itself, the
    // digest of how the unit's preprocessor saw it (see "Declarations in
    // headers" at the top of this file); NULL otherwise.
    "CREATE TABLE IF NOT EXISTS tu_input("
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  path TEXT NOT NULL,"
    "  digest TEXT NOT NULL,"
    "  view TEXT,"
    "  PRIMARY KEY(tu, path)) WITHOUT ROWID;"
    "CREATE TABLE IF NOT EXISTS send("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  selector TEXT NOT NULL,"
    "  receiver_kind TEXT NOT NULL,"
    "  receiver_type TEXT,"
    "  target_usr TEXT,"
    "  file TEXT NOT NULL,"
    "  line INTEGER NOT NULL,"
    "  col INTEGER NOT NULL,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT,"
    "  in_block INTEGER NOT NULL,"
    "  implicit_accessor INTEGER NOT NULL,"
    "  macro_name TEXT,"
    "  macro_file TEXT,"
    "  macro_line INTEGER,"
    "  macro_role TEXT,"
    "  expansion_line INTEGER,"
    "  expansion_col INTEGER,"
    "  in_migration_scope INTEGER NOT NULL," CONSTANT_FALSE_COLUMNS ","
    // In code no path from the function's entry reaches, in this unit's
    // configuration (see "Unreachable code" at the top of this file).
    "  in_unreachable_code INTEGER NOT NULL DEFAULT 0);"
    // Every Objective-C method declared or defined in the repository,
    // including accessors the compiler declares for properties (is_implicit)
    // and synthesizes in an implementation (is_synthesized_accessor).
    "CREATE TABLE IF NOT EXISTS objc_method("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  usr TEXT,"
    "  selector TEXT NOT NULL,"
    "  is_class_method INTEGER NOT NULL,"
    "  container_usr TEXT,"
    "  container_name TEXT NOT NULL,"
    "  container_kind TEXT NOT NULL,"
    "  class_name TEXT,"
    "  is_definition INTEGER NOT NULL,"
    "  is_implicit INTEGER NOT NULL,"
    "  is_synthesized_accessor INTEGER NOT NULL,"
    "  is_optional INTEGER NOT NULL,"
    "  property_usr TEXT,"
    "  return_type TEXT,"
    "  type_encoding TEXT," LOCATION_COLUMNS ");"
    // What each objc_method row overrides: the methods Clang's overridden-
    // methods query returns for it (methods of superclasses and protocol
    // requirements of the class, its categories and extensions, that have
    // its selector and kind). overridden_file is a stored path (absolute
    // when outside the repository). owner_parsed, overridden_class and
    // overridden_class_parsed: see "Overrides" at the top of this file;
    // overridden_class is the class a category or class extension extends,
    // and is NULL, as overridden_class_parsed is, for other containers.
    "CREATE TABLE IF NOT EXISTS objc_method_override("
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  method INTEGER NOT NULL REFERENCES objc_method(id),"
    "  overridden_usr TEXT,"
    "  overridden_container TEXT NOT NULL,"
    "  overridden_container_kind TEXT NOT NULL,"
    "  overridden_file TEXT,"
    "  overridden_line INTEGER,"
    "  outside_repository INTEGER NOT NULL,"
    "  owner_parsed INTEGER NOT NULL,"
    "  overridden_class TEXT,"
    "  overridden_class_parsed INTEGER,"
    "  is_optional_requirement INTEGER NOT NULL);"
    // Every property declaration, and every @synthesize and @dynamic
    // (written or done by the compiler) in an implementation.
    "CREATE TABLE IF NOT EXISTS objc_property("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  usr TEXT,"
    "  name TEXT NOT NULL,"
    "  kind TEXT NOT NULL,"
    "  is_class_property INTEGER NOT NULL,"
    "  container_usr TEXT,"
    "  container_name TEXT NOT NULL,"
    "  container_kind TEXT NOT NULL,"
    "  class_name TEXT,"
    "  getter_selector TEXT NOT NULL,"
    "  setter_selector TEXT,"
    "  attributes TEXT NOT NULL,"
    "  ivar_name TEXT,"
    "  is_readonly INTEGER NOT NULL,"
    "  is_implicit INTEGER NOT NULL,"
    "  type TEXT,"
    // For a @synthesize (written or automatic): the USR of the ivar that
    // backs the property, objc_ivar.usr; the key from a property to its
    // storage.
    "  ivar_usr TEXT," LOCATION_COLUMNS ");"
    // Every ivar of an Objective-C class in the repository: declared in an
    // @interface, a class extension or an @implementation, or synthesized
    // for a property. See "State" at the top of this file.
    "CREATE TABLE IF NOT EXISTS objc_ivar("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  usr TEXT,"
    "  class_name TEXT NOT NULL,"
    "  name TEXT NOT NULL,"
    "  container_kind TEXT NOT NULL," TYPE_COLUMNS
    "  bit_width INTEGER,"
    "  access TEXT NOT NULL,"
    "  is_iboutlet INTEGER NOT NULL,"
    "  synthesized_by TEXT,"
    "  property_name TEXT,"
    "  type_encoding TEXT," LOCATION_COLUMNS ");"
    // Every variable with static storage declared in the repository: file
    // and function statics, globals and their extern declarations, static
    // data members.
    "CREATE TABLE IF NOT EXISTS c_static("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  usr TEXT,"
    "  name TEXT NOT NULL,"
    "  kind TEXT NOT NULL,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT," TYPE_COLUMNS
    "  is_const INTEGER NOT NULL,"
    "  pointee_const INTEGER,"
    "  init_kind TEXT NOT NULL,"
    "  thread_local INTEGER NOT NULL," LOCATION_COLUMNS ");"
    // Every reference to an objc_ivar, and the accesses of the accessors the
    // compiler synthesizes.
    "CREATE TABLE IF NOT EXISTS ivar_ref("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  ivar_usr TEXT,"
    "  ivar_class TEXT NOT NULL,"
    "  ivar_name TEXT NOT NULL,"
    "  kind TEXT NOT NULL,"
    "  access TEXT NOT NULL,"
    "  partial INTEGER NOT NULL,"
    "  base_kind TEXT NOT NULL,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT,"
    "  enclosing_class TEXT,"
    "  in_block INTEGER NOT NULL,"
    "  in_once_block INTEGER NOT NULL,"
    "  in_lambda TEXT,"
    "  retain_hint TEXT,"
    "  sync_lock TEXT," LOCATION_COLUMNS "," CONSTANT_FALSE_COLUMNS ");"
    // Every reference to a c_static.
    "CREATE TABLE IF NOT EXISTS static_ref("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  var_usr TEXT,"
    "  name TEXT NOT NULL,"
    "  var_kind TEXT NOT NULL,"
    "  access TEXT NOT NULL,"
    "  partial INTEGER NOT NULL,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT,"
    "  enclosing_class TEXT,"
    "  in_block INTEGER NOT NULL,"
    "  in_once_block INTEGER NOT NULL,"
    "  in_lambda TEXT,"
    "  sync_lock TEXT," LOCATION_COLUMNS "," CONSTANT_FALSE_COLUMNS ");"
    // Every @implementation and category @implementation, with the ARC mode
    // of the unit that compiles it.
    "CREATE TABLE IF NOT EXISTS objc_impl("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  class_name TEXT NOT NULL,"
    "  category TEXT,"
    "  arc INTEGER NOT NULL," LOCATION_COLUMNS ");"
    "CREATE TABLE IF NOT EXISTS selector_ref("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  selector TEXT NOT NULL,"
    "  kind TEXT NOT NULL,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT,"
    "  in_block INTEGER NOT NULL," LOCATION_COLUMNS ");"
    // argument_kind: selector-expr (@selector, or NSStringFromSelector of
    // one), string-literal, constant (a const variable or a macro whose
    // replacement is a literal, named in argument_constant), nil (a null
    // pointer constant: nil, NULL, 0), self-selector (_cmd, the enclosing
    // method's selector), or dynamic (anything else; argument_text is its
    // source). Only the first three resolve a selector or class.
    "CREATE TABLE IF NOT EXISTS reflective_call("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  function_or_selector TEXT NOT NULL,"
    "  call_kind TEXT NOT NULL,"
    "  kind TEXT NOT NULL,"
    "  argument_index INTEGER NOT NULL,"
    "  argument_kind TEXT NOT NULL,"
    "  argument_text TEXT,"
    "  argument_constant TEXT,"
    "  resolved_selector TEXT,"
    "  resolved_class TEXT,"
    "  receiver_type TEXT,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT,"
    "  in_block INTEGER NOT NULL," LOCATION_COLUMNS ");"
    // Which unit recorded the declarations of a file, per target, content
    // and view (via_module 0), and the files a unit read only through a
    // module, whose declarations are not recorded (via_module 1, view '').
    "CREATE TABLE IF NOT EXISTS decl_source("
    "  path TEXT NOT NULL,"
    "  digest TEXT NOT NULL,"
    "  target TEXT NOT NULL,"
    "  view TEXT NOT NULL,"
    "  via_module INTEGER NOT NULL,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  PRIMARY KEY(path, digest, target, view, via_module)) WITHOUT ROWID;"
    // The preprocessor (see "Macros and conditional compilation" at the top
    // of this file). Rows of a file are recorded once per target, content and
    // view of that file, by the unit that holds its claim in decl_source;
    // view is that view (tu_input.view), so that a query can tell which units
    // saw each row. macro_ast_fact is recorded by every unit.
    "CREATE TABLE IF NOT EXISTS macro_def("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  name TEXT NOT NULL,"
    "  kind TEXT NOT NULL,"
    "  params TEXT,"
    "  variadic INTEGER NOT NULL,"
    "  body TEXT NOT NULL,"
    "  body_truncated INTEGER NOT NULL,"
    "  body_digest TEXT NOT NULL,"
    "  facts TEXT NOT NULL,"
    "  fact_detail TEXT NOT NULL,"
    "  previous_def TEXT,"
    "  view TEXT,"
    "  file TEXT NOT NULL,"
    "  line INTEGER NOT NULL,"
    "  col INTEGER NOT NULL,"
    "  in_migration_scope INTEGER NOT NULL);"
    "CREATE TABLE IF NOT EXISTS macro_undef("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  name TEXT NOT NULL,"
    "  def_file TEXT,"
    "  def_line INTEGER,"
    "  view TEXT,"
    "  file TEXT NOT NULL,"
    "  line INTEGER NOT NULL,"
    "  col INTEGER NOT NULL,"
    "  in_migration_scope INTEGER NOT NULL);"
    "CREATE TABLE IF NOT EXISTS macro_ast_fact("
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  name TEXT NOT NULL,"
    "  def_file TEXT NOT NULL,"
    "  def_line INTEGER NOT NULL,"
    "  fact TEXT NOT NULL,"
    "  detail TEXT NOT NULL,"
    "  count INTEGER NOT NULL);"
    "CREATE TABLE IF NOT EXISTS macro_expansion("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  name TEXT NOT NULL,"
    "  def_file TEXT NOT NULL,"
    "  def_line INTEGER NOT NULL,"
    "  nesting TEXT NOT NULL,"
    "  parent_name TEXT,"
    "  outer_name TEXT NOT NULL,"
    "  outer_line INTEGER NOT NULL,"
    "  outer_col INTEGER NOT NULL,"
    "  in_condition INTEGER NOT NULL,"
    "  args TEXT,"
    "  args_truncated INTEGER NOT NULL,"
    "  enclosing_usr TEXT,"
    "  enclosing_name TEXT,"
    "  view TEXT,"
    "  file TEXT NOT NULL,"
    "  line INTEGER NOT NULL,"
    "  col INTEGER NOT NULL,"
    "  in_migration_scope INTEGER NOT NULL);"
    "CREATE TABLE IF NOT EXISTS macro_use_count("
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  name TEXT NOT NULL,"
    "  def_file TEXT NOT NULL,"
    "  def_line INTEGER NOT NULL,"
    "  count INTEGER NOT NULL,"
    "  view TEXT,"
    "  file TEXT NOT NULL,"
    "  in_migration_scope INTEGER NOT NULL);"
    "CREATE TABLE IF NOT EXISTS pp_condition("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  directive TEXT NOT NULL,"
    "  condition TEXT,"
    "  chain_line INTEGER NOT NULL,"
    "  value TEXT NOT NULL,"
    "  include_guard INTEGER NOT NULL,"
    "  view TEXT,"
    "  file TEXT NOT NULL,"
    "  line INTEGER NOT NULL,"
    "  in_migration_scope INTEGER NOT NULL);"
    "CREATE TABLE IF NOT EXISTS pp_skipped("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  start_line INTEGER NOT NULL,"
    "  end_line INTEGER NOT NULL,"
    "  directive TEXT NOT NULL,"
    "  condition TEXT,"
    "  chain_line INTEGER NOT NULL,"
    "  include_guard INTEGER NOT NULL,"
    "  view TEXT,"
    "  file TEXT NOT NULL,"
    "  in_migration_scope INTEGER NOT NULL);"
    "CREATE INDEX IF NOT EXISTS macro_def_name ON macro_def(name);"
    "CREATE INDEX IF NOT EXISTS macro_def_file ON macro_def(file);"
    "CREATE INDEX IF NOT EXISTS macro_def_tu ON macro_def(tu);"
    "CREATE INDEX IF NOT EXISTS macro_undef_name ON macro_undef(name);"
    "CREATE INDEX IF NOT EXISTS macro_undef_tu ON macro_undef(tu);"
    "CREATE INDEX IF NOT EXISTS macro_ast_fact_name ON macro_ast_fact(name, def_file, def_line);"
    "CREATE INDEX IF NOT EXISTS macro_ast_fact_tu ON macro_ast_fact(tu);"
    "CREATE INDEX IF NOT EXISTS macro_expansion_name ON macro_expansion(name);"
    "CREATE INDEX IF NOT EXISTS macro_expansion_site ON macro_expansion(file, outer_line, outer_col);"
    "CREATE INDEX IF NOT EXISTS macro_expansion_enclosing ON macro_expansion(enclosing_usr);"
    "CREATE INDEX IF NOT EXISTS macro_expansion_tu ON macro_expansion(tu);"
    "CREATE INDEX IF NOT EXISTS macro_use_count_name ON macro_use_count(name);"
    "CREATE INDEX IF NOT EXISTS macro_use_count_tu ON macro_use_count(tu);"
    "CREATE INDEX IF NOT EXISTS pp_condition_file ON pp_condition(file);"
    "CREATE INDEX IF NOT EXISTS pp_condition_tu ON pp_condition(tu);"
    "CREATE INDEX IF NOT EXISTS pp_skipped_file ON pp_skipped(file);"
    "CREATE INDEX IF NOT EXISTS pp_skipped_tu ON pp_skipped(tu);"
    "CREATE INDEX IF NOT EXISTS send_selector ON send(selector);"
    "CREATE INDEX IF NOT EXISTS send_tu ON send(tu);"
    "CREATE INDEX IF NOT EXISTS tu_input_path ON tu_input(path);"
    "CREATE INDEX IF NOT EXISTS objc_method_selector ON objc_method(selector);"
    "CREATE INDEX IF NOT EXISTS objc_method_tu ON objc_method(tu);"
    "CREATE INDEX IF NOT EXISTS objc_method_override_method ON objc_method_override(method);"
    "CREATE INDEX IF NOT EXISTS objc_method_override_tu ON objc_method_override(tu);"
    "CREATE INDEX IF NOT EXISTS objc_property_name ON objc_property(name);"
    "CREATE INDEX IF NOT EXISTS objc_property_getter ON objc_property(getter_selector);"
    "CREATE INDEX IF NOT EXISTS objc_property_setter ON objc_property(setter_selector);"
    "CREATE INDEX IF NOT EXISTS objc_property_tu ON objc_property(tu);"
    "CREATE INDEX IF NOT EXISTS selector_ref_selector ON selector_ref(selector);"
    "CREATE INDEX IF NOT EXISTS selector_ref_tu ON selector_ref(tu);"
    "CREATE INDEX IF NOT EXISTS reflective_call_selector ON reflective_call(resolved_selector);"
    "CREATE INDEX IF NOT EXISTS reflective_call_text ON reflective_call(argument_text);"
    "CREATE INDEX IF NOT EXISTS reflective_call_tu ON reflective_call(tu);"
    "CREATE INDEX IF NOT EXISTS decl_source_tu ON decl_source(tu);"
    "CREATE INDEX IF NOT EXISTS objc_ivar_class ON objc_ivar(class_name, name);"
    "CREATE INDEX IF NOT EXISTS objc_ivar_usr ON objc_ivar(usr);"
    "CREATE INDEX IF NOT EXISTS objc_ivar_tu ON objc_ivar(tu);"
    "CREATE INDEX IF NOT EXISTS c_static_name ON c_static(name);"
    "CREATE INDEX IF NOT EXISTS c_static_usr ON c_static(usr);"
    "CREATE INDEX IF NOT EXISTS c_static_file ON c_static(file);"
    "CREATE INDEX IF NOT EXISTS c_static_tu ON c_static(tu);"
    "CREATE INDEX IF NOT EXISTS ivar_ref_ivar ON ivar_ref(ivar_class, ivar_name);"
    "CREATE INDEX IF NOT EXISTS ivar_ref_usr ON ivar_ref(ivar_usr);"
    "CREATE INDEX IF NOT EXISTS ivar_ref_enclosing ON ivar_ref(enclosing_class);"
    "CREATE INDEX IF NOT EXISTS ivar_ref_tu ON ivar_ref(tu);"
    "CREATE INDEX IF NOT EXISTS static_ref_usr ON static_ref(var_usr);"
    "CREATE INDEX IF NOT EXISTS static_ref_name ON static_ref(name);"
    "CREATE INDEX IF NOT EXISTS static_ref_file ON static_ref(file);"
    "CREATE INDEX IF NOT EXISTS static_ref_enclosing ON static_ref(enclosing_class);"
    "CREATE INDEX IF NOT EXISTS static_ref_tu ON static_ref(tu);"
    "CREATE INDEX IF NOT EXISTS objc_impl_class ON objc_impl(class_name);"
    "CREATE INDEX IF NOT EXISTS objc_impl_tu ON objc_impl(tu);"
    // Classes and adoptions of the repository, and the declarations outside
    // it (see "Classes and the SDK" at the top of this file).
    "CREATE TABLE IF NOT EXISTS objc_class("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  usr TEXT,"
    "  name TEXT NOT NULL,"
    "  superclass TEXT," LOCATION_COLUMNS ");"
    "CREATE TABLE IF NOT EXISTS objc_adoption("
    "  id INTEGER PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  class_or_category TEXT NOT NULL,"
    "  container_kind TEXT NOT NULL,"
    "  protocol TEXT NOT NULL," LOCATION_COLUMNS ");"
    "CREATE TABLE IF NOT EXISTS sdk_claim("
    "  module TEXT PRIMARY KEY,"
    "  tu INTEGER NOT NULL REFERENCES tu(id));"
    "CREATE TABLE IF NOT EXISTS tu_module("
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  module TEXT NOT NULL,"
    "  PRIMARY KEY(tu, module)) WITHOUT ROWID;"
    "CREATE TABLE IF NOT EXISTS sdk_method("
    "  selector TEXT NOT NULL,"
    "  container TEXT NOT NULL,"
    "  container_kind TEXT NOT NULL,"
    "  is_class_method INTEGER NOT NULL,"
    "  framework TEXT NOT NULL,"
    "  is_optional INTEGER NOT NULL,"
    "  is_action INTEGER NOT NULL,"
    "  module TEXT NOT NULL,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  UNIQUE(module, container, selector, is_class_method));"
    "CREATE TABLE IF NOT EXISTS sdk_class("
    "  name TEXT NOT NULL,"
    "  superclass TEXT,"
    "  framework TEXT NOT NULL,"
    "  module TEXT NOT NULL,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  UNIQUE(module, name));"
    "CREATE TABLE IF NOT EXISTS function_ref("
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  callee TEXT NOT NULL,"
    "  enclosing_name TEXT NOT NULL,"
    "  refs INTEGER NOT NULL,"
    "  PRIMARY KEY(tu, callee, enclosing_name)) WITHOUT ROWID;"
    "CREATE TABLE IF NOT EXISTS sdk_adoption("
    "  container TEXT NOT NULL,"
    "  container_kind TEXT NOT NULL,"
    "  protocol TEXT NOT NULL,"
    "  module TEXT NOT NULL,"
    "  tu INTEGER NOT NULL REFERENCES tu(id),"
    "  UNIQUE(module, container, protocol));"
    "CREATE INDEX IF NOT EXISTS objc_class_name ON objc_class(name);"
    "CREATE INDEX IF NOT EXISTS objc_class_tu ON objc_class(tu);"
    "CREATE INDEX IF NOT EXISTS objc_adoption_container ON objc_adoption(class_or_category);"
    "CREATE INDEX IF NOT EXISTS objc_adoption_tu ON objc_adoption(tu);"
    "CREATE INDEX IF NOT EXISTS sdk_claim_tu ON sdk_claim(tu);"
    "CREATE INDEX IF NOT EXISTS tu_module_module ON tu_module(module);"
    "CREATE INDEX IF NOT EXISTS sdk_method_selector ON sdk_method(selector);"
    "CREATE INDEX IF NOT EXISTS sdk_method_tu ON sdk_method(tu);"
    "CREATE INDEX IF NOT EXISTS sdk_class_name ON sdk_class(name);"
    "CREATE INDEX IF NOT EXISTS sdk_class_tu ON sdk_class(tu);"
    "CREATE INDEX IF NOT EXISTS sdk_adoption_container ON sdk_adoption(container);"
    "CREATE INDEX IF NOT EXISTS sdk_adoption_tu ON sdk_adoption(tu);";

// implicit_accessor values.
enum ImplicitKind { kExplicit = 0, kPropertyAccessor = 1, kSubscriptAccessor = 2 };

// Where a row is written (see the top of this file).
struct Located {
    std::string file;
    unsigned line = 0, col = 0;
    std::string macroName, macroFile, macroRole;
    unsigned macroLine = 0, expansionLine = 0, expansionCol = 0;
    int inMigrationScope = 0;
};

// Code that the compiler does not emit because a condition folds to a
// constant (see "Constant conditions" at the top of this file).
struct ConstantFalse {
    int inConstantFalse = 0;
    std::string conditionFile;
    unsigned conditionLine = 0;
};

struct SendRow : Located, ConstantFalse {
    std::string selector, receiverKind, receiverType, targetUSR;
    std::string enclosingUSR, enclosingName;
    int inBlock = 0;
    int implicitAccessor = kExplicit;
    // See "Unreachable code" at the top of this file.
    int inUnreachable = 0;
};

struct OverrideRow {
    std::string usr, container, containerKind, file, className;
    unsigned line = 0;
    int outsideRepository = 0, ownerParsed = 0, isOptionalRequirement = 0;
    int classParsed = -1;  // -1: not a category or class extension
};

struct MethodRow : Located {
    std::string usr, selector, containerUSR, containerName, containerKind, className;
    int isClassMethod = 0, isDefinition = 0, isImplicit = 0, isSynthesized = 0, isOptional = 0;
    std::string propertyUSR, returnType, typeEncoding;
    // The file whose claim decides whether a declaration row is recorded;
    // empty for rows of implementations, which are always recorded.
    std::string claimFile;
    std::vector<OverrideRow> overrides;
};

// The TYPE_COLUMNS of a declaration. bitWidth and hasObjects are -1 when
// they do not apply.
struct TypeFacts {
    std::string type, canonical, typeClass, objectClass, protocols, recordName, ownershipWritten, ownership;
    std::string importFacts, encoding;
    int hasObjects = -1, bitWidth = -1, arc = 0;
};

struct IvarRow : Located {
    std::string usr, className, name, containerKind, access, synthesizedBy, propertyName;
    TypeFacts facts;
    int isIBOutlet = 0;
    std::string claimFile;
};

struct StaticRow : Located {
    std::string usr, name, kind, enclosingUSR, enclosingName;
    TypeFacts facts;
    int isConst = 0, pointeeConst = -1, threadLocal = 0;
    std::string initKind;
    std::string claimFile;
};

struct IvarRefRow : Located, ConstantFalse {
    std::string ivarUSR, ivarClass, ivarName, kind, access, baseKind;
    std::string enclosingUSR, enclosingName, enclosingClass;
    std::string inLambda, retainHint, syncLock;
    int partial = 0, inBlock = 0, inOnceBlock = 0;
};

struct StaticRefRow : Located, ConstantFalse {
    std::string varUSR, name, varKind, access;
    std::string enclosingUSR, enclosingName, enclosingClass;
    std::string inLambda, syncLock;
    int partial = 0, inBlock = 0, inOnceBlock = 0;
};

struct ImplRow : Located {
    std::string className, category;
    int arc = 0;
};

struct PropertyRow : Located {
    std::string usr, name, kind, containerUSR, containerName, containerKind, className;
    std::string getter, setter, attributes, ivarName, ivarUSR, type;
    int isClassProperty = 0, isReadonly = 0, isImplicit = 0;
    std::string claimFile;
};

struct SelectorRefRow : Located {
    std::string selector, kind;
    std::string enclosingUSR, enclosingName;
    int inBlock = 0;
};

struct ReflectiveRow : Located {
    std::string name, callKind, kind, argumentKind, argumentText, argumentConstant;
    std::string resolvedSelector, resolvedClass, receiverType;
    int argumentIndex = 0;
    std::string enclosingUSR, enclosingName;
    int inBlock = 0;
};

struct InputRow {
    std::string path, digest, view;
    bool viaModule = false;
};

// objc_class and objc_adoption (repository declarations, claimed as methods
// are).
struct ClassRow : Located {
    std::string usr, name, superclass, claimFile;
};

struct AdoptionRow : Located {
    std::string container, containerKind, protocol, claimFile;
};

// sdk_method, sdk_class and sdk_adoption: declarations outside the
// repository, recorded per module by the unit that holds its claim.
struct SdkMethodRow {
    std::string selector, container, containerKind, framework, module;
    int isClassMethod = 0, isOptional = 0, isAction = 0;
};

struct SdkClassRow {
    std::string name, superclass, framework, module;
};

struct SdkAdoptionRow {
    std::string container, containerKind, protocol, module;
};

// Claims other units hold, read before the unit is parsed (see "Classes and
// the SDK" at the top of this file): SDK modules, and (path, digest) of files
// this target reads only through a module.
struct PriorClaims {
    std::set<std::string> modules;
    std::set<std::pair<std::string, std::string>> moduleFiles;
};

// A macro defined in a file in the repository (macro_def).
struct MacroDefRec {
    std::string name, kind, params, body, digest, facts, detail, previous, file;
    unsigned line = 0, col = 0;
    int variadic = 0, truncated = 0, inScope = 0;
    FileID fid;
    unsigned begin = 0, end = 0;  // offsets of the definition in fid
};

struct MacroUndefRec {
    std::string name, defFile, file;
    unsigned defLine = 0, line = 0, col = 0;
    int inScope = 0;
};

// One expansion of a repository macro (macro_expansion).
struct MacroExpansionRec {
    std::string name, defFile, nesting, parentName, outerName, args, file, enclosingUSR, enclosingName;
    unsigned defLine = 0, line = 0, col = 0, outerLine = 0, outerCol = 0;
    int argsTruncated = 0, inCondition = 0, inScope = 0;
    FileID siteFid;
    unsigned siteOffset = 0;
};

// A #if-family directive in a repository file (pp_condition).
struct CondRec {
    std::string file, directive, condition;
    unsigned line = 0, chainLine = 0, endifLine = 0;
    std::set<std::string> values;
    int guard = 0, inScope = 0, skippedHere = 0;
    FileID fid;
    unsigned offset = 0;
};

// A range the preprocessor skipped in a repository file (pp_skipped).
struct SkipRec {
    std::string file;
    unsigned startLine = 0, endLine = 0;
    int inScope = 0;
    FileID fid;
};

// A function or method definition, or a variable with an initializer at
// file scope, in a repository file: the innermost one around an expansion is
// its enclosing function.
struct EnclosingRange {
    FileID fid;
    unsigned begin = 0, end = 0;
    std::string usr, name;
};

struct Results {
    std::vector<SendRow> sends;
    std::vector<InputRow> inputs;
    std::vector<MethodRow> methods;
    std::vector<PropertyRow> properties;
    std::vector<SelectorRefRow> selectorRefs;
    std::vector<ReflectiveRow> reflective;
    std::vector<IvarRow> ivars;
    std::vector<StaticRow> statics;
    std::vector<IvarRefRow> ivarRefs;
    std::vector<StaticRefRow> staticRefs;
    std::vector<ImplRow> impls;
    std::vector<ClassRow> classes;
    std::vector<AdoptionRow> adoptions;
    std::vector<SdkMethodRow> sdkMethods;
    std::vector<SdkClassRow> sdkClasses;
    std::vector<SdkAdoptionRow> sdkAdoptions;
    // function_ref: {(callee, enclosing name): evaluated references}.
    std::map<std::pair<std::string, std::string>, int> functionRefs;
    // The module keys of the declarations outside the repository the unit
    // loaded (tu_module), the keys it walked (it claims those), and whether
    // it walked the declarations of the files it reads only through a module.
    std::set<std::string> loadedModules, walkedModules;
    bool walkedModuleFiles = false;
    // Function bodies in the repository files read only through a module,
    // which are not walked (tu.module_bodies_skipped).
    int moduleBodiesSkipped = 0;
    // The preprocessor tables, moved here from PreprocessorFacts when the
    // unit is done.
    std::vector<MacroDefRec> macroDefs;
    std::vector<MacroUndefRec> macroUndefs;
    std::vector<MacroExpansionRec> macroExpansions;
    std::map<std::tuple<std::string, std::string, std::string, unsigned>, std::pair<int, int>> otherMacroCounts;
    std::vector<CondRec> conds;
    std::vector<SkipRec> skips;
    // (index in macroDefs, fact, detail) -> count, from the AST.
    std::map<std::tuple<size_t, std::string, std::string>, int> macroFacts;
    std::vector<EnclosingRange> enclosingRanges;
};

static std::string hexSHA256(const void *data, size_t length) {
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data, (CC_LONG)length, md);
    static const char *hex = "0123456789abcdef";
    std::string out;
    for (unsigned char c : md) {
        out.push_back(hex[c >> 4]);
        out.push_back(hex[c & 15]);
    }
    return out;
}

static std::string realPath(const std::string &p) {
    char buf[PATH_MAX];
    if (realpath(p.c_str(), buf)) return buf;
    return p;
}

// A stored path of a file the Swift compiler or the build generated.
static bool isBuildProduct(const std::string &stored) { return stored.compare(0, 6, "Build/") == 0; }

// Paths inside the repository are stored relative to its root; others absolute.
class PathMapper {
public:
    PathMapper(std::string root, std::vector<std::string> migrationScope)
        : root_(realPath(root)), migrationScope_(std::move(migrationScope)) {}

    // A stored path (relative to the repository) under one of the
    // --migration-scope directories (see the top of this file).
    bool inMigrationScope(const std::string &stored) const {
        if (stored.empty() || stored[0] == '/') return false;
        for (const std::string &dir : migrationScope_)
            if (stored.compare(0, dir.size(), dir) == 0) return true;
        return false;
    }

    std::string store(const std::string &absolute) const {
        if (absolute.size() > root_.size() + 1 &&
            absolute.compare(0, root_.size(), root_) == 0 && absolute[root_.size()] == '/') {
            return absolute.substr(root_.size() + 1);
        }
        return absolute;
    }

    bool inRepo(const std::string &absolute) const { return store(absolute) != absolute; }

private:
    std::string root_;
    std::vector<std::string> migrationScope_;
};

// The canonical path of a file: the real file behind a VFS overlay's virtual
// path (the file entry's real path name), with every symlink resolved. Clang's
// real path name is not always resolved: for a file it looked up without
// opening it (a module map, say) it is only made absolute.
static std::string fileEntryPath(OptionalFileEntryRef ref) {
    if (!ref) return "";
    StringRef real = ref->getFileEntry().tryGetRealPathName();
    SmallString<256> abs(real.empty() ? ref->getName() : real);
    llvm::sys::fs::make_absolute(abs);
    llvm::sys::path::remove_dots(abs, true);
    return realPath(std::string(abs.str()));
}

struct MacroExpansionSite {
    std::string name, defFile;
    unsigned defLine = 0;
};

// What the preprocessor tells the visitor.
struct PreprocessorFacts {
    // Every outermost macro expansion (one whose name is written in a file,
    // not produced by another macro), keyed by the location of the name.
    std::unordered_map<SourceLocation::UIntTy, MacroExpansionSite> uses;
    // Every expansion, at any depth, of an object-like macro whose
    // replacement is only string literals (and '@'), keyed by the location
    // of its name, with the macro's name.
    std::unordered_map<SourceLocation::UIntTy, std::string> literalMacros;
    // For every @selector(...): the location of '@' to the location of the
    // first token inside the parentheses, from the expanded token stream.
    std::unordered_map<SourceLocation::UIntTy, SourceLocation> selectorTokens;
    // Every range of a file that the preprocessor skipped (an inactive #if,
    // #ifdef, #elif or #else branch), as offsets in the file.
    std::map<FileID, std::vector<std::pair<unsigned, unsigned>>> skipped;
    // The preprocessor tables (see "Macros and conditional compilation" at
    // the top of this file).
    std::vector<MacroDefRec> defs;
    std::map<FileID, std::vector<std::pair<unsigned, size_t>>> defsByFile;  // (begin, index), sorted
    std::vector<MacroUndefRec> undefs;
    std::vector<MacroExpansionRec> expansions;
    // Expansions of macros defined outside the repository whose name is
    // written in a repository file: (file, name, definition file, line) to
    // (count, in scope).
    std::map<std::tuple<std::string, std::string, std::string, unsigned>, std::pair<int, int>> otherCounts;
    // Expansions of a repository macro written in another's body:
    // (index of the outer definition, inner macro name).
    std::set<std::pair<size_t, std::string>> bodyExpands;
    std::vector<CondRec> conds;
    // (stored path, line) -> index: a header read twice in a unit has one
    // row per directive, with every value it had.
    std::map<std::pair<std::string, unsigned>, size_t> condAt;
    std::vector<SkipRec> skips;
};

// The repository macro (an index in facts.defs) whose definition contains a
// file location, or -1.
static long definitionContaining(const PreprocessorFacts &facts, const SourceManager &sm, SourceLocation spelling) {
    if (!spelling.isFileID()) return -1;
    auto it = facts.defsByFile.find(sm.getFileID(spelling));
    if (it == facts.defsByFile.end()) return -1;
    unsigned off = sm.getFileOffset(spelling);
    const auto &list = it->second;
    auto pos = std::upper_bound(list.begin(), list.end(), std::make_pair(off, (size_t)-1));
    if (pos == list.begin()) return -1;
    --pos;
    const MacroDefRec &d = facts.defs[pos->second];
    return off >= d.begin && off <= d.end ? (long)pos->second : -1;
}

// The repository macro whose replacement text spells the token at loc (a
// token made by pasting is followed to the ## that made it), or -1.
// The token is followed one macro at a time, as locate() does: from a macro
// argument to where the argument was written (in a file: no macro spells it;
// in another macro's replacement text: that macro), and from a token made by
// pasting to the paste. A token of a replacement text belongs to the macro
// whose definition contains its spelling.
static long macroSpelling(const PreprocessorFacts &facts, const SourceManager &sm, SourceLocation loc) {
    SourceLocation l = loc;
    for (int i = 0; i < 64 && l.isValid() && l.isMacroID(); i++) {
        if (sm.isMacroArgExpansion(l)) {
            l = sm.getImmediateSpellingLoc(l);
            continue;
        }
        SourceLocation sp = sm.getImmediateSpellingLoc(l);
        if (sm.isWrittenInScratchSpace(sm.getSpellingLoc(sp))) {
            l = sm.getImmediateExpansionRange(l).getBegin();
            continue;
        }
        if (sp.isFileID()) return definitionContaining(facts, sm, sp);
        l = sp;
    }
    return -1;
}

// Text that is only whitespace and C or C++ comments.
static bool onlyCommentsAndSpace(StringRef s) {
    size_t i = 0, n = s.size();
    while (i < n) {
        char c = s[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v') {
            i++;
        } else if (c == '/' && i + 1 < n && s[i + 1] == '/') {
            while (i < n && s[i] != '\n') i++;
        } else if (c == '/' && i + 1 < n && s[i + 1] == '*') {
            size_t e = s.find("*/", i + 2);
            if (e == StringRef::npos) return false;
            i = e + 2;
        } else if (c == '\\' && i + 1 < n && (s[i + 1] == '\n' || s[i + 1] == '\r')) {
            i += 2;
        } else {
            return false;
        }
    }
    return true;
}

static std::string truncateUTF8(const std::string &s, size_t limit, int &truncated) {
    if (s.size() <= limit) return s;
    truncated = 1;
    size_t n = limit;
    while (n > 0 && (static_cast<unsigned char>(s[n]) & 0xC0) == 0x80) n--;
    return s.substr(0, n);
}

static std::string jsonString(const std::string &s);

static std::string joinSet(const std::set<std::string> &s, const char *sep) {
    std::string out;
    for (const std::string &x : s) {
        if (!out.empty()) out += sep;
        out += x;
    }
    return out;
}

// The facts read from a macro's replacement tokens (macro_def.facts and
// fact_detail; see "Macros and conditional compilation" at the top of this
// file).
struct BodyFacts {
    std::set<std::string> facts;
    std::map<std::string, std::set<std::string>> detail;
    void add(const std::string &fact, const std::string &d = "") {
        facts.insert(fact);
        if (!d.empty()) detail[fact].insert(d);
    }
};

static const std::set<std::string> &methodFamilyAttributes() {
    static const std::set<std::string> names = {
        "objc_method_family",      "ns_returns_retained",     "ns_returns_not_retained", "ns_returns_autoreleased",
        "ns_consumed",             "ns_consumes_self",        "cf_returns_retained",     "cf_returns_not_retained",
        "cf_consumed",             "NS_RETURNS_RETAINED",     "NS_RETURNS_NOT_RETAINED", "NS_RETURNS_AUTORELEASED",
        "NS_CONSUMED",             "NS_CONSUMES_SELF",        "CF_RETURNS_RETAINED",     "CF_RETURNS_NOT_RETAINED",
        "CF_CONSUMED",             "NS_REPLACES_RECEIVER",    "ns_replaces_receiver"};
    return names;
}

static BodyFacts analyzeBody(const MacroInfo *mi, const std::string &macroName, const Preprocessor &pp,
                             const std::function<bool(const IdentifierInfo *)> &isRepoMacro) {
    BodyFacts out;
    std::vector<std::string> t;
    std::vector<const Token *> toks;
    for (const Token &tok : mi->tokens()) {
        t.push_back(pp.getSpelling(tok));
        toks.push_back(&tok);
    }
    std::set<std::string> params;
    for (const IdentifierInfo *ii : mi->params()) params.insert(ii->getName().str());
    bool functionLike = mi->isFunctionLike();
    size_t n = t.size();
    auto isIdent = [&](size_t i) {
        return i < n && (toks[i]->is(tok::identifier) || toks[i]->isAnyIdentifier() ||
                         (toks[i]->getIdentifierInfo() != nullptr && !t[i].empty() &&
                          (isalpha((unsigned char)t[i][0]) || t[i][0] == '_')));
    };
    auto isParam = [&](size_t i) { return functionLike && i < n && params.count(t[i]) > 0; };
    // Keywords after which an operand starts: '[' after them is a send.
    static const std::set<std::string> operandKeywords = {"return", "case", "else", "do", "throw", "co_return"};
    auto valueLike = [&](size_t i) {
        // A token that can end an operand: then '[' after it is a subscript.
        return (isIdent(i) && !operandKeywords.count(t[i])) || t[i] == ")" || t[i] == "]" ||
               toks[i]->is(tok::numeric_constant) || tok::isStringLiteral(toks[i]->getKind()) ||
               toks[i]->is(tok::char_constant);
    };
    auto matching = [&](size_t i, const std::string &open, const std::string &close) -> size_t {
        int depth = 0;
        for (size_t j = i; j < n; j++) {
            if (t[j] == open) depth++;
            else if (t[j] == close && --depth == 0) return j;
        }
        return n;
    };
    // Uses of each parameter that the compiler evaluates (not stringified or
    // pasted).
    std::map<std::string, int> evaluated;
    for (const std::string &p : params) evaluated[p] = 0;
    // The contexts of control flow: '{' of a loop or switch, of a block,
    // or another.
    enum Ctx { kPlain, kLoop, kSwitch, kBlock, kDo };
    std::vector<Ctx> ctx;
    int pendingHeader = 0;  // 1 loop, 2 switch: a header is open, the next '{' or statement is its body
    int singleDepth = -1;   // a loop or switch body that is one statement, up to the next ';' at this depth
    Ctx singleKind = kPlain;
    bool pendingBlock = false, pendingDo = false;
    int parenDepth = 0;
    std::vector<size_t> openParens;
    std::map<size_t, size_t> matchOpen;
    auto inLoop = [&](bool forBreak) {
        if (singleDepth >= 0 && (singleKind == kLoop || (forBreak && singleKind == kSwitch))) return true;
        for (auto it = ctx.rbegin(); it != ctx.rend(); ++it) {
            if (*it == kBlock) return false;
            if (*it == kLoop || *it == kDo || (forBreak && *it == kSwitch)) return true;
        }
        return false;
    };
    auto inBlock = [&]() {
        for (Ctx c : ctx)
            if (c == kBlock) return true;
        return false;
    };
    for (size_t i = 0; i < n; i++) {
        const std::string &s = t[i];
        bool prevHash = i > 0 && t[i - 1] == "#" && functionLike;
        bool pasteAdj = (i > 0 && t[i - 1] == "##") || (i + 1 < n && t[i + 1] == "##");
        if (isParam(i) && !prevHash && !pasteAdj) evaluated[s]++;
        if (s == "#" && functionLike && isParam(i + 1)) out.add("stringify", t[i + 1]);
        if (s == "##") out.add("paste", (i > 0 ? t[i - 1] : "") + "##" + (i + 1 < n ? t[i + 1] : ""));
        if (s == "self") out.add("self");
        if (s == "_cmd") out.add("cmd");
        if (s == "__FILE__" || s == "__LINE__" || s == "__func__" || s == "__FUNCTION__" ||
            s == "__PRETTY_FUNCTION__" || s == "__FILE_NAME__")
            out.add("file-line", s);
        if (s == "static") out.add("static");
        if (methodFamilyAttributes().count(s)) out.add("method-family-attribute", s);
        if (s == "@" && i + 1 < n) {
            const std::string &k = t[i + 1];
            if (k == "synchronized" || k == "autoreleasepool" || k == "try") out.add(k);
            if (k == "selector") out.add("selector");
            if (k == "interface" || k == "implementation" || k == "protocol") out.add("class-definition", k);
        }
        // A method declared or defined: '-' or '+' then '(' at the start of the
        // body or of a declaration, outside any parentheses.
        if ((s == "-" || s == "+") && i + 1 < n && t[i + 1] == "(" && parenDepth == 0 &&
            (i == 0 || t[i - 1] == ";" || t[i - 1] == "}" || t[i - 1] == "end"))
            out.add("method-definition");
        if (s == "(" && i + 1 < n && t[i + 1] == "{") out.add("statement-expression");
        // A message send: '[' that does not follow an operand, holding a
        // selector piece (an identifier before ':') or a receiver and a unary
        // selector before ']'.
        if (s == "[" && !(i > 0 && (valueLike(i - 1) || t[i - 1] == "@"))) {
            size_t close = matching(i, "[", "]");
            bool send = false;
            int depth = 0;
            for (size_t j = i + 1; j < close && !send; j++) {
                if (t[j] == "[" || t[j] == "(" || t[j] == "{") depth++;
                else if (t[j] == "]" || t[j] == ")" || t[j] == "}") depth--;
                else if (depth == 0 && isIdent(j) && j + 1 < close && t[j + 1] == ":" && j > i + 1) send = true;
            }
            // A receiver (an operand, or a block literal's closing brace) and a
            // unary selector.
            if (!send && close < n && close >= i + 3 && isIdent(close - 1) &&
                (valueLike(close - 2) || t[close - 2] == "}"))
                send = true;
            if (send) out.add("send");
        }
        // Blocks: '^' then '{', or '^' then a parameter list then '{'.
        // Blocks: '^', an optional return type (names and '*'), an optional
        // parameter list, then '{'.
        if (s == "^" && i + 1 < n) {
            size_t j = i + 1;
            while (j < n && (isIdent(j) || t[j] == "*") && t[j] != "(") j++;
            if (j < n && t[j] == "(") j = matching(j, "(", ")") + 1;
            if (j < n && t[j] == "{") {
                pendingBlock = true;
                out.add("block");
            }
        }
        // Control flow.
        if (s == "(") parenDepth++;
        if (s == ")") parenDepth--;
        if ((s == "for" || s == "while" || s == "switch") && !(s == "while" && i > 0 && t[i - 1] == "}" &&
                                                               pendingDo)) {
            pendingHeader = s == "switch" ? 2 : 1;
            if (i + 1 < n && t[i + 1] == "(") {
                size_t close = matching(i + 1, "(", ")");
                if (close + 1 < n && t[close + 1] != "{") {
                    singleDepth = (int)ctx.size();
                    singleKind = pendingHeader == 2 ? kSwitch : kLoop;
                    pendingHeader = 0;
                }
            }
        }
        if (s == "while" && i > 0 && t[i - 1] == "}" && pendingDo) pendingDo = false;
        if (s == "do") pendingHeader = 3;
        if (s == "(") openParens.push_back(i);
        if (s == ")" && !openParens.empty()) {
            matchOpen[i] = openParens.back();
            openParens.pop_back();
        }
        if (s == "{") {
            Ctx c = kPlain;
            // The body of a function or method the macro defines: a return in
            // it leaves that function, not the macro's caller.
            static const std::set<std::string> statementWords = {"do", "else", "try", "finally", "autoreleasepool",
                                                                 "return", "case", "default"};
            static const std::set<std::string> headerWords = {"if", "while", "for", "switch", "synchronized",
                                                              "catch", "sizeof", "__typeof__", "typeof"};
            bool functionBody = false;
            if (i > 0 && isIdent(i - 1) && !statementWords.count(t[i - 1]) && pendingHeader == 0 && !pendingBlock)
                functionBody = true;
            if (i > 0 && t[i - 1] == ")" && matchOpen.count(i - 1) && pendingHeader == 0 && !pendingBlock) {
                size_t o = matchOpen[i - 1];
                if (o > 0 && isIdent(o - 1) && !headerWords.count(t[o - 1])) functionBody = true;
            }
            if (functionBody) c = kBlock;
            if (pendingBlock) c = kBlock;
            else if (pendingHeader == 1) c = kLoop;
            else if (pendingHeader == 2) c = kSwitch;
            else if (pendingHeader == 3) c = kDo;
            pendingBlock = false;
            pendingHeader = 0;
            ctx.push_back(c);
        }
        if (s == "}" && !ctx.empty()) {
            if (ctx.back() == kDo) pendingDo = true;
            ctx.pop_back();
        }
        if (s == ";" && singleDepth == (int)ctx.size()) singleDepth = -1;
        if (s == "return" || s == "break" || s == "continue" || s == "goto") out.add("control-flow-keyword", s);
        if (s == "return" && !inBlock()) out.add("return");
        if (s == "goto" && !inBlock()) out.add("goto");
        if (s == "break" && !inLoop(true)) out.add("break");
        if (s == "continue" && !inLoop(false)) out.add("continue");
        // A parameter used as a type: a cast, a declaration, sizeof or
        // @encode of it.
        if (isParam(i) && !prevHash && !pasteAdj) {
            static const std::set<std::string> notCastBefore = {"if", "while", "for", "switch", "sizeof",
                                                                "alignof", "_Alignof", "__typeof__", "typeof",
                                                                "__typeof", "defined", "synchronized", "catch",
                                                                "encode"};
            static const std::set<std::string> statementWords = {"return", "break", "continue", "goto", "if",
                                                                 "else", "do", "while", "for", "switch", "case",
                                                                 "default"};
            // '(' P ')' then an operand, where '(' is not a call's or a
            // statement's: a cast.
            bool openIsCast = i > 0 && t[i - 1] == "(" &&
                              !(i > 1 && (notCastBefore.count(t[i - 2]) ||
                                          (isIdent(i - 2) && t[i - 2] != "return" && t[i - 2] != "case") ||
                                          t[i - 2] == ")" || t[i - 2] == "]"));
            bool cast = openIsCast && i + 1 < n &&
                        ((t[i + 1] == ")" && i + 2 < n &&
                          ((isIdent(i + 2) && !statementWords.count(t[i + 2])) || t[i + 2] == "(" ||
                           t[i + 2] == "@" || t[i + 2] == "^" || t[i + 2] == "[" ||
                           toks[i + 2]->is(tok::numeric_constant))) ||
                         (t[i + 1] == "*" && i + 2 < n && (t[i + 2] == ")" || t[i + 2] == "*")));
            bool sizeofOf = i > 1 && t[i - 1] == "(" && (t[i - 2] == "sizeof" || t[i - 2] == "alignof" ||
                                                        t[i - 2] == "encode" || t[i - 2] == "_Alignof") &&
                            i + 1 < n && t[i + 1] == ")";
            // P name, or P *name, at the start of a declaration, followed by
            // what can follow a declarator.
            auto endsDeclarator = [&](size_t j) {
                return j >= n || t[j] == "=" || t[j] == ";" || t[j] == "," || t[j] == ")" || t[j] == "[";
            };
            bool declStart = i == 0 || t[i - 1] == ";" || t[i - 1] == "{" || t[i - 1] == "}" || t[i - 1] == "(" ||
                             t[i - 1] == "," || t[i - 1] == "const" || t[i - 1] == "static";
            bool decl = declStart && i + 1 < n &&
                        ((isIdent(i + 1) && !statementWords.count(t[i + 1]) && endsDeclarator(i + 2)) ||
                         (t[i + 1] == "*" && i + 2 < n && isIdent(i + 2) && endsDeclarator(i + 3)));
            if (decl && i + 1 < n && isParam(i + 1)) decl = false;
            if (cast || sizeofOf || decl)
                out.add("type-parameter", s + (cast ? " (cast)" : sizeofOf ? " (sizeof)" : " (declaration)"));
        }
        if (isIdent(i) && !params.count(s) && toks[i]->getIdentifierInfo() &&
            s != macroName && isRepoMacro(toks[i]->getIdentifierInfo()))
            out.add("uses-macro", s);
    }
    for (const auto &kv : evaluated) {
        if (kv.second > 1) out.add("multiple-evaluation", kv.first);
        if (kv.second == 0) out.add("unevaluated-parameter", kv.first);
    }
    return out;
}

static std::string factDetailJSON(const BodyFacts &f) {
    std::string out = "{";
    bool first = true;
    for (const auto &kv : f.detail) {
        if (!first) out += ",";
        first = false;
        out += jsonString(kv.first) + ":[";
        bool f2 = true;
        for (const std::string &d : kv.second) {
            if (!f2) out += ",";
            f2 = false;
            out += jsonString(d);
        }
        out += "]";
    }
    return out + "}";
}

static bool isLiteralOnlyMacro(const MacroInfo *mi) {
    if (!mi || !mi->isObjectLike() || mi->getNumTokens() == 0) return false;
    bool sawString = false;
    for (const Token &t : mi->tokens()) {
        if (tok::isStringLiteral(t.getKind())) sawString = true;
        else if (!t.is(tok::at)) return false;
    }
    return sawString;
}

class MacroRecorder : public PPCallbacks {
public:
    MacroRecorder(SourceManager &sm, Preprocessor &pp, const PathMapper &paths, PreprocessorFacts &facts)
        : sm_(sm), pp_(pp), paths_(paths), facts_(facts) {}

    void MacroExpands(const Token &nameTok, const MacroDefinition &md, SourceRange range,
                      const MacroArgs *args) override {
        SourceLocation loc = nameTok.getLocation();
        if (isLiteralOnlyMacro(md.getMacroInfo()) && nameTok.getIdentifierInfo())
            facts_.literalMacros[loc.getRawEncoding()] = nameTok.getIdentifierInfo()->getName().str();
        const MacroInfo *mi = md.getMacroInfo();
        std::string name = nameTok.getIdentifierInfo() ? nameTok.getIdentifierInfo()->getName().str() : "";
        if (loc.isFileID()) {
            MacroExpansionSite use;
            use.name = name;
            if (mi) {
                SourceLocation def = mi->getDefinitionLoc();
                if (def.isValid()) {
                    PresumedLoc p = sm_.getPresumedLoc(sm_.getExpansionLoc(def), false);
                    FileID fid = sm_.getFileID(sm_.getExpansionLoc(def));
                    std::string path = fileEntryPath(sm_.getFileEntryRefForID(fid));
                    use.defFile = path.empty() ? "" : paths_.store(path);
                    use.defLine = p.isValid() ? p.getLine() : 0;
                }
            }
            facts_.uses[loc.getRawEncoding()] = use;
        }
        recordExpansion(nameTok, name, mi, args, range);
    }

    void MacroDefined(const Token &nameTok, const MacroDirective *md) override {
        const MacroInfo *mi = md ? md->getMacroInfo() : nullptr;
        if (!mi || !nameTok.getIdentifierInfo()) return;
        SourceLocation def = mi->getDefinitionLoc();
        if (!def.isFileID()) return;
        FileID fid = sm_.getFileID(def);
        const std::string &stored = storedPath(fid);
        std::string name = nameTok.getIdentifierInfo()->getName().str();
        // The #define that follows a candidate include guard's #ifndef.
        auto g = guardCandidate_.find(fid);
        if (g != guardCandidate_.end() && g->second.state == 1 && g->second.name == name) g->second.state = 2;
        noteDirective(fid);
        if (stored.empty() || stored[0] == '/' || isBuildProduct(stored)) return;
        MacroDefRec r;
        r.name = name;
        r.kind = mi->isFunctionLike() ? "function" : "object";
        if (mi->isFunctionLike()) {
            std::string params;
            for (const IdentifierInfo *ii : mi->params()) {
                if (!params.empty()) params += ", ";
                std::string pn = ii->getName().str();
                if (pn == "__VA_ARGS__") pn = "...";
                else if (mi->isGNUVarargs() && ii == mi->params().back()) pn += "...";
                params += pn;
            }
            r.params = params;
        }
        r.variadic = mi->isVariadic() ? 1 : 0;
        std::string body;
        bool first = true;
        for (const Token &t : mi->tokens()) {
            if (!first && (t.hasLeadingSpace() || t.isAtStartOfLine())) body += " ";
            first = false;
            body += pp_.getSpelling(t);
        }
        std::string identity = r.kind + "(" + r.params + ")" + body;
        r.digest = hexSHA256(identity.data(), identity.size()).substr(0, 16);
        r.body = truncateUTF8(body, kBodyLimit, r.truncated);
        BodyFacts facts = analyzeBody(mi, name, pp_, [&](const IdentifierInfo *ii) {
            const MacroInfo *other = pp_.getMacroInfo(ii);
            if (!other || other == mi) return false;
            SourceLocation od = other->getDefinitionLoc();
            if (!od.isFileID()) return false;
            const std::string &op = storedPath(sm_.getFileID(od));
            return !op.empty() && op[0] != '/' && !isBuildProduct(op);
        });
        r.facts = joinSet(facts.facts, " ");
        r.detail = factDetailJSON(facts);
        // Only a definition directly before this one: after an #undef the
        // name was not defined.
        const MacroDirective *prev = md->getPrevious();
        if (prev && prev->getKind() == MacroDirective::MD_Define) {
            if (const MacroInfo *pmi = prev->getMacroInfo()) {
                SourceLocation pl = pmi->getDefinitionLoc();
                if (pl.isFileID()) {
                    PresumedLoc p = sm_.getPresumedLoc(pl, false);
                    const std::string &pf = storedPath(sm_.getFileID(pl));
                    r.previous = (pf.empty() ? std::string(p.isValid() ? p.getFilename() : "?") : pf) + ":" +
                                 std::to_string(p.isValid() ? p.getLine() : 0);
                }
            }
        }
        r.file = stored;
        r.line = sm_.getSpellingLineNumber(def);
        r.col = sm_.getSpellingColumnNumber(def);
        r.inScope = paths_.inMigrationScope(stored) ? 1 : 0;
        r.fid = fid;
        r.begin = sm_.getFileOffset(def);
        SourceLocation end = mi->getDefinitionEndLoc();
        r.end = end.isFileID() && sm_.getFileID(end) == fid ? sm_.getFileOffset(end) : r.begin;
        auto &list = facts_.defsByFile[fid];
        list.push_back({r.begin, facts_.defs.size()});
        std::sort(list.begin(), list.end());
        facts_.defs.push_back(std::move(r));
    }

    void MacroUndefined(const Token &nameTok, const MacroDefinition &md, const MacroDirective *undef) override {
        SourceLocation loc = nameTok.getLocation();
        if (!loc.isFileID() || !nameTok.getIdentifierInfo()) return;
        FileID fid = sm_.getFileID(loc);
        noteDirective(fid);
        const std::string &stored = storedPath(fid);
        if (stored.empty() || stored[0] == '/' || isBuildProduct(stored)) return;
        MacroUndefRec r;
        r.name = nameTok.getIdentifierInfo()->getName().str();
        if (const MacroInfo *mi = md.getMacroInfo()) defLocation(mi, r.defFile, r.defLine);
        r.file = stored;
        r.line = sm_.getSpellingLineNumber(loc);
        r.col = sm_.getSpellingColumnNumber(loc);
        r.inScope = paths_.inMigrationScope(stored) ? 1 : 0;
        facts_.undefs.push_back(std::move(r));
    }

    void If(SourceLocation loc, SourceRange cond, ConditionValueKind value) override {
        size_t i = condition(loc, "if", conditionText(loc), loc);
        if (i != kNone) {
            facts_.conds[i].values.insert(valueText(value));
            maybeGuardIf(i);
        }
    }

    void Elif(SourceLocation loc, SourceRange cond, ConditionValueKind value, SourceLocation ifLoc) override {
        size_t i = condition(loc, "elif", conditionText(loc), ifLoc);
        if (i != kNone) facts_.conds[i].values.insert(valueText(value));
    }

    void Ifdef(SourceLocation loc, const Token &nameTok, const MacroDefinition &md) override {
        size_t i = condition(loc, "ifdef", tokenName(nameTok), loc);
        if (i != kNone) facts_.conds[i].values.insert(md ? "true" : "false");
    }

    void Ifndef(SourceLocation loc, const Token &nameTok, const MacroDefinition &md) override {
        size_t i = condition(loc, "ifndef", tokenName(nameTok), loc);
        if (i != kNone) {
            facts_.conds[i].values.insert(md ? "false" : "true");
            maybeGuard(i, facts_.conds[i].condition);
        }
    }

    void Elifdef(SourceLocation loc, const Token &nameTok, const MacroDefinition &md) override {
        size_t i = condition(loc, "elifdef", tokenName(nameTok), loc);
        if (i != kNone) facts_.conds[i].values.insert(md ? "true" : "false");
    }

    void Elifdef(SourceLocation loc, SourceRange cond, SourceLocation ifLoc) override {
        size_t i = condition(loc, "elifdef", conditionText(loc), ifLoc);
        if (i != kNone) facts_.conds[i].values.insert("not-evaluated");
    }

    void Elifndef(SourceLocation loc, const Token &nameTok, const MacroDefinition &md) override {
        size_t i = condition(loc, "elifndef", tokenName(nameTok), loc);
        if (i != kNone) facts_.conds[i].values.insert(md ? "false" : "true");
    }

    void Elifndef(SourceLocation loc, SourceRange cond, SourceLocation ifLoc) override {
        size_t i = condition(loc, "elifndef", conditionText(loc), ifLoc);
        if (i != kNone) facts_.conds[i].values.insert("not-evaluated");
    }

    void Else(SourceLocation loc, SourceLocation ifLoc) override {
        // Its value (whether its branch is compiled) is known when the unit
        // ends: false where a skipped range starts at it.
        condition(loc, "else", "", ifLoc);
    }

    void Endif(SourceLocation loc, SourceLocation ifLoc) override {
        if (!loc.isFileID()) return;
        FileID fid = sm_.getFileID(loc);
        noteDirective(fid);
        if (!repoFile(fid)) return;
        auto it = facts_.condAt.find({storedPath(fid), sm_.getSpellingLineNumber(ifLoc)});
        if (it == facts_.condAt.end()) return;
        CondRec &c = facts_.conds[it->second];
        c.endifLine = sm_.getSpellingLineNumber(loc);
        // An include guard (see "Macros and conditional compilation" at the
        // top of this file): nothing but comments after the #endif.
        auto g = guardCandidate_.find(fid);
        if (g != guardCandidate_.end() && g->second.index == it->second && g->second.state == 2) {
            StringRef buf = sm_.getBufferData(fid);
            unsigned off = sm_.getFileOffset(loc);
            size_t eol = buf.find('\n', off);
            if (eol == StringRef::npos || onlyCommentsAndSpace(buf.substr(eol))) c.guard = 1;
        }
    }

    void SourceRangeSkipped(SourceRange range, SourceLocation) override {
        SourceLocation b = range.getBegin(), e = range.getEnd();
        if (!b.isFileID() || !e.isFileID()) return;
        FileID fid = sm_.getFileID(b);
        if (fid != sm_.getFileID(e)) return;
        facts_.skipped[fid].push_back({sm_.getFileOffset(b), sm_.getFileOffset(e)});
        const std::string &stored = storedPath(fid);
        if (stored.empty() || stored[0] == '/' || isBuildProduct(stored)) return;
        SkipRec r;
        r.file = stored;
        r.startLine = sm_.getSpellingLineNumber(b);
        r.endLine = sm_.getSpellingLineNumber(e);
        // A range that ends at the start of a line ends on the line before.
        if (r.endLine > r.startLine && sm_.getSpellingColumnNumber(e) == 1) r.endLine--;
        r.inScope = paths_.inMigrationScope(stored) ? 1 : 0;
        r.fid = fid;
        facts_.skips.push_back(std::move(r));
    }

private:
    static constexpr size_t kNone = (size_t)-1;
    static constexpr size_t kBodyLimit = 1000;
    static constexpr size_t kArgLimit = 120;
    static constexpr size_t kConditionLimit = 300;

    // The stored path of a file ("" when it is not a file).
    const std::string &storedPath(FileID fid) {
        auto it = paths_cache_.find(fid);
        if (it != paths_cache_.end()) return it->second;
        std::string p = fileEntryPath(sm_.getFileEntryRefForID(fid));
        return paths_cache_[fid] = p.empty() ? "" : paths_.store(p);
    }

    bool repoFile(FileID fid) {
        const std::string &p = storedPath(fid);
        return !p.empty() && p[0] != '/';
    }

    void defLocation(const MacroInfo *mi, std::string &file, unsigned &line) {
        SourceLocation def = mi->getDefinitionLoc();
        if (def.isInvalid()) {
            file = "<built-in>";
            line = 0;
            return;
        }
        SourceLocation d = sm_.getExpansionLoc(def);
        const std::string &p = storedPath(sm_.getFileID(d));
        PresumedLoc pl = sm_.getPresumedLoc(d, false);
        file = !p.empty() ? p : pl.isValid() ? std::string(pl.getFilename()) : "?";
        // The predefines buffer (command-line -D and the compiler's own) has
        // no meaningful line.
        line = !p.empty() && pl.isValid() ? pl.getLine() : 0;
    }

    static std::string tokenName(const Token &t) {
        return t.getIdentifierInfo() ? t.getIdentifierInfo()->getName().str() : "";
    }

    static const char *valueText(ConditionValueKind v) {
        switch (v) {
        case CVK_True: return "true";
        case CVK_False: return "false";
        case CVK_NotEvaluated: return "not-evaluated";
        }
        return "not-evaluated";
    }

    // The condition as written: from its first token to the end of the
    // directive (continuation lines joined), comments removed, whitespace
    // collapsed.
    std::string conditionText(SourceLocation directive) {
        // directive is the location of the directive's keyword (if, elif).
        SourceLocation b = directive;
        if (b.isInvalid() || !b.isFileID()) return "";
        bool invalid = false;
        StringRef buf = sm_.getBufferData(sm_.getFileID(b), &invalid);
        if (invalid) return "";
        size_t i = sm_.getFileOffset(b), n = buf.size();
        while (i < n && (isalnum((unsigned char)buf[i]) || buf[i] == '_')) i++;
        std::string out;
        bool space = false;
        while (i < n) {
            char c = buf[i];
            if (c == '\\' && i + 1 < n && (buf[i + 1] == '\n' || buf[i + 1] == '\r')) {
                i += buf[i + 1] == '\r' && i + 2 < n && buf[i + 2] == '\n' ? 3 : 2;
                space = !out.empty();
                continue;
            }
            if (c == '\n' || c == '\r') break;
            if (c == '/' && i + 1 < n && buf[i + 1] == '/') break;
            if (c == '/' && i + 1 < n && buf[i + 1] == '*') {
                size_t e = buf.find("*/", i + 2);
                i = e == StringRef::npos ? n : e + 2;
                space = !out.empty();
                continue;
            }
            if (c == ' ' || c == '\t') {
                space = !out.empty();
                i++;
                continue;
            }
            if (space) out += ' ';
            space = false;
            out += c;
            i++;
        }
        int truncated = 0;
        return truncateUTF8(out, kConditionLimit, truncated);
    }

    // Any directive in a file ends the window in which an include guard's
    // #define must follow its #ifndef.
    void noteDirective(FileID fid) {
        auto g = guardCandidate_.find(fid);
        if (g != guardCandidate_.end() && g->second.state == 1) g->second.state = 3;
    }

    size_t condition(SourceLocation loc, const char *directive, const std::string &text, SourceLocation chain) {
        if (!loc.isFileID()) return kNone;
        FileID fid = sm_.getFileID(loc);
        noteDirective(fid);
        if (!repoFile(fid)) return kNone;
        const std::string &stored = storedPath(fid);
        if (isBuildProduct(stored)) return kNone;
        unsigned line = sm_.getSpellingLineNumber(loc);
        auto key = std::make_pair(stored, line);
        auto it = facts_.condAt.find(key);
        if (it != facts_.condAt.end()) {
            // The same directive in another inclusion of the file.
            if (!firstCondition_.count(fid)) firstCondition_[fid] = it->second;
            return it->second;
        }
        CondRec r;
        r.file = stored;
        r.directive = directive;
        r.condition = text;
        r.line = line;
        r.chainLine = chain.isValid() && chain.isFileID() ? sm_.getSpellingLineNumber(chain) : line;
        r.inScope = paths_.inMigrationScope(stored) ? 1 : 0;
        r.fid = fid;
        r.offset = sm_.getFileOffset(loc);
        facts_.condAt[key] = facts_.conds.size();
        facts_.conds.push_back(std::move(r));
        if (!firstCondition_.count(fid)) firstCondition_[fid] = facts_.conds.size() - 1;
        return facts_.conds.size() - 1;
    }

    // An include guard: the first conditional directive of the file, with
    // nothing but comments before it, is #ifndef X or #if !defined(X); the
    // next directive is #define X; nothing but comments follows its #endif.
    void maybeGuard(size_t i, const std::string &name) {
        const CondRec &c = facts_.conds[i];
        auto first = firstCondition_.find(c.fid);
        if (first == firstCondition_.end() || first->second != i || guardCandidate_.count(c.fid)) return;
        // Only the first inclusion is considered (c.fid is its file ID).
        StringRef buf = sm_.getBufferData(c.fid);
        size_t lineStart = buf.rfind('\n', c.offset);
        lineStart = lineStart == StringRef::npos ? 0 : lineStart;
        if (!onlyCommentsAndSpace(buf.substr(0, lineStart))) return;
        guardCandidate_[c.fid] = {i, 1, name};
    }

    void maybeGuardIf(size_t i) {
        std::string compact;
        for (char ch : facts_.conds[i].condition)
            if (ch != ' ' && ch != '(' && ch != ')') compact += ch;
        if (compact.compare(0, 8, "!defined") != 0 || compact.size() <= 8) return;
        std::string name = compact.substr(8);
        for (char ch : name)
            if (!(isalnum((unsigned char)ch) || ch == '_')) return;
        maybeGuard(i, name);
    }

private:
    void recordExpansion(const Token &nameTok, const std::string &name, const MacroInfo *mi, const MacroArgs *args,
                         SourceRange range) {
        if (!mi || mi->isBuiltinMacro() || name.empty()) return;
        SourceLocation loc = nameTok.getLocation();
        std::string defFile;
        unsigned defLine = 0;
        defLocation(mi, defFile, defLine);
        bool repoMacro = !defFile.empty() && defFile[0] != '/' && defFile[0] != '<' && defFile != "?" &&
                         !isBuildProduct(defFile);
        // Where the expansion is written, and how it is nested.
        SourceLocation outer = sm_.getExpansionLoc(loc);
        if (outer.isInvalid()) return;
        SourceLocation site = loc;
        std::string nesting = "none", parent;
        if (loc.isFileID()) {
            // A name written in a file inside the argument list of an
            // expansion that is still open (its arguments are expanded after
            // its own callback) is nested in that argument.
            FileID f = sm_.getFileID(loc);
            unsigned off = sm_.getFileOffset(loc);
            if (open_.valid && open_.fid == f && off > open_.begin && off <= open_.end) {
                nesting = "argument";
                outer = open_.loc;
            } else if (range.isValid() && range.getEnd().isFileID() && sm_.getFileID(range.getEnd()) == f) {
                open_ = {true, f, off, sm_.getFileOffset(range.getEnd()), loc};
            }
        } else {
            long parentDef = definitionContaining(sm_.getSpellingLoc(loc));
            SourceLocation l = loc;
            while (l.isMacroID() && sm_.isMacroArgExpansion(l)) l = sm_.getImmediateSpellingLoc(l);
            if (parentDef >= 0) {
                nesting = "body";
                parent = facts_.defs[parentDef].name;
                facts_.bodyExpands.insert({(size_t)parentDef, name});
                site = outer;
            } else if (l.isFileID() && !sm_.isWrittenInScratchSpace(l)) {
                nesting = "argument";
                site = l;
            } else {
                nesting = "body";
                site = outer;
            }
        }
        FileID fid = sm_.getFileID(site);
        if (!repoFile(fid)) return;
        const std::string &stored = storedPath(fid);
        if (isBuildProduct(stored)) return;
        int inScope = paths_.inMigrationScope(stored) ? 1 : 0;
        if (!repoMacro) {
            // Counted per file, where the name is written in a file.
            if (nesting == "body") return;
            auto &c = facts_.otherCounts[std::make_tuple(stored, name, defFile, defLine)];
            c.first++;
            c.second = inScope;
            return;
        }
        MacroExpansionRec r;
        r.name = name;
        r.defFile = defFile;
        r.defLine = defLine;
        r.nesting = nesting;
        r.parentName = parent;
        auto u = facts_.uses.find(outer.getRawEncoding());
        r.outerName = u != facts_.uses.end() ? u->second.name : name;
        r.outerLine = sm_.getSpellingLineNumber(outer);
        r.outerCol = sm_.getSpellingColumnNumber(outer);
        r.inCondition = pp_.isParsingIfOrElifDirective() ? 1 : 0;
        if (args && mi->isFunctionLike()) {
            std::string json = "[";
            for (unsigned i = 0; i < mi->getNumParams(); i++) {
                const Token *t = args->getUnexpArgument(i);
                std::string text;
                bool first = true;
                for (; t && t->isNot(tok::eof); ++t) {
                    if (!first && (t->hasLeadingSpace() || t->isAtStartOfLine())) text += " ";
                    first = false;
                    text += pp_.getSpelling(*t);
                }
                if (i) json += ",";
                json += jsonString(truncateUTF8(text, kArgLimit, r.argsTruncated));
            }
            r.args = json + "]";
        }
        r.file = stored;
        r.line = sm_.getSpellingLineNumber(site);
        r.col = sm_.getSpellingColumnNumber(site);
        r.inScope = inScope;
        r.siteFid = fid;
        r.siteOffset = sm_.getFileOffset(site);
        facts_.expansions.push_back(std::move(r));
    }

    long definitionContaining(SourceLocation spelling) {
        return ::definitionContaining(facts_, sm_, spelling);
    }

    SourceManager &sm_;
    Preprocessor &pp_;
    const PathMapper &paths_;
    PreprocessorFacts &facts_;
    std::map<FileID, std::string> paths_cache_;
    std::map<FileID, size_t> firstCondition_;
    // The candidate include guard of a file: the index of its #ifndef, its
    // state (1 waiting for its #define, 2 seen, 3 failed) and the macro.
    struct GuardCandidate {
        size_t index;
        int state;
        std::string name;
    };
    std::map<FileID, GuardCandidate> guardCandidate_;
    // The last expansion written in a file whose arguments may still be
    // expanding: its file, the offsets of its name and closing parenthesis,
    // and its name's location.
    struct OpenExpansion {
        bool valid = false;
        FileID fid;
        unsigned begin = 0, end = 0;
        SourceLocation loc;
    } open_;
};

// Watches the expanded token stream for `@ selector ( X` and records where X
// is, since the AST does not keep the selector's location.
class SelectorTokenWatcher {
public:
    explicit SelectorTokenWatcher(PreprocessorFacts &facts) : facts_(facts) {}

    void operator()(const Token &t) {
        if (t.isAnnotation()) return;
        switch (state_) {
        case 0: break;
        case 1:
            if (t.is(tok::identifier) && t.getIdentifierInfo() && t.getIdentifierInfo()->getName() == "selector") {
                state_ = 2;
                return;
            }
            break;
        case 2:
            if (t.is(tok::l_paren)) {
                state_ = 3;
                return;
            }
            break;
        case 3: facts_.selectorTokens[at_.getRawEncoding()] = t.getLocation(); break;
        }
        state_ = 0;
        if (t.is(tok::at)) {
            state_ = 1;
            at_ = t.getLocation();
        }
    }

private:
    PreprocessorFacts &facts_;
    int state_ = 0;
    SourceLocation at_;
};

// Index of the reflective table's entries by name.
struct ReflectiveIndex {
    std::multimap<std::string, const ReflectiveName *> functions, messages;
    std::vector<const ReflectiveName *> functionPrefixes, messagePrefixes;

    ReflectiveIndex() {
        for (const ReflectiveName &e : kReflectiveNames) {
            if (e.prefix) (e.message ? messagePrefixes : functionPrefixes).push_back(&e);
            else (e.message ? messages : functions).emplace(e.name, &e);
        }
    }

    std::vector<const ReflectiveName *> match(const std::string &name, bool message) const {
        std::vector<const ReflectiveName *> out;
        const auto &exact = message ? messages : functions;
        auto range = exact.equal_range(name);
        for (auto it = range.first; it != range.second; ++it) out.push_back(it->second);
        if (out.empty()) {
            for (const ReflectiveName *e : message ? messagePrefixes : functionPrefixes)
                if (name.compare(0, strlen(e->name), e->name) == 0) out.push_back(e);
        }
        return out;
    }
};

static const ReflectiveIndex &reflectiveIndex() {
    static ReflectiveIndex index;
    return index;
}

// How an argument of a reflective call names its selector, class or key.
struct ArgumentDescription {
    std::string kind, text, constant, selector, cls;
};

static const Expr *unwrapOpaque(const Expr *e) {
    while (const auto *ove = dyn_cast_or_null<OpaqueValueExpr>(e)) {
        if (!ove->getSourceExpr()) break;
        e = ove->getSourceExpr();
    }
    return e;
}

// The expression with parentheses, casts, implicit nodes and opaque values
// taken away.
static const Expr *strip(const Expr *e) {
    while (e) {
        const Expr *before = e;
        e = unwrapOpaque(e->IgnoreParenCasts()->IgnoreImplicit());
        if (e == before) break;
    }
    return e;
}

// The name of the C function a call calls directly (through casts), or "".
static std::string calledFunction(const CallExpr *call) {
    const auto *dre = dyn_cast<DeclRefExpr>(call->getCallee()->IgnoreParenCasts());
    if (!dre) return "";
    const auto *fd = dyn_cast<FunctionDecl>(dre->getDecl());
    if (!fd || !fd->getIdentifier() || isa<CXXMethodDecl>(fd)) return "";
    return fd->getName().str();
}

class SendVisitor : public RecursiveASTVisitor<SendVisitor> {
    using Base = RecursiveASTVisitor<SendVisitor>;

public:
    SendVisitor(ASTContext &ctx, const PathMapper &paths, const PreprocessorFacts &facts, Results &results)
        : ctx_(ctx), sm_(ctx.getSourceManager()), paths_(paths), facts_(facts), results_(results),
          arc_(ctx.getLangOpts().ObjCAutoRefCount), objcWeak_(ctx.getLangOpts().ObjCWeak) {
        frames_.push_back({nullptr, 0});
    }

    // Top-level declarations outside the repository (SDK headers) are
    // skipped.
    bool shouldTraverseTopLevel(Decl *d) {
        SourceLocation loc = sm_.getExpansionLoc(d->getLocation());
        if (loc.isInvalid()) return false;
        return fileInRepo(sm_.getFileID(loc));
    }

    // Unevaluated operands (see the top of this file).
    bool TraverseUnaryExprOrTypeTraitExpr(UnaryExprOrTypeTraitExpr *e) {
        Unevaluated u(*this, !e->getTypeOfArgument()->isVariablyModifiedType());
        return Base::TraverseUnaryExprOrTypeTraitExpr(e);
    }

    bool TraverseObjCEncodeExpr(ObjCEncodeExpr *e) {
        Unevaluated u(*this, true);
        return Base::TraverseObjCEncodeExpr(e);
    }

    bool TraverseCXXNoexceptExpr(CXXNoexceptExpr *e) {
        Unevaluated u(*this, true);
        return Base::TraverseCXXNoexceptExpr(e);
    }

    bool TraverseTypeOfExprTypeLoc(TypeOfExprTypeLoc tl, bool traverseQualifier) {
        Unevaluated u(*this, !tl.getUnderlyingExpr()->getType()->isVariablyModifiedType());
        return Base::TraverseTypeOfExprTypeLoc(tl, traverseQualifier);
    }

    bool TraverseTypeOfExprType(TypeOfExprType *t, bool traverseQualifier) {
        Unevaluated u(*this, !t->getUnderlyingExpr()->getType()->isVariablyModifiedType());
        return Base::TraverseTypeOfExprType(t, traverseQualifier);
    }

    bool TraverseDecltypeTypeLoc(DecltypeTypeLoc tl, bool traverseQualifier) {
        Unevaluated u(*this, true);
        return Base::TraverseDecltypeTypeLoc(tl, traverseQualifier);
    }

    bool TraverseDecltypeType(DecltypeType *t, bool traverseQualifier) {
        Unevaluated u(*this, true);
        return Base::TraverseDecltypeType(t, traverseQualifier);
    }

    // Both forms of an initializer list (see "Both forms" at the top of this
    // file). The syntactic form keeps a designator's value as written, so a
    // property access of structure or vector type there is the unconverted
    // property reference; its message send exists only in the semantic form.
    // A node the two forms share is reached twice; every recorder keys on the
    // node.
    bool TraverseInitListExpr(InitListExpr *e) {
        InitListExpr *syntactic = e->isSemanticForm() ? e->getSyntacticForm() : e;
        InitListExpr *semantic = e->isSemanticForm() ? e : e->getSemanticForm();
        if (!syntactic || !semantic || syntactic == semantic) return Base::TraverseInitListExpr(e);
        return TraverseSynOrSemInitListExpr(syntactic) && TraverseSynOrSemInitListExpr(semantic);
    }

    // The size of a variable-length array: the type location holds the
    // expression as written, the type the converted one (a property access
    // becomes its getter's send only there). Both are traversed.
    bool TraverseVariableArrayTypeLoc(VariableArrayTypeLoc tl, bool traverseQualifier) {
        if (!Base::TraverseVariableArrayTypeLoc(tl, traverseQualifier)) return false;
        return TraverseStmt(tl.getTypePtr()->getSizeExpr());
    }

    // __builtin_choose_expr: only the chosen operand is evaluated; the other
    // is an unevaluated operand (see the top of this file).
    bool TraverseChooseExpr(ChooseExpr *e) {
        if (!WalkUpFromChooseExpr(e)) return false;
        if (!TraverseStmt(e->getCond())) return false;
        const Expr *chosen = e->isConditionDependent() ? nullptr : e->getChosenSubExpr();
        for (Expr *sub : {e->getLHS(), e->getRHS()}) {
            Unevaluated u(*this, chosen && sub != chosen);
            if (!TraverseStmt(sub)) return false;
        }
        return true;
    }

    // _Generic: the controlling expression and every association but the
    // selected one are unevaluated operands.
    bool TraverseGenericSelectionExpr(GenericSelectionExpr *e) {
        if (!WalkUpFromGenericSelectionExpr(e)) return false;
        {
            Unevaluated u(*this, true);
            if (e->isExprPredicate()) {
                if (!TraverseStmt(e->getControllingExpr())) return false;
            } else if (!TraverseTypeLoc(e->getControllingType()->getTypeLoc())) {
                return false;
            }
        }
        const Expr *result = e->isResultDependent() ? nullptr : e->getResultExpr();
        for (const GenericSelectionExpr::Association assoc : e->associations()) {
            if (TypeSourceInfo *tsi = assoc.getTypeSourceInfo())
                if (!TraverseTypeLoc(tsi->getTypeLoc())) return false;
            Unevaluated u(*this, result && assoc.getAssociationExpr() != result);
            if (!TraverseStmt(assoc.getAssociationExpr())) return false;
        }
        return true;
    }

    // --- Constant conditions (see the top of this file). A parent is
    // visited before its children are traversed, so the branch a constant
    // condition skips is known when its subtree begins.

    bool VisitIfStmt(IfStmt *s) {
        if (s->isConsteval()) return true;
        noteBranchCondition(s->getCond());
        // CodeGen's EmitIfStmt: when the condition folds
        // (ConstantFoldsToSimpleInteger) it emits only the arm taken, unless
        // the other holds a label (ContainsLabel; if constexpr allows one).
        std::optional<bool> value = foldedCondition(s->getCond(), s->isConstexpr());
        if (!value) return true;
        const Stmt *skipped = *value ? s->getElse() : s->getThen();
        if (s->isConstexpr() || !containsLabel(skipped)) {
            markDead(skipped, s->getCond());
            // Not a path for "Unreachable code": the CFG's successors of an
            // if are the then arm (0) and the else arm or what follows (1).
            skippedSuccessor_[s] = *value ? 1 : 0;
        }
        return true;
    }

    bool VisitWhileStmt(WhileStmt *s) {
        noteBranchCondition(s->getCond());
        return true;
    }

    bool VisitDoStmt(DoStmt *s) {
        noteBranchCondition(s->getCond());
        return true;
    }

    bool VisitForStmt(ForStmt *s) {
        noteBranchCondition(s->getCond());
        return true;
    }

    bool VisitBinaryConditionalOperator(BinaryConditionalOperator *e) {
        // GNU a ?: b: never marked.
        noteBranchCondition(e->getCond());
        return true;
    }

    // c ? x : y with a condition that folds: the operand not taken is marked
    // only where every emitter that can reach it is known to skip it (see
    // the top of this file): a scalar prvalue (or, in C++, a glvalue) that is
    // not part of a branch condition, and whose skipped operand holds no
    // label.
    bool VisitConditionalOperator(ConditionalOperator *e) {
        noteBranchCondition(e->getCond());
        if (inBranchCondition(e)) return true;
        if (!e->isGLValue() && !scalarEvaluation(e->getType())) return true;
        std::optional<bool> value = foldedCondition(e->getCond(), false);
        if (!value) return true;
        const Expr *skipped = *value ? e->getFalseExpr() : e->getTrueExpr();
        if (!containsLabel(skipped)) {
            markDead(skipped, e->getCond());
            // The CFG's successors of a conditional operator are the true
            // operand (0) and the false operand (1).
            skippedSuccessor_[e] = *value ? 1 : 0;
        }
        return true;
    }

    // 0 && x, 1 || x: x is not emitted, under the same conditions as the
    // conditional operator. (Called from VisitBinaryOperator below.)
    void noteShortCircuit(BinaryOperator *bo) {
        if (bo->getOpcode() != BO_LAnd && bo->getOpcode() != BO_LOr) return;
        // The scalar emitter branches on the left operand.
        noteBranchCondition(bo->getLHS());
        if (inBranchCondition(bo)) return;
        std::optional<bool> value = foldedCondition(bo->getLHS(), false);
        if (value && *value == (bo->getOpcode() == BO_LOr) && !containsLabel(bo->getRHS()))
            markDead(bo->getRHS(), bo->getLHS());
    }

    bool dataTraverseStmtPre(Stmt *s) {
        auto it = deadRoots_.find(s);
        if (it != deadRoots_.end()) dead_.push_back(it->second);
        return true;
    }

    bool dataTraverseStmtPost(Stmt *s) {
        if (deadRoots_.count(s)) dead_.pop_back();
        return true;
    }

    bool TraverseDecl(Decl *d) {
        if (!d) return true;
        bool frame = isEnclosingDecl(d);
        if (frame) recordEnclosingRange(d);
        if (frame) frames_.push_back({d, 0});
        bool ok = Base::TraverseDecl(d);
        if (frame) frames_.pop_back();
        if (frame) {
            if (const auto *fd = dyn_cast<FunctionDecl>(d)) {
                if (fd->doesThisDeclarationHaveABody() && !fd->isLateTemplateParsed())
                    markUnreachable(d, fd->getBody());
            } else if (const auto *md = dyn_cast<ObjCMethodDecl>(d)) {
                if (md->hasBody()) markUnreachable(d, md->getBody());
            }
        }
        return ok;
    }

    bool TraverseBlockExpr(BlockExpr *e) {
        noteMacroFact(e->getCaretLocation(), "block", "", e);
        frames_.back().blockDepth++;
        bool once = onceBlocks_.count(e) > 0;
        if (once) onceDepth_++;
        bool ok = Base::TraverseBlockExpr(e);
        if (once) onceDepth_--;
        frames_.back().blockDepth--;
        markUnreachable(e->getBlockDecl(), e->getBody());
        return ok;
    }

    // --- How an ivar or static is used (see "State" at the top of this
    // file). A parent is visited before its children, so the access its
    // operator gives an operand is recorded before the reference is.

    bool VisitBinaryOperator(BinaryOperator *bo) {
        noteShortCircuit(bo);
        if (bo->isAssignmentOp()) markAccess(bo->getLHS(), bo->isCompoundAssignmentOp() ? "rmw" : "write");
        // _x = [y retain], [y copy], [Foo new], [[Foo alloc] init...]: the
        // ivar is given an object it owns (the retain hint).
        if (bo->getOpcode() == BO_Assign && returnsOwned(bo->getRHS())) markHint(bo->getLHS(), "assigned-owned");
        return true;
    }

    // An array that decays to a pointer (see "State" at the top of this
    // file): passed, returned, assigned or used in pointer arithmetic, it can
    // be written through the pointer unless the pointer is to const. The
    // outermost implicit cast of a chain is visited first, so its type (the
    // pointer type at the use) decides.
    bool VisitImplicitCastExpr(ImplicitCastExpr *ice) {
        const ImplicitCastExpr *cur = ice;
        while (cur->getCastKind() != CK_ArrayToPointerDecay) {
            cur = dyn_cast<ImplicitCastExpr>(cur->getSubExpr()->IgnoreParens());
            if (!cur) return true;
        }
        bool partial = false;
        const Expr *root = lvalueRoot(cur->getSubExpr(), partial);
        if (!root) return true;
        QualType use = ice->getType();
        const char *access = use->isPointerType() && !use->getPointeeType().isConstQualified() ? "byref" : "read";
        marks_.emplace(root, std::make_pair(access, partial ? 1 : 0));
        return true;
    }

    // __builtin_object_size does not evaluate its argument; the SDK's
    // fortified memcpy, memmove, memset and the like pass their destination to
    // it a second time, so references in it are not recorded. (These
    // overrides take no DataRecursionQueue, so that the children are
    // traversed before they return.)
    bool TraverseCallExpr(CallExpr *call) {
        bool objectSize = false;
        if (const FunctionDecl *fd = call->getDirectCallee()) {
            unsigned id = fd->getBuiltinID();
            objectSize = id == Builtin::BI__builtin_object_size || id == Builtin::BI__builtin_dynamic_object_size;
        }
        if (objectSize) objectSize_++;
        bool ok = Base::TraverseCallExpr(call);
        if (objectSize) objectSize_--;
        return ok;
    }

    // The compound statements being traversed, for whether a declaration a
    // macro makes leaks into its caller's scope.
    bool TraverseCompoundStmt(CompoundStmt *s) {
        compounds_.push_back(s->getLBracLoc());
        bool ok = Base::TraverseCompoundStmt(s);
        compounds_.pop_back();
        return ok;
    }

    bool TraverseLambdaExpr(LambdaExpr *e) {
        lambdas_.push_back(e);
        bool ok = Base::TraverseLambdaExpr(e);
        lambdas_.pop_back();
        markUnreachable(e->getCallOperator(), e->getBody());
        return ok;
    }

    // The lock of the @synchronized body being traversed, for the references
    // in it (sync_lock).
    bool TraverseObjCAtSynchronizedStmt(ObjCAtSynchronizedStmt *s) {
        if (!WalkUpFromObjCAtSynchronizedStmt(s)) return false;
        if (!TraverseStmt(s->getSynchExpr())) return false;
        syncLocks_.push_back(lockDescription(s->getSynchExpr()));
        bool ok = TraverseStmt(s->getSynchBody());
        syncLocks_.pop_back();
        return ok;
    }

    bool VisitUnaryOperator(UnaryOperator *uo) {
        if (uo->isIncrementDecrementOp()) markAccess(uo->getSubExpr(), "rmw");
        else if (uo->getOpcode() == UO_AddrOf) markAccess(uo->getSubExpr(), "address");
        return true;
    }

    bool VisitMemberExpr(MemberExpr *me) {
        if (!me->isArrow()) markAccess(me, "read");
        return true;
    }

    bool VisitArraySubscriptExpr(ArraySubscriptExpr *ase) {
        markAccess(ase, "read");
        return true;
    }

    bool VisitObjCAtSynchronizedStmt(ObjCAtSynchronizedStmt *s) {
        markAccess(lockOperand(s->getSynchExpr()), "synchronized");
        return true;
    }

    bool VisitObjCIvarRefExpr(ObjCIvarRefExpr *e) {
        if (e->getDecl()) noteMacroFact(e->getLocation(), "ivar", e->getDecl()->getName().str(), e);
        if (objectSize_ > 0) return true;
        if (!seenIvarRefs_.insert(e).second) return true;
        const ObjCIvarDecl *iv = e->getDecl();
        if (!iv || !declaredInRepo(iv)) return true;
        IvarRefRow row;
        if (!locate(e->getLocation(), row)) return true;
        row.ivarUSR = usr(iv);
        if (const ObjCInterfaceDecl *iface = iv->getContainingInterface()) row.ivarClass = iface->getName().str();
        row.ivarName = iv->getName().str();
        row.kind = "direct";
        accessOf(e, row.access, row.partial);
        row.baseKind = e->isFreeIvar() ? "implicit-self" : baseKind(e->getBase());
        enclose(row.enclosingUSR, row.enclosingName, row.inBlock);
        row.enclosingClass = enclosingClass();
        row.inOnceBlock = onceDepth_ > 0 ? 1 : 0;
        row.inLambda = lambdaCapture(e, e->getBase());
        auto hint = hints_.find(e);
        if (hint != hints_.end()) row.retainHint = hint->second;
        if (!syncLocks_.empty()) row.syncLock = syncLocks_.back();
        noteConstantFalse(row);
        keepReference(row.ivarUSR, std::move(row), results_.ivarRefs, ivarRefIndex_);
        return true;
    }

    bool VisitDeclRefExpr(DeclRefExpr *e) {
        if (const auto *ipd = dyn_cast<ImplicitParamDecl>(e->getDecl())) {
            if (ipd->getParameterKind() == ImplicitParamKind::ObjCSelf) {
                bool written = e->getLocation().isValid() &&
                               Lexer::getSpelling(sm_.getSpellingLoc(e->getLocation()), nameBuf_, sm_,
                                                  ctx_.getLangOpts()) == "self";
                noteMacroFact(e->getLocation(), "self", written ? "written" : "implicit (an ivar access)", e);
            } else if (ipd->getParameterKind() == ImplicitParamKind::ObjCCmd) {
                noteMacroFact(e->getLocation(), "cmd", "", e);
            }
        }
        if (const auto *fd = dyn_cast<FunctionDecl>(e->getDecl()); fd && seenFunctionRefs_.insert(e).second)
            noteFunctionRef(fd);
        const auto *vd = dyn_cast<VarDecl>(e->getDecl());
        if (!vd || !vd->hasGlobalStorage() || isa<ParmVarDecl>(vd)) return true;
        if (objectSize_ > 0) return true;
        if (!seenDeclRefs_.insert(e).second || !declaredInRepo(vd)) return true;
        StaticRefRow row;
        if (!locate(e->getLocation(), row)) return true;
        row.varUSR = usr(vd);
        row.name = vd->getName().str();
        row.varKind = staticKind(vd, false);
        accessOf(e, row.access, row.partial);
        enclose(row.enclosingUSR, row.enclosingName, row.inBlock);
        row.enclosingClass = enclosingClass();
        row.inOnceBlock = onceDepth_ > 0 ? 1 : 0;
        row.inLambda = lambdaCapture(e, nullptr);
        if (!syncLocks_.empty()) row.syncLock = syncLocks_.back();
        noteConstantFalse(row);
        keepReference(row.varUSR, std::move(row), results_.staticRefs, staticRefIndex_);
        return true;
    }

    bool VisitFunctionDecl(FunctionDecl *fd) {
        noteMacroDeclaration(fd);
        return true;
    }

    bool VisitTypedefNameDecl(TypedefNameDecl *td) {
        noteMacroDeclaration(td);
        return true;
    }

    bool VisitTagDecl(TagDecl *td) {
        noteMacroDeclaration(td);
        return true;
    }

    bool VisitObjCMethodDecl(ObjCMethodDecl *md) {
        if (md->isImplicit()) return true;
        // A macro that writes the '-' or '+' makes the method; one that only
        // spells its selector names it.
        std::string what = displayName(md) + (md->hasBody() ? " definition" : " declaration");
        long def = macroSpelling(facts_, sm_, md->getBeginLoc());
        if (def >= 0) noteMacroFact(def, "method", what, md);
        else noteMacroFact(md->getSelectorStartLoc(), "names-method", what, md);
        return true;
    }

    bool VisitVarDecl(VarDecl *vd) {
        noteMacroDeclaration(vd);
        // int &r = _x: a non-const lvalue reference to the ivar or variable
        // can write it later.
        QualType vt = vd->getType();
        if (!isa<ParmVarDecl>(vd) && !vd->isImplicit() && vt->isLValueReferenceType() &&
            !vt->getPointeeType().isConstQualified() && vd->getInit())
            markAccess(vd->getInit(), "address");
        if (isa<ParmVarDecl>(vd) || vd->isImplicit() || !vd->hasGlobalStorage() || vd->isTemplated()) return true;
        if (!seenVars_.insert(vd).second) return true;
        StaticRow row;
        if (!locate(vd->getLocation(), row) || isBuildProduct(row.file)) return true;
        row.usr = usr(vd);
        row.name = vd->getName().str();
        row.kind = staticKind(vd, true);
        if (vd->isStaticLocal()) {
            if (const Frame *f = innermostDecl()) {
                row.enclosingUSR = usr(f->decl);
                row.enclosingName = displayName(f->decl);
            }
        }
        row.facts = typeFacts(vd->getType(), nullptr);
        QualType element = ctx_.getBaseElementType(vd->getType());
        row.isConst = element.isConstQualified() ? 1 : 0;
        row.pointeeConst = pointeeConst(element);
        row.initKind = initKind(vd);
        row.threadLocal = vd->getTLSKind() != VarDecl::TLS_None ? 1 : 0;
        // A header's statics and declarations are recorded once per target,
        // content and view, as its methods are.
        if (!isSourceFile(row.file)) row.claimFile = row.file;
        results_.statics.push_back(std::move(row));
        return true;
    }

    bool TraversePseudoObjectExpr(PseudoObjectExpr *e) {
        implicitKinds_.push_back(classifyPseudoObject(e->getSyntacticForm()));
        bool ok = Base::TraversePseudoObjectExpr(e);
        implicitKinds_.pop_back();
        return ok;
    }

    bool VisitObjCMessageExpr(ObjCMessageExpr *m) {
        // The base of a property or subscript reference appears both in the
        // syntactic form and as the source of an OpaqueValueExpr in the
        // semantic form, so the same node can be visited twice.
        if (unevaluated_ > 0) return true;
        if (!seen_.insert(m).second) return true;
        noteMacroSend(m);
        const ObjCMethodDecl *callee = m->getMethodDecl();
        for (unsigned i = 0; i < m->getNumArgs(); i++)
            markByReference(m->getArg(i), callee && i < callee->param_size() ? callee->getParamDecl(i) : nullptr);
        // [_x retain], [_x release], [_x autorelease], [_x copy]: the retain
        // hint of an ivar.
        if (m->getReceiverKind() == ObjCMessageExpr::Instance) {
            const char *hint = nullptr;
            switch (m->getMethodFamily()) {
            case OMF_retain: hint = "retain"; break;
            case OMF_release: hint = "release"; break;
            case OMF_autorelease: hint = "autorelease"; break;
            case OMF_copy:
            case OMF_mutableCopy: hint = "copy"; break;
            default: break;
            }
            if (hint) markHint(m->getInstanceReceiver(), hint);
        }

        // The selector's first token decides where the send is recorded and
        // its macro role (see the comment at the top of this file).
        SourceLocation loc = m->getSelectorStartLoc();
        if (loc.isInvalid()) loc = m->getBeginLoc();
        SendRow row;
        if (!locate(loc, row)) return true;
        row.selector = m->getSelector().getAsString();
        switch (m->getReceiverKind()) {
        case ObjCMessageExpr::Instance: row.receiverKind = "instance"; break;
        case ObjCMessageExpr::Class: row.receiverKind = "class"; break;
        case ObjCMessageExpr::SuperInstance: row.receiverKind = "super"; break;
        case ObjCMessageExpr::SuperClass: row.receiverKind = "super_class"; break;
        }
        QualType rt = m->getReceiverType();
        if (!rt.isNull()) row.receiverType = rt.getUnqualifiedType().getAsString(ctx_.getPrintingPolicy());
        if (const ObjCMethodDecl *md = m->getMethodDecl()) row.targetUSR = usr(md);
        enclose(row.enclosingUSR, row.enclosingName, row.inBlock);
        if (m->isImplicit() && !implicitKinds_.empty()) row.implicitAccessor = implicitKinds_.back();
        noteConstantFalse(row);
        for (const ReflectiveName *e : reflectiveIndex().match(row.selector, true)) {
            if ((unsigned)e->argument >= m->getNumArgs()) continue;
            ReflectiveRow r = reflectiveRow(row, *e, m->getArg(e->argument), nullptr);
            r.name = row.selector;
            r.receiverType = row.receiverType;
            results_.reflective.push_back(std::move(r));
        }
        sendRowOf_[m] = results_.sends.size();
        results_.sends.push_back(std::move(row));
        return true;
    }

    bool VisitCallExpr(CallExpr *call) {
        if (unevaluated_ > 0) return true;
        if (!seenCalls_.insert(call).second) return true;
        std::string name = calledFunction(call);
        markCallArguments(call, name);
        if (name.empty()) return true;
        std::vector<const ReflectiveName *> entries = reflectiveIndex().match(name, false);
        if (entries.empty()) return true;
        const auto *dre = cast<DeclRefExpr>(call->getCallee()->IgnoreParenCasts());
        Located where;
        if (!locate(dre->getLocation(), where)) return true;
        for (const ReflectiveName *e : entries) {
            if ((unsigned)e->argument >= call->getNumArgs()) continue;
            const Expr *classArg = e->classArgument >= 0 && (unsigned)e->classArgument < call->getNumArgs()
                                       ? call->getArg(e->classArgument)
                                       : nullptr;
            ReflectiveRow r = reflectiveRow(where, *e, call->getArg(e->argument), classArg);
            r.name = name;
            results_.reflective.push_back(std::move(r));
        }
        return true;
    }

    bool VisitObjCSelectorExpr(ObjCSelectorExpr *e) {
        if (unevaluated_ > 0) return true;
        if (!seenSelectors_.insert(e).second) return true;
        noteMacroFact(e->getAtLoc(), "selector", e->getSelector().getAsString(), e);
        SourceLocation loc = e->getAtLoc();
        auto it = facts_.selectorTokens.find(loc.getRawEncoding());
        if (it != facts_.selectorTokens.end()) loc = it->second;
        SelectorRefRow row;
        if (!locate(loc, row)) return true;
        row.selector = e->getSelector().getAsString();
        row.kind = "selector-expr";
        enclose(row.enclosingUSR, row.enclosingName, row.inBlock);
        results_.selectorRefs.push_back(std::move(row));
        return true;
    }

    bool VisitObjCInterfaceDecl(ObjCInterfaceDecl *d) {
        if (d->isThisDeclarationADefinition()) recordContainer(d);
        noteMacroClass(d, "@interface");
        return true;
    }

    bool VisitObjCProtocolDecl(ObjCProtocolDecl *d) {
        if (d->isThisDeclarationADefinition()) recordContainer(d);
        noteMacroClass(d, "@protocol");
        return true;
    }

    bool VisitObjCCategoryDecl(ObjCCategoryDecl *d) {
        recordContainer(d);
        noteMacroClass(d, "@interface");
        return true;
    }

    bool VisitObjCImplementationDecl(ObjCImplementationDecl *d) {
        recordContainer(d);
        noteMacroClass(d, "@implementation");
        recordImpl(d, "");
        return true;
    }

    bool VisitObjCCategoryImplDecl(ObjCCategoryImplDecl *d) {
        recordContainer(d);
        noteMacroClass(d, "@implementation");
        recordImpl(d, d->getName().str());
        return true;
    }

    // A declaration in a repository file that the unit reads only through a
    // module (see "Declarations read through a module" at the top of this
    // file): its containers (methods, properties, ivars, classes and
    // adoptions) and its variables are recorded as a header's are. Function
    // bodies are not traversed.
    void recordModuleDeclaration(Decl *d) {
        if (auto *iface = dyn_cast<ObjCInterfaceDecl>(d)) {
            if (iface->isThisDeclarationADefinition()) recordContainer(iface);
        } else if (auto *proto = dyn_cast<ObjCProtocolDecl>(d)) {
            if (proto->isThisDeclarationADefinition()) recordContainer(proto);
        } else if (auto *cat = dyn_cast<ObjCCategoryDecl>(d)) {
            recordContainer(cat);
        } else if (auto *vd = dyn_cast<VarDecl>(d)) {
            VisitVarDecl(vd);
        }
    }

    // Whether a declaration is written in a file outside the repository.
    bool declaredOutsideRepo(const Decl *d) {
        SourceLocation loc = sm_.getExpansionLoc(d->getLocation());
        return loc.isValid() && !fileInRepo(sm_.getFileID(loc));
    }

    // The stored path of the file a declaration is written in.
    std::string headerOf(const Decl *d) {
        SourceLocation loc = sm_.getExpansionLoc(d->getLocation());
        return loc.isValid() ? filePath(sm_.getFileID(loc)) : "";
    }

    // The framework or library of a declaration outside the repository: the
    // last X.framework in its file's path, or else the file's directory.
    std::string frameworkOf(const Decl *d) {
        SourceLocation loc = sm_.getExpansionLoc(d->getLocation());
        std::string path = loc.isValid() ? fileEntryPath(sm_.getFileEntryRefForID(sm_.getFileID(loc))) : "";
        std::string framework;
        for (auto it = llvm::sys::path::begin(path), end = llvm::sys::path::end(path); it != end; ++it)
            if (it->ends_with(".framework")) framework = it->drop_back(strlen(".framework")).str();
        if (!framework.empty()) return framework;
        return llvm::sys::path::filename(llvm::sys::path::parent_path(path)).str();
    }

    // sdk_method, sdk_class and sdk_adoption rows of a container outside the
    // repository, under its module key.
    void recordSdkContainer(const ObjCContainerDecl *c, const std::string &module) {
        std::string name, kind;
        const ObjCProtocolList *protocols = nullptr;
        if (const auto *iface = dyn_cast<ObjCInterfaceDecl>(c)) {
            if (!iface->isThisDeclarationADefinition()) return;
            name = iface->getName().str();
            kind = "class";
            protocols = &iface->getReferencedProtocols();
        } else if (const auto *proto = dyn_cast<ObjCProtocolDecl>(c)) {
            if (!proto->isThisDeclarationADefinition()) return;
            name = proto->getName().str();
            kind = "protocol";
            protocols = &proto->getReferencedProtocols();
        } else if (const auto *cat = dyn_cast<ObjCCategoryDecl>(c)) {
            name = (cat->getClassInterface() ? cat->getClassInterface()->getName().str() : "") + "(" +
                   cat->getName().str() + ")";
            kind = "category";
            protocols = &cat->getReferencedProtocols();
        } else {
            return;
        }
        std::string framework = frameworkOf(c);
        if (const auto *iface = dyn_cast<ObjCInterfaceDecl>(c)) {
            SdkClassRow row;
            row.name = name;
            if (const ObjCInterfaceDecl *super = iface->getSuperClass()) row.superclass = super->getName().str();
            row.framework = framework;
            row.module = module;
            results_.sdkClasses.push_back(std::move(row));
        }
        for (const ObjCProtocolDecl *p : *protocols)
            results_.sdkAdoptions.push_back({name, kind, p->getName().str(), module});
        auto add = [&](const std::string &selector, bool isClass, bool optional, bool action) {
            if (!sdkSeen_.insert(module + "|" + name + "|" + (isClass ? "+" : "-") + selector).second) return;
            SdkMethodRow row;
            row.selector = selector;
            row.container = name;
            row.containerKind = kind;
            row.isClassMethod = isClass ? 1 : 0;
            row.framework = framework;
            row.isOptional = optional ? 1 : 0;
            row.isAction = action ? 1 : 0;
            row.module = module;
            results_.sdkMethods.push_back(std::move(row));
        };
        for (const ObjCMethodDecl *md : c->methods()) {
            // The accessors the compiler declares for a property are its
            // getter and setter rows, below.
            if (md->isImplicit()) continue;
            bool action = false;
            SourceLocation rt = md->getReturnTypeSourceRange().getBegin();
            if (rt.isValid() && rt.isMacroID())
                action = Lexer::getImmediateMacroName(rt, sm_, ctx_.getLangOpts()) == "IBAction";
            add(md->getSelector().getAsString(), md->isClassMethod(), md->isOptional(), action);
        }
        for (const ObjCPropertyDecl *pd : c->properties()) {
            bool optional = pd->getPropertyImplementation() == ObjCPropertyDecl::Optional;
            add(pd->getGetterName().getAsString(), pd->isClassProperty(), optional, false);
            if (!pd->isReadOnly()) add(pd->getSetterName().getAsString(), pd->isClassProperty(), optional, false);
        }
    }

private:
    struct Frame {
        Decl *decl;
        int blockDepth;
    };

    struct ContainerInfo {
        std::string usr, kind, name, className, claimFile;
    };

    // The value of a condition that folds as CodeGen's
    // ConstantFoldsToSimpleInteger folds it: Expr::EvaluateAsInt (an integer
    // constant expression, or a const-qualified variable with a constant
    // initializer, and no side effects), and no label in the condition
    // unless allowLabels; nothing otherwise.
    std::optional<bool> foldedCondition(const Expr *cond, bool allowLabels) {
        if (!cond || cond->isValueDependent() || cond->isTypeDependent()) return std::nullopt;
        Expr::EvalResult result;
        if (!cond->EvaluateAsInt(result, ctx_) || !result.Val.isInt()) return std::nullopt;
        if (!allowLabels && containsLabel(cond)) return std::nullopt;
        return result.Val.getInt().getBoolValue();
    }

    // CodeGenFunction::ContainsLabel: a label, or a case or default of an
    // enclosing switch (not one of a switch inside), anywhere in s.
    static bool containsLabel(const Stmt *s, bool ignoreCases = false) {
        if (!s) return false;
        if (isa<LabelStmt>(s)) return true;
        if (isa<SwitchCase>(s) && !ignoreCases) return true;
        if (isa<SwitchStmt>(s)) ignoreCases = true;
        for (const Stmt *child : s->children())
            if (containsLabel(child, ignoreCases)) return true;
        return false;
    }

    // A type CodeGen's scalar emitter evaluates (not an aggregate or a
    // complex number; atomic and member pointer types are left out too).
    static bool scalarEvaluation(QualType t) {
        if (t.isNull()) return false;
        t = t.getCanonicalType();
        return !(t->isRecordType() || t->isArrayType() || t->isAnyComplexType() || t->isAtomicType() ||
                 t->isMemberPointerType() || t->isDependentType());
    }

    static const Expr *throughWrappers(const Expr *e) {
        while (e) {
            const Expr *next = e->IgnoreParens();
            if (const auto *c = dyn_cast<CastExpr>(next)) next = c->getSubExpr();
            else if (const auto *f = dyn_cast<FullExpr>(next)) next = f->getSubExpr();
            else if (const auto *m = dyn_cast<MaterializeTemporaryExpr>(next)) next = m->getSubExpr();
            else if (const auto *b = dyn_cast<CXXBindTemporaryExpr>(next)) next = b->getSubExpr();
            if (next == e) return e;
            e = next;
        }
        return e;
    }

    // Records e as part of a branch condition, and with it what CodeGen's
    // EmitBranchOnBoolExpr reaches from it (through !, && and ||, both
    // operands of a conditional operator, and, more widely than needed, any
    // cast, __builtin_expect, __builtin_choose_expr and _Generic). There
    // CodeGen emits both operands of a conditional operator and the right
    // operand of 0 && x, so nothing there is marked.
    void noteBranchCondition(const Expr *e) {
        e = throughWrappers(e);
        if (!e || !branchConditions_.insert(e).second) return;
        if (const auto *u = dyn_cast<UnaryOperator>(e)) {
            if (u->getOpcode() == UO_LNot) noteBranchCondition(u->getSubExpr());
        } else if (const auto *b = dyn_cast<BinaryOperator>(e)) {
            if (b->isLogicalOp()) {
                noteBranchCondition(b->getLHS());
                noteBranchCondition(b->getRHS());
            }
        } else if (const auto *c = dyn_cast<AbstractConditionalOperator>(e)) {
            noteBranchCondition(c->getCond());
            noteBranchCondition(c->getTrueExpr());
            noteBranchCondition(c->getFalseExpr());
        } else if (const auto *call = dyn_cast<CallExpr>(e)) {
            unsigned id = call->getBuiltinCallee();
            if ((id == Builtin::BI__builtin_expect || id == Builtin::BI__builtin_expect_with_probability ||
                 id == Builtin::BI__builtin_unpredictable) && call->getNumArgs() > 0)
                noteBranchCondition(call->getArg(0));
        } else if (const auto *ch = dyn_cast<ChooseExpr>(e)) {
            if (!ch->isConditionDependent()) noteBranchCondition(ch->getChosenSubExpr());
        } else if (const auto *g = dyn_cast<GenericSelectionExpr>(e)) {
            if (!g->isResultDependent()) noteBranchCondition(g->getResultExpr());
        }
    }

    bool inBranchCondition(const Expr *e) const { return branchConditions_.count(e) > 0; }

    void markDead(const Stmt *branch, const Expr *cond) {
        if (!branch) return;
        Located where;
        if (!locate(cond->getExprLoc(), where)) {
            SourceLocation exp = sm_.getExpansionLoc(cond->getExprLoc());
            where.file = exp.isValid() ? filePath(sm_.getFileID(exp)) : "";
            where.line = exp.isValid() ? sm_.getExpansionLineNumber(exp) : 0;
        }
        deadRoots_.emplace(branch, std::make_pair(where.file, where.line));
    }

    // "Unreachable code" (see the top of this file): marks the send rows of
    // the body of d (a function, method, block or lambda; not the bodies of
    // blocks and lambdas inside it, which have their own) that are placed
    // only in blocks of its CFG that no path from the entry reaches.
    void markUnreachable(const Decl *d, Stmt *body) {
        if (!d || !body || !isa<DeclContext>(d) || Decl::castToDeclContext(d)->isDependentContext()) return;
        CFG::BuildOptions options;
        options.PruneTriviallyFalseEdges = false;
        options.setAllAlwaysAdd();
        std::unique_ptr<CFG> cfg = CFG::buildCFG(d, body, &ctx_, options);
        if (!cfg) return;
        std::vector<char> reached(cfg->getNumBlockIDs(), 0);
        std::vector<const CFGBlock *> work;
        auto reach = [&](const CFGBlock *b) {
            if (b && !reached[b->getBlockID()]) {
                reached[b->getBlockID()] = 1;
                work.push_back(b);
            }
        };
        reach(&cfg->getEntry());
        // The handlers of a try or @try hang off the block its statement
        // terminates, which only exception edges (not built) lead to: they
        // are roots too, as CodeGen emits them.
        for (const CFGBlock *b : *cfg) {
            const Stmt *t = b->getTerminatorStmt();
            if (t && (isa<CXXTryStmt>(t) || isa<ObjCAtTryStmt>(t))) reach(b);
        }
        while (!work.empty()) {
            const CFGBlock *b = work.back();
            work.pop_back();
            const Stmt *t = b->getTerminatorStmt();
            int skip = -1;
            if (t) {
                auto it = skippedSuccessor_.find(t);
                if (it != skippedSuccessor_.end()) skip = (int)it->second;
            }
            // A block the CFG ends as noreturn ends the path only when
            // CodeGen ends it too (endsPathForCodeGen); otherwise the edge it
            // keeps, called unreachable, to the code after is followed.
            bool followUnreachable = (t && isa<SwitchStmt>(t)) || (b->hasNoReturnElement() && !endsPathForCodeGen(*b));
            int index = 0;
            for (const CFGBlock::AdjacentBlock &a : b->succs()) {
                if (index++ == skip) continue;
                reach(a.getReachableBlock());
                // An edge the CFG keeps but calls unreachable is followed
                // out of a switch (its default when the cases list every
                // enumerator), which CodeGen emits, and out of a noreturn
                // block CodeGen does not end. The others link the code after
                // a noreturn call and the like, which no path reaches.
                if (followUnreachable) reach(a.getPossiblyUnreachableBlock());
            }
        }
        std::unordered_set<const Stmt *> live, dead;
        for (const CFGBlock *b : *cfg) {
            for (const CFGElement &el : *b) {
                std::optional<CFGStmt> cs = el.getAs<CFGStmt>();
                if (!cs || !isa<ObjCMessageExpr>(cs->getStmt())) continue;
                (reached[b->getBlockID()] ? live : dead).insert(cs->getStmt());
            }
        }
        for (const Stmt *st : dead) {
            if (live.count(st)) continue;
            auto it = sendRowOf_.find(st);
            if (it != sendRowOf_.end()) results_.sends[it->second].inUnreachable = 1;
        }
    }

    // Whether a block the CFG marks as ending in a noreturn element ends the
    // path for CodeGen too: its last statement is a throw or @throw, or a
    // call CodeGen emits as noreturn (a callee with the noreturn attribute,
    // _Noreturn or [[noreturn]], or of a noreturn function type, or
    // __builtin_unreachable). Not __builtin_assume(0), __builtin_trap,
    // __builtin_debugtrap or another builtin, nor analyzer_noreturn, after
    // which the CFG ends the path but CodeGen emits the code that follows.
    bool endsPathForCodeGen(const CFGBlock &b) const {
        const Stmt *last = nullptr;
        for (auto it = b.rbegin(); it != b.rend(); ++it) {
            if (std::optional<CFGStmt> cs = it->getAs<CFGStmt>()) {
                last = cs->getStmt();
                break;
            }
        }
        if (!last) return false;
        if (isa<CXXThrowExpr>(last) || isa<ObjCAtThrowStmt>(last)) return true;
        const auto *call = dyn_cast<CallExpr>(last);
        if (!call) return false;
        if (const FunctionDecl *fd = call->getDirectCallee()) {
            unsigned id = fd->getBuiltinID();
            if (id == Builtin::BI__builtin_unreachable) return true;
            if (id && !ctx_.BuiltinInfo.isLibFunction(id)) return false;
            if (fd->hasAttr<NoReturnAttr>() || fd->hasAttr<C11NoReturnAttr>() || fd->hasAttr<CXX11NoReturnAttr>())
                return true;
        }
        QualType callee = call->getCallee()->getType();
        if (const auto *pt = callee->getAs<PointerType>()) callee = pt->getPointeeType();
        else if (const auto *bt = callee->getAs<BlockPointerType>()) callee = bt->getPointeeType();
        if (const auto *ft = callee->getAs<FunctionType>()) return ft->getNoReturnAttr();
        return false;
    }

    void noteConstantFalse(ConstantFalse &row) const {
        if (dead_.empty()) return;
        row.inConstantFalse = 1;
        row.conditionFile = dead_.back().first;
        row.conditionLine = dead_.back().second;
    }

    // Counts the unevaluated operands being traversed, for one scope.
    class Unevaluated {
    public:
        Unevaluated(SendVisitor &v, bool active) : v_(v), active_(active) {
            if (active_) v_.unevaluated_++;
        }
        ~Unevaluated() {
            if (active_) v_.unevaluated_--;
        }

    private:
        SendVisitor &v_;
        bool active_;
    };

    // --- Facts about macros from the AST (macro_ast_fact) ------------------

    // Each node is counted once (the visitor reaches some nodes twice: the
    // syntactic and semantic forms of a property access, and declarations
    // in an @implementation).
    void noteMacroFact(long def, const char *fact, const std::string &detail, const void *node) {
        if (def < 0 || !seenMacroNodes_.insert({node, fact}).second) return;
        results_.macroFacts[std::make_tuple((size_t)def, std::string(fact), detail)]++;
    }

    void noteMacroFact(SourceLocation loc, const char *fact, const std::string &detail, const void *node) {
        if (loc.isValid() && loc.isMacroID()) noteMacroFact(macroSpelling(facts_, sm_, loc), fact, detail, node);
    }

    // A send whose '[' (or, for a property access, whose selector) a macro
    // spells; its selector is the macro's own, pasted by it, or from an
    // argument.
    void noteMacroSend(const ObjCMessageExpr *m) {
        SourceLocation sel = m->getSelectorStartLoc();
        SourceLocation bracket = m->isImplicit() ? sel : m->getLeftLoc();
        if (bracket.isInvalid()) bracket = sel;
        if (bracket.isInvalid() || !bracket.isMacroID()) return;
        long def = macroSpelling(facts_, sm_, bracket);
        if (def < 0) return;
        std::string detail = m->getSelector().getAsString();
        if (sel.isInvalid() || macroSpelling(facts_, sm_, sel) != def) detail += " [argument]";
        else if (sm_.isWrittenInScratchSpace(sm_.getSpellingLoc(sel))) detail += " [pasted]";
        noteMacroFact(def, "send", detail, m);
    }

    void noteMacroClass(const ObjCContainerDecl *d, const char *kind) {
        // A macro that writes the @interface, @implementation or @protocol
        // makes the container; one that only spells its name names it.
        std::string name = d->getNameAsString();
        if (const auto *cat = dyn_cast<ObjCCategoryDecl>(d))
            name = (cat->getClassInterface() ? cat->getClassInterface()->getNameAsString() : "") + "(" + name + ")";
        else if (const auto *cimpl = dyn_cast<ObjCCategoryImplDecl>(d))
            name = (cimpl->getClassInterface() ? cimpl->getClassInterface()->getNameAsString() : "") + "(" + name + ")";
        std::string what = std::string(kind) + " " + name;
        long def = macroSpelling(facts_, sm_, d->getBeginLoc());
        if (def >= 0) noteMacroFact(def, "class", what, d);
        else noteMacroFact(d->getLocation(), "names-class", what, d);
    }

    // A declaration a macro makes that is not inside a compound statement
    // the same expansion of that macro opens: its name is visible to the
    // code around the macro's use.
    void noteMacroDeclaration(const NamedDecl *d) {
        if (d->isImplicit() || isa<ParmVarDecl>(d) || !d->getIdentifier()) return;
        SourceLocation begin = d->getBeginLoc();
        long def = macroSpelling(facts_, sm_, begin);
        if (def < 0) def = macroSpelling(facts_, sm_, d->getLocation());
        if (def < 0) return;
        if (!compounds_.empty()) {
            SourceLocation lb = compounds_.back();
            if (lb.isMacroID() && macroSpelling(facts_, sm_, lb) == def &&
                sm_.getExpansionLoc(lb) == sm_.getExpansionLoc(begin))
                return;
        }
        noteMacroFact(def, "declaration", d->getNameAsString(), d);
    }

    void recordEnclosingRange(const Decl *d) {
        if (const auto *fd = dyn_cast<FunctionDecl>(d)) {
            if (!fd->doesThisDeclarationHaveABody()) return;
        } else if (const auto *md = dyn_cast<ObjCMethodDecl>(d)) {
            if (!md->hasBody()) return;
        }
        SourceRange r = d->getSourceRange();
        SourceLocation b = sm_.getExpansionLoc(r.getBegin());
        SourceLocation e = sm_.getExpansionRange(r.getEnd()).getEnd();
        if (b.isInvalid() || e.isInvalid()) return;
        FileID fid = sm_.getFileID(b);
        if (fid != sm_.getFileID(e) || !fileInRepo(fid)) return;
        results_.enclosingRanges.push_back({fid, sm_.getFileOffset(b), sm_.getFileOffset(e), usr(d), displayName(d)});
    }

    // Fills a row's location from the token at loc (see the top of this
    // file). False if the token is not written in a file in the repository.
    bool locate(SourceLocation loc, Located &row) {
        SourceLocation exp = sm_.getExpansionLoc(loc);
        if (exp.isInvalid()) return false;
        SourceLocation written = exp;
        if (loc.isMacroID()) {
            // Follow the token back toward the file, one macro at a time: from
            // a macro argument to where the argument was written, from a macro
            // body to where that macro was used.
            bool viaBody = false;
            SourceLocation l = loc;
            while (l.isMacroID()) {
                if (sm_.isMacroArgExpansion(l)) {
                    l = sm_.getImmediateSpellingLoc(l);
                } else {
                    viaBody = true;
                    l = sm_.getImmediateExpansionRange(l).getBegin();
                }
            }
            bool pasted = sm_.isWrittenInScratchSpace(sm_.getSpellingLoc(loc));
            row.macroRole = pasted ? "pasted" : viaBody ? "body" : "argument";
            if (!pasted && l.isValid() && l.isFileID()) written = l;
            SourceLocation nameLoc = sm_.getExpansionRange(loc).getBegin();
            row.expansionLine = sm_.getExpansionLineNumber(nameLoc);
            row.expansionCol = sm_.getExpansionColumnNumber(nameLoc);
        }
        // The scope applies to the file the row is written in.
        if (!fileInRepo(sm_.getFileID(written))) return false;
        row.file = filePath(sm_.getFileID(written));
        row.inMigrationScope = paths_.inMigrationScope(row.file) ? 1 : 0;
        row.line = sm_.getSpellingLineNumber(written);
        row.col = sm_.getSpellingColumnNumber(written);
        if (loc.isMacroID()) {
            SourceLocation nameLoc = sm_.getExpansionRange(loc).getBegin();
            auto it = facts_.uses.find(nameLoc.getRawEncoding());
            if (it != facts_.uses.end()) {
                row.macroName = it->second.name;
                row.macroFile = it->second.defFile;
                row.macroLine = it->second.defLine;
            } else {
                // Not seen by the callback (should not happen); keep the name.
                row.macroName = Lexer::getSpelling(nameLoc, nameBuf_, sm_, ctx_.getLangOpts()).str();
            }
        }
        return true;
    }

    void enclose(std::string &enclosingUSR, std::string &enclosingName, int &inBlock) {
        const Frame *enclosing = innermostDecl();
        if (enclosing) {
            enclosingUSR = usr(enclosing->decl);
            enclosingName = displayName(enclosing->decl);
        }
        inBlock = blockDepthSinceEnclosing() > 0 ? 1 : 0;
    }

    // --- Methods and properties ---------------------------------------------

    void recordContainer(ObjCContainerDecl *c) {
        if (!seenContainers_.insert(c).second) return;
        ContainerInfo ci;
        ci.usr = usr(c);
        bool implementation = false;
        if (const auto *iface = dyn_cast<ObjCInterfaceDecl>(c)) {
            ci.kind = "interface";
            ci.name = ci.className = iface->getName().str();
        } else if (const auto *cat = dyn_cast<ObjCCategoryDecl>(c)) {
            ci.className = cat->getClassInterface() ? cat->getClassInterface()->getName().str() : "";
            ci.kind = cat->IsClassExtension() ? "extension" : "category";
            ci.name = ci.className + "(" + cat->getName().str() + ")";
        } else if (const auto *proto = dyn_cast<ObjCProtocolDecl>(c)) {
            ci.kind = "protocol";
            ci.name = proto->getName().str();
        } else if (const auto *impl = dyn_cast<ObjCImplementationDecl>(c)) {
            ci.kind = "implementation";
            ci.name = ci.className = impl->getName().str();
            implementation = true;
        } else if (const auto *catImpl = dyn_cast<ObjCCategoryImplDecl>(c)) {
            ci.kind = "category-implementation";
            ci.className = catImpl->getClassInterface() ? catImpl->getClassInterface()->getName().str() : "";
            ci.name = ci.className + "(" + catImpl->getName().str() + ")";
            implementation = true;
        } else {
            return;
        }
        if (!implementation) {
            SourceLocation loc = sm_.getExpansionLoc(c->getLocation());
            if (loc.isValid()) ci.claimFile = filePath(sm_.getFileID(loc));
        }
        for (ObjCMethodDecl *md : c->methods()) recordMethod(md, c, ci, implementation);
        if (!implementation) recordClassAndAdoptions(c, ci);
        if (!implementation) {
            for (ObjCPropertyDecl *pd : c->properties()) recordPropertyDeclaration(pd, ci);
        } else {
            for (ObjCPropertyImplDecl *pid : cast<ObjCImplDecl>(c)->property_impls()) recordPropertyImpl(pid, ci);
            for (ObjCMethodDecl *md : c->methods())
                if (md->isSynthesizedAccessorStub()) recordSynthesizedAccess(md, cast<ObjCImplDecl>(c), ci);
        }
        if (const auto *iface = dyn_cast<ObjCInterfaceDecl>(c)) {
            for (const ObjCIvarDecl *iv : iface->ivars()) recordIvar(iv, ci, nullptr);
        } else if (const auto *cat = dyn_cast<ObjCCategoryDecl>(c)) {
            if (cat->IsClassExtension())
                for (const ObjCIvarDecl *iv : cat->ivars()) recordIvar(iv, ci, nullptr);
        } else if (const auto *impl = dyn_cast<ObjCImplementationDecl>(c)) {
            for (const ObjCIvarDecl *iv : impl->ivars()) recordIvar(iv, ci, impl);
        }
    }

    // objc_class (an @interface: its superclass) and objc_adoption (the
    // protocols an @interface, category, class extension or protocol lists),
    // declaration rows claimed as methods are.
    void recordClassAndAdoptions(const ObjCContainerDecl *c, const ContainerInfo &ci) {
        const ObjCProtocolList *protocols = nullptr;
        if (const auto *iface = dyn_cast<ObjCInterfaceDecl>(c)) {
            ClassRow row;
            if (!locate(iface->getLocation(), row) || isBuildProduct(row.file)) return;
            row.usr = ci.usr;
            row.name = ci.name;
            if (const ObjCInterfaceDecl *super = iface->getSuperClass()) row.superclass = super->getName().str();
            row.claimFile = ci.claimFile;
            results_.classes.push_back(std::move(row));
            protocols = &iface->getReferencedProtocols();
        } else if (const auto *cat = dyn_cast<ObjCCategoryDecl>(c)) {
            protocols = &cat->getReferencedProtocols();
        } else if (const auto *proto = dyn_cast<ObjCProtocolDecl>(c)) {
            protocols = &proto->getReferencedProtocols();
        }
        if (!protocols) return;
        for (const ObjCProtocolDecl *p : *protocols) {
            AdoptionRow row;
            if (!locate(c->getLocation(), row) || isBuildProduct(row.file)) return;
            row.container = ci.name;
            row.containerKind = ci.kind;
            row.protocol = p->getName().str();
            row.claimFile = ci.claimFile;
            results_.adoptions.push_back(std::move(row));
        }
    }

    // --- Ivars and statics ----------------------------------------------------

    // An ivar of an @interface, class extension or @implementation (impl
    // given), including those the compiler synthesizes for a property.
    void recordIvar(const ObjCIvarDecl *iv, const ContainerInfo &ci, const ObjCImplementationDecl *impl) {
        // The unnamed ivar the compiler adds after a bit-field that is last
        // among a class's ivars is not an ivar of the source or the runtime.
        if (iv->getName().empty()) return;
        IvarRow row;
        if (!locate(iv->getLocation(), row) || isBuildProduct(row.file)) return;
        row.usr = usr(iv);
        const ObjCInterfaceDecl *iface = iv->getContainingInterface();
        row.className = iface ? iface->getName().str() : ci.className;
        row.name = iv->getName().str();
        row.containerKind = ci.kind;
        row.facts = typeFacts(iv->getType(), iv);
        switch (iv->getCanonicalAccessControl()) {
        case ObjCIvarDecl::None:
        case ObjCIvarDecl::Private: row.access = "private"; break;
        case ObjCIvarDecl::Protected: row.access = "protected"; break;
        case ObjCIvarDecl::Public: row.access = "public"; break;
        case ObjCIvarDecl::Package: row.access = "package"; break;
        }
        row.isIBOutlet = iv->hasAttr<IBOutletAttr>() ? 1 : 0;
        if (impl && iv->getSynthesize()) {
            for (const ObjCPropertyImplDecl *pid : impl->property_impls()) {
                if (pid->getPropertyIvarDecl() != iv || !pid->getPropertyDecl()) continue;
                row.synthesizedBy = pid->getLocation().isInvalid() ? "automatic" : "explicit";
                row.propertyName = pid->getPropertyDecl()->getName().str();
                break;
            }
        }
        row.claimFile = ci.claimFile;
        results_.ivars.push_back(std::move(row));
    }

    // The ivar access of an accessor the compiler synthesizes: a read for a
    // getter, a write for a setter, at the accessor (as objc_method records
    // it).
    void recordSynthesizedAccess(const ObjCMethodDecl *md, const ObjCImplDecl *impl, const ContainerInfo &ci) {
        Selector sel = md->getSelector();
        for (const ObjCPropertyImplDecl *pid : impl->property_impls()) {
            const ObjCPropertyDecl *pd = pid->getPropertyDecl();
            const ObjCIvarDecl *iv = pid->getPropertyIvarDecl();
            if (!pd || !iv || pd->isClassProperty() != md->isClassMethod()) continue;
            bool getter = pd->getGetterName() == sel, setter = !getter && pd->getSetterName() == sel;
            if (!getter && !setter) continue;
            SourceLocation loc = md->getSelectorStartLoc();
            if (loc.isInvalid()) loc = md->getLocation();
            IvarRefRow row;
            if (!locate(loc, row)) return;
            row.ivarUSR = usr(iv);
            const ObjCInterfaceDecl *iface = iv->getContainingInterface();
            row.ivarClass = iface ? iface->getName().str() : ci.className;
            row.ivarName = iv->getName().str();
            row.kind = getter ? "synthesized-getter" : "synthesized-setter";
            row.access = getter ? "read" : "write";
            row.baseKind = "self";
            row.enclosingUSR = usr(md);
            row.enclosingName = displayName(md);
            row.enclosingClass = ci.className;
            results_.ivarRefs.push_back(std::move(row));
            return;
        }
    }

    bool declaredInRepo(const Decl *d) {
        SourceLocation loc = sm_.getExpansionLoc(d->getLocation());
        return loc.isValid() && fileInRepo(sm_.getFileID(loc));
    }

    // The kind of a variable with static storage. For a declaration row
    // (c_static), a global's declaration that is not a definition is
    // "extern"; a reference names every global "global".
    static std::string staticKind(const VarDecl *vd, bool declaration) {
        if (vd->isStaticDataMember()) return "static-member";
        if (vd->isStaticLocal()) return "local-static";
        if (vd->getStorageClass() == SC_Static) return "file-static";
        if (declaration && vd->isThisDeclarationADefinition() == VarDecl::DeclarationOnly) return "extern";
        return "global";
    }

    // The class of the method the current position is in, or "".
    std::string enclosingClass() const {
        const Frame *f = innermostDecl();
        const auto *md = f ? dyn_cast<ObjCMethodDecl>(f->decl) : nullptr;
        const ObjCInterfaceDecl *iface = md ? md->getClassInterface() : nullptr;
        return iface ? iface->getName().str() : "";
    }

    // What the base of obj->_ivar is: self, a parameter, a local (one
    // initialized from a __weak variable is the strong half of a weak-strong
    // dance), or another expression.
    std::string baseKind(const Expr *base) const {
        const Expr *e = strip(base);
        const auto *dre = dyn_cast_or_null<DeclRefExpr>(e);
        if (!dre) return "other";
        if (const auto *ipd = dyn_cast<ImplicitParamDecl>(dre->getDecl()))
            return ipd->getParameterKind() == ImplicitParamKind::ObjCSelf ? "self" : "other";
        if (isa<ParmVarDecl>(dre->getDecl())) return "parameter";
        const auto *vd = dyn_cast<VarDecl>(dre->getDecl());
        if (!vd || !vd->isLocalVarDecl()) return "other";
        if (const Expr *init = vd->getInit()) {
            const auto *src = dyn_cast_or_null<DeclRefExpr>(strip(init));
            const auto *sv = src ? dyn_cast<VarDecl>(src->getDecl()) : nullptr;
            if (sv && sv->getType().getObjCLifetime() == Qualifiers::OCL_Weak) return "weak-strong-local";
        }
        return "local";
    }

    // The ivar or variable reference that an lvalue expression is, or is a
    // part of (a member through '.', an element of an array): nullptr when
    // the expression reaches it through a pointer, or is something else.
    static const Expr *lvalueRoot(const Expr *e, bool &partial) {
        while (e) {
            e = e->IgnoreParens();
            if (const auto *ice = dyn_cast<ImplicitCastExpr>(e)) {
                switch (ice->getCastKind()) {
                case CK_NoOp:
                case CK_LValueToRValue:
                case CK_ARCConsumeObject:
                case CK_ARCReclaimReturnedObject:
                case CK_ARCExtendBlockObject:
                    e = ice->getSubExpr();
                    continue;
                case CK_ArrayToPointerDecay:
                    partial = true;
                    e = ice->getSubExpr();
                    continue;
                default: return nullptr;
                }
            }
            if (const auto *ewc = dyn_cast<ExprWithCleanups>(e)) {
                e = ewc->getSubExpr();
                continue;
            }
            if (const auto *ove = dyn_cast<OpaqueValueExpr>(e)) {
                e = ove->getSourceExpr();
                continue;
            }
            if (const auto *me = dyn_cast<MemberExpr>(e)) {
                if (me->isArrow()) return nullptr;
                partial = true;
                e = me->getBase();
                continue;
            }
            if (const auto *ase = dyn_cast<ArraySubscriptExpr>(e)) {
                const auto *decay = dyn_cast<ImplicitCastExpr>(ase->getBase()->IgnoreParens());
                if (!decay || decay->getCastKind() != CK_ArrayToPointerDecay) return nullptr;
                partial = true;
                e = decay->getSubExpr();
                continue;
            }
            if (isa<ObjCIvarRefExpr>(e) || isa<DeclRefExpr>(e)) return e;
            return nullptr;
        }
        return nullptr;
    }

    // Records how the ivar or variable an expression is (or is part of) is
    // used, unless its parent already did.
    void markAccess(const Expr *e, const char *access) {
        bool partial = false;
        const Expr *root = lvalueRoot(e, partial);
        if (root) marks_.emplace(root, std::make_pair(access, partial ? 1 : 0));
    }

    // An argument that passes an ivar or variable by reference: &x, or x
    // bound to a non-const lvalue reference parameter (param, when known).
    void markByReference(const Expr *arg, const ParmVarDecl *param) {
        const Expr *a = arg->IgnoreParenImpCasts();
        if (const auto *uo = dyn_cast<UnaryOperator>(a); uo && uo->getOpcode() == UO_AddrOf) {
            // The argument's type is the parameter's after conversion: &x
            // passed as a pointer to const is a read.
            QualType at = arg->getType();
            bool toConst = at->isPointerType() && at->getPointeeType().isConstQualified();
            markAccess(uo->getSubExpr(), toConst ? "read" : "byref");
            return;
        }
        QualType pt = param ? param->getType() : QualType();
        if (!pt.isNull() && pt->isLValueReferenceType() && !pt->getPointeeType().isConstQualified())
            markAccess(arg, "byref");
    }

    void markCallArguments(const CallExpr *call, const std::string &name) {
        if (const auto *op = dyn_cast<CXXOperatorCallExpr>(call)) {
            if (call->getNumArgs() == 0) return;
            OverloadedOperatorKind k = op->getOperator();
            if (k == OO_Equal) markAccess(call->getArg(0), "write");
            else if (op->isAssignmentOp() || k == OO_PlusPlus || k == OO_MinusMinus) markAccess(call->getArg(0), "rmw");
            return;
        }
        // dispatch_once(&token, ^{ ... }): the token, and the block whose
        // writes run once. The SDK defines dispatch_once as a macro for the
        // inline function _dispatch_once.
        if ((name == "dispatch_once" || name == "_dispatch_once" || name == "dispatch_once_f" ||
             name == "_dispatch_once_f") &&
            call->getNumArgs() >= 2) {
            const auto *uo = dyn_cast<UnaryOperator>(call->getArg(0)->IgnoreParenImpCasts());
            if (uo && uo->getOpcode() == UO_AddrOf) markAccess(uo->getSubExpr(), "once-token");
            if (const auto *block = dyn_cast<BlockExpr>(call->getArg(1)->IgnoreParenImpCasts()))
                onceBlocks_.insert(block);
        }
        if ((name == "CFRetain" || name == "CFRelease" || name == "CFAutorelease") && call->getNumArgs() == 1)
            markHint(call->getArg(0), name == "CFRetain" ? "retain" : name == "CFRelease" ? "release" : "autorelease");
        const FunctionDecl *fd = call->getDirectCallee();
        for (unsigned i = 0; i < call->getNumArgs(); i++)
            markByReference(call->getArg(i), fd && i < fd->getNumParams() ? fd->getParamDecl(i) : nullptr);
    }

    // The retain hint of the ivar an expression is (through casts).
    void markHint(const Expr *e, const char *hint) {
        if (const auto *iv = dyn_cast_or_null<ObjCIvarRefExpr>(strip(e))) hints_.emplace(iv, hint);
    }

    // Whether an expression's value is an object its caller owns: the result
    // of retain, copy, mutableCopy, new, alloc, or init sent to the result of
    // alloc.
    static bool returnsOwned(const Expr *e) {
        const auto *m = dyn_cast_or_null<ObjCMessageExpr>(strip(e));
        if (!m) return false;
        switch (m->getMethodFamily()) {
        case OMF_retain:
        case OMF_copy:
        case OMF_mutableCopy:
        case OMF_new:
        case OMF_alloc: return true;
        case OMF_init: return m->getReceiverKind() == ObjCMessageExpr::Instance && returnsOwned(m->getInstanceReceiver());
        default: return false;
        }
    }

    // The expression @synchronized locks: through statement expressions (as
    // ITNonnilLock makes), following the result expression and, when that is
    // a local declared in the statement expression, its initializer.
    static const Expr *lockOperand(const Expr *e) {
        for (int i = 0; i < 8 && e; i++) {
            e = strip(e);
            const auto *se = dyn_cast_or_null<StmtExpr>(e);
            if (!se || se->getSubStmt()->body_empty()) return e;
            const CompoundStmt *cs = se->getSubStmt();
            const auto *result = dyn_cast<Expr>(cs->body_back());
            if (!result) return e;
            result = strip(result);
            const auto *dre = dyn_cast_or_null<DeclRefExpr>(result);
            const auto *vd = dre ? dyn_cast<VarDecl>(dre->getDecl()) : nullptr;
            if (vd && vd->isLocalVarDecl() && vd->getInit() && declaredIn(cs, vd)) {
                e = vd->getInit();
                continue;
            }
            e = result;
        }
        return e;
    }

    static bool declaredIn(const CompoundStmt *cs, const VarDecl *vd) {
        for (const Stmt *st : cs->body())
            if (const auto *ds = dyn_cast<DeclStmt>(st))
                for (const Decl *d : ds->decls())
                    if (d == vd) return true;
        return false;
    }

    // What a @synchronized locks: "ivar USR", "self", "class NAME" (or
    // "class of self"), "static USR", or "other SOURCE".
    std::string lockDescription(const Expr *operand) {
        const Expr *e = strip(lockOperand(operand));
        if (!e) return "other";
        if (const auto *iv = dyn_cast<ObjCIvarRefExpr>(e)) return "ivar " + usr(iv->getDecl());
        if (const auto *dre = dyn_cast<DeclRefExpr>(e)) {
            if (const auto *ipd = dyn_cast<ImplicitParamDecl>(dre->getDecl());
                ipd && ipd->getParameterKind() == ImplicitParamKind::ObjCSelf)
                return "self";
            if (const auto *vd = dyn_cast<VarDecl>(dre->getDecl()); vd && vd->hasGlobalStorage())
                return "static " + usr(vd);
        }
        if (const auto *m = dyn_cast<ObjCMessageExpr>(e); m && m->getSelector().getAsString() == "class") {
            if (m->getReceiverKind() == ObjCMessageExpr::Class) {
                if (const ObjCInterfaceDecl *iface = m->getReceiverInterface())
                    return "class " + iface->getName().str();
            } else if (m->getReceiverKind() == ObjCMessageExpr::Instance && baseKind(m->getInstanceReceiver()) == "self") {
                return "class of self";
            }
        }
        return "other " + sourceText(e);
    }

    // The source of an expression, whitespace collapsed, at most 120
    // characters.
    std::string sourceText(const Expr *e) {
        const LangOptions &lo = ctx_.getLangOpts();
        CharSourceRange range = Lexer::makeFileCharRange(CharSourceRange::getTokenRange(e->getSourceRange()), sm_, lo);
        if (range.isInvalid())
            range = CharSourceRange::getTokenRange(sm_.getSpellingLoc(e->getBeginLoc()), sm_.getSpellingLoc(e->getEndLoc()));
        std::string text, raw = Lexer::getSourceText(range, sm_, lo).str();
        for (char c : raw) {
            bool space = c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\\';
            if (space) {
                if (!text.empty() && text.back() != ' ') text.push_back(' ');
            } else {
                text.push_back(c);
            }
        }
        while (!text.empty() && text.back() == ' ') text.pop_back();
        if (text.size() > 120) text = text.substr(0, 117) + "...";
        return text.empty() ? "?" : text;
    }

    // For a reference in the body of a C++ lambda: how the lambda captures
    // the variable the ivar is reached through (base; for a static, nothing
    // is captured): "NAME by reference", "NAME by copy", "init-capture", or
    // "not captured". "" outside a lambda.
    std::string lambdaCapture(const Expr *ref, const Expr *base) const {
        SourceLocation loc = sm_.getExpansionLoc(ref->getBeginLoc());
        const LambdaExpr *le = nullptr;
        for (auto it = lambdas_.rbegin(); it != lambdas_.rend() && !le; ++it) {
            SourceRange body = (*it)->getBody()->getSourceRange();
            SourceLocation b = sm_.getExpansionLoc(body.getBegin()), en = sm_.getExpansionLoc(body.getEnd());
            if (!sm_.isBeforeInTranslationUnit(loc, b) && !sm_.isBeforeInTranslationUnit(en, loc)) le = *it;
        }
        if (!le) return "";
        const auto *dre = base ? dyn_cast_or_null<DeclRefExpr>(strip(base)) : nullptr;
        const auto *vd = dre ? dyn_cast<VarDecl>(dre->getDecl()) : nullptr;
        if (!vd) return "not captured";
        if (vd->isInitCapture()) return "init-capture";
        for (const LambdaCapture &c : le->captures()) {
            if (!c.capturesVariable() || c.getCapturedVar() != vd) continue;
            std::string name = vd->getName().str();
            return name + (c.getCaptureKind() == LCK_ByRef ? " by reference" : " by copy");
        }
        return "not captured";
    }

    // function_ref: an evaluated reference to a function with internal
    // linkage or declared inline, defined in the repository (the functions
    // whose code the object may hold once per call, inlined, or not at all).
    // References in a template are left out; its instantiations count.
    void noteFunctionRef(const FunctionDecl *fd) {
        if (unevaluated_ > 0 || isa<CXXMethodDecl>(fd)) return;
        const FunctionDecl *def = nullptr;
        if (!fd->hasBody(def) || !def) return;
        if (!def->isInlined() && def->isExternallyVisible()) return;
        if (!declaredInRepo(def)) return;
        std::string enclosingUSR, enclosingName;
        int inBlock = 0;
        if (const Frame *f = innermostDecl()) {
            if (const auto *dc = dyn_cast<DeclContext>(f->decl); dc && dc->isDependentContext()) return;
        }
        enclose(enclosingUSR, enclosingName, inBlock);
        results_.functionRefs[{displayName(def), enclosingName}]++;
    }

    // Records a reference, once per place, access and enclosing function (a
    // macro argument expanded twice is one row). The row is marked as in
    // code the compiler does not emit only if every reference folded into it
    // is.
    template <typename Row>
    void keepReference(const std::string &target, Row &&row, std::vector<Row> &out,
                       std::unordered_map<std::string, size_t> &index) {
        std::string key = target + "|" + row.file + "|" + std::to_string(row.line) + "|" + std::to_string(row.col) +
                          "|" + row.access + "|" + row.enclosingUSR;
        auto [it, inserted] = index.emplace(key, out.size());
        if (inserted) {
            out.push_back(std::move(row));
            return;
        }
        if (row.inConstantFalse) return;
        Row &kept = out[it->second];
        kept.inConstantFalse = 0;
        kept.conditionFile.clear();
        kept.conditionLine = 0;
    }

    void recordImpl(const ObjCImplDecl *d, const std::string &category) {
        ImplRow row;
        if (!locate(d->getLocation(), row) || isBuildProduct(row.file)) return;
        const ObjCInterfaceDecl *iface = d->getClassInterface();
        row.className = iface ? iface->getName().str() : d->getName().str();
        row.category = category;
        row.arc = arc_ ? 1 : 0;
        results_.impls.push_back(std::move(row));
    }

    // The access recorded for a reference, "read" when its parent recorded
    // none; "unevaluated" in an operand that is not evaluated.
    void accessOf(const Expr *ref, std::string &access, int &partial) {
        if (unevaluated_ > 0) {
            access = "unevaluated";
            return;
        }
        auto it = marks_.find(ref);
        if (it == marks_.end()) {
            access = "read";
            return;
        }
        access = it->second.first;
        partial = it->second.second;
    }

    static const char *lifetimeName(Qualifiers::ObjCLifetime lt) {
        switch (lt) {
        case Qualifiers::OCL_None: return "";
        case Qualifiers::OCL_ExplicitNone: return "unsafe_unretained";
        case Qualifiers::OCL_Strong: return "strong";
        case Qualifiers::OCL_Weak: return "weak";
        case Qualifiers::OCL_Autoreleasing: return "autoreleasing";
        }
        return "";
    }

    // Whether a record (struct, union, C++ class) holds an Objective-C object
    // or block pointer in a field, directly or in a nested record or array.
    bool recordHasObjects(const RecordDecl *rd, int depth) const {
        if (!rd || depth > 8) return false;
        const RecordDecl *def = rd->getDefinition();
        if (!def) return false;
        for (const FieldDecl *f : def->fields()) {
            QualType ft = ctx_.getBaseElementType(f->getType());
            if (ft->isObjCRetainableType()) return true;
            if (const auto *rt = ft->getAs<RecordType>())
                if (recordHasObjects(rt->getDecl(), depth + 1)) return true;
        }
        return false;
    }

    // The facts of import_facts (see "State" at the top of this file) for t,
    // each word prefixed with prefix ("" for t itself, "in-" for a part of
    // it: a pointee, an array or vector element, a block's or function's
    // result or parameter, a field).
    void importFacts(QualType t, const std::string &prefix, int depth, std::set<std::string> &out,
                     std::set<const Type *> &seen) const {
        if (t.isNull()) return;
        if (depth > 8) {
            out.insert(prefix + "too-deep");
            return;
        }
        const std::string in = "in-";
        auto add = [&](const std::string &w) { out.insert(prefix + w); };
        sugarFacts(t, prefix, out);
        QualType c = t.getCanonicalType();
        const Type *ty = c.getTypePtr();
        if (ty->isDependentType()) {
            add("dependent-type");
            return;
        }
        if (const auto *at = dyn_cast<AtomicType>(ty)) {
            add("atomic");
            importFacts(at->getValueType(), in, depth + 1, out, seen);
            return;
        }
        if (const auto *arr = dyn_cast<ArrayType>(ty)) {
            if (isa<VariableArrayType>(arr)) add("variable-array");
            else if (isa<IncompleteArrayType>(arr)) add("incomplete-array");
            importFacts(arr->getElementType(), in, depth + 1, out, seen);
            return;
        }
        if (const auto *bt = dyn_cast<BuiltinType>(ty)) {
            switch (bt->getKind()) {
            case BuiltinType::Void: case BuiltinType::Bool: case BuiltinType::Char_S: case BuiltinType::Char_U:
            case BuiltinType::SChar: case BuiltinType::UChar: case BuiltinType::Short: case BuiltinType::UShort:
            case BuiltinType::Int: case BuiltinType::UInt: case BuiltinType::Long: case BuiltinType::ULong:
            case BuiltinType::LongLong: case BuiltinType::ULongLong: case BuiltinType::Float:
            case BuiltinType::Double: case BuiltinType::ObjCId: case BuiltinType::ObjCClass:
            case BuiltinType::ObjCSel: case BuiltinType::WChar_S: case BuiltinType::WChar_U:
            case BuiltinType::Char16: case BuiltinType::Char32:
                break;
            case BuiltinType::Int128: case BuiltinType::UInt128: add("int128"); break;
            case BuiltinType::LongDouble: add("long-double"); break;
            case BuiltinType::Half: case BuiltinType::Float16: add("float16"); break;
            default: add("unusual-builtin"); break;
            }
            return;
        }
        if (isa<BitIntType>(ty)) {
            add("unusual-builtin");
            return;
        }
        if (isa<ComplexType>(ty)) {
            add("complex");
            return;
        }
        if (const auto *et = dyn_cast<EnumType>(ty)) {
            bool flag = false, extensible = false;
            for (const TagDecl *r : et->getDecl()->redecls()) {
                flag = flag || r->hasAttr<FlagEnumAttr>();
                extensible = extensible || r->hasAttr<EnumExtensibilityAttr>();
            }
            add(flag ? "enum-options" : extensible ? "enum-ns" : "enum-plain");
            return;
        }
        if (const auto *vt = dyn_cast<VectorType>(ty)) {
            add("vector-elements-" + std::to_string(vt->getNumElements()));
            QualType el = vt->getElementType().getCanonicalType();
            if (const auto *eb = dyn_cast<BuiltinType>(el.getTypePtr()))
                add("vector-element-" + std::string(eb->getName(ctx_.getPrintingPolicy())));
            else
                add("vector-element-other");
            return;
        }
        if (const auto *pt = dyn_cast<PointerType>(ty)) {
            QualType pointee = pt->getPointeeType().getCanonicalType();
            if (const auto *ft = dyn_cast<FunctionType>(pointee.getTypePtr())) {
                add("function-pointer");
                functionImportFacts(ft, prefix, depth, out, seen);
                return;
            }
            if (pointee->isRecordType() && pointee->isIncompleteType()) add("opaque-pointee");
            if (pointee->isObjCRetainableType()) add("object-pointee");
            if (pointee->isConstantArrayType()) add("array-pointee");
            if (const auto *prt = pointee->getAs<RecordType>()) {
                for (const TagDecl *r : prt->getDecl()->redecls())
                    if (r->hasAttr<ObjCBridgeAttr>() || r->hasAttr<ObjCBridgeMutableAttr>() ||
                        r->hasAttr<ObjCBridgeRelatedAttr>()) {
                        add("cf-bridged");
                        break;
                    }
            }
            importFacts(pointee, in, depth + 1, out, seen);
            return;
        }
        if (const auto *bp = dyn_cast<BlockPointerType>(ty)) {
            if (const auto *ft = bp->getPointeeType()->getAs<FunctionType>()) functionImportFacts(ft, prefix, depth, out, seen);
            return;
        }
        if (const auto *rt = dyn_cast<ReferenceType>(ty)) {
            add("cxx-reference");
            importFacts(rt->getPointeeType(), in, depth + 1, out, seen);
            return;
        }
        if (isa<MemberPointerType>(ty)) {
            add("member-pointer");
            return;
        }
        if (const auto *opt = dyn_cast<ObjCObjectPointerType>(ty)) {
            objectImportFacts(opt, prefix, depth, out, seen);
            return;
        }
        if (isa<ObjCObjectType>(ty)) return;
        if (const auto *rt = dyn_cast<RecordType>(ty)) {
            const RecordDecl *def = rt->getDecl()->getDefinition();
            if (!def) {
                add("incomplete-record");
                return;
            }
            if (!seen.insert(ty).second) return;
            const auto *cxx = dyn_cast<CXXRecordDecl>(def);
            if (cxx && !cxx->isCLike()) add("cxx-record");
            if (isa<ClassTemplateSpecializationDecl>(def)) add("cxx-template");
            if (def->isUnion()) add("union");
            recordImportFacts(def, prefix, depth, out, seen);
            seen.erase(ty);
            return;
        }
        if (const auto *ft = dyn_cast<FunctionType>(ty)) {
            add("function");
            functionImportFacts(ft, prefix, depth, out, seen);
            return;
        }
        add("other-type");
    }

    // Facts read from the type as written, before it is made canonical:
    // type-in-main-file (the typedef, struct, union or enum that names it is
    // declared in the unit's main file, so it is private to that file),
    // cf-type-ref (a typedef named CFTypeRef on the way), va-list (a typedef
    // named va_list, __builtin_va_list or __darwin_va_list on the way; on
    // arm64 va_list is char *, so the canonical type cannot decide it),
    // objc-imp, lock-type (a typedef or record named os_unfair_lock,
    // os_unfair_lock_s, pthread_mutex_t, pthread_rwlock_t or OSSpinLock on the
    // way: a lock whose value must not be copied).
    void sugarFacts(QualType t, const std::string &prefix, std::set<std::string> &out) const {
        static const char *const locks[] = {"os_unfair_lock", "os_unfair_lock_s", "pthread_mutex_t",
                                            "pthread_rwlock_t", "OSSpinLock", "_opaque_pthread_mutex_t",
                                            "_opaque_pthread_rwlock_t"};
        const SourceManager &sm = ctx_.getSourceManager();
        bool first = true;
        QualType cur = t;
        for (int i = 0; i < 32 && !cur.isNull(); i++) {
            const NamedDecl *named = nullptr;
            if (const auto *td = cur->getAs<TypedefType>()) named = td->getDecl();
            else if (const auto *tt = dyn_cast<TagType>(cur.getTypePtr())) named = tt->getDecl();
            if (named) {
                if (first && prefix.empty() && sm.isInMainFile(sm.getExpansionLoc(named->getLocation())))
                    out.insert("type-in-main-file");
                first = false;
                std::string name = named->getName().str();
                if (name == "CFTypeRef") out.insert(prefix + "cf-type-ref");
                if (name == "va_list" || name == "__builtin_va_list" || name == "__darwin_va_list")
                    out.insert(prefix + "va-list");
                // IMP is void (*)(void) where OBJC_OLD_DISPATCH_PROTOTYPES is
                // 0, as Clang compiles the app on arm64, but the Swift
                // importer reads the SDK with it set to 1, where IMP is
                // id (*)(id, SEL, ...): variadic.
                if (name == "IMP" && !const_cast<SendVisitor *>(this)->declaredInRepo(named))
                    out.insert(prefix + "objc-imp");
                for (const char *l : locks)
                    if (name == l) out.insert(prefix + "lock-type");
            }
            QualType next = cur.getSingleStepDesugaredType(ctx_);
            if (next == cur) break;
            cur = next;
        }
    }

    // An Objective-C object pointer's facts: kindof (__kindof), type-args (a
    // specialized generic class, Foo<NSString *>) with where its class is:
    // generic-bridged (NSArray, NSDictionary or NSSet itself, which the
    // Swift Foundation overlay bridges to Array, Dictionary and Set, keeping
    // the arguments), generic-repository (declared in the repository, which
    // has no API notes: imported as a generic class with Objective-C type
    // arguments, Foo<NSString>), generic-sdk (another SDK class: imported
    // either as Foo<NSString> or, where the SDK's API notes say
    // SwiftImportAsNonGeneric, as NSMutableArray's do, without its
    // arguments; the extractor does not read API notes, because upstream
    // Clang applying them rejects code that Xcode's compiler accepts); and
    // the facts of each type argument as parts.
    void objectImportFacts(const ObjCObjectPointerType *opt, const std::string &prefix, int depth,
                           std::set<std::string> &out, std::set<const Type *> &seen) const {
        if (opt->isKindOfType()) out.insert(prefix + "kindof");
        const ObjCObjectType *obj = opt->getObjectType();
        const ObjCInterfaceDecl *qualified = opt->getInterfaceDecl();
        if (qualified && !qualified->hasDefinition()) out.insert(prefix + "forward-declared-class");
        bool osObject = opt->getNumProtocols() > 0;
        for (const ObjCProtocolDecl *p : opt->quals()) {
            if (!p->hasDefinition()) out.insert(prefix + "forward-declared-protocol");
            osObject = osObject && p->getName().starts_with("OS_");
        }
        // dispatch_queue_t and the other dispatch and os objects are
        // NSObject<OS_dispatch_queue> *: Swift imports them as its own classes.
        if (qualified && opt->getNumProtocols() > 0 && qualified->getName() == "NSObject")
            out.insert(prefix + (osObject ? "os-object" : "nsobject-qualified"));
        if (!obj || !obj->isSpecialized()) return;
        out.insert(prefix + "type-args");
        const ObjCInterfaceDecl *iface = opt->getInterfaceDecl();
        std::string name = iface ? iface->getName().str() : "";
        bool bridged = name == "NSArray" || name == "NSDictionary" || name == "NSSet";
        bool repository = iface && const_cast<SendVisitor *>(this)->declaredInRepo(iface);
        out.insert(prefix + (bridged ? "generic-bridged" : repository ? "generic-repository" : "generic-sdk"));
        // An NSSet element or NSDictionary key of protocol type (id<P>),
        // which Swift imports as AnyHashable.
        if ((name == "NSSet" || name == "NSDictionary") && !obj->getTypeArgs().empty()) {
            QualType key = obj->getTypeArgs()[0];
            if (const auto *kp = key->getAs<ObjCObjectPointerType>(); kp && kp->isObjCQualifiedIdType())
                out.insert(prefix + "protocol-key");
        }
        for (QualType arg : obj->getTypeArgs()) importFacts(arg, "in-", depth + 1, out, seen);
    }

    // A function's or block's facts: variadic or unprototyped, and the facts
    // of its result and parameters as parts.
    void functionImportFacts(const FunctionType *ft, const std::string &prefix, int depth, std::set<std::string> &out,
                             std::set<const Type *> &seen) const {
        if (isa<FunctionNoProtoType>(ft)) out.insert(prefix + "unprototyped-function");
        importFacts(ft->getReturnType(), "in-", depth + 1, out, seen);
        if (const auto *fp = dyn_cast<FunctionProtoType>(ft)) {
            if (fp->isVariadic()) out.insert(prefix + "variadic-function");
            for (QualType p : fp->param_types()) importFacts(p, "in-", depth + 1, out, seen);
        }
    }

    // A record's facts, from its fields and the fields of the records it
    // holds by value (directly or in arrays): bit-field-member,
    // flexible-array-member, object-member-<ownership> for an object or
    // block field (strong, weak, unsafe_unretained, autoreleasing, or
    // unqualified: no qualifier in a unit compiled without ARC); and the
    // facts of every field's type as parts.
    void recordImportFacts(const RecordDecl *def, const std::string &prefix, int depth, std::set<std::string> &out,
                           std::set<const Type *> &seen) const {
        if (def->hasFlexibleArrayMember()) out.insert(prefix + "flexible-array-member");
        for (const FieldDecl *fd : def->fields()) {
            if (fd->isBitField()) out.insert(prefix + "bit-field-member");
            QualType ft = fd->getType();
            if (ft->isConstantArrayType()) out.insert(prefix + "array-member");
            QualType el = ctx_.getBaseElementType(ft);
            if (el->isObjCRetainableType()) {
                Qualifiers::ObjCLifetime lt = el.getObjCLifetime();
                out.insert(prefix + "object-member-" + (lt == Qualifiers::OCL_None ? "unqualified" : lifetimeName(lt)));
            } else if (const auto *nested = el->getAs<RecordType>()) {
                const RecordDecl *nd = nested->getDecl()->getDefinition();
                if (nd && depth < 8 && seen.insert(nested).second) {
                    recordImportFacts(nd, prefix, depth + 1, out, seen);
                    seen.erase(nested);
                }
            }
            importFacts(ft, "in-", depth + 1, out, seen);
        }
    }

    TypeFacts typeFacts(QualType t, const FieldDecl *field) const {
        TypeFacts f;
        const PrintingPolicy &pp = ctx_.getPrintingPolicy();
        f.type = t.getAsString(pp);
        f.canonical = t.getCanonicalType().getAsString(pp);
        f.arc = arc_ ? 1 : 0;
        {
            std::set<std::string> words;
            std::set<const Type *> seen;
            importFacts(t, "", 0, words, seen);
            for (const std::string &w : words) f.importFacts += (f.importFacts.empty() ? "" : " ") + w;
        }
        // The encoding the compiler emits for an ivar in the class's ivar
        // list (with the field names of structures, as the runtime lists it).
        if (const auto *iv = dyn_cast_or_null<ObjCIvarDecl>(field)) ctx_.getObjCEncodingForType(iv->getType(), f.encoding, iv);
        QualType element = ctx_.getBaseElementType(t);
        if (field && field->isBitField()) {
            f.typeClass = "bit-field";
            f.bitWidth = (int)field->getBitWidthValue();
        } else if (t->isAtomicType()) {
            f.typeClass = "atomic";
        } else if (t->isArrayType()) {
            f.typeClass = "array";
        } else if (const auto *opt = t->getAs<ObjCObjectPointerType>()) {
            f.typeClass = "object";
            if (opt->isObjCIdType() || opt->isObjCQualifiedIdType()) f.objectClass = "id";
            else if (opt->isObjCClassType() || opt->isObjCQualifiedClassType()) f.objectClass = "Class";
            else if (const ObjCInterfaceDecl *iface = opt->getInterfaceDecl()) f.objectClass = iface->getName().str();
            for (const ObjCProtocolDecl *p : opt->quals()) f.protocols += (f.protocols.empty() ? "" : ",") + p->getName().str();
        } else if (t->isBlockPointerType()) {
            f.typeClass = "block";
        } else if (t->isObjCSelType()) {
            f.typeClass = "selector";
        } else if (t->isAnyPointerType() || t->isReferenceType() || t->isMemberPointerType()) {
            f.typeClass = "c-pointer";
        } else if (const auto *rt = t->getAs<RecordType>()) {
            const RecordDecl *rd = rt->getDecl();
            const auto *cxx = dyn_cast<CXXRecordDecl>(rd);
            const CXXRecordDecl *cxxDef = cxx ? cxx->getDefinition() : nullptr;
            f.typeClass = rd->isUnion() ? "union" : (cxxDef && !cxxDef->isCLike()) ? "cxx-object" : "struct";
            if (!rd->getName().empty()) f.recordName = rd->getName().str();
            else if (const TypedefNameDecl *td = rd->getTypedefNameForAnonDecl()) f.recordName = td->getName().str();
            f.hasObjects = recordHasObjects(rd, 0) ? 1 : 0;
        } else if (t->isVectorType()) {
            f.typeClass = "vector";
        } else if (t->isScalarType()) {
            f.typeClass = "scalar";
        } else {
            f.typeClass = "other";
        }
        // Ownership: of the element, for an array.
        if (!element->isObjCRetainableType()) {
            f.ownership = "none";
        } else {
            Qualifiers::ObjCLifetime lt = element.getObjCLifetime();
            if (arc_) f.ownership = lt == Qualifiers::OCL_None ? "unqualified" : lifetimeName(lt);
            else if (lt == Qualifiers::OCL_Weak && objcWeak_) f.ownership = "weak";
            else if (lt == Qualifiers::OCL_ExplicitNone) f.ownership = "unsafe_unretained";
            else f.ownership = "manual";
            // Written: an ownership qualifier spelled in the declaration (or
            // in a typedef it uses), not one ARC infers.
            QualType cur = element;
            for (int i = 0; i < 32; i++) {
                if (const auto *at = dyn_cast<AttributedType>(cur.getTypePtr());
                    at && at->getAttrKind() == attr::ObjCOwnership) {
                    f.ownershipWritten = lifetimeName(lt);
                    break;
                }
                QualType next = cur.getSingleStepDesugaredType(ctx_);
                if (next == cur) break;
                cur = next;
            }
        }
        return f;
    }

    // For a C pointer: 1 if every level it points through is const, 0 if not.
    // -1 for anything else (objects, blocks, scalars).
    static int pointeeConst(QualType t) {
        if (!t->isPointerType() || t->isObjCObjectPointerType() || t->isBlockPointerType()) return -1;
        while (t->isPointerType()) {
            t = t->getPointeeType();
            if (!t.isConstQualified()) return 0;
        }
        return 1;
    }

    std::string initKind(const VarDecl *vd) const {
        const Expr *init = vd->getInit();
        if (!init) return "none";
        // The zero initialization the compiler adds (a __strong static under
        // ARC, a trivial C++ default constructor) is none.
        const Expr *implicit = init->IgnoreImplicit();
        if (isa<ImplicitValueInitExpr>(implicit)) return "none";
        if (const auto *ctor = dyn_cast<CXXConstructExpr>(implicit);
            ctor && ctor->getNumArgs() == 0 && ctor->getConstructor()->isTrivial())
            return "none";
        const Expr *e = strip(init);
        if (const auto *uo = dyn_cast_or_null<UnaryOperator>(e);
            uo && (uo->getOpcode() == UO_Minus || uo->getOpcode() == UO_Plus))
            e = strip(uo->getSubExpr());
        if (isa_and_nonnull<StringLiteral>(e) || isa_and_nonnull<ObjCStringLiteral>(e) ||
            isa_and_nonnull<IntegerLiteral>(e) || isa_and_nonnull<FloatingLiteral>(e) ||
            isa_and_nonnull<CharacterLiteral>(e) || isa_and_nonnull<ObjCBoolLiteralExpr>(e) ||
            isa_and_nonnull<CXXBoolLiteralExpr>(e) || isa_and_nonnull<CXXNullPtrLiteralExpr>(e) ||
            isa_and_nonnull<GNUNullExpr>(e))
            return "literal";
        return init->isConstantInitializer(ctx_, vd->getType()->isReferenceType()) ? "constant" : "runtime";
    }

    // The property of this container (for an implementation, a property it
    // synthesizes or makes dynamic) whose getter or setter is md's selector.
    // ObjCMethodDecl::findPropertyDecl is not used: it reaches an unreachable
    // path for an accessor synthesized from a protocol's property.
    static const ObjCPropertyDecl *propertyOfAccessor(const ObjCMethodDecl *md, const ObjCContainerDecl *c) {
        Selector sel = md->getSelector();
        auto matches = [&](const ObjCPropertyDecl *pd) {
            if (!pd || pd->isClassProperty() != md->isClassMethod()) return false;
            return pd->getGetterName() == sel || pd->getSetterName() == sel;
        };
        if (const auto *impl = dyn_cast<ObjCImplDecl>(c)) {
            for (const ObjCPropertyImplDecl *pid : impl->property_impls())
                if (matches(pid->getPropertyDecl())) return pid->getPropertyDecl();
            return nullptr;
        }
        for (const ObjCPropertyDecl *pd : c->properties())
            if (matches(pd)) return pd;
        return nullptr;
    }

    void recordMethod(const ObjCMethodDecl *md, const ObjCContainerDecl *c, const ContainerInfo &ci,
                      bool implementation) {
        SourceLocation loc = md->getSelectorStartLoc();
        if (loc.isInvalid()) loc = md->getLocation();
        MethodRow row;
        if (!locate(loc, row) || isBuildProduct(row.file)) return;
        row.usr = usr(md);
        row.selector = md->getSelector().getAsString();
        row.isClassMethod = md->isClassMethod() ? 1 : 0;
        row.containerUSR = ci.usr;
        row.containerName = ci.name;
        row.containerKind = ci.kind;
        row.className = ci.className;
        row.isDefinition = md->hasBody() ? 1 : 0;
        row.isImplicit = md->isImplicit() ? 1 : 0;
        row.isSynthesized = md->isSynthesizedAccessorStub() ? 1 : 0;
        row.isOptional = md->isOptional() ? 1 : 0;
        if (const ObjCPropertyDecl *pd = propertyOfAccessor(md, c)) row.propertyUSR = usr(pd);
        row.returnType = md->getReturnType().getAsString(ctx_.getPrintingPolicy());
        row.typeEncoding = ctx_.getObjCEncodingForMethodDecl(md);
        row.claimFile = ci.claimFile;
        SmallVector<const ObjCMethodDecl *, 4> overridden;
        md->getOverriddenMethods(overridden);
        std::set<const ObjCMethodDecl *> overriddenSeen;
        for (const ObjCMethodDecl *om : overridden) {
            if (!overriddenSeen.insert(om).second) continue;
            OverrideRow o;
            o.usr = usr(om);
            const auto *oc = dyn_cast<ObjCContainerDecl>(om->getDeclContext());
            containerNameAndKind(oc, o.container, o.containerKind);
            SourceLocation oloc = sm_.getExpansionLoc(om->getLocation());
            if (oloc.isValid()) {
                FileID fid = sm_.getFileID(oloc);
                o.file = filePath(fid);
                o.line = sm_.getExpansionLineNumber(oloc);
                o.outsideRepository = fileInRepo(fid) ? 0 : 1;
                o.ownerParsed = !o.outsideRepository && !sm_.isLoadedFileID(fid) && ownerIsSource(o.file) ? 1 : 0;
            } else {
                o.outsideRepository = 1;
            }
            if (const auto *cat = dyn_cast_or_null<ObjCCategoryDecl>(oc)) {
                if (const ObjCInterfaceDecl *iface = cat->getClassInterface()) {
                    o.className = iface->getName().str();
                    o.classParsed = classCodeParsed(iface) ? 1 : 0;
                    if (!o.classParsed) o.ownerParsed = 0;
                }
            }
            o.isOptionalRequirement = isa_and_nonnull<ObjCProtocolDecl>(oc) && om->isOptional() ? 1 : 0;
            row.overrides.push_back(std::move(o));
        }
        results_.methods.push_back(std::move(row));
    }

    // Whether the code that owns a declaration is parsed into this database,
    // by the rule of owner_parsed.
    bool declarationOwnerParsed(const Decl *d) {
        SourceLocation loc = sm_.getExpansionLoc(d->getLocation());
        if (loc.isInvalid()) return false;
        FileID fid = sm_.getFileID(loc);
        return fileInRepo(fid) && !sm_.isLoadedFileID(fid) && ownerIsSource(filePath(fid));
    }

    // Whether the code of a class is parsed into this database: its
    // @interface's owner is parsed (declarationOwnerParsed), and the class is
    // not one that a source file (not a header) declares without this unit
    // holding its @implementation, which is how the repository declares a
    // private SDK class (NSThemeFrame in PTYWindow.m).
    bool classCodeParsed(const ObjCInterfaceDecl *iface) {
        const ObjCInterfaceDecl *def = iface->getDefinition() ? iface->getDefinition() : iface;
        if (!declarationOwnerParsed(def)) return false;
        if (def->getImplementation()) return true;
        return !isSourceFile(filePath(sm_.getFileID(sm_.getExpansionLoc(def->getLocation()))));
    }

    static bool isSourceFile(const std::string &path) {
        for (const char *ext : {".m", ".mm", ".c", ".cpp", ".cc", ".cxx"}) {
            size_t n = strlen(ext);
            if (path.size() >= n && path.compare(path.size() - n, n, ext) == 0) return true;
        }
        return false;
    }

    // Whether a stored path in the repository can hold source this database
    // parses: not inside a .framework bundle, not a generated -Swift.h.
    static bool ownerIsSource(const std::string &stored) {
        if (stored.find(".framework/") != std::string::npos) return false;
        static const std::string swiftHeader = "-Swift.h";
        return !(stored.size() >= swiftHeader.size() &&
                 stored.compare(stored.size() - swiftHeader.size(), swiftHeader.size(), swiftHeader) == 0);
    }

    // The name and kind of an Objective-C container, as objc_method's
    // container_name and container_kind give them.
    static void containerNameAndKind(const ObjCContainerDecl *c, std::string &name, std::string &kind) {
        if (const auto *iface = dyn_cast_or_null<ObjCInterfaceDecl>(c)) {
            kind = "interface";
            name = iface->getName().str();
        } else if (const auto *cat = dyn_cast_or_null<ObjCCategoryDecl>(c)) {
            kind = cat->IsClassExtension() ? "extension" : "category";
            name = (cat->getClassInterface() ? cat->getClassInterface()->getName().str() : "") + "(" +
                   cat->getName().str() + ")";
        } else if (const auto *proto = dyn_cast_or_null<ObjCProtocolDecl>(c)) {
            kind = "protocol";
            name = proto->getName().str();
        } else if (const auto *impl = dyn_cast_or_null<ObjCImplementationDecl>(c)) {
            kind = "implementation";
            name = impl->getName().str();
        } else if (const auto *catImpl = dyn_cast_or_null<ObjCCategoryImplDecl>(c)) {
            kind = "category-implementation";
            name = (catImpl->getClassInterface() ? catImpl->getClassInterface()->getName().str() : "") + "(" +
                   catImpl->getName().str() + ")";
        } else {
            kind = "unknown";
            name = "?";
        }
    }

    static std::string attributesText(const ObjCPropertyDecl *pd) {
        unsigned a = pd->getPropertyAttributesAsWritten();
        std::vector<std::string> out;
        auto add = [&](unsigned bit, const char *name) {
            if (a & bit) out.push_back(name);
        };
        add(ObjCPropertyAttribute::kind_class, "class");
        add(ObjCPropertyAttribute::kind_direct, "direct");
        add(ObjCPropertyAttribute::kind_atomic, "atomic");
        add(ObjCPropertyAttribute::kind_nonatomic, "nonatomic");
        add(ObjCPropertyAttribute::kind_readonly, "readonly");
        add(ObjCPropertyAttribute::kind_readwrite, "readwrite");
        add(ObjCPropertyAttribute::kind_assign, "assign");
        add(ObjCPropertyAttribute::kind_retain, "retain");
        add(ObjCPropertyAttribute::kind_copy, "copy");
        add(ObjCPropertyAttribute::kind_strong, "strong");
        add(ObjCPropertyAttribute::kind_weak, "weak");
        add(ObjCPropertyAttribute::kind_unsafe_unretained, "unsafe_unretained");
        add(ObjCPropertyAttribute::kind_null_resettable, "null_resettable");
        if (a & ObjCPropertyAttribute::kind_nullability) {
            if (auto n = pd->getType()->getNullability())
                out.push_back(getNullabilitySpelling(*n, /*isContextSensitive=*/true).str());
        }
        if (a & ObjCPropertyAttribute::kind_getter) out.push_back("getter=" + pd->getGetterName().getAsString());
        if (a & ObjCPropertyAttribute::kind_setter) out.push_back("setter=" + pd->getSetterName().getAsString());
        std::string joined;
        for (size_t i = 0; i < out.size(); i++) joined += (i ? "," : "") + out[i];
        return joined;
    }

    void fillProperty(PropertyRow &row, const ObjCPropertyDecl *pd, const ContainerInfo &ci) {
        row.usr = usr(pd);
        row.name = pd->getName().str();
        row.isClassProperty = pd->isClassProperty() ? 1 : 0;
        row.containerUSR = ci.usr;
        row.containerName = ci.name;
        row.containerKind = ci.kind;
        row.className = ci.className;
        row.getter = pd->getGetterName().getAsString();
        row.attributes = attributesText(pd);
        row.type = pd->getType().getAsString(ctx_.getPrintingPolicy());
        row.claimFile = ci.claimFile;
    }

    void recordPropertyDeclaration(const ObjCPropertyDecl *pd, const ContainerInfo &ci) {
        PropertyRow row;
        if (!locate(pd->getLocation(), row) || isBuildProduct(row.file)) return;
        fillProperty(row, pd, ci);
        row.kind = "declaration";
        // As written: the compiler marks a readonly property readwrite when a
        // class extension in the same unit redeclares it so.
        row.isReadonly = (pd->getPropertyAttributesAsWritten() & ObjCPropertyAttribute::kind_readonly) ? 1 : 0;
        if (!row.isReadonly) row.setter = pd->getSetterName().getAsString();
        row.isImplicit = pd->isImplicit() ? 1 : 0;
        results_.properties.push_back(std::move(row));
    }

    void recordPropertyImpl(const ObjCPropertyImplDecl *pid, const ContainerInfo &ci) {
        const ObjCPropertyDecl *pd = pid->getPropertyDecl();
        if (!pd) return;
        // A property the compiler synthesizes has no location of its own: it
        // is recorded at the property's declaration.
        bool automatic = pid->getLocation().isInvalid();
        PropertyRow row;
        if (!locate(automatic ? pd->getLocation() : pid->getLocation(), row) || isBuildProduct(row.file)) return;
        fillProperty(row, pd, ci);
        row.claimFile.clear();
        row.kind = pid->getPropertyImplementation() == ObjCPropertyImplDecl::Dynamic ? "dynamic" : "synthesize";
        row.isReadonly = pd->isReadOnly() ? 1 : 0;
        if (!row.isReadonly) row.setter = pd->getSetterName().getAsString();
        if (const ObjCIvarDecl *ivar = pid->getPropertyIvarDecl()) {
            row.ivarName = ivar->getName().str();
            row.ivarUSR = usr(ivar);
        }
        row.isImplicit = automatic ? 1 : 0;
        results_.properties.push_back(std::move(row));
    }

    // --- Reflective calls ---------------------------------------------------

    ReflectiveRow reflectiveRow(const Located &where, const ReflectiveName &e, const Expr *arg, const Expr *classArg) {
        ReflectiveRow r;
        static_cast<Located &>(r) = where;
        r.callKind = e.message ? "message" : "function";
        r.kind = e.names;
        r.argumentIndex = e.argument;
        ArgumentDescription d = describe(arg, e.names, 0);
        r.argumentKind = d.kind;
        r.argumentText = d.text;
        r.argumentConstant = d.constant;
        r.resolvedSelector = d.selector;
        r.resolvedClass = d.cls;
        if (classArg && r.resolvedClass.empty()) r.resolvedClass = classNameOf(classArg);
        enclose(r.enclosingUSR, r.enclosingName, r.inBlock);
        return r;
    }

    // The selector of @selector(x) or NSStringFromSelector(@selector(x)).
    static bool selectorExpression(const Expr *e, std::string &selector) {
        e = strip(e);
        if (const auto *se = dyn_cast_or_null<ObjCSelectorExpr>(e)) {
            selector = se->getSelector().getAsString();
            return true;
        }
        const auto *call = dyn_cast_or_null<CallExpr>(e);
        if (call && call->getNumArgs() == 1 && calledFunction(call) == "NSStringFromSelector") {
            if (const auto *se = dyn_cast<ObjCSelectorExpr>(strip(call->getArg(0)))) {
                selector = se->getSelector().getAsString();
                return true;
            }
        }
        return false;
    }

    // The text of a string literal, an Objective-C string literal or a boxed
    // C string literal (adjacent literals are already joined).
    static bool literalText(const Expr *e, std::string &text) {
        e = strip(e);
        if (const auto *ol = dyn_cast_or_null<ObjCStringLiteral>(e)) e = ol->getString();
        else if (const auto *boxed = dyn_cast_or_null<ObjCBoxedExpr>(e)) e = strip(boxed->getSubExpr());
        const auto *sl = dyn_cast_or_null<StringLiteral>(e);
        if (!sl || sl->getCharByteWidth() != 1) return false;
        text = sl->getString().str();
        return true;
    }

    // The name of the object-like macro, made only of string literals, that
    // the literal was expanded from, or "".
    std::string literalMacro(const Expr *e) const {
        e = strip(e);
        SourceLocation loc = e->getBeginLoc();
        if (!loc.isMacroID() || sm_.isMacroArgExpansion(loc)) return "";
        SourceLocation nameLoc = sm_.getImmediateExpansionRange(loc).getBegin();
        auto it = facts_.literalMacros.find(nameLoc.getRawEncoding());
        return it == facts_.literalMacros.end() ? "" : it->second;
    }

    ArgumentDescription describe(const Expr *raw, const std::string &names, int depth) {
        ArgumentDescription d;
        const Expr *e = strip(raw);
        std::string text;
        // A null selector, class or key names nothing; _cmd is the selector
        // of the enclosing method. Neither is resolved.
        // (nil is ((void *)0); a cast such as (id)0 counts as well. The
        // argument must be a pointer: a recognized selector such as a
        // protobuf message's setAction: can take an enum, whose 0 is not
        // nil.)
        QualType argType = raw ? raw->getType() : QualType();
        bool pointer = !argType.isNull() && (argType->isAnyPointerType() || argType->isBlockPointerType() ||
                                             argType->isObjCSelType() || argType->isObjCIdType() ||
                                             argType->isObjCClassType());
        if (pointer && e && e->isNullPointerConstant(ctx_, Expr::NPC_ValueDependentIsNotNull) != Expr::NPCK_NotNull) {
            d.kind = "nil";
            d.text = spelling(unwrapOpaque(raw));
            return d;
        }
        if (const auto *dre = dyn_cast_or_null<DeclRefExpr>(e)) {
            const auto *ipd = dyn_cast<ImplicitParamDecl>(dre->getDecl());
            if (ipd && ipd->getParameterKind() == ImplicitParamKind::ObjCCmd) {
                d.kind = "self-selector";
                d.text = spelling(unwrapOpaque(raw));
                return d;
            }
        }
        if (selectorExpression(e, text)) {
            d.kind = "selector-expr";
            d.text = d.selector = text;
        } else if (literalText(e, text)) {
            d.text = text;
            d.constant = literalMacro(e);
            d.kind = d.constant.empty() ? "string-literal" : "constant";
        } else if (const auto *dre = dyn_cast_or_null<DeclRefExpr>(e)) {
            // Only a const variable is followed to its initializer: any
            // other, static or not, can be assigned another value.
            const auto *vd = dyn_cast<VarDecl>(dre->getDecl());
            const Expr *init = vd ? vd->getAnyInitializer() : nullptr;
            bool constant = vd && vd->getType().isConstQualified();
            if (constant && init && selectorExpression(init, text)) {
                d.kind = "constant";
                d.text = d.selector = text;
                d.constant = vd->getName().str();
            } else if (constant && init && literalText(init, text)) {
                d.kind = "constant";
                d.text = text;
                d.constant = vd->getName().str();
            }
        } else if (const auto *call = dyn_cast_or_null<CallExpr>(e)) {
            // A call that turns a literal or constant into a selector, class,
            // protocol or method counts as that literal or constant.
            std::string fn = calledFunction(call);
            if (depth == 0 && !fn.empty()) {
                for (const ReflectiveName *inner : reflectiveIndex().match(fn, false)) {
                    std::string innerNames = inner->names;
                    if (innerNames == "method" || (unsigned)inner->argument >= call->getNumArgs()) continue;
                    bool fits = innerNames == names || (names == "method" && innerNames == "selector");
                    if (!fits) continue;
                    ArgumentDescription in = describe(call->getArg(inner->argument), innerNames, depth + 1);
                    if (in.kind == "dynamic" || in.kind == "self-selector") break;
                    if (in.kind == "nil") {
                        // NSSelectorFromString(nil) is nil too.
                        d.kind = "nil";
                        d.text = spelling(unwrapOpaque(raw));
                        return d;
                    }
                    d = in;
                    if (names == "method" && inner->classArgument >= 0 &&
                        (unsigned)inner->classArgument < call->getNumArgs())
                        d.cls = classNameOf(call->getArg(inner->classArgument));
                    break;
                }
            }
        }
        if (d.kind.empty()) {
            d = ArgumentDescription();
            d.kind = "dynamic";
            d.text = spelling(unwrapOpaque(raw));
            return d;
        }
        if (names == "selector" || names == "method") d.selector = d.text;
        else if (names == "class" || names == "protocol") d.cls = d.text;
        return d;
    }

    // The class an argument names: [Name class], or a class function with a
    // literal name. "" otherwise.
    std::string classNameOf(const Expr *e) {
        e = strip(e);
        if (const auto *m = dyn_cast_or_null<ObjCMessageExpr>(e)) {
            if (m->getReceiverKind() == ObjCMessageExpr::Class && m->getSelector().getAsString() == "class")
                if (const ObjCInterfaceDecl *iface = m->getReceiverInterface()) return iface->getName().str();
            return "";
        }
        if (const auto *call = dyn_cast_or_null<CallExpr>(e)) {
            std::string fn = calledFunction(call);
            for (const ReflectiveName *inner : reflectiveIndex().match(fn, false)) {
                if (std::string(inner->names) != "class" || (unsigned)inner->argument >= call->getNumArgs()) continue;
                ArgumentDescription in = describe(call->getArg(inner->argument), "class", 1);
                return in.kind == "dynamic" ? "" : in.text;
            }
        }
        return "";
    }

    // The source text of an expression, on one line, at most 200 bytes.
    std::string spelling(const Expr *e) const {
        if (!e) return "";
        const LangOptions &lo = ctx_.getLangOpts();
        CharSourceRange range =
            Lexer::makeFileCharRange(CharSourceRange::getTokenRange(e->getSourceRange()), sm_, lo);
        if (range.isInvalid()) {
            CharSourceRange exp = sm_.getExpansionRange(e->getSourceRange());
            range = Lexer::makeFileCharRange(exp, sm_, lo);
        }
        if (range.isInvalid()) return "";
        StringRef text = Lexer::getSourceText(range, sm_, lo);
        std::string out;
        bool space = false;
        for (char c : text) {
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                space = !out.empty();
                continue;
            }
            if (space) out.push_back(' ');
            space = false;
            out.push_back(c);
        }
        if (out.size() > 200) {
            size_t n = 200;
            while (n > 0 && (static_cast<unsigned char>(out[n]) & 0xC0) == 0x80) n--;
            out.resize(n);
        }
        return out;
    }

    // --- Shared ---------------------------------------------------------------

    bool isEnclosingDecl(const Decl *d) const {
        if (isa<ObjCMethodDecl>(d)) return true;
        // A lambda's body is traversed from the LambdaExpr, not through its call
        // operator's declaration, so the enclosing function stays the outer one.
        if (isa<FunctionDecl>(d)) return true;
        // A variable at file scope or a static member: its initializer can
        // contain sends (blocks assigned to globals, ObjC++ initializers).
        if (const auto *vd = dyn_cast<VarDecl>(d)) return !vd->isLocalVarDeclOrParm() && frames_.size() == 1;
        return false;
    }

    const Frame *innermostDecl() const {
        for (auto it = frames_.rbegin(); it != frames_.rend(); ++it)
            if (it->decl) return &*it;
        return nullptr;
    }

    int blockDepthSinceEnclosing() const {
        int depth = 0;
        for (auto it = frames_.rbegin(); it != frames_.rend(); ++it) {
            depth += it->blockDepth;
            if (it->decl) break;
        }
        return depth;
    }

    static int classifyPseudoObject(Expr *syntactic) {
        Expr *e = syntactic->IgnoreParens();
        while (true) {
            if (auto *bo = dyn_cast<BinaryOperator>(e)) { e = bo->getLHS()->IgnoreParens(); continue; }
            if (auto *uo = dyn_cast<UnaryOperator>(e)) { e = uo->getSubExpr()->IgnoreParens(); continue; }
            break;
        }
        if (isa<ObjCSubscriptRefExpr>(e)) return kSubscriptAccessor;
        if (isa<ObjCPropertyRefExpr>(e)) return kPropertyAccessor;
        return kExplicit;
    }

    std::string usr(const Decl *d) const {
        SmallString<128> buf;
        if (index::generateUSRForDecl(d, buf)) return "";
        return std::string(buf.str());
    }

    static std::string displayName(const Decl *d) {
        if (const auto *md = dyn_cast<ObjCMethodDecl>(d)) {
            std::string cls;
            if (const ObjCInterfaceDecl *iface = md->getClassInterface()) cls = iface->getName().str();
            const DeclContext *dc = md->getDeclContext();
            if (const auto *cat = dyn_cast<ObjCCategoryImplDecl>(dc)) cls += "(" + cat->getName().str() + ")";
            else if (const auto *cat = dyn_cast<ObjCCategoryDecl>(dc)) cls += "(" + cat->getName().str() + ")";
            return std::string(md->isInstanceMethod() ? "-[" : "+[") + cls + " " +
                   md->getSelector().getAsString() + "]";
        }
        if (const auto *nd = dyn_cast<NamedDecl>(d)) return nd->getQualifiedNameAsString();
        return "";
    }

    bool fileInRepo(FileID fid) {
        auto it = inRepo_.find(fid);
        if (it != inRepo_.end()) return it->second;
        std::string p = fileEntryPath(sm_.getFileEntryRefForID(fid));
        bool in = !p.empty() && paths_.inRepo(p);
        inRepo_[fid] = in;
        return in;
    }

    std::string filePath(FileID fid) {
        auto it = pathCache_.find(fid);
        if (it != pathCache_.end()) return it->second;
        std::string p = paths_.store(fileEntryPath(sm_.getFileEntryRefForID(fid)));
        pathCache_[fid] = p;
        return p;
    }

    ASTContext &ctx_;
    SourceManager &sm_;
    const PathMapper &paths_;
    const PreprocessorFacts &facts_;
    Results &results_;
    std::vector<Frame> frames_;
    std::vector<int> implicitKinds_;
    int unevaluated_ = 0;
    std::set<const ObjCMessageExpr *> seen_;
    // "Unreachable code": the row of each recorded send, and the successor
    // of a folded if or conditional operator that CodeGen does not emit.
    std::unordered_map<const Stmt *, size_t> sendRowOf_;
    std::unordered_map<const Stmt *, unsigned> skippedSuccessor_;
    std::unordered_set<const CallExpr *> seenCalls_;
    std::unordered_set<const ObjCSelectorExpr *> seenSelectors_;
    std::unordered_set<const ObjCContainerDecl *> seenContainers_;
    std::unordered_set<const ObjCIvarRefExpr *> seenIvarRefs_;
    std::unordered_set<const DeclRefExpr *> seenDeclRefs_;
    std::unordered_set<const VarDecl *> seenVars_;
    // The access an operator gives the ivar or variable reference at the
    // root of its operand (markAccess), and whether it is to a part of it.
    std::unordered_map<const Expr *, std::pair<const char *, int>> marks_;
    // The blocks passed to dispatch_once, and how many are being traversed.
    std::unordered_set<const BlockExpr *> onceBlocks_;
    int onceDepth_ = 0;
    // The retain hint of an ivar reference (markHint).
    std::unordered_map<const Expr *, const char *> hints_;
    // References in __builtin_object_size are not recorded.
    int objectSize_ = 0;
    std::vector<const LambdaExpr *> lambdas_;
    std::vector<std::string> syncLocks_;
    // The references function_ref has counted (a node can be reached twice).
    std::unordered_set<const Expr *> seenFunctionRefs_;
    // Where each ivar_ref and static_ref row is, by keepReference's key.
    std::unordered_map<std::string, size_t> ivarRefIndex_, staticRefIndex_;
    bool arc_, objcWeak_;
    std::map<FileID, bool> inRepo_;
    std::map<FileID, std::string> pathCache_;
    SmallString<64> nameBuf_;
    std::vector<SourceLocation> compounds_;
    std::set<std::pair<const void *, std::string>> seenMacroNodes_;
    std::unordered_set<std::string> sdkSeen_;
    // The branches constant conditions skip, with the condition's place, and
    // those being traversed (innermost last).
    std::unordered_map<const Stmt *, std::pair<std::string, unsigned>> deadRoots_;
    std::vector<std::pair<std::string, unsigned>> dead_;
    // The expressions that are part of a branch condition
    // (noteBranchCondition).
    std::unordered_set<const Expr *> branchConditions_;
};

// Paths whose inputs are not recorded: the SDK and clang's resource directory.
struct ExcludedInputs {
    std::vector<std::string> prefixes;

    void add(const std::string &dir) {
        if (dir.empty()) return;
        for (const std::string &p : {dir, realPath(dir)}) {
            std::string withSlash = p.back() == '/' ? p : p + "/";
            prefixes.push_back(withSlash);
        }
    }

    bool contains(const std::string &path) const {
        for (const std::string &p : prefixes)
            if (path.compare(0, p.size(), p) == 0) return true;
        return false;
    }
};

class SendConsumer : public ASTConsumer {
public:
    SendConsumer(CompilerInstance &ci, const PathMapper &paths, const ExcludedInputs &excluded, Results &results,
                 PreprocessorFacts &facts, const PriorClaims &prior)
        : ci_(ci), paths_(paths), excluded_(excluded), results_(results), facts_(facts), prior_(prior) {}

    bool HandleTopLevelDecl(DeclGroupRef group) override {
        for (Decl *d : group) topLevel_.push_back(d);
        return true;
    }

    void HandleTopLevelDeclInObjCContainer(DeclGroupRef group) override {
        for (Decl *d : group) topLevel_.push_back(d);
    }

    void HandleTranslationUnit(ASTContext &ctx) override {
        SendVisitor visitor(ctx, paths_, facts_, results_);
        for (Decl *d : topLevel_) {
            if (visitor.shouldTraverseTopLevel(d)) visitor.TraverseDecl(d);
        }
        std::set<std::string> done;
        collectViews(ctx);
        collectInputs(ctx.getSourceManager(), done);
        collectModuleInputs(done);
        recordModulesAndOutside(visitor, ctx);
        finishPreprocessorTables();
    }

private:
    // The claim key of a declaration outside the repository: its top-level
    // module, or "textual:" and its header's path for one parsed from a
    // header that is not in a module (units include different headers of a
    // framework textually, so the header is the unit of the claim); then the
    // configuration (configKey).
    std::string moduleKey(const Decl *d, SendVisitor &v) {
        if (const Module *m = d->getOwningModule()) return m->getTopLevelModuleName().str() + configKey();
        return "textual:" + v.headerOf(d) + configKey();
    }

    // What a header's declarations depend on besides its text: the OS and
    // deployment target (availability #if) and Objective-C++ (__cplusplus),
    // as " macosx13.0" or " macosx13.0 objc++".
    std::string configKey() {
        if (!config_.empty()) return config_;
        const llvm::Triple &t = ci_.getTarget().getTriple();
        VersionTuple v = t.getOSVersion();
        config_ = " " + llvm::Triple::getOSTypeName(t.getOS()).str() + std::to_string(v.getMajor()) + "." +
                  std::to_string(v.getMinor().value_or(0));
        if (ci_.getLangOpts().CPlusPlus) config_ += " objc++";
        return config_;
    }

    // The declarations this unit does not parse itself (see "Declarations
    // read through a module" and "Classes and the SDK" at the top of this
    // file): those of the repository files it reads only through a module,
    // and the containers outside the repository, each recorded only when no
    // other unit holds the claim on them. Iterating the translation unit's
    // declarations deserializes every module the unit loaded, so it is done
    // only when there is something unclaimed to record.
    void recordModulesAndOutside(SendVisitor &v, ASTContext &ctx) {
        std::set<std::string> loaded;
        IntrusiveRefCntPtr<ASTReader> reader = ci_.getASTReader();
        if (reader) {
            for (serialization::ModuleFile &mf : reader->getModuleManager())
                if (mf.Kind == serialization::MK_ImplicitModule || mf.Kind == serialization::MK_ExplicitModule)
                    loaded.insert(mf.ModuleName + configKey());
        }
        std::set<std::string> fromModules = loaded;
        std::vector<std::pair<ObjCContainerDecl *, std::string>> textual;
        for (Decl *d : topLevel_) {
            auto *c = dyn_cast<ObjCContainerDecl>(d);
            if (!c || c->isFromASTFile() || !v.declaredOutsideRepo(c)) continue;
            std::string key = moduleKey(c, v);
            loaded.insert(key);
            textual.push_back({c, key});
        }
        std::set<std::string> want;
        for (const std::string &k : loaded)
            if (!prior_.modules.count(k)) want.insert(k);
        bool repoFiles = false;
        for (const InputRow &in : results_.inputs)
            if (in.viaModule && !in.path.empty() && in.path[0] != '/' && !isBuildProduct(in.path) &&
                !prior_.moduleFiles.count({in.path, in.digest}))
                repoFiles = true;
        for (auto &kv : textual)
            if (want.count(kv.second)) v.recordSdkContainer(kv.first, kv.second);
        bool walk = repoFiles;
        for (const std::string &k : want)
            if (fromModules.count(k)) walk = true;
        if (walk) walkModuleDecls(v, ctx.getTranslationUnitDecl(), want, repoFiles);
        results_.loadedModules = std::move(loaded);
        results_.walkedModules = std::move(want);
        results_.walkedModuleFiles = repoFiles;
    }

    // The function and method bodies a declaration read through a module
    // holds: a function (or function template) definition, the methods of
    // an @implementation, and the methods defined in a C++ record.
    static int bodiesIn(const Decl *d) {
        if (const auto *ft = dyn_cast<FunctionTemplateDecl>(d)) d = ft->getTemplatedDecl();
        if (const auto *ct = dyn_cast<ClassTemplateDecl>(d)) d = ct->getTemplatedDecl();
        if (const auto *fd = dyn_cast<FunctionDecl>(d)) return fd->doesThisDeclarationHaveABody() ? 1 : 0;
        int n = 0;
        if (const auto *impl = dyn_cast<ObjCImplDecl>(d)) {
            for (const ObjCMethodDecl *md : impl->methods())
                if (md->hasBody()) n++;
        } else if (const auto *rd = dyn_cast<CXXRecordDecl>(d)) {
            for (const Decl *member : rd->decls())
                if (member != rd) n += bodiesIn(member);
        }
        return n;
    }

    void walkModuleDecls(SendVisitor &v, DeclContext *dc, const std::set<std::string> &want, bool repoFiles) {
        for (Decl *d : dc->decls()) {
            if (isa<LinkageSpecDecl>(d) || isa<ExportDecl>(d) || isa<NamespaceDecl>(d)) {
                walkModuleDecls(v, cast<DeclContext>(d), want, repoFiles);
                continue;
            }
            if (!d->isFromASTFile() || d->getLocation().isInvalid()) continue;
            if (!v.declaredOutsideRepo(d)) {
                if (repoFiles) {
                    v.recordModuleDeclaration(d);
                    results_.moduleBodiesSkipped += bodiesIn(d);
                }
                continue;
            }
            auto *c = dyn_cast<ObjCContainerDecl>(d);
            if (!c) continue;
            std::string key = moduleKey(c, v);
            if (want.count(key)) v.recordSdkContainer(c, key);
        }
    }

    // The enclosing function of each expansion, the value of each #else, and
    // the expansion graph; then the preprocessor tables move to results_.
    void finishPreprocessorTables() {
        std::map<FileID, std::vector<const EnclosingRange *>> byFile;
        for (const EnclosingRange &r : results_.enclosingRanges) byFile[r.fid].push_back(&r);
        std::map<FileID, std::vector<unsigned>> maxEnd;
        for (auto &kv : byFile) {
            std::sort(kv.second.begin(), kv.second.end(),
                      [](const EnclosingRange *a, const EnclosingRange *b) { return a->begin < b->begin; });
            std::vector<unsigned> &m = maxEnd[kv.first];
            unsigned best = 0;
            for (const EnclosingRange *r : kv.second) m.push_back(best = std::max(best, r->end));
        }
        for (MacroExpansionRec &x : facts_.expansions) {
            auto it = byFile.find(x.siteFid);
            if (it == byFile.end()) continue;
            const auto &list = it->second;
            const auto &m = maxEnd[x.siteFid];
            // The innermost range with begin < site <= end.
            size_t hi = std::lower_bound(list.begin(), list.end(), x.siteOffset,
                                         [](const EnclosingRange *r, unsigned off) { return r->begin < off; }) -
                        list.begin();
            const EnclosingRange *best = nullptr;
            for (size_t i = hi; i-- > 0;) {
                if (m[i] < x.siteOffset) break;
                const EnclosingRange *r = list[i];
                if (r->end >= x.siteOffset && (!best || r->end - r->begin < best->end - best->begin)) best = r;
            }
            if (best) {
                x.enclosingUSR = best->usr;
                x.enclosingName = best->name;
            }
        }
        std::set<std::pair<std::string, unsigned>> skipStarts;
        for (const SkipRec &r : facts_.skips) skipStarts.insert({r.file, r.startLine});
        for (CondRec &c : facts_.conds) {
            if (c.directive == "else") c.values.insert(skipStarts.count({c.file, c.line}) ? "false" : "true");
            if (c.values.empty()) c.values.insert("not-evaluated");
        }
        for (const auto &e : facts_.bodyExpands) results_.macroFacts[std::make_tuple(e.first, std::string("expands"), e.second)]++;
        results_.macroDefs = std::move(facts_.defs);
        results_.macroUndefs = std::move(facts_.undefs);
        results_.macroExpansions = std::move(facts_.expansions);
        results_.otherMacroCounts = std::move(facts_.otherCounts);
        results_.conds = std::move(facts_.conds);
        results_.skips = std::move(facts_.skips);
    }

    // The view of each file the unit read (see the top of this file): the
    // language and the ranges the preprocessor skipped in it. Files with no
    // skipped range share the language-only view.
    void collectViews(ASTContext &ctx) {
        const LangOptions &lo = ctx.getLangOpts();
        language_ = lo.ObjC ? (lo.CPlusPlus ? "objective-c++" : "objective-c") : (lo.CPlusPlus ? "c++" : "c");
        // ARC changes the types of a header's ivars and globals, so a header
        // read with and without it has two views.
        if (lo.ObjCAutoRefCount) language_ += " arc";
        SourceManager &sm = ctx.getSourceManager();
        std::map<std::string, std::set<std::pair<unsigned, unsigned>>> byPath;
        for (const auto &kv : facts_.skipped) {
            std::string path = fileEntryPath(sm.getFileEntryRefForID(kv.first));
            if (path.empty()) continue;
            byPath[path].insert(kv.second.begin(), kv.second.end());
        }
        for (const auto &kv : byPath) {
            std::string text = language_;
            for (const auto &r : kv.second) text += " " + std::to_string(r.first) + "-" + std::to_string(r.second);
            views_[kv.first] = hexSHA256(text.data(), text.size()).substr(0, 16);
        }
        plainView_ = hexSHA256(language_.data(), language_.size()).substr(0, 16);
    }

    std::string viewOf(const std::string &path) const {
        auto it = views_.find(path);
        return it == views_.end() ? plainView_ : it->second;
    }

    void addInput(const std::string &path, std::set<std::string> &done) {
        if (path.empty() || !done.insert(path).second) return;
        auto file = llvm::MemoryBuffer::getFile(path);
        if (!file) return;
        results_.inputs.push_back(
            {paths_.store(path), hexSHA256((*file)->getBufferStart(), (*file)->getBufferSize()), "", true});
    }

    // The input files (module maps and headers) of every module file the unit
    // loaded. They are not in the unit's own source locations: a module's
    // headers are read from its module file. Those under the SDK or the
    // resource directory are skipped before anything is read.
    void collectModuleInputs(std::set<std::string> &done) {
        IntrusiveRefCntPtr<ASTReader> reader = ci_.getASTReader();
        if (!reader) return;
        for (serialization::ModuleFile &mf : reader->getModuleManager()) {
            reader->visitInputFileInfos(mf, /*IncludeSystem=*/true,
                                        [&](const serialization::InputFileInfo &info, bool) {
                StringRef name = info.UnresolvedImportedFilename.empty() ? info.UnresolvedImportedFilenameAsRequested
                                                                          : info.UnresolvedImportedFilename;
                if (name.empty()) return;
                SmallString<256> path;
                if (!llvm::sys::path::is_absolute(name)) path = mf.BaseDirectory;
                llvm::sys::path::append(path, name);
                llvm::sys::path::remove_dots(path, true);
                std::string p(path.str());
                if (excluded_.contains(p)) return;
                std::string real = realPath(p);
                if (excluded_.contains(real)) return;
                addInput(real, done);
            });
        }
    }

    void collectInputs(SourceManager &sm, std::set<std::string> &done) {
        for (unsigned i = 0, n = sm.local_sloc_entry_size(); i != n; ++i) {
            const SrcMgr::SLocEntry &entry = sm.getLocalSLocEntry(i);
            if (!entry.isFile()) continue;
            const SrcMgr::ContentCache &cache = entry.getFile().getContentCache();
            if (!cache.OrigEntry) continue;
            std::string path = fileEntryPath(cache.OrigEntry);
            if (path.empty() || !done.insert(path).second) continue;
            std::string digest;
            if (std::optional<llvm::MemoryBufferRef> buf = cache.getBufferIfLoaded()) {
                digest = hexSHA256(buf->getBufferStart(), buf->getBufferSize());
            } else {
                auto file = llvm::MemoryBuffer::getFile(path);
                if (!file) continue;
                digest = hexSHA256((*file)->getBufferStart(), (*file)->getBufferSize());
            }
            std::string stored = paths_.store(path);
            std::string view = stored[0] == '/' || isBuildProduct(stored) ? "" : viewOf(path);
            results_.inputs.push_back({stored, digest, view, false});
        }
    }

    CompilerInstance &ci_;
    const PathMapper &paths_;
    const ExcludedInputs &excluded_;
    Results &results_;
    PreprocessorFacts &facts_;
    const PriorClaims &prior_;
    std::string config_;
    std::vector<Decl *> topLevel_;
    std::string language_, plainView_;
    std::map<std::string, std::string> views_;
};

class SendAction : public ASTFrontendAction {
public:
    SendAction(const PathMapper &paths, const ExcludedInputs &excluded, Results &results, const PriorClaims &prior)
        : paths_(paths), excluded_(excluded), results_(results), prior_(prior) {}

    std::unique_ptr<ASTConsumer> CreateASTConsumer(CompilerInstance &ci, StringRef) override {
        ci.getPreprocessor().addPPCallbacks(
            std::make_unique<MacroRecorder>(ci.getSourceManager(), ci.getPreprocessor(), paths_, facts_));
        ci.getPreprocessor().setTokenWatcher(SelectorTokenWatcher(facts_));
        return std::make_unique<SendConsumer>(ci, paths_, excluded_, results_, facts_, prior_);
    }

private:
    const PathMapper &paths_;
    const ExcludedInputs &excluded_;
    Results &results_;
    const PriorClaims &prior_;
    PreprocessorFacts facts_;
};

// Counts errors (including fatal ones) and prints every diagnostic.
class CountingConsumer : public DiagnosticConsumer {
public:
    explicit CountingConsumer(DiagnosticOptions &opts) : printer_(llvm::errs(), opts) {}
    void BeginSourceFile(const LangOptions &lo, const Preprocessor *pp) override { printer_.BeginSourceFile(lo, pp); }
    void EndSourceFile() override { printer_.EndSourceFile(); }
    void HandleDiagnostic(DiagnosticsEngine::Level level, const Diagnostic &info) override {
        DiagnosticConsumer::HandleDiagnostic(level, info);
        printer_.HandleDiagnostic(level, info);
    }

private:
    TextDiagnosticPrinter printer_;
};

static std::string jsonString(const std::string &s) {
    std::string out = "\"";
    for (unsigned char c : s) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[8];
                snprintf(buf, sizeof buf, "\\u%04x", c);
                out += buf;
            } else {
                out.push_back((char)c);
            }
        }
    }
    return out + "\"";
}

static void bindText(sqlite3_stmt *s, int i, const std::string &v) {
    if (v.empty()) sqlite3_bind_null(s, i);
    else sqlite3_bind_text(s, i, v.c_str(), -1, SQLITE_TRANSIENT);
}

// Binds the location columns, in LOCATION_COLUMNS order, from column i.
static void bindLocation(sqlite3_stmt *s, int i, const Located &l) {
    sqlite3_bind_text(s, i, l.file.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(s, i + 1, (int)l.line);
    sqlite3_bind_int(s, i + 2, (int)l.col);
    bindText(s, i + 3, l.macroName);
    bindText(s, i + 4, l.macroFile);
    if (l.macroName.empty()) sqlite3_bind_null(s, i + 5);
    else sqlite3_bind_int(s, i + 5, (int)l.macroLine);
    bindText(s, i + 6, l.macroRole);
    if (l.macroRole.empty()) {
        sqlite3_bind_null(s, i + 7);
        sqlite3_bind_null(s, i + 8);
    } else {
        sqlite3_bind_int(s, i + 7, (int)l.expansionLine);
        sqlite3_bind_int(s, i + 8, (int)l.expansionCol);
    }
    sqlite3_bind_int(s, i + 9, l.inMigrationScope);
}

#define LOCATION_NAMES "file, line, col, macro_name, macro_file, macro_line, macro_role, expansion_line, " \
                       "expansion_col, in_migration_scope"
#define LOCATION_PLACEHOLDERS "?,?,?,?,?,?,?,?,?,?"
#define TYPE_NAMES "type, canonical_type, type_class, object_class, object_protocols, record_name, " \
                   "record_has_objects, ownership_written, ownership, arc, import_facts"
#define TYPE_PLACEHOLDERS "?,?,?,?,?,?,?,?,?,?,?"

#define CONSTANT_FALSE_NAMES "in_constant_false_branch, constant_condition_file, constant_condition_line"
#define CONSTANT_FALSE_PLACEHOLDERS "?,?,?"

static void bindConstantFalse(sqlite3_stmt *s, int i, const ConstantFalse &c) {
    sqlite3_bind_int(s, i, c.inConstantFalse);
    if (c.inConstantFalse) {
        sqlite3_bind_text(s, i + 1, c.conditionFile.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(s, i + 2, (int)c.conditionLine);
    } else {
        sqlite3_bind_null(s, i + 1);
        sqlite3_bind_null(s, i + 2);
    }
}

static void bindOptionalInt(sqlite3_stmt *s, int i, int v) {
    if (v < 0) sqlite3_bind_null(s, i);
    else sqlite3_bind_int(s, i, v);
}

// Binds the TYPE_COLUMNS, in TYPE_NAMES order, from column i.
static void bindTypeFacts(sqlite3_stmt *s, int i, const TypeFacts &f) {
    sqlite3_bind_text(s, i, f.type.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(s, i + 1, f.canonical.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(s, i + 2, f.typeClass.c_str(), -1, SQLITE_TRANSIENT);
    bindText(s, i + 3, f.objectClass);
    bindText(s, i + 4, f.protocols);
    bindText(s, i + 5, f.recordName);
    bindOptionalInt(s, i + 6, f.hasObjects);
    bindText(s, i + 7, f.ownershipWritten);
    sqlite3_bind_text(s, i + 8, f.ownership.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(s, i + 9, f.arc);
    sqlite3_bind_text(s, i + 10, f.importFacts.c_str(), -1, SQLITE_TRANSIENT);
}

static bool exec(sqlite3 *db, const char *sql) {
    char *err = nullptr;
    if (sqlite3_exec(db, sql, nullptr, nullptr, &err) != SQLITE_OK) {
        fprintf(stderr, "extract_sends: sqlite: %s\n", err ? err : "?");
        sqlite3_free(err);
        return false;
    }
    return true;
}

struct Options {
    std::string db, root, target, mainFile, sdkPath, sdkVersion, configuration, arch;
    std::vector<std::string> args;
    std::vector<std::string> migrationScope;
};

static int usage() {
    fprintf(stderr,
            "usage: extract_sends --db DB --root REPO --target TARGET --main FILE\n"
            "       [--sdk-path P] [--sdk-version V] [--configuration C] [--arch A]\n"
            "       [--migration-scope DIR]...\n"
            "       -- <clang arguments>\n"
            "       extract_sends --version | --reflective-table\n");
    return 2;
}

static const char *kUnitTables[] = {"send",         "tu_input",     "objc_method",     "objc_method_override",
                                    "objc_property", "selector_ref", "reflective_call", "decl_source",
                                    "objc_ivar",     "c_static",     "ivar_ref",        "static_ref",
                                    "objc_impl",     "macro_def",    "macro_undef",     "macro_ast_fact",
                                    "macro_expansion", "macro_use_count", "pp_condition", "pp_skipped",
                                    "objc_class",    "objc_adoption", "sdk_claim",      "tu_module",
                                    "sdk_method",    "sdk_class",    "sdk_adoption",   "function_ref"};

// The claims other units hold (PriorClaims), from the database as it is
// before this unit is parsed; empty when there is no database of this
// schema yet. The write checks every claim again in its transaction.
static PriorClaims readPriorClaims(const Options &o, const std::string &mainStored) {
    PriorClaims prior;
    sqlite3 *db = nullptr;
    if (sqlite3_open_v2(o.db.c_str(), &db, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
        sqlite3_close(db);
        return prior;
    }
    sqlite3_busy_timeout(db, 60000);
    sqlite3_stmt *s = nullptr;
    int version = -1;
    if (sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &s, nullptr) == SQLITE_OK && sqlite3_step(s) == SQLITE_ROW)
        version = sqlite3_column_int(s, 0);
    sqlite3_finalize(s);
    if (version == kSchemaVersion) {
        const char *other = " tu NOT IN (SELECT id FROM tu WHERE target=?1 AND main_file=?2)";
        std::string modules = std::string("SELECT module, '' FROM sdk_claim WHERE") + other;
        std::string files = std::string("SELECT path, digest FROM decl_source WHERE via_module=1 AND view='' AND "
                                        "target=?1 AND") + other;
        for (int pass = 0; pass < 2; pass++) {
            s = nullptr;
            if (sqlite3_prepare_v2(db, (pass ? files : modules).c_str(), -1, &s, nullptr) != SQLITE_OK) break;
            sqlite3_bind_text(s, 1, o.target.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 2, mainStored.c_str(), -1, SQLITE_TRANSIENT);
            while (sqlite3_step(s) == SQLITE_ROW) {
                std::string a = (const char *)sqlite3_column_text(s, 0), b = (const char *)sqlite3_column_text(s, 1);
                if (pass) prior.moduleFiles.insert({a, b});
                else prior.modules.insert(a);
            }
            sqlite3_finalize(s);
        }
    }
    sqlite3_close(db);
    return prior;
}

static bool writeDatabase(const Options &o, const Results &r, unsigned errors,
                          const std::string &mainStored) {
    sqlite3 *db = nullptr;
    if (sqlite3_open(o.db.c_str(), &db) != SQLITE_OK) {
        fprintf(stderr, "extract_sends: cannot open %s\n", o.db.c_str());
        return false;
    }
    sqlite3_busy_timeout(db, 60000);
    bool ok = exec(db, "PRAGMA journal_mode=WAL;") && exec(db, "BEGIN IMMEDIATE;");
    if (ok) {
        // A database made by another version of the schema is not written to;
        // codedb.py update replaces it.
        int version = -1;
        bool hasTu = false;
        sqlite3_stmt *s = nullptr;
        if (sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &s, nullptr) == SQLITE_OK &&
            sqlite3_step(s) == SQLITE_ROW)
            version = sqlite3_column_int(s, 0);
        sqlite3_finalize(s);
        s = nullptr;
        if (sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='tu'", -1, &s,
                               nullptr) == SQLITE_OK &&
            sqlite3_step(s) == SQLITE_ROW)
            hasTu = true;
        sqlite3_finalize(s);
        if (hasTu && version != kSchemaVersion) {
            fprintf(stderr, "extract_sends: %s has schema version %d, this extractor writes %d; run codedb.py update\n",
                    o.db.c_str(), version, kSchemaVersion);
            ok = false;
        }
    }
    if (ok) {
        std::string pragma = "PRAGMA user_version=" + std::to_string(kSchemaVersion) + ";";
        ok = exec(db, kSchema) && exec(db, pragma.c_str());
    }
    // Statements are prepared once per text and reused.
    std::map<const char *, sqlite3_stmt *> statements;
    auto statement = [&](const char *sql) -> sqlite3_stmt * {
        auto it = statements.find(sql);
        if (it != statements.end()) {
            sqlite3_reset(it->second);
            sqlite3_clear_bindings(it->second);
            return it->second;
        }
        sqlite3_stmt *s = nullptr;
        if (sqlite3_prepare_v2(db, sql, -1, &s, nullptr) != SQLITE_OK) {
            fprintf(stderr, "extract_sends: sqlite: %s\n", sqlite3_errmsg(db));
            return nullptr;
        }
        statements[sql] = s;
        return s;
    };
    auto run = [&](const char *sql, const std::function<void(sqlite3_stmt *)> &bind) {
        if (!ok) return;
        sqlite3_stmt *s = statement(sql);
        if (!s) {
            ok = false;
            return;
        }
        bind(s);
        int rc = sqlite3_step(s);
        if (rc != SQLITE_DONE) {
            fprintf(stderr, "extract_sends: sqlite: %s\n", sqlite3_errmsg(db));
            ok = false;
        }
    };
    // True if a row exists for the query.
    auto exists = [&](const char *sql, const std::function<void(sqlite3_stmt *)> &bind) {
        if (!ok) return false;
        sqlite3_stmt *s = statement(sql);
        if (!s) {
            ok = false;
            return false;
        }
        bind(s);
        int rc = sqlite3_step(s);
        if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
            fprintf(stderr, "extract_sends: sqlite: %s\n", sqlite3_errmsg(db));
            ok = false;
        }
        return rc == SQLITE_ROW;
    };
    auto bindKey = [&](sqlite3_stmt *s) {
        sqlite3_bind_text(s, 1, o.target.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(s, 2, mainStored.c_str(), -1, SQLITE_TRANSIENT);
    };
    std::vector<std::string> deletes;
    for (const char *table : kUnitTables)
        deletes.push_back(std::string("DELETE FROM ") + table +
                          " WHERE tu IN (SELECT id FROM tu WHERE target=? AND main_file=?)");
    for (const std::string &d : deletes) run(d.c_str(), bindKey);
    run("DELETE FROM tu WHERE target=? AND main_file=?", bindKey);

    std::string joined;
    std::string argsJSON = "[";
    bool firstJoined = true;
    for (size_t i = 0; i < o.args.size(); i++) {
        if (i) argsJSON += ",";
        argsJSON += jsonString(o.args[i]);
        // The module cache is where the compiler keeps its private cache, not
        // what it compiles: a copy of the database with its own cache has the
        // same commands (codedb.py command_digest skips it too).
        if (o.args[i].rfind("-fmodules-cache-path=", 0) == 0) continue;
        if (!firstJoined) joined.push_back('\0');
        firstJoined = false;
        joined += o.args[i];
    }
    argsJSON += "]";
    std::string digest = hexSHA256(joined.data(), joined.size());
    char when[32];
    time_t now = time(nullptr);
    strftime(when, sizeof when, "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));

    std::string scopeList;
    for (size_t i = 0; i < o.migrationScope.size(); i++) {
        if (i) scopeList.push_back(',');
        scopeList += o.migrationScope[i];
    }
    run("INSERT INTO tu(target, main_file, cmd_digest, extracted_at, clang_version, diagnostics_errors,"
        " sdk_path, sdk_version, configuration, arch, extractor_version, arguments, migration_scope,"
        " module_bodies_skipped) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [&](sqlite3_stmt *s) {
            bindKey(s);
            sqlite3_bind_text(s, 3, digest.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 4, when, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 5, getClangFullVersion().c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(s, 6, (int)errors);
            bindText(s, 7, o.sdkPath);
            bindText(s, 8, o.sdkVersion);
            bindText(s, 9, o.configuration);
            bindText(s, 10, o.arch);
            sqlite3_bind_text(s, 11, CODEDB_EXTRACTOR_DIGEST, -1, SQLITE_STATIC);
            sqlite3_bind_text(s, 12, argsJSON.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 13, scopeList.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(s, 14, r.moduleBodiesSkipped);
        });
    sqlite3_int64 tuId = sqlite3_last_insert_rowid(db);

    for (const InputRow &in : r.inputs) {
        run("INSERT OR REPLACE INTO tu_input(tu, path, digest, view) VALUES(?,?,?,?)", [&](sqlite3_stmt *s) {
            sqlite3_bind_int64(s, 1, tuId);
            sqlite3_bind_text(s, 2, in.path.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 3, in.digest.c_str(), -1, SQLITE_TRANSIENT);
            bindText(s, 4, in.view);
        });
    }
    // Claims on the declarations of files in the repository (see the top of
    // this file). A file another unit of this target already recorded at this
    // content and view is skipped.
    std::set<std::string> claimedElsewhere;
    for (const InputRow &in : r.inputs) {
        if (in.path.empty() || in.path[0] == '/' || isBuildProduct(in.path)) continue;
        auto bindClaim = [&](sqlite3_stmt *s) {
            sqlite3_bind_text(s, 1, in.path.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 2, in.digest.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 3, o.target.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 4, in.view.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(s, 5, in.viaModule ? 1 : 0);
        };
        if (exists("SELECT 1 FROM decl_source WHERE path=? AND digest=? AND target=? AND view=? AND via_module=?",
                   bindClaim)) {
            claimedElsewhere.insert(in.path);
            continue;
        }
        // A file read only through a module is claimed only by a unit that
        // walked the module's declarations (see "Declarations read through a
        // module" at the top of this file); otherwise the claim is left to
        // one that does.
        if (in.viaModule && !r.walkedModuleFiles) continue;
        run("INSERT OR IGNORE INTO decl_source(path, digest, target, view, via_module, tu) VALUES(?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                bindClaim(s);
                sqlite3_bind_int64(s, 6, tuId);
            });
    }
    for (const SendRow &row : r.sends) {
        run("INSERT INTO send(tu, selector, receiver_kind, receiver_type, target_usr, file, line, col,"
            " enclosing_usr, enclosing_name, in_block, implicit_accessor, macro_name, macro_file, macro_line,"
            " macro_role, expansion_line, expansion_col, in_migration_scope, " CONSTANT_FALSE_NAMES ","
            " in_unreachable_code)"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?," CONSTANT_FALSE_PLACEHOLDERS ",?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, row.selector.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, row.receiverKind.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 4, row.receiverType);
                bindText(s, 5, row.targetUSR);
                sqlite3_bind_text(s, 6, row.file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 7, (int)row.line);
                sqlite3_bind_int(s, 8, (int)row.col);
                bindText(s, 9, row.enclosingUSR);
                bindText(s, 10, row.enclosingName);
                sqlite3_bind_int(s, 11, row.inBlock);
                sqlite3_bind_int(s, 12, row.implicitAccessor);
                bindText(s, 13, row.macroName);
                bindText(s, 14, row.macroFile);
                if (row.macroName.empty()) sqlite3_bind_null(s, 15);
                else sqlite3_bind_int(s, 15, (int)row.macroLine);
                bindText(s, 16, row.macroRole);
                if (row.macroRole.empty()) {
                    sqlite3_bind_null(s, 17);
                    sqlite3_bind_null(s, 18);
                } else {
                    sqlite3_bind_int(s, 17, (int)row.expansionLine);
                    sqlite3_bind_int(s, 18, (int)row.expansionCol);
                }
                sqlite3_bind_int(s, 19, row.inMigrationScope);
                bindConstantFalse(s, 20, row);
                sqlite3_bind_int(s, 23, row.inUnreachable);
            });
    }
    for (const MethodRow &row : r.methods) {
        if (!row.claimFile.empty() && claimedElsewhere.count(row.claimFile)) continue;
        run("INSERT INTO objc_method(tu, usr, selector, is_class_method, container_usr, container_name,"
            " container_kind, class_name, is_definition, is_implicit, is_synthesized_accessor, is_optional,"
            " property_usr, return_type, type_encoding, " LOCATION_NAMES ")"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.usr);
                sqlite3_bind_text(s, 3, row.selector.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 4, row.isClassMethod);
                bindText(s, 5, row.containerUSR);
                sqlite3_bind_text(s, 6, row.containerName.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 7, row.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 8, row.className);
                sqlite3_bind_int(s, 9, row.isDefinition);
                sqlite3_bind_int(s, 10, row.isImplicit);
                sqlite3_bind_int(s, 11, row.isSynthesized);
                sqlite3_bind_int(s, 12, row.isOptional);
                bindText(s, 13, row.propertyUSR);
                bindText(s, 14, row.returnType);
                bindText(s, 15, row.typeEncoding);
                bindLocation(s, 16, row);
            });
        sqlite3_int64 methodId = sqlite3_last_insert_rowid(db);
        for (const OverrideRow &o : row.overrides) {
            run("INSERT INTO objc_method_override(tu, method, overridden_usr, overridden_container,"
                " overridden_container_kind, overridden_file, overridden_line, outside_repository,"
                " owner_parsed, overridden_class, overridden_class_parsed, is_optional_requirement)"
                " VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                [&](sqlite3_stmt *s) {
                    sqlite3_bind_int64(s, 1, tuId);
                    sqlite3_bind_int64(s, 2, methodId);
                    bindText(s, 3, o.usr);
                    sqlite3_bind_text(s, 4, o.container.c_str(), -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(s, 5, o.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                    bindText(s, 6, o.file);
                    if (o.line) sqlite3_bind_int(s, 7, (int)o.line);
                    else sqlite3_bind_null(s, 7);
                    sqlite3_bind_int(s, 8, o.outsideRepository);
                    sqlite3_bind_int(s, 9, o.ownerParsed);
                    bindText(s, 10, o.className);
                    if (o.classParsed >= 0) sqlite3_bind_int(s, 11, o.classParsed);
                    else sqlite3_bind_null(s, 11);
                    sqlite3_bind_int(s, 12, o.isOptionalRequirement);
                });
        }
    }
    for (const PropertyRow &row : r.properties) {
        if (!row.claimFile.empty() && claimedElsewhere.count(row.claimFile)) continue;
        run("INSERT INTO objc_property(tu, usr, name, kind, is_class_property, container_usr, container_name,"
            " container_kind, class_name, getter_selector, setter_selector, attributes, ivar_name, is_readonly,"
            " is_implicit, type, ivar_usr, " LOCATION_NAMES ")"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.usr);
                sqlite3_bind_text(s, 3, row.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.kind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 5, row.isClassProperty);
                bindText(s, 6, row.containerUSR);
                sqlite3_bind_text(s, 7, row.containerName.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 8, row.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 9, row.className);
                sqlite3_bind_text(s, 10, row.getter.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 11, row.setter);
                sqlite3_bind_text(s, 12, row.attributes.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 13, row.ivarName);
                sqlite3_bind_int(s, 14, row.isReadonly);
                sqlite3_bind_int(s, 15, row.isImplicit);
                bindText(s, 16, row.type);
                bindText(s, 17, row.ivarUSR);
                bindLocation(s, 18, row);
            });
    }
    for (const SelectorRefRow &row : r.selectorRefs) {
        run("INSERT INTO selector_ref(tu, selector, kind, enclosing_usr, enclosing_name, in_block, " LOCATION_NAMES
            ") VALUES(?,?,?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, row.selector.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, row.kind.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 4, row.enclosingUSR);
                bindText(s, 5, row.enclosingName);
                sqlite3_bind_int(s, 6, row.inBlock);
                bindLocation(s, 7, row);
            });
    }
    for (const ReflectiveRow &row : r.reflective) {
        run("INSERT INTO reflective_call(tu, function_or_selector, call_kind, kind, argument_index, argument_kind,"
            " argument_text, argument_constant, resolved_selector, resolved_class, receiver_type, enclosing_usr,"
            " enclosing_name, in_block, " LOCATION_NAMES ")"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, row.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, row.callKind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.kind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 5, row.argumentIndex);
                sqlite3_bind_text(s, 6, row.argumentKind.c_str(), -1, SQLITE_TRANSIENT);
                // An empty literal is text, not a missing value.
                if (row.argumentKind == "dynamic" && row.argumentText.empty()) sqlite3_bind_null(s, 7);
                else sqlite3_bind_text(s, 7, row.argumentText.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 8, row.argumentConstant);
                bindText(s, 9, row.resolvedSelector);
                bindText(s, 10, row.resolvedClass);
                bindText(s, 11, row.receiverType);
                bindText(s, 12, row.enclosingUSR);
                bindText(s, 13, row.enclosingName);
                sqlite3_bind_int(s, 14, row.inBlock);
                bindLocation(s, 15, row);
            });
    }
    for (const IvarRow &row : r.ivars) {
        if (!row.claimFile.empty() && claimedElsewhere.count(row.claimFile)) continue;
        run("INSERT INTO objc_ivar(tu, usr, class_name, name, container_kind, " TYPE_NAMES ", bit_width, access,"
            " is_iboutlet, synthesized_by, property_name, type_encoding, " LOCATION_NAMES ")"
            " VALUES(?,?,?,?,?," TYPE_PLACEHOLDERS ",?,?,?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.usr);
                sqlite3_bind_text(s, 3, row.className.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 5, row.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                bindTypeFacts(s, 6, row.facts);
                bindOptionalInt(s, 17, row.facts.bitWidth);
                sqlite3_bind_text(s, 18, row.access.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 19, row.isIBOutlet);
                bindText(s, 20, row.synthesizedBy);
                bindText(s, 21, row.propertyName);
                bindText(s, 22, row.facts.encoding);
                bindLocation(s, 23, row);
            });
    }
    for (const StaticRow &row : r.statics) {
        if (!row.claimFile.empty() && claimedElsewhere.count(row.claimFile)) continue;
        run("INSERT INTO c_static(tu, usr, name, kind, enclosing_usr, enclosing_name, " TYPE_NAMES ", is_const,"
            " pointee_const, init_kind, thread_local, " LOCATION_NAMES ")"
            " VALUES(?,?,?,?,?,?," TYPE_PLACEHOLDERS ",?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.usr);
                sqlite3_bind_text(s, 3, row.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.kind.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 5, row.enclosingUSR);
                bindText(s, 6, row.enclosingName);
                bindTypeFacts(s, 7, row.facts);
                sqlite3_bind_int(s, 18, row.isConst);
                bindOptionalInt(s, 19, row.pointeeConst);
                sqlite3_bind_text(s, 20, row.initKind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 21, row.threadLocal);
                bindLocation(s, 22, row);
            });
    }
    for (const IvarRefRow &row : r.ivarRefs) {
        run("INSERT INTO ivar_ref(tu, ivar_usr, ivar_class, ivar_name, kind, access, partial, base_kind,"
            " enclosing_usr, enclosing_name, enclosing_class, in_block, in_once_block, in_lambda, retain_hint,"
            " sync_lock, " LOCATION_NAMES ", " CONSTANT_FALSE_NAMES ")"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?," LOCATION_PLACEHOLDERS "," CONSTANT_FALSE_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.ivarUSR);
                sqlite3_bind_text(s, 3, row.ivarClass.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.ivarName.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 5, row.kind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 6, row.access.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 7, row.partial);
                sqlite3_bind_text(s, 8, row.baseKind.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 9, row.enclosingUSR);
                bindText(s, 10, row.enclosingName);
                bindText(s, 11, row.enclosingClass);
                sqlite3_bind_int(s, 12, row.inBlock);
                sqlite3_bind_int(s, 13, row.inOnceBlock);
                bindText(s, 14, row.inLambda);
                bindText(s, 15, row.retainHint);
                bindText(s, 16, row.syncLock);
                bindLocation(s, 17, row);
                bindConstantFalse(s, 27, row);
            });
    }
    for (const StaticRefRow &row : r.staticRefs) {
        run("INSERT INTO static_ref(tu, var_usr, name, var_kind, access, partial, enclosing_usr, enclosing_name,"
            " enclosing_class, in_block, in_once_block, in_lambda, sync_lock, " LOCATION_NAMES ", "
            CONSTANT_FALSE_NAMES ")"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?," LOCATION_PLACEHOLDERS "," CONSTANT_FALSE_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.varUSR);
                sqlite3_bind_text(s, 3, row.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.varKind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 5, row.access.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 6, row.partial);
                bindText(s, 7, row.enclosingUSR);
                bindText(s, 8, row.enclosingName);
                bindText(s, 9, row.enclosingClass);
                sqlite3_bind_int(s, 10, row.inBlock);
                sqlite3_bind_int(s, 11, row.inOnceBlock);
                bindText(s, 12, row.inLambda);
                bindText(s, 13, row.syncLock);
                bindLocation(s, 14, row);
                bindConstantFalse(s, 24, row);
            });
    }
    for (const ImplRow &row : r.impls) {
        run("INSERT INTO objc_impl(tu, class_name, category, arc, " LOCATION_NAMES ")"
            " VALUES(?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, row.className.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 3, row.category);
                sqlite3_bind_int(s, 4, row.arc);
                bindLocation(s, 5, row);
            });
    }
    for (const ClassRow &row : r.classes) {
        if (!row.claimFile.empty() && claimedElsewhere.count(row.claimFile)) continue;
        run("INSERT INTO objc_class(tu, usr, name, superclass, " LOCATION_NAMES ") VALUES(?,?,?,?," LOCATION_PLACEHOLDERS
            ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                bindText(s, 2, row.usr);
                sqlite3_bind_text(s, 3, row.name.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 4, row.superclass);
                bindLocation(s, 5, row);
            });
    }
    for (const AdoptionRow &row : r.adoptions) {
        if (!row.claimFile.empty() && claimedElsewhere.count(row.claimFile)) continue;
        run("INSERT INTO objc_adoption(tu, class_or_category, container_kind, protocol, " LOCATION_NAMES
            ") VALUES(?,?,?,?," LOCATION_PLACEHOLDERS ")",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, row.container.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, row.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.protocol.c_str(), -1, SQLITE_TRANSIENT);
                bindLocation(s, 5, row);
            });
    }
    // Declarations outside the repository (see "Classes and the SDK" at the
    // top of this file): the modules the unit loaded, then the claims on the
    // modules it walked; a module another unit claimed in the meantime gives
    // no rows.
    for (const std::string &m : r.loadedModules) {
        run("INSERT OR IGNORE INTO tu_module(tu, module) VALUES(?,?)", [&](sqlite3_stmt *s) {
            sqlite3_bind_int64(s, 1, tuId);
            sqlite3_bind_text(s, 2, m.c_str(), -1, SQLITE_TRANSIENT);
        });
    }
    std::set<std::string> sdkMine;
    for (const std::string &m : r.walkedModules) {
        run("INSERT OR IGNORE INTO sdk_claim(module, tu) VALUES(?,?)", [&](sqlite3_stmt *s) {
            sqlite3_bind_text(s, 1, m.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(s, 2, tuId);
        });
        if (ok && sqlite3_changes(db) > 0) sdkMine.insert(m);
    }
    for (const SdkMethodRow &row : r.sdkMethods) {
        if (!sdkMine.count(row.module)) continue;
        run("INSERT OR IGNORE INTO sdk_method(selector, container, container_kind, is_class_method, framework,"
            " is_optional, is_action, module, tu) VALUES(?,?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_text(s, 1, row.selector.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 2, row.container.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, row.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 4, row.isClassMethod);
                sqlite3_bind_text(s, 5, row.framework.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 6, row.isOptional);
                sqlite3_bind_int(s, 7, row.isAction);
                sqlite3_bind_text(s, 8, row.module.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(s, 9, tuId);
            });
    }
    for (const SdkClassRow &row : r.sdkClasses) {
        if (!sdkMine.count(row.module)) continue;
        run("INSERT OR IGNORE INTO sdk_class(name, superclass, framework, module, tu) VALUES(?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_text(s, 1, row.name.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 2, row.superclass);
                sqlite3_bind_text(s, 3, row.framework.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.module.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(s, 5, tuId);
            });
    }
    for (const auto &kv : r.functionRefs) {
        run("INSERT INTO function_ref(tu, callee, enclosing_name, refs) VALUES(?,?,?,?)", [&](sqlite3_stmt *s) {
            sqlite3_bind_int64(s, 1, tuId);
            sqlite3_bind_text(s, 2, kv.first.first.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(s, 3, kv.first.second.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(s, 4, kv.second);
        });
    }
    for (const SdkAdoptionRow &row : r.sdkAdoptions) {
        if (!sdkMine.count(row.module)) continue;
        run("INSERT OR IGNORE INTO sdk_adoption(container, container_kind, protocol, module, tu) VALUES(?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_text(s, 1, row.container.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 2, row.containerKind.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, row.protocol.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 4, row.module.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(s, 5, tuId);
            });
    }
    // The preprocessor tables (see "Macros and conditional compilation" at
    // the top of this file): a file's rows by the unit that holds its claim.
    std::map<std::string, std::string> viewOf;
    for (const InputRow &in : r.inputs)
        if (!in.viaModule) viewOf[in.path] = in.view;
    auto mine = [&](const std::string &file) { return !claimedElsewhere.count(file); };
    auto bindView = [&](sqlite3_stmt *s, int i, const std::string &file) {
        auto it = viewOf.find(file);
        if (it == viewOf.end() || it->second.empty()) sqlite3_bind_null(s, i);
        else sqlite3_bind_text(s, i, it->second.c_str(), -1, SQLITE_TRANSIENT);
    };
    // A header read more than once in the unit (without a guard) gives the
    // same rows again; each is written once.
    std::set<std::string> written;
    auto once = [&](const std::string &key) { return written.insert(key).second; };
    for (const MacroDefRec &d : r.macroDefs) {
        if (!mine(d.file) || !once("d|" + d.file + "|" + std::to_string(d.line) + "|" + d.digest)) continue;
        run("INSERT INTO macro_def(tu, name, kind, params, variadic, body, body_truncated, body_digest, facts,"
            " fact_detail, previous_def, view, file, line, col, in_migration_scope)"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, d.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, d.kind.c_str(), -1, SQLITE_TRANSIENT);
                if (d.kind == "function") sqlite3_bind_text(s, 4, d.params.c_str(), -1, SQLITE_TRANSIENT);
                else sqlite3_bind_null(s, 4);
                sqlite3_bind_int(s, 5, d.variadic);
                sqlite3_bind_text(s, 6, d.body.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 7, d.truncated);
                sqlite3_bind_text(s, 8, d.digest.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 9, d.facts.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 10, d.detail.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 11, d.previous);
                bindView(s, 12, d.file);
                sqlite3_bind_text(s, 13, d.file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 14, (int)d.line);
                sqlite3_bind_int(s, 15, (int)d.col);
                sqlite3_bind_int(s, 16, d.inScope);
            });
    }
    for (const MacroUndefRec &u : r.macroUndefs) {
        if (!mine(u.file) || !once("u|" + u.file + "|" + std::to_string(u.line))) continue;
        run("INSERT INTO macro_undef(tu, name, def_file, def_line, view, file, line, col, in_migration_scope)"
            " VALUES(?,?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, u.name.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 3, u.defFile);
                if (u.defFile.empty()) sqlite3_bind_null(s, 4);
                else sqlite3_bind_int(s, 4, (int)u.defLine);
                bindView(s, 5, u.file);
                sqlite3_bind_text(s, 6, u.file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 7, (int)u.line);
                sqlite3_bind_int(s, 8, (int)u.col);
                sqlite3_bind_int(s, 9, u.inScope);
            });
    }
    // At most kFactDetails details per macro and fact; the rest are counted
    // in one row whose detail is "(N more)".
    const size_t kFactDetails = 20;
    std::map<std::pair<size_t, std::string>, std::vector<std::pair<std::string, int>>> factGroups;
    for (const auto &kv : r.macroFacts)
        factGroups[{std::get<0>(kv.first), std::get<1>(kv.first)}].push_back({std::get<2>(kv.first), kv.second});
    for (const auto &g : factGroups) {
        const MacroDefRec &d = r.macroDefs[g.first.first];
        std::vector<std::pair<std::string, int>> rows = g.second;
        if (rows.size() > kFactDetails) {
            int rest = 0;
            for (size_t i = kFactDetails; i < rows.size(); i++) rest += rows[i].second;
            std::string more = "(" + std::to_string(rows.size() - kFactDetails) + " more)";
            rows.resize(kFactDetails);
            rows.push_back({more, rest});
        }
        for (const auto &row : rows) {
            run("INSERT INTO macro_ast_fact(tu, name, def_file, def_line, fact, detail, count) VALUES(?,?,?,?,?,?,?)",
                [&](sqlite3_stmt *s) {
                    sqlite3_bind_int64(s, 1, tuId);
                    sqlite3_bind_text(s, 2, d.name.c_str(), -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(s, 3, d.file.c_str(), -1, SQLITE_TRANSIENT);
                    sqlite3_bind_int(s, 4, (int)d.line);
                    sqlite3_bind_text(s, 5, g.first.second.c_str(), -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(s, 6, row.first.c_str(), -1, SQLITE_TRANSIENT);
                    sqlite3_bind_int(s, 7, row.second);
                });
        }
    }
    for (const MacroExpansionRec &x : r.macroExpansions) {
        if (!mine(x.file) || !once("x|" + x.file + "|" + std::to_string(x.line) + "|" + std::to_string(x.col) + "|" +
                                   x.name + "|" + x.nesting + "|" + std::to_string(x.outerLine) + "|" +
                                   std::to_string(x.outerCol) + "|" + x.args))
            continue;
        run("INSERT INTO macro_expansion(tu, name, def_file, def_line, nesting, parent_name, outer_name, outer_line,"
            " outer_col, in_condition, args, args_truncated, enclosing_usr, enclosing_name, view, file, line, col,"
            " in_migration_scope) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, x.name.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, x.defFile.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 4, (int)x.defLine);
                sqlite3_bind_text(s, 5, x.nesting.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 6, x.parentName);
                sqlite3_bind_text(s, 7, x.outerName.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 8, (int)x.outerLine);
                sqlite3_bind_int(s, 9, (int)x.outerCol);
                sqlite3_bind_int(s, 10, x.inCondition);
                bindText(s, 11, x.args);
                sqlite3_bind_int(s, 12, x.argsTruncated);
                bindText(s, 13, x.enclosingUSR);
                bindText(s, 14, x.enclosingName);
                bindView(s, 15, x.file);
                sqlite3_bind_text(s, 16, x.file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 17, (int)x.line);
                sqlite3_bind_int(s, 18, (int)x.col);
                sqlite3_bind_int(s, 19, x.inScope);
            });
    }
    for (const auto &kv : r.otherMacroCounts) {
        const std::string &file = std::get<0>(kv.first);
        if (!mine(file)) continue;
        run("INSERT INTO macro_use_count(tu, name, def_file, def_line, count, view, file, in_migration_scope)"
            " VALUES(?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, std::get<1>(kv.first).c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(s, 3, std::get<2>(kv.first).c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 4, (int)std::get<3>(kv.first));
                sqlite3_bind_int(s, 5, kv.second.first);
                bindView(s, 6, file);
                sqlite3_bind_text(s, 7, file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 8, kv.second.second);
            });
    }
    std::map<std::pair<std::string, unsigned>, const CondRec *> condAt;
    for (const CondRec &c : r.conds) condAt[{c.file, c.line}] = &c;
    for (const CondRec &c : r.conds) {
        if (!mine(c.file)) continue;
        std::string value = joinSet(c.values, ",");
        run("INSERT INTO pp_condition(tu, directive, condition, chain_line, value, include_guard, view, file, line,"
            " in_migration_scope) VALUES(?,?,?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_text(s, 2, c.directive.c_str(), -1, SQLITE_TRANSIENT);
                bindText(s, 3, c.condition);
                sqlite3_bind_int(s, 4, (int)c.chainLine);
                sqlite3_bind_text(s, 5, value.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 6, c.guard);
                bindView(s, 7, c.file);
                sqlite3_bind_text(s, 8, c.file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 9, (int)c.line);
                sqlite3_bind_int(s, 10, c.inScope);
            });
    }
    for (const SkipRec &k : r.skips) {
        if (!mine(k.file) || !once("k|" + k.file + "|" + std::to_string(k.startLine) + "|" + std::to_string(k.endLine)))
            continue;
        auto it = condAt.find({k.file, k.startLine});
        const CondRec *c = it == condAt.end() ? nullptr : it->second;
        const CondRec *head = nullptr;
        if (c) {
            auto h = condAt.find({k.file, c->chainLine});
            head = h == condAt.end() ? c : h->second;
        }
        run("INSERT INTO pp_skipped(tu, start_line, end_line, directive, condition, chain_line, include_guard, view,"
            " file, in_migration_scope) VALUES(?,?,?,?,?,?,?,?,?,?)",
            [&](sqlite3_stmt *s) {
                sqlite3_bind_int64(s, 1, tuId);
                sqlite3_bind_int(s, 2, (int)k.startLine);
                sqlite3_bind_int(s, 3, (int)k.endLine);
                sqlite3_bind_text(s, 4, c ? c->directive.c_str() : "?", -1, SQLITE_TRANSIENT);
                if (c) bindText(s, 5, c->condition);
                else sqlite3_bind_null(s, 5);
                sqlite3_bind_int(s, 6, (int)(c ? c->chainLine : k.startLine));
                sqlite3_bind_int(s, 7, head && head->guard ? 1 : 0);
                bindView(s, 8, k.file);
                sqlite3_bind_text(s, 9, k.file.c_str(), -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(s, 10, k.inScope);
            });
    }
    for (auto &kv : statements) sqlite3_finalize(kv.second);
    ok = ok && exec(db, "COMMIT;");
    if (!ok) exec(db, "ROLLBACK;");
    sqlite3_close(db);
    return ok;
}

static void printReflectiveTable() {
    printf("name\tcall\tmatch\targument\tnames\tclass_argument\tcomment\n");
    for (const ReflectiveName &e : kReflectiveNames) {
        printf("%s\t%s\t%s\t%d\t%s\t%d\t%s\n", e.name, e.message ? "message" : "function",
               e.prefix ? "prefix" : "exact", e.argument, e.names, e.classArgument, e.comment);
    }
}

int main(int argc, char **argv) {
    if (argc == 2 && std::string(argv[1]) == "--version") {
        printf("extract_sends %s %s\n", CODEDB_EXTRACTOR_DIGEST, getClangFullVersion().c_str());
        return 0;
    }
    if (argc == 2 && std::string(argv[1]) == "--reflective-table") {
        printReflectiveTable();
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
        if (i + 1 >= argc) return usage();
        std::string v = argv[++i];
        if (a == "--db") o.db = v;
        else if (a == "--root") o.root = v;
        else if (a == "--target") o.target = v;
        else if (a == "--main") o.mainFile = v;
        else if (a == "--sdk-path") o.sdkPath = v;
        else if (a == "--sdk-version") o.sdkVersion = v;
        else if (a == "--configuration") o.configuration = v;
        else if (a == "--arch") o.arch = v;
        else if (a == "--migration-scope") o.migrationScope.push_back(v);
        else return usage();
    }
    for (; i < argc; i++) o.args.push_back(argv[i]);
    if (o.db.empty() || o.root.empty() || o.target.empty() || o.mainFile.empty() || o.args.empty())
        return usage();

    PathMapper paths(o.root, o.migrationScope);
    std::string mainStored = paths.store(realPath(o.mainFile));

    std::vector<std::string> cmd;
    cmd.push_back(CODEDB_LLVM_CLANG);
    cmd.insert(cmd.end(), o.args.begin(), o.args.end());
    cmd.push_back("-fsyntax-only");
    cmd.push_back("-resource-dir");
    cmd.push_back(CODEDB_RESOURCE_DIR);

    Results results;
    DiagnosticOptions diagOpts;
    CountingConsumer diags(diagOpts);
    // ToolInvocation does not apply -ivfsoverlay when it is given a file
    // manager, so the overlays are applied here.
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
    llvm::IntrusiveRefCntPtr<FileManager> files(new FileManager(FileSystemOptions(), vfs));
    ExcludedInputs excluded;
    excluded.add(o.sdkPath);
    excluded.add(CODEDB_RESOURCE_DIR);
    for (size_t k = 0; k + 1 < o.args.size(); k++)
        if (o.args[k] == "-isysroot") excluded.add(o.args[k + 1]);
    PriorClaims prior = readPriorClaims(o, mainStored);
    tooling::ToolInvocation invocation(cmd, std::make_unique<SendAction>(paths, excluded, results, prior),
                                       files.get());
    invocation.setDiagnosticConsumer(&diags);
    bool ran = invocation.run();
    unsigned errors = diags.getNumErrors();
    if (!ran && errors == 0) {
        fprintf(stderr, "extract_sends: clang did not run on %s, with no diagnostic\n", o.mainFile.c_str());
        errors = 1;
    }
    if (!writeDatabase(o, results, errors, mainStored)) return 2;
    if (errors) {
        fprintf(stderr, "extract_sends: %s: recorded with %u error(s); %zu sends\n", mainStored.c_str(), errors,
                results.sends.size());
        return 3;
    }
    return 0;
}
