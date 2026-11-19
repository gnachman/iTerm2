#!/usr/bin/env python3
"""Code database for the Objective-C to Swift migration: compile database,
extraction driver and query helper.

Commands:

  codedb.py cdb [--accept-removals]
                     Build tmp/codedb/compile_commands.jsonl from the clang
                     fragments written by capture_compile_commands.sh: one
                     unit for every compiled file inside the repository (not
                     generated under Build/), in every captured target. It
                     records the SDK and a digest of the project's build
                     settings, and reports files on disk in the migration's
                     scope that no target compiles.
                     It also merges the captures of the other Xcode projects
                     of other_projects.json that are in the tree
                     (tmp/codedb/other-fragments/NAME, written by
                     capture_compile_commands.sh --other-projects; global
                     option --other-fragments DIR): each unit of a target
                     the project's entry keeps is in the target NAME:TARGET
                     and its entry names the project; a project with no
                     capture is recorded as not captured, and its files stay
                     under "Not parsed". The other projects' file lists,
                     build settings and entries are checked as the main
                     project's are (out of date when one changed).
                     Refuses to replace a compile database with one that has
                     fewer entries for a target, or that drops a target, and
                     names the files that would be dropped, unless
                     --accept-removals is given; when the capture compiled
                     far fewer files than the compile database has (an
                     incremental build), it says that a capture needs a clean
                     build instead. Refuses fragments from a capture that did
                     not finish.
                     Exit 0; 1 if the compile database does not match the
                     project; 2 on error, refusal, or while another update,
                     cdb or capture holds the lock.
  codedb.py update [--file PATH] [--force] [--accept-removals]
                   [--objc-only | --swift-only | --imports-only]
                   [--swift-module M]... [--accept-compiler-version]
                     Bring tmp/codedb/codedb.sqlite up to date. Last, the
                     swift_import rows (what Swift imports, swiftimports.py)
                     of each captured module that has a bridging header, when
                     they are not current (--imports-only does only this;
                     --objc-only skips it). After the
                     Objective-C units, the Swift modules (when the capture
                     kept the Swift inputs; see swiftdb.py): each module that
                     is not current is read again in full, one at a time,
                     by swiftreader/swift_refs running the Swift compiler's
                     JSON AST dump under guard.sh (6 GB), in one transaction;
                     a module whose compiler or reader fails is recorded as
                     failed. --swift-module reads only that module. A compiler
                     whose major and minor version are not the reader's is
                     refused unless --accept-compiler-version. The global
                     options --swift-work DIR (the work directory and the
                     compiler's module cache, DIR/modcache; default
                     tmp/codedb/swift) and --swift-reader PATH (default
                     tmp/codedb/bin/swift_refs) choose where the Swift side
                     works; a module's command digest does not depend on
                     them, so a copy of the database updated elsewhere is
                     current here. Likewise --module-cache DIR (default
                     tmp/codedb/modcache) is the Objective-C side's module
                     cache, used in place of the one the compile database
                     names and left out of a unit's command digest.
                     For the Objective-C side: build the
                     compile database if new fragments were captured, then
                     extract every unit that is not current, serially, each
                     under the memory watchdog in its own process group.
                     --file PATH extracts only that file (every target that
                     compiles it); --force re-extracts regardless of state.
                     Units in the database that are not in the compile
                     database are removed, and each one is named.
                     Exit 0; 1 if any extraction failed, any unit has parse
                     errors, or the compile database is out of date; 2 on
                     error or while another update, cdb or capture holds the
                     lock; 130 if interrupted.
  codedb.py sends [--update] SELECTOR
                     Print each send of SELECTOR, then a status block.
                     --update runs `update` first (serially, under the lock
                     and the memory watchdog; its progress goes to stderr),
                     then answers. This is the usual way to ask.
                     Sends written anywhere in the repository are printed;
                     those outside the migration's scope (MIGRATION_SCOPE_DIRS)
                     are marked so, and so are those only test targets
                     compile ("test code").
                     The status block lists, under "Not parsed", every C,
                     Objective-C or C++ implementation file in the
                     repository that no unit covers (built by another Xcode
                     project or Swift package, under submodules/, compiled by
                     an uncaptured target of the main project, or compiled by
                     no target of any project found), except files a current
                     unit reads (#include of a .m) and files under
                     tools/swift_migration/. It searches them as text
                     (stopping after 50 matches) for the selector's first
                     keyword as a message send and, for a setter-shaped,
                     is-prefixed or unary selector, for the property it stands
                     for with dot syntax; the matches are printed as possible
                     callers, each with the form that matched.
                     When the capture kept the Swift inputs, the Swift sends
                     follow in their own group: calls, initializers, dynamic
                     lookups, property references by role (a read when
                     SELECTOR is a getter, a write when it is a setter, both
                     for a read-modify-write or an unknown access) and key
                     path components; #selector expressions are in reach.
  codedb.py methods [--update] SELECTOR
                     Print where SELECTOR is declared and defined, in every
                     class, class extension, category, protocol and
                     implementation: methods written out, accessors the
                     compiler declares for a property (implicit) and
                     synthesizes in an implementation, and methods made by
                     macros (at the place the macro is used, with the macro).
                     A header's declarations are recorded once per target,
                     content and view (the language the unit reads it as and
                     the #if branches its preprocessor skipped), by the first
                     unit of the target that reads it with that view; a
                     declaration found in only some views of a file says so.
                     A file that current units read with no recorded
                     declarations for their view makes the answer incomplete.
                     When a definition overrides a method or satisfies a
                     protocol requirement, the two groups reach prints for
                     them follow (only those that have rows; they are not
                     counted for the exit status).
  codedb.py selrefs [--update] SELECTOR
                     Print the @selector expressions of SELECTOR and the
                     reflective calls whose selector resolves to it (an
                     @selector, a string literal, or a constant followed one
                     step).
  codedb.py reflective [--update] [--dynamic | --all] [--kind K] [--list]
                     Print reflective call sites (calls that reach code by
                     name: NSSelectorFromString, performSelector:,
                     valueForKey:, setAction: and the others in the
                     extractor's table), grouped by file. By default only
                     those whose argument is dynamic: nobody can resolve them
                     mechanically, and a person must read each once.
                     Arguments that are nil, NULL or 0 (argument kind nil)
                     or _cmd (argument kind self-selector) are counted on one
                     line, not listed. --all prints every site; --kind K
                     only those whose argument names K (selector, class,
                     protocol, key, key-path, predicate-format, method,
                     property, implementation). --list prints the table of recognized
                     calls.
  codedb.py reach [--update] SELECTOR
                     Print every way SELECTOR is reached from the Objective-C
                     in this database, in groups: its sends; its @selector
                     expressions and reflective calls; and, when it is an
                     accessor of a property or has a key-value coding shape
                     (foo, isFoo, setFoo:, countOfFoo and the others), the
                     key-value coding calls, key paths and predicate formats
                     whose literal names that key; the methods declared in
                     code that is not in this database (the SDK, a prebuilt
                     .framework bundle in the repository, a -Swift.h header
                     the Swift compiler generates, a header read only
                     through a compiled module; and a category or class
                     extension, wherever it is, on a class declared in such
                     code) that a definition of SELECTOR overrides or whose
                     protocol requirement it satisfies, so that code outside
                     this database may call it ("May be called by code
                     outside this database"); and
                     those declared in parsed code of the repository. Then
                     what reach does not search ("Not covered by reach").
                     When the capture kept the Swift inputs, also the Swift
                     references (calls, initializers, #selector, key paths,
                     property references whose getter or setter it is, with
                     their access, and dynamic lookups by selector), the
                     Swift declarations with the selector (see swiftrefs),
                     and a text search of the Swift #if clauses that
                     produced no node of the compiler's dump (inactive in
                     this configuration) for the selector's Swift forms.
                     Last, a text search for the selector's first keyword in
                     the Objective-C ranges that every unit reading the file
                     skips ("Objective-C code that is not compiled"); with
                     no rows, a match makes the answer incomplete (3).
                     Exit 0 if any group has rows, the methods declared in
                     parsed code of the repository not counting (Objective-C
                     sends to them are among its sends, Swift references
                     among the Swift references).
  codedb.py swiftrefs [--update] SELECTOR
                     Print only the Swift side of reach: the Swift references
                     that reach SELECTOR and the Swift declarations visible
                     to Objective-C that have it (methods, initializers,
                     getters and setters, with the source of the selector:
                     the compiler's, @objc(name), or derived from the Swift
                     name for private and fileprivate @objc members). Exit
                     statuses as for reach; 3 also when the capture kept no
                     Swift inputs.
  codedb.py ivars [--update] CLASS
                     The ivar table of CLASS: every ivar of its @interface,
                     class extensions and @implementation, and those the
                     compiler synthesizes for its properties, with type,
                     type class, ownership under the unit's ARC mode,
                     access, the property it backs (with that property's
                     attributes), IBOutlet. It first names the files that
                     hold the class's @implementation and category
                     @implementations and their ARC mode: that mode governs
                     the ownership shown, and a header ivar's row from units
                     of the other mode is a CONFLICT "as seen by units of
                     the other mode" (a class implemented in both modes shows
                     both as governing). For a class compiled with manual
                     reference counting, each object ivar has a retain hint
                     from its own code (retain, release, autorelease, copy
                     sent to it, or assigned an owned result). For each: its
                     references counted by access (read, write, rmw,
                     address, byref, synchronized, once-token,
                     unevaluated), direct versus synthesized accessor, in
                     blocks (capturing self strongly, or through a
                     weak-strong local), from other objects (obj->_x), from
                     other classes (subclasses, other classes' methods),
                     from other files (units that do not hold the class's
                     @implementation: categories, subclasses); by method;
                     and for a backed property the sends to its accessors
                     and the Swift references to it; how many references
                     are inside a @synchronized body and on which locks,
                     and for a lock ivar the ivars accessed under it. Then
                     the methods of
                     CLASS that reach ivars of other classes directly.
                     Searches files that are not parsed for @interface or
                     @implementation of CLASS, and the Objective-C ranges
                     every unit skips for CLASS and its ivars' names as
                     words (with no rows, a match makes the answer
                     incomplete).
  codedb.py ivarrefs [--update] CLASS IVAR
                     The declaration of CLASS's ivar IVAR and every
                     reference to it, with access, base (implicit self,
                     self, parameter, weak-strong local, local, other
                     object), block, dispatch_once block, lambda capture,
                     retain hint, the @synchronized lock it is under, macro
                     and the class of the method when it is not CLASS.
                     Searches files
                     that are not parsed for IVAR as a word.
  codedb.py statics [--update] FILE | CLASS
                     The statics and globals FILE declares or uses (a path
                     relative to the repository, or a name ending in a
                     source or header extension), or that the methods of
                     CLASS use: each with kind (file-static, local-static,
                     global, extern, static-member), type, ownership,
                     const-ness, initializer kind, thread-local, how it is
                     written (an address taken or a by-reference use, an
                     array passed as a pointer to non-const included, counts
                     as a write: none recorded, only in a dispatch_once
                     block, or from how many functions), whether it is
                     defined in a header (a copy per including unit), the
                     target when several targets define a global of that
                     name, its other declarations (an extern
                     in a header), and reads and writes per function.
                     INCOMPLETE when no unit reads FILE.
  codedb.py staticrefs [--update] [--per-unit] NAME
                     Every static or global named NAME (each file's own
                     static of that name separately, and a global that
                     several targets define once per target), with every
                     reference; a static defined in a header says so (each
                     including unit has its own copy), and --per-unit lists
                     each unit's references. Searches files that are not
                     parsed for NAME as a word.
                     For these four, Swift: Swift imports no Objective-C
                     ivar, and the Swift tables record no reference to an
                     ivar or to a C global or static.
  codedb.py classstate [--update] [--json] [--runtime-methods FILE]... CLASS
                     The ivar and static table of objc-state.md for CLASS
                     (classstate.py documents it): one row per ivar of the
                     class and per static its implementation files define,
                     with the type as the compiler prints it, where it is
                     declared, the ARC mode, ownership, whether Swift can
                     import the type (yes, degraded, no or unknown, with the
                     reason, from objc_ivar.import_facts), the methods named
                     like it, every function that uses it with its accesses
                     and lines, and each reference from outside the class's
                     own code, in blocks and lambdas, and under
                     @synchronized. Importable: yes (Swift sees the type as
                     declared), degraded (Swift sees it, losing something:
                     a tuple for a C array, OpaquePointer, a struct for a
                     plain enum, type arguments), no (the member is
                     dropped), unknown (not decided, with what is missing);
                     whether the type is visible to the bridging header is
                     not checked. Without --runtime-methods, accessor names
                     are looked up in the repository and the SDK headers
                     only, and an accessor not found there says that
                     private framework methods were not consulted (JSON:
                     private_methods_consulted false); --runtime-methods
                     FILE (repeatable) also looks them up in a run-time
                     method list (sdk_selectors.py --runtime-methods,
                     private methods included). --json prints the same as
                     one JSON document. Exit statuses as for ivars.
  codedb.py verifyinventory [--update] [--snapshot FILE] [--only-snapshot]
                     [CLASS...]
                     Compare the inventory's parsed classes, superclasses,
                     protocols, ivars, methods and properties with the
                     database, one class at a time (all classes, or those
                     named), and with --snapshot, a runtime snapshot's
                     superclasses, ivars and methods with the database
                     (verify_inventory.py documents both and the rules that
                     explain a disagreement). Exit 0 nothing unexplained, 1
                     unexplained disagreements, 3 none but the database is
                     incomplete, 2 error.
  codedb.py macros [--update] [--file F | --name N | --class C]
                     The repository's macro definitions (all, those in file
                     F, those named N, or those of kind C), each with its
                     kinds in the table of hidden-callers.md section 6
                     (send, stringify, control-flow, context, method, paste,
                     class, method-family; decided by facts), its body, the
                     facts from its tokens and from the AST of its
                     expansions (see extract_sends.cpp, "Macros and
                     conditional compilation"), how many sites expand it,
                     where it is redefined or undefined, and a CONFLICT when
                     units see different definitions of the name (seen by
                     disjoint sets of units; definitions the same units see
                     in turn are a redefinition). With --name, also a macro
                     defined outside the repository that repository code
                     expands, a text search for #define N in the ranges
                     every unit skips (a definition no unit compiles), and
                     the same search in files that are not parsed.
                     INCOMPLETE for --file when no unit reads F.
  codedb.py macrouses [--update] NAME
                     Every expansion of the macro NAME (each site once,
                     however many units recorded it) with its enclosing
                     function or method, its nesting (written in a file, in
                     another expansion's arguments, or made by another
                     macro's body) and its arguments; for a macro defined
                     outside the repository, the count per file. When NAME is
                     a method (-[Class sel], +[Class sel]), a function or a
                     class with an @implementation: the macros its code
                     expands, each with its kinds (a port must translate
                     each), and the macros that make its methods. Searches
                     the ranges every unit skips, and files that are not
                     parsed, for NAME as a word.
  codedb.py skipped [--update] FILE
                     The lines of FILE that some or all units do not compile
                     (inactive #if branches), in segments of lines skipped
                     by the same units, each with the directives that skip
                     it and whether every unit that reads FILE skips it or
                     which targets compile it; then each condition's value
                     per unit. Include guards are not listed (named on one
                     line). INCOMPLETE when no unit reads FILE.
  codedb.py sdkmethods [--update] SELECTOR
                     Who outside the repository (the SDK, from every header
                     a unit parses or imports through a module) declares
                     SELECTOR: as a method, or as a property's getter or
                     setter, in a class, protocol or category, with its
                     framework and whether it is an @optional protocol
                     method or an IBAction (table sdk_method). Each module's
                     declarations are recorded once, by the unit that holds
                     its claim (sdk_claim); INCOMPLETE when a module a unit
                     loads has no claim.
  codedb.py swiftimports [--update] [--module M] NAME | --header PATH |
                         --not-importable CLASS
                     How Swift imports Objective-C declarations through the
                     bridging header of M (default: the only captured module
                     that has one, iTerm2SharedARC), from the swift_import
                     rows joined to the database's declarations by USR: by
                     NAME (a selector, -[Class sel], Class.property, a class,
                     global or macro name, a Swift name, or a USR); every
                     declaration the database has for a header, imported or
                     not; or the declarations of a class or protocol Swift
                     does not import. Each line is the declaration, its
                     kind, and "imported as" its Swift name and declaration,
                     "imported through the property" (an accessor), "NOT
                     IMPORTED:" with the reason a rule gives, "ABSENT FROM
                     THE SYMBOL GRAPH:" with "probably usable through" a
                     colliding member or "reason unknown; it may still be
                     usable from Swift", "IMPORTED WITHOUT A USABLE TYPE",
                     or "NOT IN THIS TABLE" (a header of a framework's
                     Clang module, which Swift imports as a module). A name
                     nothing declares is said to be so. The rules and
                     limits are in swiftimports.py. Exit 0, 1, 3 and 2 as the
                     queries below; 3 also when the module's rows are not
                     current.
  codedb.py classinfo [--update] CLASS
                     The superclass chain of CLASS through the repository's
                     classes (objc_class) into the SDK's (sdk_class), the
                     protocols the class and each superclass list, with
                     their categories and extensions (objc_adoption,
                     sdk_adoption), and the protocols those inherit.
  codedb.py macrolint [--classification FILE] [--write [--prune]]
                     [--allow-unreviewed]
                     The lint of hidden-callers.md section 6: every macro
                     that the migration's scope defines or expands, and that
                     is of a kind in that section's table, has a row in
                     docs/swift-migration/macro-classification.tsv with its
                     current digest, its kinds, and a reading (what it
                     expands to and reaches, written by a person; UNREVIEWED
                     until then). A macro has the kinds of the macros it
                     expands, to any depth, marked "(via M)"; a macro from
                     outside the repository counts as one that sends when a
                     send row says its body sends. Fails on a macro with no
                     row, a definition whose digest changed, kinds that
                     changed, a row whose macro is gone and, unless
                     --allow-unreviewed, a row still UNREVIEWED; reports,
                     without failing, a row whose line no longer names the
                     definition (LINE MOVED: same digest, so the reading
                     holds; --write updates the line). Covers only
                     macros a captured unit reads in the captured
                     configuration, and lists the #defines in code no unit
                     compiles. --write rewrites the file from the database
                     first, keeping each reading whose digest is unchanged
                     and keeping rows of macros this run did not see
                     (marked not-seen-in-this-run) unless --prune, which is
                     refused on an incomplete database. Exit 0 clean and
                     complete, 1 failures (even when the database is also
                     incomplete), 3 no failure but the database is
                     incomplete, 2 error.
  codedb.py crosscheck [--target T] [--file F] [--list-explained]
                     [--build-root DIR]...
                     Compare each Objective-C unit with its object file
                     under Build/, or under each --build-root DIR in turn
                     (read-only): the selectors it sends, the methods and
                     the ivars it defines, against the unit's rows, and the
                     number of call sites of each selector against the
                     unit's send sites; every difference is explained by a
                     rule (printed with the output) or UNEXPLAINED; units
                     whose object is missing, older than a file they read,
                     or unreadable, and units whose rows are not current,
                     are not compared and are listed. See crosscheck.py.
                     Exit 0 nothing unexplained and every unit compared, 1
                     unexplained differences, 3 some units not compared, 2
                     error.
  codedb.py swift-capture --log LOG --into DIR
                     Run by capture_compile_commands.sh after its build: keep
                     the build log's SwiftDriver commands of the
                     Variant-NoSanitizers variant and a copy of each module's
                     .SwiftFileList in DIR (the fragments' swift/). Exit 2
                     when the project compiles Swift files and the log has
                     no such command (the capture then fails).
  codedb.py adopt-swift-capture [--log LOG] [--accept-edited-files]
                     One time only, for a capture made before captures kept
                     the Swift inputs: keep them from its build log and the
                     .SwiftFileList files under Build/. Refuses if a file list
                     was written outside the capture's build, or (unless
                     --accept-edited-files) a listed Swift file was modified
                     after the capture. Prints what it asserts.
  codedb.py other-projects
                     Print the other projects of other_projects.json that are
                     in the tree, one per line, tab-separated: name, project,
                     configuration, targets and extra build settings
                     (space-separated). capture_compile_commands.sh
                     --other-projects reads it.
  codedb.py capture-record [--project NAME]
                     With --project, the record of the other project NAME:
                     its project, the digest of its other_projects.json
                     entry, its own build settings digest, the SDK and the
                     date. Without it:
                     Print, as JSON, what a capture records: the digest of
                     the project's build settings, the SDK and the date, as
                     of now. capture_compile_commands.sh runs it before its
                     build and writes its output to .capture-record in the
                     fragments directory only if the build succeeds. cdb
                     takes the build settings digest from that record, never
                     from the project as it is when the compile database is
                     built, and refuses fragments that have none.
  codedb.py adopt-capture --i-know-the-project-is-unchanged-since
                     One time only, for the fragments captured before
                     captures wrote a record: write the record from the
                     project and SDK as they are now. It prints exactly what
                     it asserts. Refuses fragments that have a record.
                     Exit 0; 2 on error or while the lock is held.
  codedb.py hold-lock [--label L] -- PROGRAM [ARGS...]
                     Take the lock, then run PROGRAM in this process (exec)
                     holding it on fd 9. capture_compile_commands.sh runs
                     itself this way. Exit 2 while another holds the lock.

Swift modules (when the capture kept the Swift inputs) have the states
current, stale ("command changed", "file list changed", "compiler changed",
"reader changed", "migration scope changed", "input changed: PATH", "input
missing: PATH"), missing, failed and no longer captured; any that is not
current makes every query incomplete (3), as for units, and so does a
captured file list that no longer matches the project's Swift files for that
target. Without a Swift capture, queries say that Swift is not in this
database, as before the Swift side existed.

Query exit statuses (every query: sends, methods, selrefs, reflective, reach, swiftrefs, ivars, ivarrefs, statics,
staticrefs, classstate, macros, macrouses, skipped; macrolint and verifyinventory state their own):
  0  answered, with at least one row
  1  answered, with no rows. Callers in files that are not parsed are not
     rows: the status block says how many such files there are.
     0 and 1 are returned only when every unit is current, none has parse
     errors, the compile database covers the project, and the project's
     build settings are the ones the capture was made with (for methods and
     reach, also only when every file a current unit reads has its
     declarations recorded); 1 only when, in addition, the text search finds
     none of the forms it searches in a file that is not parsed (for sends:
     the first keyword as a message send, and the property of a
     setter-shaped, is-prefixed or unary selector with dot syntax; each
     query states its forms). reflective searches no text.
  3  answered, but incomplete: some unit is not current (stale for any
     reason, missing from the database, its last extraction failed, recorded
     with parse errors, or in the database but not in the compile database),
     there is no compile database, the compile database does not cover the
     project's sources, the build settings changed (see below), or there are
     no rows and the text search finds a match in a file that is not
     parsed. Sends in those units or files may be missing or wrong;
     a send added to an edited file since its extraction is not printed at
     all. The INCOMPLETE line says how many units are in each state.
  2  error (no database, old schema, bad arguments, or --update could not
     take the lock)

Unit states. One function, unit_states(), decides the state of every unit, and
both `update` and every query use it:
  current        extracted from the inputs, command, extractor, compiler and
                 SDK in use
  stale          extracted, but something changed since; the reason is one of
                 "input changed: PATH", "input missing: PATH", "command
                 changed", "extractor changed", "compiler changed" (the
                 Homebrew LLVM the extractor runs on now reports another
                 version than the unit records), "compiler unknown",
                 "SDK changed" (the SDK xcrun reports now, path, version
                 or build version, is not the one the unit was extracted
                 with, or not the one the compile database was built with),
                 "migration scope changed"
  missing        in the compile database, not in the database
  failed         its last extraction failed (killed by the watchdog, crashed,
                 or could not write); any rows are from an earlier extraction
  orphan         in the database, not in the compile database
and, separately, whether the unit was recorded with parse errors. Every query
prints the count in each state, names the first few units in each state that
is not current, and marks each row that comes from a unit that is not current
with the reason.

Locking: update, cdb and capture_compile_commands.sh (through hold-lock) take
an exclusive flock(2) on tmp/codedb/codedb.lock (next to the compile
database), without waiting, and hold it for the life of the process. A
second one exits 2 and names the holder. The kernel releases the lock when
its holder dies in any way, so there is no stale lock and no --break-lock.
The file holds the holder's pid, command and start time, for messages only.
While update runs an extraction, and while the capture runs its build, the
holder records that process group in the file; if the holder is killed with
SIGKILL, the group survives in its own session, and the next holder kills it
(if its leader still has the recorded start time) before it proceeds.

Signals: SIGINT (Ctrl-C), SIGTERM and SIGHUP stop update, release the lock
and kill the running extraction's process group. But a command started in
the background by a non-interactive shell (for example `codedb.py update &`
in a script, or a tool that runs it that way) has SIGINT ignored from the
start, and an ignored signal cannot be caught: send TERM or HUP instead.
guard.sh and capture_compile_commands.sh behave the same way.

Refreshing the compile database: run capture_compile_commands.sh (one clean
Development build), then any command above rebuilds compile_commands.jsonl
from the new fragments. It must be redone when source files are added,
removed or renamed, or when compile flags change. `update`, `cdb` and every
query compare the project's source files with the compile database, and a
digest of the project's build settings (every build configuration's
settings and .xcconfig file, every per-file COMPILER_FLAGS, the
configuration lists of the project and its targets) with the one the
capture recorded before its build, and say when it is out of date. Other
changes to project.pbxproj (comments, groups, localizations) do not count.

Written in Python 3 with its standard library. It also runs `xcrun` to find the
macOS SDK (the one use of Xcode's tools besides the build itself), `git` (to
list the repository's files), `ps`, the extractor (extractor/build.sh builds
it on upstream LLVM), and guard.sh. The Swift side (swiftdb.py) runs the
Swift compiler and its driver that the captured commands name, and its reader
(swiftreader/build.sh builds it with RapidJSON).
"""

import argparse
import collections
import fcntl
import hashlib
import io
import json
import os
import re
import resource
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import swiftdb  # noqa: E402
REPO_ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
GUARD = os.path.join(HERE, 'guard.sh')
EXTRACTOR_DIR = os.path.join(HERE, 'extractor')
BUILD_SCRIPT = os.path.join(EXTRACTOR_DIR, 'build.sh')
# The files whose digest is the extractor's version, in the order build.sh
# lists them to shasum.
EXTRACTOR_SOURCE_NAMES = ('build.sh', 'extract_sends.cpp', 'reflective_table.h')

# PRAGMA user_version of the database; the extractor's kSchemaVersion.
SCHEMA_VERSION = 12
# The tables whose rows belong to a unit (column tu), deleted with it.
UNIT_TABLES = ('send', 'tu_input', 'objc_method', 'objc_method_override', 'objc_property', 'selector_ref',
               'reflective_call', 'decl_source', 'objc_ivar', 'c_static', 'ivar_ref', 'static_ref', 'objc_impl',
               'macro_def', 'macro_undef', 'macro_ast_fact', 'macro_expansion', 'macro_use_count', 'pp_condition',
               'pp_skipped', 'objc_class', 'objc_adoption', 'sdk_claim', 'tu_module', 'sdk_method', 'sdk_class',
               'sdk_adoption', 'function_ref')

C_FAMILY_EXTENSIONS = ('.c', '.m', '.mm', '.cpp', '.cc', '.cxx')
# The migration's scope, as docs/swift-migration/README.md section 2 defines
# it: the directories (relative to the repository root) whose code is to be
# moved to Swift. Sends are recorded wherever they are in the repository;
# this list only sets send.in_migration_scope (the extractor gets it with
# --migration-scope), the files on disk the coverage check lists when no
# target compiles them, and the status block's text. ModernTests/ is not in
# it: section 2 scopes code compiled into the app or its helper programs, and
# test code is not that. Rows from test targets are still extracted, and
# labeled "test code" (TEST_PRODUCT_TYPES).
MIGRATION_SCOPE_DIRS = ('sources/', 'ThirdParty/PSMTabBarControl/', 'SignedArchive/', 'pidinfo/',
                        'iTerm2SandboxedWorker/', 'ShellLauncher/', 'ColorPicker/', 'SearchableComboListView/',
                        'BetterFontPicker/')
DISK_SCOPE_DIRS = tuple(d.rstrip('/') for d in MIGRATION_SCOPE_DIRS)
MIGRATION_SCOPE_TEXT = ','.join(MIGRATION_SCOPE_DIRS)
SCOPE_STATEMENT = ("callers anywhere in the repository are listed; the migration's scope is %s and rows elsewhere "
                   "are marked outside the migration's scope" % ', '.join(MIGRATION_SCOPE_DIRS))

# The first item of REACH_NOT_COVERED, and what replaces it when the Swift
# side is in the database.
REACH_SWIFT_NOT_COVERED = 'Swift callers (Swift sources are not in this database)'
REACH_SWIFT_NOT_COVERED_WITH_SWIFT = [
    swiftdb.PROTOCOL_WITNESS_NOT_COVERED,
    'Swift code in inactive #if branches, which is only searched as text (see Swift code that is not compiled, '
    'above), and Swift built for other configurations and architectures',
    'the call of super.init() the compiler adds at the end of a Swift initializer that calls no initializer of '
    'its superclass: the dump does not show it (it is added after type checking), so it is not among the Swift '
    'references to init',
    'selectors Swift builds from strings: Selector("..."), NSSelectorFromString, perform(_:) or similar with a '
    'selector held in a variable',
    'Swift files that no captured module compiles, and Swift modules that are stale or failed (see swift modules '
    'in the status block)',
    'Swift dynamic lookups (AnyObject, optional protocol methods) are matched by selector alone, whatever class '
    'receives them',
]
# What no query of this database sees, whatever it asks.
NOT_IN_DATABASE_COMMON = [
    'Swift sources: Swift callers of Objective-C, and methods and properties declared in Swift (also those in the '
    'generated -Swift.h headers under Build/, which are not read for declarations)',
    'xib and storyboard files (actions, outlets, bindings, key paths)',
    'the sdef (AppleScript commands and properties)',
    'plists, Core Data models and other resources',
    'code in inactive #if/#ifdef branches',
    'other build configurations (Beta, Deployment, Nightly) and the other architecture',
    'code written in files outside the repository (the SDK, the compiler resource headers, Homebrew), and '
    'units whose main file is outside the repository (Swift package checkouts) or generated under Build/',
    'files that only targets of iTerm2.xcodeproj that the capture does not build compile (see Not parsed, '
    'class c)',
]
# What replaces the first item above when the Swift side is in the database.
SWIFT_NOT_IN_DATABASE = (
    'Swift: references in inactive #if branches (reach searches them as text); the call of super.init() the '
    'compiler adds at the end of an initializer that calls none (not in the dump); selectors Swift builds from strings (Selector("..."), '
    'NSSelectorFromString, perform(_:) or similar with a selector in a variable); Swift files that no captured '
    'module compiles, and modules that are stale or failed (see swift modules); methods and properties declared in '
    'Swift are in the Swift tables (codedb.py swiftrefs, reach), not among the Objective-C declarations')
# The "Not in this database" list of `sends`.
NOT_IN_DATABASE = [
    '@selector expressions and reflective calls (the selector a performSelector:, NSSelectorFromString, '
    'valueForKey:, respondsToSelector: or similar call names): in the database, but not in this answer; ask '
    'codedb.py selrefs or reach (the call itself is a send and is here)',
] + NOT_IN_DATABASE_COMMON + [
    'sends the compiler generates with no message expression in the source: boxed literals '
    '(@[], @{}, @()), for-in enumeration, retain/release/autorelease and other ARC or MRC '
    'runtime calls, synthesized accessors, @synchronized and exceptions',
    'sends in an operand that is not evaluated (sizeof, alignof, typeof, @encode, decltype, noexcept): '
    'they send nothing',
]
METHODS_NOT_IN_DATABASE = NOT_IN_DATABASE_COMMON + [
    'methods added or replaced at run time (class_addMethod, class_replaceMethod, method_exchangeImplementations, '
    'method_setImplementation, imp_implementationWithBlock): their call sites are listed by codedb.py reflective',
    'methods of classes outside the repository (the SDK), which a send of the selector can also reach',
    'declarations in a header read only through a compiled module',
    'declarations that a header makes through a macro that units of one target define differently, without an '
    "#if that skips part of the header: a header's declarations are recorded once per target, content and view (the "
    'language and the inactive #if branches), from the first unit of the target that reads it with that view',
    'callers: ask codedb.py reach',
]
SELREFS_NOT_IN_DATABASE = NOT_IN_DATABASE_COMMON + [
    'message sends of the selector: ask codedb.py sends or reach',
    'selector names built at run time (formats, concatenation, variables): those calls have argument kind '
    'dynamic and are listed by codedb.py reflective, not here; calls whose argument is _cmd (argument kind '
    'self-selector) or nil (argument kind nil) are listed by codedb.py reflective --all',
    'selectors compared or stored as strings without a recognized call (NSStringFromSelector, sel_getName, '
    'isEqualToString:, dictionary keys)',
    'calls not in the table of recognized reflective calls (codedb.py reflective --list)',
    '@selector expressions and reflective calls in an operand that is not evaluated (sizeof, typeof, @encode)',
]
REFLECTIVE_NOT_IN_DATABASE = NOT_IN_DATABASE_COMMON + [
    'calls not in the table of recognized reflective calls (codedb.py reflective --list), among them '
    'NSStringFromSelector, sel_getName, class_getName, NSStringFromClass and object_getClass',
    'reflective calls in an operand that is not evaluated (sizeof, typeof, @encode)',
]
REACH_NOT_COVERED = [
    REACH_SWIFT_NOT_COVERED,
    'xibs and storyboards: actions (First Responder actions in MainMenu.xib among them), outlets, bindings and '
    'key paths',
    'the sdef (AppleScript commands and properties)',
    'plists and Core Data models',
    'selectors and keys built at run time beyond the sites listed by codedb.py reflective (argument kind dynamic): '
    'the strings those sites build are not known',
    'calls not in the table of recognized reflective calls (codedb.py reflective --list), and selectors compared '
    'or stored as strings',
    'code that is not parsed (see Not parsed), code in inactive #if branches, other build configurations and the '
    'other architecture',
    'the receiver: every send and reference of the selector is listed, whatever class it reaches',
    'overrides the defining unit cannot see: the overrides listed above include only relationships visible through '
    "declarations that unit can see, so a method that overrides a superclass method declared only in the "
    "superclass's .m file, or that satisfies a conformance declared only in a superclass's private class extension, "
    'is not listed; codedb.py methods SELECTOR lists every definition in every class',
]
# The "Not covered by reach" item about callers that are not parsed at all.
FRAMEWORK_CALLERS_NOT_COVERED = (
    'calls made by system frameworks and other code that is not in this database (prebuilt frameworks in the '
    'repository, Swift) are not recorded. A method that overrides or implements something declared in code that is '
    'not in this database is listed above as possibly called from outside. Methods the frameworks call without a '
    'declaration the method overrides that its unit can see are not identified, for example: a method of a protocol '
    'the class does not declare it adopts (validateUserInterfaceItem: in a class that declares NSMenuItemValidation '
    "but not NSUserInterfaceValidations); an override of a private framework method that no public header declares "
    "(an NSWindow subclass's _usesCustomDrawing); +load in a category on NSObject itself; actions sent through the "
    'responder chain and methods named only in xibs, storyboards, the sdef or plists; and accessors reached only by '
    'key-value coding from a binding')
SDK_MODULE_NOTE = ('note: the SDK is the one xcrun reports now. A change of its path, version or build version '
                   'since a unit was extracted, or since the compile database was built, is detected and makes the '
                   'units stale. Every file a unit reads itself is recorded and compared, SDK module maps and headers '
                   'included. A header in the SDK or the compiler resource directory that a unit reads only through '
                   'a compiled module is not recorded: the SDK path, version and build version stand for it, so an '
                   'edit to it that keeps them is not detected.')
# Product types of the project's test targets; their rows are labeled
# "test code".
TEST_PRODUCT_TYPES = ('com.apple.product-type.bundle.unit-test', 'com.apple.product-type.bundle.ui-testing')
# The text search of files that are not parsed stops after this many matches.
TEXT_MATCHES_MAX = 50
# The migration's own tools and their test fixtures: not listed as not parsed
# and not searched.
MIGRATION_TOOLS_DIR = 'tools/swift_migration/'
# How many files of class (d), compiled by no target of any project found, the
# status block lists.
NOT_PARSED_LISTED = 20
EXTRA_ROWS_NOTE = ('note: rows can be listed for sends the binary never makes: in a template pattern as well as '
                   'in its instantiations (both arms of an if constexpr in the pattern), in a default argument that '
                   'no call uses, in a static or inline function that is never emitted, and in code that a constant '
                   'condition skips (in_constant_false_branch marks the cases where the compiler certainly emits '
                   'nothing). The operands of _Generic and __builtin_choose_expr that are not chosen are not listed.')

# Flags of the captured Apple clang command that take a value and are dropped
# with it: they write build products, or read Xcode-private files.
DROP_WITH_VALUE = {
    '-o', '-MF', '-MT', '-MQ', '--serialize-diagnostics', '-ivfsstatcache',
    '-index-store-path', '-index-unit-output-path', '-gen-cdb-fragment-path',
}
# -gmodules only changes debug information, but it makes clang wrap module
# files in an object-file container that a syntax-only tool cannot read.
DROP_SINGLE = {'-c', '-MMD', '-MD', '-M', '-MM', '-fmodules-validate-once-per-build-session', '-gmodules'}
DROP_PREFIXES = ('-fbuild-session-file=', '-fmodules-prune-interval=', '-fmodules-prune-after=',
                 '-fmodules-cache-path=', '--serialize-diagnostics=', '-index-')
# Values of -Xclang that upstream clang rejects or that are Apple-only.
DROP_XCLANG_PREFIXES = ('-clang-vendor-feature=', '-W')
DROP_XCLANG_EXACT = {'-fno-odr-hash-protocols'}


class CodeDBError(Exception):
    pass


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


MODULE_CACHE_FLAG = '-fmodules-cache-path='


def command_digest(args):
    """SHA-256 of the arguments joined with NUL, as the extractor computes it.
    The module cache path is left out: it says where the compiler keeps its
    private cache, not what it compiles, so a copy of the database that uses
    its own cache (--module-cache) has the same commands."""
    return sha256_bytes(b'\0'.join(a.encode('utf-8') for a in args if not a.startswith(MODULE_CACHE_FLAG)))


def is_warning_flag(arg):
    return arg.startswith('-W') and not arg.startswith(('-Wl,', '-Wa,', '-Wp,'))


def translate_command(arguments, pch_map, module_cache, sdk_path):
    """Translate a captured Apple clang command for upstream clang.

    `arguments` is the fragment's argument list including the compiler path.
    Returns (args, dropped): args has no compiler path, and dropped lists every
    removed argument (with its value) in order.

    Dropped: flags that write build products (-o, -MMD, -MF, -MT, -MQ, -MD,
    --serialize-diagnostics, -index-store-path, -index-unit-output-path,
    -gen-cdb-fragment-path, -c), flags that read Xcode-private files
    (-ivfsstatcache, -fbuild-session-file=, and with it
    -fmodules-validate-once-per-build-session), module cache housekeeping
    (-fmodules-prune-*), -gmodules (debug information only; its module
    container format needs code generation), Apple-only frontend flags (-Xclang
    -clang-vendor-feature=..., -Xclang -fno-odr-hash-protocols), and every
    warning flag (-W..., -Xclang -W...), since upstream warnings differ and
    -Werror would turn them into errors.
    Replaced: -fmodules-cache-path (a private cache), -isysroot (the SDK from
    xcrun), and -include of an Xcode precompiled-header copy (the prefix header
    source it was compiled from). Added: -w.
    """
    args = []
    dropped = []
    a = list(arguments[1:])
    i = 0
    while i < len(a):
        x = a[i]
        nxt = a[i + 1] if i + 1 < len(a) else None
        if x in DROP_WITH_VALUE:
            dropped += [x, nxt] if nxt is not None else [x]
            i += 2
            continue
        if x in DROP_SINGLE or x.startswith(DROP_PREFIXES) or is_warning_flag(x):
            dropped.append(x)
            i += 1
            continue
        if x == '-Xclang' and nxt is not None and (
                nxt in DROP_XCLANG_EXACT or nxt.startswith(DROP_XCLANG_PREFIXES)):
            dropped += [x, nxt]
            i += 2
            continue
        if x == '-isysroot' and nxt is not None:
            args += ['-isysroot', sdk_path]
            i += 2
            continue
        if x == '-include' and nxt is not None and nxt in pch_map:
            args += ['-include', pch_map[nxt]]
            i += 2
            continue
        if x == '-include' and nxt is not None and nxt.endswith('.pch') and not os.path.exists(nxt):
            raise CodeDBError('no prefix header source known for precompiled header %s' % nxt)
        args.append(x)
        i += 1
    args.append('-fmodules-cache-path=' + module_cache)
    args.append('-w')
    return args, dropped


def output_facts(output):
    """(target, configuration, arch, variant) from an object path like
    .../Variant-NoSanitizers/iTerm2.build/Development/T.build/Objects-normal/arm64/x.o"""
    parts = output.split('/')
    for i, p in enumerate(parts):
        if p.startswith('Objects-') and i >= 2 and i + 1 < len(parts):
            target = parts[i - 1][:-len('.build')] if parts[i - 1].endswith('.build') else parts[i - 1]
            variant = next((q for q in parts if q.startswith('Variant-')), '')
            return target, parts[i - 2], parts[i + 1], variant
    return None


def is_sanitizer_variant(output):
    return '/Variant-ASan/' in output or '/Variant-TSan/' in output or '-asan/' in output or '-tsan/' in output


def rel(path, root):
    path = os.path.realpath(path)
    root = os.path.realpath(root)
    if path.startswith(root + os.sep):
        return path[len(root) + 1:]
    return path


def in_repo_source(relpath):
    """A C-family source file inside the repository that the compile
    database covers: anything but generated files under Build/."""
    return (not os.path.isabs(relpath) and not relpath.startswith('Build/') and
            relpath.endswith(C_FAMILY_EXTENSIONS))


def in_migration_scope(relpath):
    return not os.path.isabs(relpath) and relpath.startswith(MIGRATION_SCOPE_DIRS)


def read_fragment(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read().strip()
    if text.endswith(','):
        text = text[:-1]
    return json.loads(text)


def sdk_info():
    """(path, version) of the SDK xcrun reports. The version includes the
    SDK's build version ('27.0 build 26A425'), so that an SDK rebuilt under
    the same version string is another SDK."""
    try:
        path, version, build = (subprocess.run(['xcrun', flag], capture_output=True, text=True,
                                               check=True).stdout.strip()
                                for flag in ('--show-sdk-path', '--show-sdk-version', '--show-sdk-build-version'))
    except (OSError, subprocess.CalledProcessError) as e:
        raise CodeDBError('cannot locate the macOS SDK with xcrun: %s' % e)
    return path, '%s build %s' % (version, build)


_CURRENT_SDK = []


def current_sdk():
    """(path, version) of the SDK xcrun reports now, asked once per process."""
    if not _CURRENT_SDK:
        _CURRENT_SDK.append(sdk_info())
    return _CURRENT_SDK[0]


class CodeDBLocked(CodeDBError):
    pass


def extractor_source_digest(directory=EXTRACTOR_DIR):
    """The extractor's version: SHA-256 of the output of
    `shasum -a 256 build.sh extract_sends.cpp reflective_table.h` in the
    extractor's directory, as build.sh computes it."""
    listing = ''.join('%s  %s\n' % (sha256_file(os.path.join(directory, n)), n) for n in EXTRACTOR_SOURCE_NAMES)
    return sha256_bytes(listing.encode('utf-8'))


# --- Xcode project files -----------------------------------------------------

_UNQUOTED = frozenset('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$+/:.-')
# Octal escapes 200 to 375 name characters of the NeXTSTEP encoding, as plutil
# (CoreFoundation) reads them; 376 and 377 have none and are an error there.
# Read from plutil, one escape at a time.
_NEXTSTEP_HIGH = ('\u00a0\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u00c7\u00c8\u00c9\u00ca\u00cb\u00cc\u00cd\u00ce\u00cf'
                  '\u00d0\u00d1\u00d2\u00d3\u00d4\u00d5\u00d6\u00d9\u00da\u00db\u00dc\u00dd\u00de\u00b5\u00d7\u00f7'
                  '\u00a9\u00a1\u00a2\u00a3\u2044\u00a5\u0192\u00a7\u00a4\u2019\u201c\u00ab\u2039\u203a\ufb01\ufb02'
                  '\u00ae\u2013\u2020\u2021\u00b7\u00a6\u00b6\u2022\u201a\u201e\u201d\u00bb\u2026\u2030\u00ac\u00bf'
                  '\u00b9\u02cb\u00b4\u02c6\u02dc\u00af\u02d8\u02d9\u00a8\u00b2\u02da\u00b8\u00b3\u02dd\u02db\u02c7'
                  '\u2014\u00b1\u00bc\u00bd\u00be\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e7\u00e8\u00e9\u00ea\u00eb'
                  '\u00ec\u00c6\u00ed\u00aa\u00ee\u00ef\u00f0\u00f1\u0141\u00d8\u0152\u00ba\u00f2\u00f3\u00f4\u00f5'
                  '\u00f6\u00e6\u00f9\u00fa\u00fb\u0131\u00fc\u00fd\u0142\u00f8\u0153\u00df\u00fe\u00ff')
_ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v',
            '"': '"', '\\': '\\', "'": "'"}


class _PlistParser:
    def __init__(self, text):
        self.text = text
        self.i = 0

    def fail(self, what):
        line = self.text.count('\n', 0, self.i) + 1
        raise CodeDBError('property list: %s at line %d' % (what, line))

    def skip(self):
        t = self.text
        n = len(t)
        while self.i < n:
            c = t[self.i]
            if c.isspace():
                self.i += 1
            elif t.startswith('//', self.i):
                end = t.find('\n', self.i)
                self.i = n if end < 0 else end + 1
            elif t.startswith('/*', self.i):
                end = t.find('*/', self.i + 2)
                if end < 0:
                    self.fail('unterminated comment')
                self.i = end + 2
            else:
                break

    def expect(self, c):
        self.skip()
        if self.i >= len(self.text) or self.text[self.i] != c:
            self.fail('expected %r' % c)
        self.i += 1

    def value(self):
        self.skip()
        if self.i >= len(self.text):
            self.fail('unexpected end')
        c = self.text[self.i]
        if c == '{':
            self.i += 1
            result = {}
            while True:
                self.skip()
                if self.text.startswith('}', self.i):
                    self.i += 1
                    return result
                key = self.string()
                self.expect('=')
                result[key] = self.value()
                self.expect(';')
        if c == '(':
            self.i += 1
            result = []
            while True:
                self.skip()
                if self.text.startswith(')', self.i):
                    self.i += 1
                    return result
                result.append(self.value())
                self.skip()
                if self.text.startswith(',', self.i):
                    self.i += 1
                elif not self.text.startswith(')', self.i):
                    self.fail("expected ',' or ')'")
        if c == '<':
            end = self.text.find('>', self.i)
            if end < 0:
                self.fail('unterminated data')
            digits = ''.join(self.text[self.i + 1:end].split())
            self.i = end + 1
            try:
                return bytes.fromhex(digits)
            except ValueError:
                self.fail('bad data')
        return self.string()

    def string(self):
        self.skip()
        t = self.text
        if self.i < len(t) and t[self.i] == '"':
            self.i += 1
            out = []
            while True:
                if self.i >= len(t):
                    self.fail('unterminated string')
                c = t[self.i]
                if c == '"':
                    self.i += 1
                    return ''.join(out)
                if c == '\\':
                    if self.i + 1 >= len(t):
                        self.fail('unterminated string')
                    e = t[self.i + 1]
                    if e == 'U':
                        out.append(chr(int(t[self.i + 2:self.i + 6], 16)))
                        self.i += 6
                    elif e in '01234567':
                        j = self.i + 1
                        while j < len(t) and j < self.i + 4 and t[j] in '01234567':
                            j += 1
                        code = int(t[self.i + 1:j], 8)
                        if code < 0o200:
                            out.append(chr(code))
                        elif code - 0o200 < len(_NEXTSTEP_HIGH):
                            out.append(_NEXTSTEP_HIGH[code - 0o200])
                        else:
                            self.fail('octal escape \\%o has no NeXTSTEP character' % code)
                        self.i = j
                    else:
                        out.append(_ESCAPES.get(e, e))
                        self.i += 2
                    continue
                out.append(c)
                self.i += 1
        start = self.i
        while self.i < len(t) and t[self.i] in _UNQUOTED:
            self.i += 1
        if self.i == start:
            self.fail('expected a string')
        return t[start:self.i]


def parse_openstep_plist(text):
    """Parse a property list in the old OpenStep text format that Xcode uses
    for project.pbxproj. Scalars are strings, as plutil reads them. A leading
    byte-order mark is ignored, as plutil ignores it."""
    if text.startswith('\ufeff'):
        text = text[1:]
    p = _PlistParser(text)
    result = p.value()
    p.skip()
    if p.i != len(text):
        p.fail('unexpected text after the property list')
    return result


def read_pbxproj(path):
    with open(path, 'r', encoding='utf-8') as f:
        return parse_openstep_plist(f.read())


# --- The capture record --------------------------------------------------------

# Next to the .captured stamp in the fragments directory. Not named *.json, so
# that it is never read as a fragment.
CAPTURE_RECORD = '.capture-record'


def capture_record(root):
    """What capture_compile_commands.sh records about a capture, computed
    before its build starts: the digest of the project's build settings, the
    SDK and the date. The script writes it next to the .captured stamp only
    when the build succeeds."""
    sdk_path, sdk_version = sdk_info()
    return {'build_settings_sha256': build_settings_digest(root), 'sdk_path': sdk_path, 'sdk_version': sdk_version,
            'captured_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}


# --- Other Xcode projects ------------------------------------------------------
#
# In-repository projects whose code the main capture's build does not compile
# (frameworks the app embeds prebuilt, and command line tools), listed in
# other_projects.json: for each, the project, the targets to build and keep,
# the configuration and extra build settings. `capture_compile_commands.sh
# --other-projects` builds each in its own directories under tmp/codedb
# (other-build/NAME, fragments in other-fragments/NAME, with a .captured stamp
# and a .capture-record like the main capture's), and `codedb.py cdb` merges
# those fragments into the compile database, each unit under the target
# NAME:TARGET with the project recorded.

OTHER_PROJECTS_SPEC = os.path.join(HERE, 'other_projects.json')
OtherProject = collections.namedtuple('OtherProject', 'name project targets configuration settings stale_copy')
_OTHER_NAME = re.compile(r'^[A-Za-z0-9_][A-Za-z0-9_.-]*$')
# A target or setting: no white space or shell characters, except a build
# setting reference $(NAME), which xcodebuild expands.
_OTHER_WORD = re.compile(r'^(?:[^\s\'"\\$`]|\$\([A-Za-z0-9_]+\))+$')
OTHER_CAPTURE_HINT = 'run capture_compile_commands.sh --other-projects'


def parse_other_projects(text):
    """[OtherProject] from the text of other_projects.json. Raises
    CodeDBError when an entry lacks a field or has a value the capture
    script cannot pass safely (a name that is not a plain word, an absolute
    project path, no targets, a target or setting with white space or shell
    characters)."""
    try:
        data = json.loads(text)
    except ValueError as e:
        raise CodeDBError('other_projects.json is not JSON: %s' % e)
    if not isinstance(data, list):
        raise CodeDBError('other_projects.json must hold a list of projects')
    out, names = [], set()
    for e in data:
        try:
            name, project, targets = e['name'], e['project'], e['targets']
            configuration, settings = e['configuration'], e['settings']
        except (KeyError, TypeError) as x:
            raise CodeDBError('other_projects.json: an entry lacks %s: %r' % (x, e))
        words = list(targets) + list(settings) + [configuration, project]
        if (not isinstance(name, str) or not _OTHER_NAME.match(name) or name in names or
                not isinstance(project, str) or os.path.isabs(project) or not project.endswith('.xcodeproj') or
                '..' in project.split('/') or not isinstance(targets, list) or not targets or
                not isinstance(settings, list) or not all(isinstance(w, str) and _OTHER_WORD.match(w) for w in words)):
            raise CodeDBError('other_projects.json: bad entry %r' % (e,))
        stale_copy = e.get('stale_copy')
        if stale_copy is not None and (not isinstance(stale_copy, str) or os.path.isabs(stale_copy)):
            raise CodeDBError('other_projects.json: bad stale_copy in %r' % (e,))
        names.add(name)
        out.append(OtherProject(name, project, tuple(targets), configuration, tuple(settings), stale_copy))
    return out


def read_other_projects(path=None):
    with open(path or OTHER_PROJECTS_SPEC, 'r', encoding='utf-8') as f:
        return parse_other_projects(f.read())


def present_other_projects(root, spec):
    """The projects of spec whose project file is in the tree at root."""
    return [p for p in spec if os.path.exists(os.path.join(root, p.project, 'project.pbxproj'))]


def absent_other_projects(root, spec):
    """The projects of spec whose project file is not in the tree although
    the directory that holds it is (a submodule that is not checked out, as
    in a lane): [(project, that directory)]."""
    out = []
    for p in spec:
        d = os.path.dirname(p.project)
        if not os.path.exists(os.path.join(root, p.project, 'project.pbxproj')) and d and \
                os.path.isdir(os.path.join(root, d)):
            out.append((p, d))
    return out


def stale_copy_differs(root, p):
    """Whether the project's stale tracked copy (stale_copy) exists and
    differs from the project's directory (.git ignored)."""
    import filecmp
    if not p.stale_copy or not os.path.isdir(os.path.join(root, p.stale_copy)):
        return False
    a, b = os.path.join(root, p.stale_copy), os.path.join(root, os.path.dirname(p.project))

    def differs(c):
        if c.left_only or c.right_only or c.diff_files or c.funny_files:
            return True
        return any(differs(sub) for sub in c.subdirs.values())
    return differs(filecmp.dircmp(a, b, ignore=['.git', '.DS_Store']))


def other_spec_digest(p):
    """The digest of how an other project is captured, recorded with its
    capture, so that a change to its entry in other_projects.json is seen."""
    return sha256_bytes(json.dumps([p.name, p.project, list(p.targets), p.configuration, list(p.settings)])
                        .encode('utf-8'))


def other_target_name(p, target):
    return '%s:%s' % (p.name, target)


def other_capture_record(root, p):
    """The capture record of an other project: as capture_record, with the
    build settings of its own project file, the project and the digest of
    its spec."""
    sdk_path, sdk_version = sdk_info()
    return {'project': p.project, 'spec_sha256': other_spec_digest(p),
            'build_settings_sha256': build_settings_digest(root, p.project), 'sdk_path': sdk_path,
            'sdk_version': sdk_version, 'captured_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}


def read_capture_record(fragments_dir):
    """The capture record of the fragments, or a CodeDBError saying to
    capture again."""
    path = os.path.join(fragments_dir, CAPTURE_RECORD)
    try:
        with open(path, 'r', encoding='utf-8') as f:
            record = json.load(f)
        if not all(k in record for k in ('build_settings_sha256', 'sdk_path', 'sdk_version', 'captured_at')):
            raise ValueError('a field is missing')
        return record
    except FileNotFoundError:
        raise CodeDBError('%s has no capture record (%s): the build settings the capture was made with are unknown. '
                          'Capture again with capture_compile_commands.sh.' % (fragments_dir, CAPTURE_RECORD))
    except (OSError, ValueError, AttributeError, TypeError) as e:
        raise CodeDBError('cannot read the capture record %s (%s). Capture again with capture_compile_commands.sh.'
                          % (path, e))


def adopt_capture(paths, out=print):
    """Write a capture record for fragments captured before captures wrote
    one, from the project and SDK as they are now. It is an assertion by the
    person who runs it, and it says so."""
    stamp = os.path.join(paths.fragments, '.captured')
    record_path = os.path.join(paths.fragments, CAPTURE_RECORD)
    if not os.path.exists(stamp):
        raise CodeDBError('the capture in %s did not finish (it has no .captured stamp); nothing to adopt'
                          % paths.fragments)
    if os.path.exists(record_path):
        raise CodeDBError('%s already has a capture record (%s); adopt-capture is only for captures made before '
                          'captures recorded one' % (paths.fragments, record_path))
    with open(stamp, 'r', encoding='utf-8') as f:
        finished = f.read().strip()
    record = capture_record(paths.root)
    record['captured_at'] = finished
    record['adopted'] = True
    tmp = record_path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(record, f)
    os.replace(tmp, record_path)
    out('adopt-capture: you assert that the build settings of %s are the same now as when the capture in %s was '
        'made (it finished at %s).' % (project_file(paths.root), paths.fragments, finished))
    out("adopt-capture: on that assertion alone, %s now records, as the capture's: build settings digest %s "
        '(computed from the project as it is now), SDK %s (%s) (the one xcrun reports now), date %s (from the '
        '.captured stamp).' % (record_path, record['build_settings_sha256'], record['sdk_path'],
                               record['sdk_version'], finished))
    out('adopt-capture: if the assertion is false, queries can exit 0 or 1 with sends missing. Use this only for '
        'fragments captured before captures recorded their build settings; capture again with '
        'capture_compile_commands.sh otherwise.')


# --- The compile database ----------------------------------------------------

def pch_sources(fragments_dir, names):
    """{precompiled header copy: the prefix header source it was compiled
    from} of a capture's fragments."""
    pch_map = {}
    for n in names:
        frag = read_fragment(os.path.join(fragments_dir, n))
        if any(x.endswith('-header') for x in frag['arguments'] if x.startswith('-x')):
            out = frag.get('output', '')
            if out.endswith('.gch') or out.endswith('.pch'):
                pch_map[out[:-4] if out.endswith('.gch') else out] = frag['file']
    return pch_map


def count_dropped(dropped, dropped_counts):
    j = 0
    while j < len(dropped):
        flag = dropped[j]
        key = flag if not flag.startswith('-') or '=' not in flag else flag.split('=')[0] + '='
        if flag == '-Xclang' and j + 1 < len(dropped):
            key = '-Xclang ' + (dropped[j + 1].split('=')[0] + '=' if '=' in dropped[j + 1] else dropped[j + 1])
            j += 1
        elif flag in DROP_WITH_VALUE:
            j += 1
        elif is_warning_flag(flag):
            key = '-W... (warning flags)'
        dropped_counts[key] = dropped_counts.get(key, 0) + 1
        j += 1


def other_entries(root, p, d, module_cache, sdk_path, entries, dropped_counts):
    """Add the units of an other project's capture in d to entries; return
    what the compile database's meta records of it. Raises CodeDBError for a
    capture that did not finish, has no record, or was made for another
    project."""
    if not os.path.exists(os.path.join(d, '.captured')):
        raise CodeDBError('the capture of %s that wrote %s did not finish (it has no .captured stamp); %s again' % (
            p.name, d, OTHER_CAPTURE_HINT))
    record = read_capture_record(d)
    if record.get('project') != p.project:
        raise CodeDBError('the capture in %s was made for the project %s, not %s; %s again' % (
            d, record.get('project'), p.project, OTHER_CAPTURE_HINT))
    names = sorted(n for n in os.listdir(d) if n.endswith('.json'))
    pch_map = pch_sources(d, names)
    skipped = {'header': 0, 'sanitizer variant': 0, 'outside the repository': 0, 'generated in the build directory': 0,
               'target not kept': 0, 'unknown output': 0}
    units = 0
    for n in names:
        frag = read_fragment(os.path.join(d, n))
        args = frag['arguments']
        if any(x.endswith('-header') for x in args if x.startswith('-x')):
            skipped['header'] += 1
            continue
        out = frag.get('output', '')
        if is_sanitizer_variant(out):
            skipped['sanitizer variant'] += 1
            continue
        facts = output_facts(out)
        if not facts:
            skipped['unknown output'] += 1
            continue
        target, configuration, arch, variant = facts
        if target not in p.targets:
            skipped['target not kept'] += 1
            continue
        directory = frag.get('directory', root)
        file_abs = frag['file'] if os.path.isabs(frag['file']) else os.path.join(directory, frag['file'])
        relpath = rel(file_abs, root)
        if os.path.isabs(relpath):
            skipped['outside the repository'] += 1
            continue
        # Xcode's generated files (the version file) are in the capture's
        # build directory under tmp/.
        if relpath.startswith(('Build/', 'tmp/')):
            skipped['generated in the build directory'] += 1
            continue
        translated, dropped = translate_command(args, pch_map, module_cache, sdk_path)
        count_dropped(dropped, dropped_counts)
        entries[(other_target_name(p, target), relpath)] = {
            'target': other_target_name(p, target), 'file': relpath, 'directory': directory,
            'configuration': configuration, 'arch': arch, 'variant': variant, 'output': out,
            'arguments': translated, 'project': p.project,
        }
        units += 1
    return {'project': p.project, 'captured': True, 'targets': list(p.targets),
            'build_settings_sha256': record['build_settings_sha256'], 'spec_sha256': record.get('spec_sha256'),
            'captured_at': record['captured_at'], 'captured_sdk_path': record['sdk_path'],
            'captured_sdk_version': record['sdk_version'], 'fragment_count': len(names), 'units': units,
            'skipped': skipped}


def build_cdb(root, fragments_dir, out_path, module_cache, sdk=None, log=print, accept_removals=False,
              other_fragments=None, other_projects=()):
    """Build the compile database from clang fragments. Reads one small fragment
    file at a time and writes JSON Lines: a meta line, then one entry per line.

    Refuses fragments from a capture that did not finish (no .captured stamp)
    or that has no capture record, and refuses to replace an existing compile
    database with one that has fewer entries for a target or that drops a
    target, unless accept_removals.

    The build settings digest recorded is the capture record's, the one the
    project had when the capture was made, never the project's as it is now:
    so a flag change made after the capture still shows when the compile
    database is built again from the same fragments. The commands name the
    SDK given, or the one xcrun reports now; the capture's SDK and date are
    recorded as well.

    With other_fragments (tmp/codedb/other-fragments) and other_projects
    (the projects of other_projects.json in the tree), the units of each
    other project's capture in other_fragments/NAME are added, under the
    target NAME:TARGET for the targets its spec keeps, with the project
    recorded in each entry and the capture's facts in meta['other_projects'];
    a project with no capture there is recorded as not captured."""
    if not os.path.isdir(fragments_dir):
        raise CodeDBError('no compile command fragments at %s; run %s' % (
            fragments_dir, os.path.join(HERE, 'capture_compile_commands.sh')))
    if not os.path.exists(os.path.join(fragments_dir, '.captured')):
        raise CodeDBError('the capture that wrote %s did not finish (it has no .captured stamp); run %s again' % (
            fragments_dir, os.path.join(HERE, 'capture_compile_commands.sh')))
    record = read_capture_record(fragments_dir)
    sdk_path, sdk_version = sdk or current_sdk()
    names = sorted(n for n in os.listdir(fragments_dir) if n.endswith('.json'))
    # Pass 1: map each precompiled-header copy to its prefix header source.
    pch_map = pch_sources(fragments_dir, names)
    entries = {}
    skipped = {'header': 0, 'sanitizer variant': 0, 'outside the repository': 0, 'generated under Build/': 0,
               'unknown output': 0}
    dropped_counts = {}
    for n in names:
        frag = read_fragment(os.path.join(fragments_dir, n))
        args = frag['arguments']
        if any(x.endswith('-header') for x in args if x.startswith('-x')):
            skipped['header'] += 1
            continue
        out = frag.get('output', '')
        if is_sanitizer_variant(out):
            skipped['sanitizer variant'] += 1
            continue
        facts = output_facts(out)
        if not facts:
            skipped['unknown output'] += 1
            continue
        target, configuration, arch, variant = facts
        directory = frag.get('directory', root)
        file_abs = frag['file'] if os.path.isabs(frag['file']) else os.path.join(directory, frag['file'])
        relpath = rel(file_abs, root)
        # Every unit whose main file is inside the repository, in every
        # captured target.
        if os.path.isabs(relpath):
            skipped['outside the repository'] += 1
            continue
        if relpath.startswith('Build/'):
            skipped['generated under Build/'] += 1
            continue
        translated, dropped = translate_command(args, pch_map, module_cache, sdk_path)
        count_dropped(dropped, dropped_counts)
        entries[(target, relpath)] = {
            'target': target, 'file': relpath, 'directory': directory,
            'configuration': configuration, 'arch': arch, 'variant': variant,
            'output': out, 'arguments': translated,
        }
    others = None
    if other_fragments is not None and other_projects:
        others = {}
        for p in other_projects:
            d = os.path.join(other_fragments, p.name)
            if not os.path.isdir(d):
                others[p.name] = {'project': p.project, 'captured': False}
                continue
            others[p.name] = other_entries(root, p, d, module_cache, sdk_path, entries, dropped_counts)
    removed = check_removals(out_path, entries, accept_removals)
    pbx = os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj')
    meta = {
        'meta': True,
        'fragments': fragments_dir,
        'fragment_count': len(names),
        'pbxproj_sha256': sha256_file(pbx) if os.path.exists(pbx) else None,
        # As of the capture (see above).
        'build_settings_sha256': record['build_settings_sha256'],
        'captured_at': record['captured_at'],
        'captured_sdk_path': record['sdk_path'], 'captured_sdk_version': record['sdk_version'],
        'capture_record_adopted': bool(record.get('adopted')),
        'sdk_path': sdk_path, 'sdk_version': sdk_version,
        'skipped': skipped, 'dropped': dropped_counts,
        'built_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    }
    if others is not None:
        meta['other_projects'] = others
    tmp = out_path + '.tmp'
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(json.dumps(meta) + '\n')
        for key in sorted(entries):
            f.write(json.dumps(entries[key]) + '\n')
    os.replace(tmp, out_path)
    log('compile database: %d units from %d fragments -> %s' % (len(entries), len(names), out_path))
    log('  skipped: ' + ', '.join('%s %d' % kv for kv in sorted(skipped.items())))
    log('  dropped flags: ' + ', '.join('%s x%d' % kv for kv in sorted(dropped_counts.items())))
    for name, info in sorted((others or {}).items()):
        if info['captured']:
            log('  other project %s (%s): %d units, captured %s; skipped: %s' % (
                name, info['project'], info['units'], info['captured_at'],
                ', '.join('%s %d' % kv for kv in sorted(info['skipped'].items()))))
        else:
            log('  other project %s (%s): not captured (%s)' % (name, info['project'], OTHER_CAPTURE_HINT))
    for target, f in removed:
        log('  removed: %s (%s)' % (f, target))
    return meta


def check_removals(out_path, entries, accept_removals):
    """The (target, file) pairs that replacing out_path with entries removes.
    Raises if a target loses entries or disappears and removals are not
    accepted."""
    if not os.path.exists(out_path):
        return []
    old = {}
    try:
        for e in read_cdb(out_path):
            if not e.get('meta'):
                old.setdefault(e['target'], set()).add(e['file'])
    except (ValueError, KeyError, OSError):
        return []
    new = {}
    for target, f in entries:
        new.setdefault(target, set()).add(f)
    removed = sorted((t, f) for t, files in old.items() for f in files - new.get(t, set()))
    old_total = sum(len(files) for files in old.values())
    problems = []
    for target in sorted(old):
        if target not in new:
            problems.append('target %s would be dropped (%d entries)' % (target, len(old[target])))
        elif len(new[target]) < len(old[target]):
            problems.append('target %s would have %d entries instead of %d' % (
                target, len(new[target]), len(old[target])))
    if problems and not accept_removals and len(entries) * 2 < old_total:
        raise CodeDBError(
            'refusing to replace the compile database %s: the capture compiled %d files, but the compile database '
            'has %d: an incremental build writes fragments only for the files it recompiles. A capture needs a clean '
            "build of the test scheme's products; capture_compile_commands.sh cleans them itself (xcodebuild clean "
            'build-for-testing), so run it again, and do not build in Build/ while it runs.' % (
                out_path, len(entries), old_total))
    if problems and not accept_removals:
        raise CodeDBError(
            'refusing to replace the compile database %s:\n  %s\nfiles that would be dropped:\n  %s\n'
            'If the capture was complete and these files really are gone, run again with --accept-removals.' % (
                out_path, '\n  '.join(problems), '\n  '.join('%s (%s)' % (f, t) for t, f in removed)))
    return removed


def read_cdb(path):
    """Yield the meta line, then each entry, reading one line at a time."""
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def read_cdb_index(path):
    """(meta, {(target, file): command digest}), or (None, None) if there is no
    compile database. Streams the file; keeps only the digests."""
    if not os.path.exists(path):
        return None, None
    meta = {}
    index = {}
    for e in read_cdb(path):
        if e.get('meta'):
            meta = e
        else:
            index[(e['target'], e['file'])] = command_digest(e['arguments'])
    return meta, index


def project_file(root):
    return os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj')


def lexical_rel(path, root):
    """path relative to root without resolving symlinks, for files found by
    walking a directory under root."""
    return os.path.relpath(path, root)


def project_swift_sources(root):
    """{target: set(relpath)} of the Swift files each native target of the
    project compiles, or None with no project."""
    info = project_info(root, ('.swift',))
    return None if info is None else info[0]


def project_sources(root):
    """{target: set(relpath)} of C-family sources each native target compiles,
    from project.pbxproj and synchronized folders, or None with no project."""
    info = project_info(root)
    return None if info is None else info[0]


def path_resolver(objects):
    """A function that gives the path of a project object (a file reference
    or a group) relative to the repository root, absolute, or None."""
    parent = {}
    for oid, o in objects.items():
        for child in o.get('children', []):
            parent[child] = oid

    def path_of(oid, depth=0):
        o = objects.get(oid)
        if o is None or depth > 64:
            return None
        tree = o.get('sourceTree')
        p = o.get('path', '')
        if tree == '<group>':
            par = parent.get(oid)
            base = path_of(par, depth + 1) if par else ''
            if base is None:
                return None
            return os.path.normpath(os.path.join(base, p)) if (base or p) else ''
        if tree == 'SOURCE_ROOT':
            return os.path.normpath(p)
        if tree == '<absolute>':
            return p
        return None
    return path_of


def project_pbx(root, project=None):
    """(path of the project.pbxproj, its project's directory relative to
    root): the main project's, or with project (an .xcodeproj path relative
    to root) that one's."""
    if project is None:
        return project_file(root), ''
    return os.path.join(root, project, 'project.pbxproj'), os.path.dirname(project)


def project_info(root, extensions=C_FAMILY_EXTENSIONS, project=None):
    """(project_sources, synchronized folder paths, names of test targets), or
    None with no project. project_sources has the files with one of
    extensions (the C family by default; the Swift side asks for .swift).
    project: another project (an .xcodeproj path relative to root) instead of
    the main one; its paths are made relative to root too."""
    pbx, proj_dir = project_pbx(root, project)
    if not os.path.exists(pbx):
        return None
    objects = read_pbxproj(pbx)['objects']
    resolve = path_resolver(objects)

    def path_of(oid):
        p = resolve(oid)
        return p if p is None or os.path.isabs(p) or not proj_dir else os.path.normpath(os.path.join(proj_dir, p))

    result = {}
    synchronized = set()
    tests = set()
    for oid, o in objects.items():
        if o.get('isa') != 'PBXNativeTarget':
            continue
        if o.get('productType') in TEST_PRODUCT_TYPES:
            tests.add(o.get('name'))
        files = set()
        for phase_id in o.get('buildPhases', []):
            phase = objects.get(phase_id, {})
            if phase.get('isa') != 'PBXSourcesBuildPhase':
                continue
            for bf in phase.get('files', []):
                ref = objects.get(bf, {}).get('fileRef')
                p = path_of(ref) if ref else None
                if p and p.endswith(extensions):
                    files.add(p)
        for gid in o.get('fileSystemSynchronizedGroups', []):
            base = path_of(gid)
            if base is None:
                continue
            synchronized.add(base)
            excluded = set()
            for ex in objects.get(gid, {}).get('exceptions', []):
                for m in objects.get(ex, {}).get('membershipExceptions', []):
                    excluded.add(os.path.normpath(os.path.join(base, m)))
            for dirpath, _, names in os.walk(os.path.join(root, base)):
                for n in names:
                    if n.endswith(extensions):
                        p = lexical_rel(os.path.join(dirpath, n), root)
                        if p not in excluded:
                            files.add(p)
        result[o.get('name')] = files
    return result, sorted(synchronized), sorted(tests)


# The kinds of project objects whose settings can change what is compiled.
BUILD_SETTING_OWNERS = ('PBXProject', 'PBXNativeTarget', 'PBXAggregateTarget', 'PBXLegacyTarget')


def build_settings(root, project=None):
    """(digest, {xcconfig path: digest of its contents}) of everything in
    project.pbxproj that can change how a file is compiled: every
    XCBuildConfiguration's buildSettings and its base configuration file (an
    .xcconfig, by the digest of its contents), every PBXBuildFile's settings
    (per-file COMPILER_FLAGS), every configuration list, and the
    configuration list of the project and of each target. Anything else (a
    comment, a group, a localization, a file added to a target) leaves the
    digest unchanged. (None, {}) with no project file. An .xcconfig that
    #includes another is read as one file; the included one is not followed.
    project: another project (an .xcodeproj path relative to root), whose
    .xcconfig paths are then made relative to root."""
    pbx, proj_dir = project_pbx(root, project)
    if not os.path.exists(pbx):
        return None, {}
    objects = read_pbxproj(pbx)['objects']
    resolve = path_resolver(objects)

    def path_of(oid):
        p = resolve(oid)
        return p if p is None or os.path.isabs(p) or not proj_dir else os.path.normpath(os.path.join(proj_dir, p))
    configurations, lists, build_files, owners, xcconfigs = {}, {}, {}, {}, {}
    for oid, o in objects.items():
        isa = o.get('isa')
        if isa == 'XCBuildConfiguration':
            entry = {'name': o.get('name'), 'buildSettings': o.get('buildSettings', {})}
            ref = o.get('baseConfigurationReference')
            if ref is not None:
                p = path_of(ref)
                digest = None
                if p:
                    try:
                        digest = sha256_file(p if os.path.isabs(p) else os.path.join(root, p))
                    except OSError:
                        digest = None
                    xcconfigs[p] = digest
                entry['base'] = {'ref': ref, 'path': p, 'sha256': digest}
            configurations[oid] = entry
        elif isa == 'XCConfigurationList':
            lists[oid] = {'buildConfigurations': o.get('buildConfigurations', []),
                          'defaultConfigurationName': o.get('defaultConfigurationName')}
        elif isa == 'PBXBuildFile' and 'settings' in o:
            build_files[oid] = {'fileRef': o.get('fileRef'), 'settings': o['settings']}
        elif isa in BUILD_SETTING_OWNERS:
            owners[oid] = {'isa': isa, 'name': o.get('name'), 'buildConfigurationList': o.get('buildConfigurationList')}
    text = json.dumps({'configurations': configurations, 'lists': lists, 'build_files': build_files,
                       'owners': owners}, sort_keys=True, default=lambda b: b.hex())
    return sha256_bytes(text.encode('utf-8')), xcconfigs


def build_settings_digest(root, project=None):
    return build_settings(root, project)[0]


def disk_listing(root, dirs):
    """Sorted relative paths of the C-family files under each of dirs."""
    found = set()
    for d in dirs:
        for dirpath, subdirs, names in os.walk(os.path.join(root, d)):
            # Build products of nested projects (generated sources).
            subdirs[:] = [s for s in subdirs if s != 'Build']
            for n in names:
                if n.endswith(C_FAMILY_EXTENSIONS):
                    found.add(lexical_rel(os.path.join(dirpath, n), root))
    return sorted(found)


def disk_sources(root):
    return set(disk_listing(root, DISK_SCOPE_DIRS))


def repository_files(root):
    """Relative paths of the files in the repository: those git tracks,
    including in submodules, or, when root is not the top of a git work
    tree, every file under root except in .git and Build directories."""
    try:
        top = subprocess.run(['git', '-C', root, 'rev-parse', '--show-toplevel'], capture_output=True, text=True,
                             check=True).stdout.strip()
        if os.path.realpath(top) == os.path.realpath(root):
            out = subprocess.run(['git', '-C', root, 'ls-files', '-z', '--recurse-submodules'], capture_output=True,
                                 check=True).stdout
            return sorted(p for p in out.decode('utf-8', 'surrogateescape').split('\0') if p)
    except (OSError, subprocess.CalledProcessError):
        pass
    found = []
    for dirpath, subdirs, names in os.walk(root):
        subdirs[:] = [d for d in subdirs if d not in ('.git', 'Build')]
        found += [lexical_rel(os.path.join(dirpath, n), root) for n in names]
    return sorted(found)


def other_projects(files):
    """{directory: [project]} for every directory other than the root that
    holds an Xcode project (the .xcodeproj's path) or a Swift package (the
    Package.swift's path), from a list of the repository's files."""
    projects = {}
    for f in files:
        if f.endswith('.xcodeproj/project.pbxproj'):
            project = os.path.dirname(f)
        elif os.path.basename(f) == 'Package.swift':
            project = f
        else:
            continue
        d = os.path.dirname(project)
        if d:
            projects.setdefault(d, []).append(project)
    return projects


def classify_not_parsed(root, files, covered, compiled_by_project):
    """Every C-family implementation file in the repository (files) that no
    unit of the compile database covers (covered), by class:
      other_projects  [(project, [files])]: under a directory that holds
                      another Xcode project or a Swift package (the nearest)
      submodules      [files] under submodules/
      main_project    [(file, [targets])]: compiled by a target of the main
                      project (one the capture did not build, or one whose
                      file is listed as not covered)
      no_project      [files] compiled by no target of any project found
    Files under MIGRATION_TOOLS_DIR (the migration's own tools and test
    fixtures) are left out."""
    projects = other_projects(files)
    other, submodules, main_project, nowhere = {}, [], [], []
    for f in sorted(set(f for f in files if in_repo_source(f)) - covered):
        if f.startswith(MIGRATION_TOOLS_DIR) or not os.path.isfile(os.path.join(root, f)):
            continue
        if f.startswith('submodules/'):
            submodules.append(f)
            continue
        if f in compiled_by_project:
            main_project.append((f, sorted(compiled_by_project[f])))
            continue
        d = os.path.dirname(f)
        while d and d not in projects:
            d = os.path.dirname(d)
        if d:
            other.setdefault(', '.join(sorted(projects[d])), []).append(f)
        else:
            nowhere.append(f)
    return {'other_projects': sorted(other.items()), 'submodules': submodules, 'main_project': main_project,
            'no_project': nowhere}


def without_files(np, parsed):
    """np (classify_not_parsed) without the files in parsed."""
    return {'other_projects': [(p, [f for f in fs if f not in parsed]) for p, fs in np['other_projects']
                               if any(f not in parsed for f in fs)],
            'submodules': [f for f in np['submodules'] if f not in parsed],
            'main_project': [(f, t) for f, t in np['main_project'] if f not in parsed],
            'no_project': [f for f in np['no_project'] if f not in parsed]}


def not_parsed_count(np):
    return (sum(len(fs) for _, fs in np['other_projects']) + len(np['submodules']) + len(np['main_project']) +
            len(np['no_project']))


def not_parsed_files(np):
    return sorted([f for _, fs in np['other_projects'] for f in fs] + np['submodules'] +
                  [f for f, _ in np['main_project']] + np['no_project'])


def dot_syntax_properties(selector):
    """The property names a selector can stand for when written with dot
    syntax: for setFoo: (one keyword, 'set' and an uppercase letter) foo and
    Foo; for a unary isFoo, foo and isFoo; for any other unary foo, foo. None
    for other selectors."""
    if re.match(r'^set[A-Z][A-Za-z0-9_$]*:$', selector):
        name = selector[3:-1]
        return [name[0].lower() + name[1:], name]
    if ':' in selector or not selector:
        return []
    m = re.match(r'^is([A-Z][A-Za-z0-9_$]*)$', selector)
    if m:
        name = m.group(1)
        return [name[0].lower() + name[1:], selector]
    return [selector]


def text_matches(root, files, selector, limit=TEXT_MATCHES_MAX, forms=None, skip_definitions=True):
    """A plain text search of files for forms, each (needle, label, regular
    expression); by default the forms TEXT_SEARCH_FORMS states
    (search_forms_sends): the selector's first keyword as a message send (a
    whole word followed by ':' or ']'), and each name dot_syntax_properties
    gives as a whole word after '.' (dot syntax). With skip_definitions, lines
    that begin a method definition ('- (' or '+ (') are skipped; a matching
    line is kept to its first 200 characters. Reads one file at a time, one
    line at a time, and stops after limit matches. Returns ([(file, line
    number, forms, line)], stopped early), where forms names the forms that
    matched the line."""
    if forms is None:
        forms = search_forms_sends(selector)
    if not forms:
        return [], False
    definition = re.compile(r'^\s*[-+]\s*\(')
    found = []
    for f in files:
        try:
            handle = open(os.path.join(root, f), 'r', encoding='utf-8', errors='replace')
        except OSError:
            continue
        with handle:
            for n, line in enumerate(handle, 1):
                labels = [label for needle, label, pattern in forms if needle in line and pattern.search(line)]
                if labels and not (skip_definitions and definition.match(line)):
                    found.append((f, n, '; '.join(labels), line.strip()[:200]))
                    if len(found) >= limit:
                        return found, True
    return found, False


# The coverage of the project by the compile database.
#   project           path of project.pbxproj, or None if there is none
#   not_covered       [(file, [targets])]: source files in the repository that
#                     a project target compiles and that no unit of the
#                     compile database covers for that target (including
#                     files on disk in the migration's scope that some target
#                     compiles and no unit covers at all)
#   extra             [(file, target)]: units no longer in the project
#   uncompiled        [file]: files on disk in the migration's scope that no
#                     target of the main project compiles and no unit covers.
#                     Another project may build them: see not_parsed
#   uncaptured        [(target, [files])]: project targets the capture did not
#                     build, with their source files in the repository
#   unchecked         [(target, units)]: captured targets that are not in the
#                     project (Swift package targets); their units are not
#                     compared with the project
#   settings_changed  the build settings in project.pbxproj (see
#                     build_settings) differ from those the capture the
#                     compile database was built from was made with, or it
#                     records none
#   not_parsed        every C-family implementation file in the repository
#                     that no unit covers, by class (classify_not_parsed):
#                     callers in them are not in the database
#   test_targets      names of the project's test targets
#   others            the other projects of other_projects.json that are in
#                     the tree: {'captured': [(name, project, units)],
#                     'not_captured': [(name, project)], 'settings_changed':
#                     [name] (their project's build settings differ from
#                     those of their capture), 'spec_changed': [name] (their
#                     entry in other_projects.json differs from the one they
#                     were captured with)}. The files of a captured one are
#                     compared with its own project in not_covered and extra,
#                     under the target NAME:TARGET
Coverage = collections.namedtuple('Coverage', 'project not_covered extra uncompiled uncaptured unchecked '
                                              'settings_changed not_parsed test_targets others')
NO_OTHERS = {'captured': [], 'not_captured': [], 'not_checked_out': [], 'settings_changed': [], 'spec_changed': []}


def coverage_out_of_date(c):
    """The compile database does not cover the project's files. A change of
    the build settings is reported separately (c.settings_changed)."""
    return c.project is None or bool(c.not_covered or c.extra)


def others_out_of_date(c):
    """The build settings or the spec of a captured other project changed
    since its capture."""
    return bool(c.others['settings_changed'] or c.others['spec_changed'])


def default_other_projects(root, spec_path=None):
    """The projects of other_projects.json (or spec_path) that are in the
    tree at root."""
    return present_other_projects(root, read_other_projects(spec_path))


def other_coverage(root, meta, by_target, other_projects):
    """(others, missing {file: set(targets)}, extra [(file, target)], the
    compile database targets that belong to other projects, {xcconfig path:
    digest}) for compute_coverage."""
    others = {'captured': [], 'not_captured': [], 'not_checked_out': [], 'settings_changed': [], 'spec_changed': []}
    missing, extra, known, xcconfigs = {}, [], set(), {}
    recorded = meta.get('other_projects') or {}
    for p, _ in absent_other_projects(root, other_projects):
        known |= set(t for t in by_target if t.startswith(p.name + ':'))
        others['not_checked_out'].append((p.name, p.project))
    for p in present_other_projects(root, other_projects):
        known |= set(t for t in by_target if t.startswith(p.name + ':'))
        info = recorded.get(p.name)
        if not info or not info.get('captured'):
            others['not_captured'].append((p.name, p.project))
            continue
        others['captured'].append((p.name, p.project, sum(len(by_target.get(other_target_name(p, t), ()))
                                                          for t in p.targets)))
        digest, xc = build_settings(root, p.project)
        xcconfigs.update(xc)
        if info.get('build_settings_sha256') != digest:
            others['settings_changed'].append(p.name)
        if info.get('spec_sha256') != other_spec_digest(p):
            others['spec_changed'].append(p.name)
        info_now = project_info(root, project=p.project)
        sources = info_now[0] if info_now else {}
        for t in p.targets:
            name = other_target_name(p, t)
            pfiles = set(f for f in sources.get(t, ()) if in_repo_source(f))
            files = by_target.get(name, set())
            for f in pfiles - files:
                missing.setdefault(f, set()).add(name)
            extra += [(f, name) for f in sorted(files - pfiles)]
    return others, missing, extra, known, xcconfigs


def compute_coverage(root, cdb_path, repo_files=None, other_projects=None):
    """(Coverage, synchronized folders read, {xcconfig path: digest}).
    repo_files is repository_files(root), if the caller has it.
    other_projects: the other projects to check (default: those of
    other_projects.json in the tree)."""
    if other_projects is None:
        other_projects = default_other_projects(root)
    by_target = {}
    meta = {}
    for e in read_cdb(cdb_path):
        if e.get('meta'):
            meta = e
        else:
            by_target.setdefault(e['target'], set()).add(e['file'])
    compiled = set()
    for files in by_target.values():
        compiled |= files
    disk = disk_sources(root)
    in_repo = sorted(set(repository_files(root) if repo_files is None else repo_files) | disk)
    pbx = project_file(root)
    info = project_info(root) if os.path.exists(pbx) else None
    if info is None:
        return Coverage(None, [], [], sorted(disk - compiled), [], [], False,
                        classify_not_parsed(root, in_repo, compiled, {}), [], dict(NO_OTHERS)), [], {}
    proj, synchronized, tests = info
    others, missing, extra, known, other_xcconfigs = other_coverage(root, meta, by_target, other_projects)
    unchecked = []
    for target, files in sorted(by_target.items()):
        if target in known:
            continue
        if target not in proj:
            unchecked.append((target, len(files)))
            continue
        pfiles = set(f for f in proj[target] if in_repo_source(f))
        for f in pfiles - files:
            missing.setdefault(f, set()).add(target)
        extra += [(f, target) for f in sorted(files - pfiles)]
    compiled_by_project = {}
    for target, files in proj.items():
        for f in files:
            if in_repo_source(f):
                compiled_by_project.setdefault(f, set()).add(target)
    uncompiled = []
    for f in sorted(disk - compiled):
        if f in compiled_by_project:
            missing.setdefault(f, set()).update(compiled_by_project[f])
        else:
            uncompiled.append(f)
    uncaptured = []
    for target in sorted(t for t in proj if t not in by_target):
        pfiles = sorted(f for f in proj[target] if in_repo_source(f))
        if pfiles:
            uncaptured.append((target, pfiles))
        # A file in the migration's scope that only a target the capture did
        # not build compiles is in no unit, and is not covered. Such files
        # outside the scope are counted under not_parsed (class main_project).
        for f in pfiles:
            if f not in compiled and in_migration_scope(f):
                missing.setdefault(f, set()).add(target)
    settings_digest, xcconfigs = build_settings(root)
    xcconfigs = dict(xcconfigs, **other_xcconfigs)
    changed = meta.get('build_settings_sha256') != settings_digest
    not_covered = [(f, sorted(t)) for f, t in sorted(missing.items())]
    not_parsed = classify_not_parsed(root, in_repo, compiled, compiled_by_project)
    return (Coverage(pbx, not_covered, extra, uncompiled, uncaptured, unchecked, changed, not_parsed, tests, others),
            synchronized, xcconfigs)


def coverage_cache_path(cdb_path):
    return os.path.join(os.path.dirname(os.path.abspath(cdb_path)), 'coverage-cache.json')


def _file_digests(root, paths):
    out = {}
    for p in sorted(paths):
        try:
            out[p] = sha256_file(p if os.path.isabs(p) else os.path.join(root, p))
        except OSError:
            out[p] = None
    return out


def _coverage_key(root, cdb_path, synchronized, xcconfigs, files, other_projects=()):
    pbx = project_file(root)
    listing = disk_listing(root, sorted(set(DISK_SCOPE_DIRS) | set(synchronized)))
    return {
        'others': [[other_spec_digest(p), _file_digests(root, [project_pbx(root, p.project)[0]])]
                   for p in other_projects],
        'root': root,
        'tool': sha256_file(os.path.abspath(__file__)),
        'pbxproj': sha256_file(pbx) if os.path.exists(pbx) else None,
        'cdb': sha256_file(cdb_path),
        'synchronized': sorted(synchronized),
        'xcconfigs': _file_digests(root, xcconfigs),
        'listing': sha256_bytes('\n'.join(listing).encode('utf-8')),
        'repository': sha256_bytes('\n'.join(files).encode('utf-8', 'surrogateescape')),
    }


def coverage(root, cdb_path, cache_path=None, other_projects=None):
    """The Coverage, from a cache keyed on the digests of project.pbxproj, the
    compile database, this file and the .xcconfig files the project names,
    on the listing of the migration's directories and synchronized folders
    on disk, on the list of the repository's files (repository_files), and
    on the project files and specs of the other projects. Any change to one
    of them computes it again."""
    if other_projects is None:
        other_projects = default_other_projects(root)
    cache_path = cache_path or coverage_cache_path(cdb_path)
    cached = None
    files = repository_files(root)
    try:
        with open(cache_path, 'r', encoding='utf-8') as f:
            cached = json.load(f)
        key = _coverage_key(root, cdb_path, cached['key']['synchronized'], list(cached['key']['xcconfigs']), files,
                            other_projects)
        if cached['key'] == key:
            c = cached['coverage']
            np = c['not_parsed']
            return Coverage(c['project'], [(f, list(t)) for f, t in c['not_covered']],
                            [tuple(x) for x in c['extra']], c['uncompiled'],
                            [(t, list(fs)) for t, fs in c['uncaptured']], [tuple(x) for x in c['unchecked']],
                            c['settings_changed'],
                            {'other_projects': [(p, list(fs)) for p, fs in np['other_projects']],
                             'submodules': list(np['submodules']),
                             'main_project': [(f, list(t)) for f, t in np['main_project']],
                             'no_project': list(np['no_project'])},
                            list(c['test_targets']),
                            {'captured': [tuple(x) for x in c['others']['captured']],
                             'not_captured': [tuple(x) for x in c['others']['not_captured']],
                             'not_checked_out': [tuple(x) for x in c['others']['not_checked_out']],
                             'settings_changed': list(c['others']['settings_changed']),
                             'spec_changed': list(c['others']['spec_changed'])})
    except (OSError, ValueError, KeyError, TypeError):
        pass
    result, synchronized, xcconfigs = compute_coverage(root, cdb_path, files, other_projects)
    try:
        tmp = cache_path + '.%d.tmp' % os.getpid()
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump({'key': _coverage_key(root, cdb_path, synchronized, xcconfigs, files, other_projects),
                       'coverage': result._asdict()}, f)
        os.replace(tmp, cache_path)
    except OSError:
        pass
    return result


def check_cdb_against_project(root, cdb_path, log=print, other_projects=None):
    """Report how the compile database differs from the project and the disk.
    Returns True if the compile database is out of date (it does not cover
    the project or a captured other project, or the build settings of either
    changed, or how an other project is captured changed)."""
    c = coverage(root, cdb_path, other_projects=other_projects)
    out_of_date = coverage_out_of_date(c)
    if c.project is None:
        log('COMPILE DATABASE NOT CHECKED: there is no project file at %s' % project_file(root))
    elif out_of_date:
        log('COMPILE DATABASE OUT OF DATE: it does not match the project. Run %s' %
            os.path.join(HERE, 'capture_compile_commands.sh'))
        for f, targets in c.not_covered:
            log('  in the project, not in the compile database: %s (%s)' % (f, ','.join(targets)))
        for f, target in c.extra:
            log('  in the compile database, not in the project: %s (%s)' % (f, target))
    if c.project is not None and c.settings_changed:
        log('COMPILE DATABASE OUT OF DATE: the build settings changed since the compile commands were captured; '
            'run capture_compile_commands.sh')
        out_of_date = True
    for name in c.others['settings_changed']:
        project = [p for n, p, _ in c.others['captured'] if n == name][0]
        log('COMPILE DATABASE OUT OF DATE: the build settings of %s changed since it was captured; %s' % (
            project, OTHER_CAPTURE_HINT))
        out_of_date = True
    for name in c.others['spec_changed']:
        log('COMPILE DATABASE OUT OF DATE: how %s is captured (other_projects.json) changed since it was captured; '
            '%s' % (name, OTHER_CAPTURE_HINT))
        out_of_date = True
    for name, project in c.others['not_captured']:
        log('other project %s (%s) is not captured: its files are not parsed; %s' % (name, project,
                                                                                    OTHER_CAPTURE_HINT))
    for name, project in c.others['not_checked_out']:
        log('other project %s (%s) is not captured: %s is not checked out here' % (name, project,
                                                                                  os.path.dirname(project)))
    # Targets the capture's scheme does not build. Not an error: their files
    # in the migration's scope are compiled by another target too, or they
    # would be listed above; the others are counted as not parsed by every
    # query.
    for target, pfiles in c.uncaptured:
        log('project target %s compiles %d file(s) and is not in the compile database: %s%s' % (
            target, len(pfiles), ', '.join(pfiles[:5]), ', ...' if len(pfiles) > 5 else ''))
    for target, n in c.unchecked:
        log('captured target %s is not in the project (a Swift package target); its %d units are not compared '
            'with the project' % (target, n))
    if c.uncompiled:
        log("%d files on disk in the migration's scope are compiled by no target of %s (another project may build "
            'them; every query lists the files that are not parsed):' % (
                len(c.uncompiled), os.path.basename(os.path.dirname(project_file(root)))))
        for u in c.uncompiled:
            log('  ' + u)
    return out_of_date


class Paths:
    def __init__(self, root, db=None, cdb=None, fragments=None, extractor=None, module_cache=None, lock=None,
                 guard=None, swift_reader=None, swift_work=None, swift_reader_prebuilt=False, other_fragments=None,
                 other_spec=None):
        self.root = os.path.realpath(root)
        work = os.path.join(self.root, 'tmp', 'codedb')
        # The other projects' captures (other_projects.json): one directory
        # per project, written by capture_compile_commands.sh
        # --other-projects.
        self.other_fragments = other_fragments or os.path.join(work, 'other-fragments')
        self.other_spec = other_spec or OTHER_PROJECTS_SPEC
        # The Swift side (swiftdb.py): the reader, its scratch directory (one
        # subdirectory per module) and the compiler's private module cache.
        self.swift_reader = swift_reader or os.path.join(work, 'bin', 'swift_refs')
        # The reader is used as it is, never rebuilt (the tests' prebuilt
        # reader, CODEDB_TEST_SWIFT_READER).
        self.swift_reader_prebuilt = swift_reader_prebuilt
        self.swift_work = swift_work or os.path.join(work, 'swift')
        self.swift_module_cache = os.path.join(self.swift_work, 'modcache')
        self.db = db or os.path.join(work, 'codedb.sqlite')
        self.cdb = cdb or os.path.join(work, 'compile_commands.jsonl')
        self.fragments = fragments or os.path.join(work, 'cdb-fragments')
        self.extractor = extractor or os.path.join(work, 'bin', 'extract_sends')
        self.module_cache = module_cache or os.path.join(work, 'modcache')
        # Next to the compile database, which is where the capture script
        # (tmp/codedb) puts it too.
        self.lock = lock or os.path.join(os.path.dirname(os.path.abspath(self.cdb)), 'codedb.lock')
        self.guard = guard or GUARD


# --- Locking and processes ---------------------------------------------------

def _ps_field(pid, field):
    """A ps field of pid with whitespace collapsed, or None if there is no
    such process. ps sees every user's processes."""
    try:
        out = subprocess.run(['ps', '-o', field + '=', '-p', str(pid)], capture_output=True, text=True).stdout
    except OSError:
        return None
    out = ' '.join(out.split())
    return out or None


def process_start(pid):
    """The start time of pid as `ps -o lstart=` prints it, or None."""
    return _ps_field(pid, 'lstart')


LockInfo = collections.namedtuple('LockInfo', 'pid command start child_pgid child_start')


def parse_lock_text(text):
    """LockInfo from the text of a lock file, or None if it is empty."""
    lines = text.splitlines()
    if not lines:
        return None
    try:
        pid = int(lines[0])
    except ValueError:
        pid = None
    command = lines[1] if len(lines) > 1 else '?'
    start = (lines[2] or None) if len(lines) > 2 and not lines[2].startswith('child ') else None
    child_pgid = child_start = None
    for line in lines[2:]:
        if line.startswith('child '):
            parts = line.split(' ', 2)
            try:
                child_pgid = int(parts[1])
                child_start = parts[2] if len(parts) > 2 else None
            except (IndexError, ValueError):
                pass
    return LockInfo(pid, command, start, child_pgid, child_start)


class Lock:
    """The code database lock, shared with capture_compile_commands.sh: an
    exclusive flock(2) on the file, taken without waiting and held on an open
    descriptor for the life of the holder. The kernel releases it when the
    holder dies in any way, so two holders are impossible and a lock is never
    stale. Only the flock decides who holds the lock. The file's text is for
    messages and for cleaning up:

        <pid>
        <command>
        <start time of pid, as `ps -o lstart=` prints it>
        child <pgid> <start time of that group's leader>     (optional)

    The holder records the process group it is running (an extraction, or the
    capture's build) on the child line, so that if the holder is killed with
    SIGKILL the next holder kills that group, which is in its own session and
    survives. The group is killed only if its leader still has the recorded
    start time.

    The holder removes the file before it closes the descriptor. A taker that
    locked a file that was removed (or replaced) meanwhile sees that the path
    no longer names the file it locked, and tries again.

    capture_compile_commands.sh takes the lock through `codedb.py hold-lock`,
    which takes it with this class and then runs the script with the locked
    descriptor as fd 9."""

    def __init__(self, path, command, log=print):
        self.path = path
        self.command = command
        self.log = log
        self.fd = None
        self.held = False
        self.start = None

    def read(self):
        """LockInfo from the file, or None if there is none or it is empty."""
        try:
            with open(self.path) as f:
                return parse_lock_text(f.read())
        except FileNotFoundError:
            return None

    def kill_left_child(self, info):
        if info is None or info.child_pgid is None or info.child_start is None:
            return
        if process_start(info.child_pgid) != info.child_start:
            return
        self.log('killing process group %d, left running by pid %s (%s), which is gone' % (
            info.child_pgid, info.pid, info.command))
        kill_process_group(info.child_pgid)

    def acquire(self):
        os.makedirs(os.path.dirname(os.path.abspath(self.path)), exist_ok=True)
        self.start = process_start(os.getpid())
        for _ in range(100):
            fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o644)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                os.close(fd)
                info = self.read()
                holder = ('pid %s: %s' % (info.pid, info.command) if info is not None and info.pid is not None
                          else 'its holder has not written its pid yet')
                raise CodeDBLocked('another code database operation holds the lock %s (%s)' % (self.path, holder))
            try:
                mine = os.fstat(fd)
                now = os.stat(self.path)
                same = (mine.st_dev, mine.st_ino) == (now.st_dev, now.st_ino)
            except FileNotFoundError:
                same = False
            if not same:
                os.close(fd)
                continue
            left = parse_lock_text(os.pread(fd, 1 << 16, 0).decode('utf-8', 'replace'))
            self.fd = fd
            self.held = True
            # Whoever wrote it is gone: it held the flock until it died.
            self.kill_left_child(left)
            self._write(self.contents())
            return
        raise CodeDBLocked('cannot take the lock %s' % self.path)

    def contents(self, child=None):
        text = '%d\n%s\n%s\n' % (os.getpid(), self.command, self.start or '')
        if child is not None:
            text += 'child %d %s\n' % child
        return text

    def _write(self, text):
        # In place: the flock is on this file, so it is never replaced.
        data = text.encode('utf-8')
        os.ftruncate(self.fd, 0)
        os.pwrite(self.fd, data, 0)

    def record_child(self, pgid):
        """Record (or with None, clear) the process group being run."""
        if not self.held:
            return
        child = None
        if pgid is not None:
            start = process_start(pgid)
            if start is None:
                return
            child = (pgid, start)
        self._write(self.contents(child))

    def release(self):
        if not self.held:
            return
        try:
            mine = os.fstat(self.fd)
            now = os.stat(self.path)
            if (mine.st_dev, mine.st_ino) == (now.st_dev, now.st_ino):
                os.remove(self.path)
        except FileNotFoundError:
            pass
        os.close(self.fd)
        self.fd = None
        self.held = False

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, *exc):
        self.release()
        return False


def kill_process_group(pgid):
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


# The status run_in_group returns when the command ran out of time (as
# timeout(1) does).
TIMEOUT_STATUS = 124


def run_in_group(cmd, cwd=None, capture=True, lock=None, stdout=None, timeout=None):
    """Run cmd in a new session (its own process group), and kill that whole
    group on every way out, including KeyboardInterrupt. With lock, the group
    is recorded in the lock while it runs, so that it can be killed if this
    process is killed with SIGKILL. With stdout (an open file), the command's
    standard output goes there. With timeout (seconds), the group is killed
    when the command has not finished by then, and the status is
    TIMEOUT_STATUS. Returns (status, stderr)."""
    pipe = subprocess.PIPE if capture else None
    p = subprocess.Popen(cmd, cwd=cwd, stdout=stdout if stdout is not None else pipe, stderr=pipe, text=True,
                         start_new_session=True)
    try:
        if lock is not None:
            lock.record_child(p.pid)
        try:
            _, err = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            kill_process_group(p.pid)
            _, err = p.communicate()
            return TIMEOUT_STATUS, (err or '') + '\ncodedb: timed out after %d s; its process group was killed\n' % (
                timeout)
    finally:
        kill_process_group(p.pid)
        if p.returncode is None:
            p.wait()
        if lock is not None:
            lock.record_child(None)
    return p.returncode, err or ''


# --- The extractor -----------------------------------------------------------

def binary_version(exe):
    """(source digest, compiler) the extractor binary reports with --version,
    or (None, None). The compiler is the full version of the Homebrew LLVM
    it runs on, as libclang reports it ('Homebrew clang version 22.1.8'):
    the library is loaded at run time, so it is the one actually used."""
    if not os.path.exists(exe):
        return None, None
    try:
        out = subprocess.run([exe, '--version'], capture_output=True, text=True, timeout=60).stdout.split(None, 2)
    except (OSError, subprocess.SubprocessError):
        return None, None
    if len(out) < 2 or out[0] != 'extract_sends':
        return None, None
    return out[1], (out[2].strip() if len(out) > 2 else None)


def binary_digest(exe):
    """The source digest the extractor binary reports, or None."""
    return binary_version(exe)[0]


def ensure_extractor(paths, log=print, builder=None, lock=None):
    """Build the extractor if the binary's digest is not the digest of the
    current sources."""
    want = extractor_source_digest()
    have = binary_digest(paths.extractor)
    if have == want:
        return
    log('building the extractor (%s)' % ('none at %s' % paths.extractor if have is None else 'its sources changed'))
    status, _ = run_in_group([paths.guard, '--', builder or BUILD_SCRIPT, paths.extractor], capture=False, lock=lock)
    if status != 0:
        raise CodeDBError('extractor build failed (status %d)' % status)
    have = binary_digest(paths.extractor)
    if have != want:
        raise CodeDBError('the extractor at %s reports source digest %s after a build; expected %s' % (
            paths.extractor, have, want))


def extractor_version(paths):
    """The source digest the extractor reports; it is stored with each unit."""
    digest = binary_digest(paths.extractor)
    if digest is None:
        raise CodeDBError('cannot get the version of the extractor at %s' % paths.extractor)
    return digest


def extractor_compiler(paths):
    """The compiler version the extractor at paths.extractor reports, or None
    if it cannot run. Each unit records the one it was extracted with
    (tu.clang_version)."""
    return binary_version(paths.extractor)[1]


def other_stamps(paths):
    """The .captured stamps of the other projects' captures."""
    d = paths.other_fragments
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, n, '.captured') for n in sorted(os.listdir(d))
            if os.path.exists(os.path.join(d, n, '.captured'))]


def build_cdb_for(paths, log=print, accept_removals=False):
    """build_cdb with the paths' fragments and the other projects' captures."""
    return build_cdb(paths.root, paths.fragments, paths.cdb, paths.module_cache, log=log,
                     accept_removals=accept_removals, other_fragments=paths.other_fragments,
                     other_projects=default_other_projects(paths.root, paths.other_spec))


def ensure_cdb(paths, log=print, accept_removals=False):
    # Rebuilt when new fragments were captured (by the main capture or an
    # other project's), when this file (which holds the command translation)
    # or other_projects.json changed since the compile database was built,
    # or when the SDK xcrun reports is not the one its commands name.
    stamp = os.path.join(paths.fragments, '.captured')
    if os.path.exists(paths.cdb):
        built = os.path.getmtime(paths.cdb)
        newer_fragments = any(os.path.exists(s) and os.path.getmtime(s) > built
                              for s in [stamp] + other_stamps(paths))
        newer_translation = os.path.exists(stamp) and any(
            os.path.exists(f) and os.path.getmtime(f) > built for f in (os.path.abspath(__file__), paths.other_spec))
        other_sdk = os.path.exists(stamp) and cdb_sdk(read_cdb_index(paths.cdb)[0]) not in (None, current_sdk())
        if not newer_fragments and not newer_translation and not other_sdk:
            return
    build_cdb_for(paths, log=log, accept_removals=accept_removals)


# --- The database and unit states --------------------------------------------

class DigestCache:
    def __init__(self, root):
        self.root = root
        self.cache = {}

    def digest(self, path):
        if path not in self.cache:
            full = path if os.path.isabs(path) else os.path.join(self.root, path)
            try:
                self.cache[path] = sha256_file(full)
            except OSError:
                self.cache[path] = None
        return self.cache[path]


def open_db(path, must_exist=True):
    if must_exist and not os.path.exists(path):
        raise CodeDBError('no database at %s; run codedb.py update' % path)
    con = sqlite3.connect(path)
    con.execute('PRAGMA busy_timeout=60000')
    return con


def table_names(con):
    return set(r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'"))


def has_schema(con):
    return {'tu', 'tu_input', 'send'} <= table_names(con)


def schema_version(con):
    return con.execute('PRAGMA user_version').fetchone()[0]


FAILURE_SCHEMA = ('CREATE TABLE IF NOT EXISTS tu_failure(target TEXT NOT NULL, main_file TEXT NOT NULL, '
                  'status INTEGER NOT NULL, reason TEXT NOT NULL, failed_at TEXT NOT NULL, '
                  'PRIMARY KEY(target, main_file))')


def prepare_db(con, log=print):
    """Replace a database made with another schema version, and add the
    driver's own table."""
    if 'tu' in table_names(con) and schema_version(con) != SCHEMA_VERSION:
        log('the database has schema version %d, not %d; removing every unit so that all are extracted again' % (
            schema_version(con), SCHEMA_VERSION))
        with con:
            for t in UNIT_TABLES + ('tu', 'tu_failure'):
                con.execute('DROP TABLE IF EXISTS %s' % t)
        con.execute('PRAGMA user_version=0')
    with con:
        con.execute(FAILURE_SCHEMA)


CURRENT, STALE, MISSING, FAILED, ORPHAN = 'current', 'stale', 'missing', 'failed', 'orphan'
STATE_LABELS = collections.OrderedDict([
    (CURRENT, 'current'),
    (STALE, 'stale'),
    (MISSING, 'missing from the database'),
    (FAILED, 'last extraction failed'),
    (ORPHAN, 'in the database, not in the compile database'),
])
UnitState = collections.namedtuple('UnitState', 'target file tu state reason errors')


def cdb_sdk(meta):
    """(path, version) of the SDK the compile database was built with, or
    None if it records none."""
    if meta and meta.get('sdk_path'):
        return (meta['sdk_path'], meta.get('sdk_version'))
    return None


def first_stale_inputs(con, digests):
    """{tu id: reason} for every unit with an input whose digest on disk differs
    from the one recorded (or that is gone). Every input counts, including SDK
    and compiler headers with absolute paths."""
    result = {}
    for tu, path, digest in con.execute('SELECT tu, path, digest FROM tu_input ORDER BY tu, path'):
        if tu in result:
            continue
        now = digests.digest(path)
        if now is None:
            result[tu] = 'input missing: ' + path
        elif now != digest:
            result[tu] = 'input changed: ' + path
    return result


def unit_states(con, index, current_version, sdk, digests, built_sdk=None, compiler=False, extractor=None):
    """The state of every unit, {(target, file): UnitState}.

    index is {(target, file): command digest} from the compile database, or
    None if there is none (then no unit can be found missing, and none is an
    orphan). current_version is the extractor's source digest; sdk is the
    (path, version) xcrun reports now, or None to skip that check. A unit
    extracted with another SDK is stale ("SDK changed"), and so is every unit
    when built_sdk, the SDK the compile database was built with, is not sdk.
    A unit extracted with another list of the migration's directories is
    stale ("migration scope changed"). compiler is the compiler version the
    extractor reports now (extractor_compiler), None if it cannot report one,
    or False to skip the check: a unit extracted with another is stale
    ("compiler changed"), and with None every unit is ("compiler unknown",
    naming extractor, the extractor binary's path)."""
    sdk_moved = sdk is not None and built_sdk is not None and tuple(built_sdk) != tuple(sdk)
    tus = {}
    failures = {}
    stale = {}
    names = table_names(con)
    if {'tu', 'tu_input', 'send'} <= names:
        for row in con.execute('SELECT id, target, main_file, cmd_digest, extractor_version, sdk_path, '
                               'sdk_version, diagnostics_errors, migration_scope, clang_version FROM tu'):
            tus[(row[1], row[2])] = row
        stale = first_stale_inputs(con, digests)
    if 'tu_failure' in names:
        for target, main, reason in con.execute('SELECT target, main_file, reason FROM tu_failure'):
            failures[(target, main)] = reason
    states = {}
    for key in sorted(set(index or ()) | set(tus)):
        tu = tus.get(key)
        tu_id = tu[0] if tu else None
        errors = tu[7] if tu else 0
        in_cdb = index is not None and key in index
        if in_cdb and key in failures:
            state, reason = FAILED, 'last extraction failed: ' + failures[key]
        elif in_cdb and tu is None:
            state, reason = MISSING, 'missing from the database'
        elif index is not None and not in_cdb:
            state, reason = ORPHAN, 'not in the compile database'
        elif in_cdb and tu[3] != index[key]:
            state, reason = STALE, 'command changed'
        elif tu[4] != current_version:
            state, reason = STALE, 'extractor changed'
        elif compiler is None:
            state, reason = STALE, ('compiler unknown: the extractor at %s cannot report its version; run codedb.py '
                                    'update, which builds it' % (extractor or '?'))
        elif compiler is not False and tu[9] != compiler:
            state, reason = STALE, 'compiler changed'
        elif sdk is not None and ((tu[5], tu[6]) != tuple(sdk) or sdk_moved):
            state, reason = STALE, 'SDK changed'
        elif tu[8] != MIGRATION_SCOPE_TEXT:
            state, reason = STALE, 'migration scope changed'
        elif tu_id in stale:
            state, reason = STALE, stale[tu_id]
        else:
            state, reason = CURRENT, None
        states[key] = UnitState(key[0], key[1], tu_id, state, reason, errors)
    return states


# --- Extraction --------------------------------------------------------------

def run_extractor(paths, entry, sdk, peak_file, lock=None):
    cmd = [paths.guard, '--peak-file', peak_file, '--', paths.extractor,
           '--db', paths.db, '--root', paths.root, '--target', entry['target'],
           '--main', os.path.join(paths.root, entry['file'])]
    if sdk is not None:
        cmd += ['--sdk-path', sdk[0], '--sdk-version', sdk[1]]
    if entry.get('configuration'):
        cmd += ['--configuration', entry['configuration']]
    if entry.get('arch'):
        cmd += ['--arch', entry['arch']]
    for d in MIGRATION_SCOPE_DIRS:
        cmd += ['--migration-scope', d]
    # The compile database names the module cache it was built with; this
    # database's own cache replaces it (it is not part of the command digest).
    cmd += ['--'] + [MODULE_CACHE_FLAG + paths.module_cache if a.startswith(MODULE_CACHE_FLAG) else a
                     for a in entry['arguments']]
    return run_in_group(cmd, cwd=entry.get('directory') or paths.root, lock=lock)


def read_peak_kb(peak_file):
    """The peak the guard wrote for this unit, or None if it wrote none."""
    try:
        with open(peak_file) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def record_outcome(paths, entry, failure):
    con = open_db(paths.db, must_exist=False)
    try:
        with con:
            con.execute(FAILURE_SCHEMA)
            if failure is None:
                con.execute('DELETE FROM tu_failure WHERE target=? AND main_file=?', (entry['target'], entry['file']))
            else:
                status, reason = failure
                con.execute('INSERT OR REPLACE INTO tu_failure(target, main_file, status, reason, failed_at) '
                            'VALUES(?,?,?,?,?)', (entry['target'], entry['file'], status, reason,
                                                  time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))
    finally:
        con.close()


def extract_units(paths, todo, sdk, lock, log, peak_dir, counts, numbered_from):
    """Extract each (entry, reason) of todo, serially, and add to counts
    (extracted, with_errors, failed, peak_kb)."""
    for n, (entry, reason) in enumerate(todo, numbered_from + 1):
        t0 = time.time()
        # A fresh file per unit, so that a unit whose guard wrote no peak
        # does not report the previous unit's.
        peak_file = os.path.join(peak_dir, 'peak-%d' % n)
        status, stderr = run_extractor(paths, entry, sdk, peak_file, lock=lock)
        unit_peak = read_peak_kb(peak_file)
        counts['peak_kb'] = max(counts['peak_kb'], unit_peak or 0)
        peak_text = 'peak unknown' if unit_peak is None else '%d MB' % (unit_peak // 1024)
        label = '[%d/%d] %s %s (%s)' % (n, numbered_from + len(todo), entry['target'], entry['file'], reason)
        if status == 0:
            counts['extracted'] += 1
            record_outcome(paths, entry, None)
            log('%s: ok %.1fs %s' % (label, time.time() - t0, peak_text))
        elif status == 3:
            counts['extracted'] += 1
            counts['with_errors'] += 1
            record_outcome(paths, entry, None)
            log('%s: RECORDED WITH ERRORS %.1fs %s\n%s' % (label, time.time() - t0, peak_text, stderr.rstrip()))
        else:
            counts['failed'] += 1
            why = 'killed by the memory watchdog' if status == 137 else 'status %d' % status
            record_outcome(paths, entry, (status, why))
            log('%s: FAILED (%s) %s\n%s' % (label, why, peak_text, stderr.rstrip()))


# What the argument of a reflective call can name (reflective_table.h).
REFLECTIVE_KINDS = ('selector', 'class', 'protocol', 'key', 'key-path', 'predicate-format', 'method',
                    'implementation', 'property')


# Files in the repository that units read, whose declarations no unit records
# for that target, content and view (how the unit's preprocessor saw the file;
# '' for a file read only through a module, whose claim has view ''):
# [(path, target, the first such unit's id)]. Files under Build/ are not
# recorded (the extractor skips them).
DECLARATION_GAPS_SQL = (
    "SELECT i.path, t.target, min(t.id) FROM tu_input i JOIN tu t ON t.id = i.tu "
    "WHERE substr(i.path, 1, 1) != '/' AND substr(i.path, 1, 6) != 'Build/' "
    "AND NOT EXISTS (SELECT 1 FROM decl_source d WHERE d.path = i.path AND d.digest = i.digest "
    "AND d.target = t.target AND d.view = coalesce(i.view, '')) "
    "GROUP BY i.path, i.digest, coalesce(i.view, ''), t.target ORDER BY i.path, t.target")


def declaration_gaps(con):
    return con.execute(DECLARATION_GAPS_SQL).fetchall()


# Modules (sdk_claim keys) that a unit loaded whose declarations outside the
# repository no unit records (the unit that held the claim was removed):
# [(module, the first such unit's id)].
SDK_GAPS_SQL = (
    "SELECT m.module, min(m.tu) FROM tu_module m WHERE NOT EXISTS (SELECT 1 FROM sdk_claim c WHERE c.module = "
    "m.module) GROUP BY m.module ORDER BY m.module")


def sdk_gaps(con):
    if 'tu_module' not in table_names(con):
        return []
    return con.execute(SDK_GAPS_SQL).fetchall()


def sdk_gaps_of(paths):
    con = open_db(paths.db, must_exist=False)
    try:
        return sdk_gaps(con) if has_schema(con) else []
    finally:
        con.close()


def update(paths, only_file=None, force=False, sdk=None, log=print, build_cdb_if_needed=True,
           accept_removals=False, objc=True, swift=True, accept_compiler_version=False, swift_modules=None,
           imports=None):
    """Bring the database up to date: the Objective-C units, then the Swift
    modules (when the capture kept the Swift inputs), then the swift_import
    rows of each module with a bridging header (swiftimports.py). objc and
    swift choose the sides (update --objc-only, --swift-only); imports
    defaults to swift (update --imports-only: imports alone)."""
    if imports is None:
        imports = swift
    with Lock(paths.lock, 'codedb.py update', log=log) as lock:
        status = 0
        if objc:
            status = _update(paths, only_file, force, sdk, log, build_cdb_if_needed, accept_removals, lock)
        if swift and only_file is None:
            status = max(status, update_swift_side(paths, force, sdk, log, lock, accept_compiler_version,
                                                   swift_modules))
        if imports and only_file is None:
            import swiftimports as imp
            status = max(status, imp.update_imports(paths, log=log, force=force,
                                                    only=swift_modules if swift_modules else None,
                                                    sdk_path=(sdk or current_sdk())[0]))
        return status


def update_swift_side(paths, force, sdk, log, lock, accept_compiler_version, only=None):
    """The Swift side of update: every Swift module that is not current,
    one at a time. Returns 0, or 1 if a module failed."""
    if sdk is None:
        sdk = current_sdk()
    ctx = swiftdb.SwiftContext(paths, MIGRATION_SCOPE_TEXT, sdk[0])
    if only:
        unknown = sorted(set(only) - set(m.name for m in ctx.modules))
        if unknown:
            raise CodeDBError('not a captured Swift module: %s' % ', '.join(unknown))
    if not ctx.captured:
        log('swift: the capture in %s kept no Swift inputs, so Swift references are not in the database; run '
            'codedb.py adopt-swift-capture once, or capture again' % paths.fragments)
        return 0
    os.makedirs(os.path.dirname(paths.db), exist_ok=True)
    started = time.time()
    try:
        counts, _ = swiftdb.update_swift(paths, ctx, run_in_group, DigestCache(paths.root), MIGRATION_SCOPE_DIRS,
                                         lock=lock, log=log, force=force,
                                         accept_version=accept_compiler_version, only=only)
    except swiftdb.SwiftError as e:
        raise CodeDBError(str(e))
    log('swift: extracted %d, failed %d, skipped as current %d, removed %d; %.0fs' % (
        counts['extracted'], counts['failed'], counts['skipped'], counts['removed'], time.time() - started))
    return 1 if counts['failed'] else 0


def _update(paths, only_file, force, sdk, log, build_cdb_if_needed, accept_removals, lock):
    started = time.time()
    ensure_extractor(paths, log=log, lock=lock)
    if build_cdb_if_needed:
        ensure_cdb(paths, log=log, accept_removals=accept_removals)
    if not os.path.exists(paths.cdb):
        raise CodeDBError('no compile database at %s' % paths.cdb)
    out_of_date = False
    if build_cdb_if_needed:
        out_of_date = check_cdb_against_project(paths.root, paths.cdb, log=log,
                                                other_projects=default_other_projects(paths.root, paths.other_spec))
    meta, index = read_cdb_index(paths.cdb)
    if sdk is None:
        sdk = current_sdk()
    current = extractor_version(paths)
    compiler = extractor_compiler(paths)
    os.makedirs(os.path.dirname(paths.db), exist_ok=True)
    con = open_db(paths.db, must_exist=False)
    try:
        prepare_db(con, log=log)
        states = unit_states(con, index, current, sdk, DigestCache(paths.root), built_sdk=cdb_sdk(meta),
                             compiler=compiler, extractor=paths.extractor)
    finally:
        con.close()
    wanted = None
    if only_file:
        wanted = rel(os.path.abspath(only_file), paths.root)
    todo = []
    skipped = 0
    for entry in read_cdb(paths.cdb):
        if entry.get('meta'):
            continue
        if wanted is not None and entry['file'] != wanted:
            continue
        state = states[(entry['target'], entry['file'])]
        if force:
            todo.append((entry, 'forced'))
        elif state.state == CURRENT:
            skipped += 1
        else:
            todo.append((entry, state.reason))
    if wanted is not None and not todo and not skipped:
        raise CodeDBError('%s is not in the compile database' % wanted)

    counts = {'extracted': 0, 'with_errors': 0, 'failed': 0, 'peak_kb': 0}
    peak_dir = tempfile.mkdtemp(prefix='codedb-')
    try:
        extract_units(paths, todo, sdk, lock, log, peak_dir, counts, 0)

        removed = 0
        con = open_db(paths.db, must_exist=False)
        try:
            if has_schema(con) and wanted is None:
                gone = [r for r in con.execute('SELECT id, target, main_file FROM tu ORDER BY target, main_file')
                        if (r[1], r[2]) not in index]
                with con:
                    for tu_id, target, main in gone:
                        log('removing %s %s from the database: it is not in the compile database' % (target, main))
                        for table in UNIT_TABLES:
                            con.execute('DELETE FROM %s WHERE tu=?' % table, (tu_id,))
                        con.execute('DELETE FROM tu WHERE id=?', (tu_id,))
                    for target, main in list(con.execute('SELECT target, main_file FROM tu_failure')):
                        if (target, main) not in index:
                            con.execute('DELETE FROM tu_failure WHERE target=? AND main_file=?', (target, main))
                removed = len(gone)
        finally:
            con.close()

        # A unit that reads a file whose declarations no unit records (the
        # unit that recorded them was removed, or no longer reads it) is
        # extracted again, so that it records them.
        entries = dict(((e['target'], e['file']), e) for e in read_cdb(paths.cdb) if not e.get('meta'))
        done = len(todo)
        for _ in range(3 if wanted is None else 0):
            con = open_db(paths.db, must_exist=False)
            try:
                if not has_schema(con):
                    break
                gaps = declaration_gaps(con)
                units = dict((r[0], (r[1], r[2])) for r in con.execute('SELECT id, target, main_file FROM tu'))
                failures = set(con.execute('SELECT target, main_file FROM tu_failure'))
            finally:
                con.close()
            refill = []
            for path, target, tu_id in gaps:
                key = units.get(tu_id)
                if key in entries and key not in failures and all(key != (e['target'], e['file']) for e, _ in refill):
                    refill.append((entries[key], 'declarations of %s are recorded by no unit' % path))
            for module, tu_id in sdk_gaps_of(paths):
                key = units.get(tu_id)
                if key in entries and key not in failures and all(key != (e['target'], e['file']) for e, _ in refill):
                    refill.append((entries[key], 'declarations of module %s are recorded by no unit' % module))
            if not refill:
                break
            extract_units(paths, refill, sdk, lock, log, peak_dir, counts, done)
            done += len(refill)
    finally:
        shutil.rmtree(peak_dir, ignore_errors=True)
    extracted, with_errors, failed, peak_kb = (counts['extracted'], counts['with_errors'], counts['failed'],
                                               counts['peak_kb'])

    con = open_db(paths.db, must_exist=False)
    try:
        error_units = (con.execute('SELECT count(*) FROM tu WHERE diagnostics_errors > 0').fetchone()[0]
                       if has_schema(con) else 0)
        bodies = (con.execute('SELECT sum(module_bodies_skipped), (SELECT main_file FROM tu WHERE '
                              'module_bodies_skipped > 0 ORDER BY main_file LIMIT 1) FROM tu').fetchone()
                  if has_schema(con) else None)
    finally:
        con.close()
    if bodies and bodies[0]:
        # extract_sends.cpp "Declarations read through a module": the bodies
        # are not traversed, so a send in one would be a silent miss.
        log('warning: %d function bodies in repository headers that units read only through a module are not '
            'walked: their sends and references are not in the database (first: %s)' % bodies)
    children_peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024
    log('extracted %d (%d with parse errors), skipped as current %d, failed %d, removed %d; '
        '%.0fs; peak memory of one extraction %d MB (watchdog); largest child process %d MB (rusage, includes any extractor rebuild)' % (
            extracted, with_errors, skipped, failed, removed, time.time() - started,
            peak_kb // 1024, children_peak // 1024))
    if error_units:
        log('%d units in the database have parse errors; their rows are incomplete' % error_units)
    if out_of_date:
        log('the compile database is out of date (see above)')
    return 0 if (failed == 0 and error_units == 0 and not out_of_date) else 1


# --- Queries -----------------------------------------------------------------

UNITS_LISTED = 5
EXIT_STATUS_TEXT = ('exit status: 0 sends printed, 1 none (0 and 1 only when every unit is current, the compile '
                    'database covers the project, the build settings are unchanged and, with no rows, the text '
                    'search finds none of the forms it searches in a file that is not parsed: the first keyword as a '
                    'message send, and the property of a setter-shaped, is-prefixed or unary selector with dot '
                    'syntax), 3 answered but incomplete, 2 error')
NOT_PARSED_HEADING = 'Not parsed: callers in these files are NOT in this database'
TEXT_MATCHES_HEADING = 'Possible callers in files that are not parsed (text search, unverified)'
# What text_matches searches for, and what it does not.
TEXT_SEARCH_FORMS = ('  searched: the first keyword of the selector as a message send (followed by : or ]), and, for a '
                     'setter-shaped (setFoo:), is-prefixed (isFoo) or unary (foo) selector, the property it stands for '
                     'accessed with dot syntax, whether or not an assignment follows (.foo and .Foo for setFoo:, .foo '
                     'and .isFoo for isFoo, .foo for foo); not searched: later keywords alone, selectors built by '
                     'macros or strings, @selector of a unary selector, and properties whose accessor names were '
                     'customized with getter= or setter= other than the is form')
METHODS_SEARCH_FORMS = ('  searched: a line that declares or defines a method whose first keyword is the selector\'s '
                        '(- or +, the return type in parentheses, then the keyword), and, for a setter-shaped, '
                        'is-prefixed or unary selector, an @property line naming the property it stands for; not '
                        'searched: methods made by macros, and properties whose accessors were renamed with getter= '
                        'or setter=')
SELREFS_SEARCH_FORMS = ('  searched: @selector of the selector, and the selector as a string literal ("name" or '
                        '@"name"); not searched: selector names built by macros, formats or concatenation')
KEYS_SEARCH_FORMS = ('  searched for each key: a string literal that is the key, or a key path with the key as one of '
                     'its components')
DECLARATIONS_NOTE = ('note: a header\'s method and property declarations are recorded once per target, content and '
                     'view of the header (the language it is read as and the #if branches the preprocessor skipped), '
                     'by the first unit of the target that reads it with that view; their rows carry that unit\'s '
                     'state. A declaration recorded in some views of a file and not others says so ("in 1 of 2 views '
                     'of this file"), with the units that recorded it')

# What a query prints in its status block, and how it decides completeness.
#   name             the command
#   not_in           the "Not in this database" items
#   exit_text        the exit status line
#   search_forms     what the text search of files that are not parsed looks
#                    for, or None when the query searches none
#   declarations     the answer uses declarations from headers, so a file whose
#                    declarations no unit records makes it incomplete
QuerySpec = collections.namedtuple('QuerySpec', 'name not_in exit_text search_forms declarations')


def exit_text(rows, declarations, search, extra=''):
    return ('exit status: 0 %s, 1 none (0 and 1 only when every unit is current, the compile database covers the '
            'project, the build settings are unchanged%s%s), 3 answered but incomplete, 2 error' % (
                rows, ', every file a unit reads has its declarations recorded' if declarations else '',
                ' and, with no rows, the text search finds none of the forms it searches in a file that is not '
                'parsed' if search else '') + extra)


SENDS_SPEC = QuerySpec('sends', NOT_IN_DATABASE, EXIT_STATUS_TEXT, TEXT_SEARCH_FORMS, False)
METHODS_SPEC = QuerySpec('methods', METHODS_NOT_IN_DATABASE, exit_text('declarations printed', True, True),
                         METHODS_SEARCH_FORMS, True)
SELREFS_SPEC = QuerySpec('selrefs', SELREFS_NOT_IN_DATABASE, exit_text('references printed', False, True),
                         SELREFS_SEARCH_FORMS, False)
REFLECTIVE_SPEC = QuerySpec('reflective', REFLECTIVE_NOT_IN_DATABASE, exit_text('call sites printed', False, False),
                            None, False)
REACH_SPEC = QuerySpec('reach', NOT_IN_DATABASE_COMMON,
                       exit_text('if any group has rows', True, True), None, True)


SWIFTREFS_SPEC_ARGS = ('swiftrefs', NOT_IN_DATABASE_COMMON,
                       exit_text('Swift references or declarations printed', False, False), None, False)


def search_forms_sends(selector):
    """The forms text_matches searches by default (TEXT_SEARCH_FORMS)."""
    keyword = selector.split(':')[0]
    if not keyword:
        return []
    forms = [(keyword, 'message send', re.compile(r'(?<![A-Za-z0-9_$])%s\s*[:\]]' % re.escape(keyword)))]
    for name in dot_syntax_properties(selector):
        forms.append((name, 'dot syntax, property ' + name, re.compile(r'\.\s*%s(?![A-Za-z0-9_$])' % re.escape(name))))
    return forms


def search_forms_methods(selector):
    """METHODS_SEARCH_FORMS."""
    keyword = selector.split(':')[0]
    if not keyword:
        return []
    forms = [(keyword, 'method declaration',
              re.compile(r'^\s*[-+]\s*\(.*\)\s*%s(?![A-Za-z0-9_$])' % re.escape(keyword)))]
    for name in dot_syntax_properties(selector):
        forms.append((name, 'property ' + name,
                      re.compile(r'^\s*@property\b.*(?<![A-Za-z0-9_$])%s\s*;' % re.escape(name))))
    return forms


def search_forms_selrefs(selector):
    """SELREFS_SEARCH_FORMS."""
    if not selector:
        return []
    s = re.escape(selector)
    return [(selector, '@selector', re.compile(r'@selector\s*\(\s*%s\s*\)' % s)),
            (selector, 'string literal', re.compile(r'"%s"' % s))]


def search_forms_keys(keys):
    """KEYS_SEARCH_FORMS."""
    return [(k, 'key ' + k, re.compile(r'"(?:[^"]*\.)?%s(?:\.[^"]*)?"' % re.escape(k))) for k in keys]


_PROPERTY_IN_USR = re.compile(r'\(c?py\)([^()]*)$')


def property_name_of_usr(usr):
    """The property name at the end of a property's USR, or None."""
    m = _PROPERTY_IN_USR.search(usr or '')
    return m.group(1) if m else None


def lower_first(s):
    return s[:1].lower() + s[1:]


# Selector shapes that key-value coding (and key-value observing) looks up by
# assembling a key into a name; each pattern's group is the key, capitalized.
KVC_SHAPES = [re.compile(p) for p in (
    r'^set([A-Z][A-Za-z0-9_]*):$', r'^is([A-Z][A-Za-z0-9_]*)$', r'^get([A-Z][A-Za-z0-9_]*)$',
    r'^countOf([A-Z][A-Za-z0-9_]*)$', r'^enumeratorOf([A-Z][A-Za-z0-9_]*)$', r'^memberOf([A-Z][A-Za-z0-9_]*):$',
    r'^objectIn([A-Z][A-Za-z0-9_]*)AtIndex:$', r'^([a-z][A-Za-z0-9_]*)AtIndexes:$',
    r'^insertObject:in([A-Z][A-Za-z0-9_]*)AtIndex:$', r'^insert([A-Z][A-Za-z0-9_]*):atIndexes:$',
    r'^removeObjectFrom([A-Z][A-Za-z0-9_]*)AtIndex:$', r'^remove([A-Z][A-Za-z0-9_]*)AtIndexes:$',
    r'^replaceObjectIn([A-Z][A-Za-z0-9_]*)AtIndex:withObject:$',
    r'^replace([A-Z][A-Za-z0-9_]*)AtIndexes:with[A-Z][A-Za-z0-9_]*:$',
    r'^add([A-Z][A-Za-z0-9_]*)Object:$', r'^remove([A-Z][A-Za-z0-9_]*)Object:$',
    r'^add([A-Z][A-Za-z0-9_]*):$', r'^remove([A-Z][A-Za-z0-9_]*):$', r'^intersect([A-Z][A-Za-z0-9_]*):$',
    r'^validate([A-Z][A-Za-z0-9_]*):error:$', r'^keyPathsForValuesAffecting([A-Z][A-Za-z0-9_]*)$',
    r'^automaticallyNotifiesObserversOf([A-Z][A-Za-z0-9_]*)$',
    # The underscore forms the accessor search also tries: _get<Key>,
    # _set<Key>: and _<key>. _is<Key> is not one: the search tries that name
    # only for an instance variable.
    r'^_get([A-Z][A-Za-z0-9_]*)$', r'^_set([A-Z][A-Za-z0-9_]*):$', r'^_([a-z][A-Za-z0-9_]*)$')]


def kvc_keys(selector):
    """The keys whose key-value coding reaches selector by its shape: for a
    unary selector the selector itself; for every shape in KVC_SHAPES the key
    in it, with its first letter lowered and as written. The lowered form is
    left out when the second letter is a capital (setURL: is reached by URL,
    not uRL)."""
    keys = []
    if selector and ':' not in selector:
        keys.append(selector)
    for p in KVC_SHAPES:
        m = p.match(selector)
        if m:
            key = m.group(1)
            forms = (key,) if key[1:2].isupper() else (lower_first(key), key)
            for k in forms:
                if k not in keys:
                    keys.append(k)
    return keys


def key_matches(kind, text, keys):
    """Whether a literal key, key path or predicate format names one of keys."""
    if text is None:
        return False
    if kind == 'key':
        return text in keys
    if kind == 'key-path':
        return any(part in keys for part in text.split('.'))
    if kind == 'predicate-format':
        return any(word in keys for word in re.findall(r'[A-Za-z_$][A-Za-z0-9_$]*', text))
    return False


class QueryContext:
    """What every query needs: the database, and the state of every unit, to
    mark rows and to write the status block."""

    def __init__(self, paths, spec=SENDS_SPEC):
        self.paths = paths
        self.spec = spec
        self.con = open_db(paths.db)
        if not has_schema(self.con):
            self.con.close()
            raise CodeDBError('%s has no code database schema' % paths.db)
        if schema_version(self.con) != SCHEMA_VERSION:
            version = schema_version(self.con)
            self.con.close()
            raise CodeDBError('%s has schema version %d, not %d; run codedb.py update' % (
                paths.db, version, SCHEMA_VERSION))
        self.meta, self.index = read_cdb_index(paths.cdb)
        digests = DigestCache(paths.root)
        self.states = unit_states(self.con, self.index, extractor_source_digest(), current_sdk(),
                                  digests, built_sdk=cdb_sdk(self.meta),
                                  compiler=extractor_compiler(paths), extractor=paths.extractor)
        # The Swift side, when the capture kept the Swift inputs; otherwise
        # Swift is reported as not in this database, as before it existed.
        self.swift = swiftdb.SwiftContext(paths, MIGRATION_SCOPE_TEXT, current_sdk()[0],
                                          project_swift=lambda: project_swift_sources(paths.root))
        self.swift_states = (swiftdb.module_states(self.con, self.swift, digests) if self.swift.captured
                             else None)
        self.swift_by_unit = dict((s.unit, s) for s in (self.swift_states or {}).values() if s.unit is not None)
        self.by_tu = dict((s.tu, s) for s in self.states.values() if s.tu is not None)
        # The same coverage check `update` makes, cached.
        self.coverage = (coverage(paths.root, paths.cdb, other_projects=default_other_projects(
            paths.root, paths.other_spec)) if self.index is not None else None)
        if self.coverage is not None:
            # An implementation file a current unit reads (#include of a .m,
            # as PTYWindow.m includes iTermWindowImpl.m) is parsed.
            current = set(s.tu for s in self.states.values() if s.state == CURRENT and s.tu is not None)
            parsed = set()
            for f in not_parsed_files(self.coverage.not_parsed):
                if any(tu in current for (tu,) in self.con.execute('SELECT tu FROM tu_input WHERE path=?', (f,))):
                    parsed.add(f)
            self.coverage = self.coverage._replace(not_parsed=without_files(self.coverage.not_parsed, parsed))
        # Files whose declarations no current unit records.
        self.gaps = []
        if spec.declarations:
            current = set(s.tu for s in self.states.values() if s.state == CURRENT and not s.errors)
            self.gaps = [(path, target) for path, target, tu in declaration_gaps(self.con) if tu in current]
        # Set by search_not_parsed(): the text search of the files that are
        # not parsed.
        self.matches, self.matches_stopped = [], False
        self.rows_printed = None
        # INCOMPLETE lines a query adds for reasons of its own.
        self.extra_incomplete = []

    def marks(self, tu_ids):
        """Marks for a row that comes from these units, one per distinct
        reason, in a stable order."""
        out = []
        for tu in sorted(tu_ids):
            s = self.by_tu[tu]
            if s.state == FAILED:
                m = 'FAILED (%s; these rows are from an earlier extraction)' % s.reason
            elif s.state == STALE:
                m = 'STALE (%s)' % s.reason
            elif s.state == ORPHAN:
                m = 'NOT IN THE COMPILE DATABASE'
            else:
                m = None
            for x in (m, 'UNIT HAS PARSE ERRORS' if s.errors else None):
                if x and x not in out:
                    out.append(x)
        return out

    def counts(self):
        by_state = collections.Counter(s.state for s in self.states.values())
        errors = sum(1 for s in self.states.values() if s.errors)
        return by_state, errors

    def not_current(self):
        """Units whose rows may be missing or wrong: every unit that is not
        current, and every unit recorded with parse errors."""
        return [s for s in self.states.values() if s.state != CURRENT or s.errors]

    def incomplete(self):
        return bool(self.incomplete_lines())

    def not_parsed_count(self):
        c = self.coverage
        return not_parsed_count(c.not_parsed) if c is not None else 0

    def search_not_parsed(self, selector=None, forms=None, skip_definitions=True):
        """Search the files that are not parsed as text, for the default forms
        of selector (search_forms_sends) or for forms."""
        if self.coverage is not None:
            self.matches, self.matches_stopped = text_matches(
                self.paths.root, not_parsed_files(self.coverage.not_parsed), selector, forms=forms,
                skip_definitions=skip_definitions)

    def incomplete_lines(self):
        """One line per reason the answer is incomplete; none when every
        unit is current, the compile database covers the project, (for a
        query that uses declarations) every file a current unit reads has its
        declarations recorded and, when there are no rows, the text search
        finds no match in a file that is not parsed."""
        lines = []
        if self.rows_printed == 0 and self.matches:
            lines.append('INCOMPLETE: no rows, but files that are not parsed mention the selector (text matches: %d, '
                         'listed under Possible callers); callers in them are not in this database.'
                         % len(self.matches))
        if self.index is None:
            lines.append('INCOMPLETE: there is no compile database at %s, so units missing from the database cannot '
                         'be found; sends may be absent from this answer. Run capture_compile_commands.sh, then '
                         'codedb.py update.' % self.paths.cdb)
        c = self.coverage
        if c is not None and c.project is None:
            lines.append('INCOMPLETE: there is no project file at %s, so the compile database cannot be checked '
                         'against the project.' % project_file(self.paths.root))
        elif c is not None and c.settings_changed:
            lines.append('INCOMPLETE: the build settings changed since the compile commands were captured; capture '
                         'again with capture_compile_commands.sh, then run codedb.py update.')
        if c is not None and c.project is not None and others_out_of_date(c):
            lines.append('INCOMPLETE: the build settings or the capture spec of other projects changed since they '
                         'were captured (%s); %s, then run codedb.py update.' % (
                             ', '.join(sorted(set(c.others['settings_changed'] + c.others['spec_changed']))),
                             OTHER_CAPTURE_HINT))
        if c is not None and c.project is not None and coverage_out_of_date(c):
            lines.append('INCOMPLETE: the compile database does not cover the project (not covered %d, no longer in '
                         'the project %d); sends in those files may be missing or wrong. Run '
                         'capture_compile_commands.sh, then codedb.py update.' % (len(c.not_covered), len(c.extra)))
        not_current = self.not_current()
        if not_current:
            by_state, errors = self.counts()
            lines.append('INCOMPLETE: %d of %d units are not current (stale %d, missing %d, failed %d, not in the '
                         'compile database %d, recorded with parse errors %d); sends in them may be missing or '
                         'wrong. Run codedb.py update, or ask with sends --update.' % (
                             len(not_current), len(self.states), by_state[STALE], by_state[MISSING],
                             by_state[FAILED], by_state[ORPHAN], errors))
        if self.gaps:
            lines.append('INCOMPLETE: %d files that current units read have no recorded declarations (the unit that '
                         'recorded them was removed or no longer reads them), first: %s (%s). Run codedb.py update.'
                         % (len(self.gaps), self.gaps[0][0], self.gaps[0][1]))
        if self.swift_states is not None:
            by = collections.Counter(s.state for s in self.swift_states.values())
            bad = sum(n for state, n in by.items() if state != 'current')
            if self.swift.project_mismatch:
                name, (added, removed) = sorted(self.swift.project_mismatch.items())[0]
                lines.append('INCOMPLETE: the captured Swift file lists of %d modules do not match the project (%s: '
                             '%d added, %d removed since the capture, first %s); references in those files are not '
                             'in this database. Run capture_compile_commands.sh, then codedb.py update.' % (
                                 len(self.swift.project_mismatch), name, len(added), len(removed),
                                 (added + removed)[0]))
            if bad:
                lines.append('INCOMPLETE: %d of %d Swift modules are not current (stale %d, missing %d, failed %d, '
                             'no longer captured %d); Swift references in them may be missing or wrong. Run '
                             'codedb.py update.' % (bad, len(self.swift_states), by['stale'], by['missing'],
                                                    by['failed'], by['orphan']))
        return lines + self.extra_incomplete

    def swift_unknowns(self):
        """[(module, unknown node kinds, unknown access kinds)] of the Swift
        modules in the database (the texts swift_refs stored)."""
        if self.swift_states is None or not swiftdb.has_swift_tables(self.con):
            return []
        return self.con.execute('SELECT module, unknown_node_kinds, unknown_access_kinds FROM swift_unit '
                                'ORDER BY module').fetchall()

    def warning_lines(self):
        """Lines printed with the INCOMPLETE ones that do not change the exit
        status: node kinds the Swift reader does not know."""
        unknown = [(m, k) for m, k, _ in self.swift_unknowns() if k]
        if not unknown:
            return []
        return ['WARNING: the Swift reader met node kinds it does not know in %d modules (%s); references under them '
                'may be missing or have access unknown. Classify them in '
                'tools/swift_migration/codedb/swiftreader/dump_format.h.' % (
                    len(unknown), '; '.join('%s: %s' % mk for mk in unknown))]

    def swift_marks(self, unit):
        s = self.swift_by_unit.get(unit)
        if s is None or s.state == 'current':
            return []
        if s.state == 'failed':
            return ['FAILED (%s; these rows are from an earlier extraction)' % s.reason]
        if s.state == 'orphan':
            return ['NOT A CAPTURED MODULE']
        return ['STALE (%s)' % s.reason]

    def not_in_items(self, items):
        """The "Not in this database" items, with the Swift item replaced by
        what is still not covered when the Swift side is in the database."""
        if self.swift_states is None:
            return items
        return [SWIFT_NOT_IN_DATABASE if item == NOT_IN_DATABASE_COMMON[0] else item for item in items]

    def write_swift_status(self, out):
        if self.swift_states is None:
            return
        by = collections.Counter(s.state for s in self.swift_states.values())
        in_db = sum(1 for s in self.swift_states.values() if s.unit is not None)
        out.write('swift modules: %d captured, %d in the database\n' % (len(self.swift.modules), in_db))
        stale_kinds = collections.Counter(s.reason.split(':')[0] for s in self.swift_states.values()
                                          if s.state == 'stale')
        for state, label in (('current', 'current'), ('stale', 'stale'), ('missing', 'missing from the database'),
                             ('failed', 'last extraction failed'), ('orphan', 'in the database, no longer captured')):
            detail = ' (%s)' % ', '.join('%s %d' % kv for kv in sorted(stale_kinds.items())) if (
                state == 'stale' and stale_kinds) else ''
            out.write('  %s: %d%s\n' % (label, by[state], detail))
        for s in sorted(self.swift_states.values()):
            if s.state != 'current':
                out.write('    %s: %s\n' % (s.module, s.reason))
        for name, (added, removed) in sorted(self.swift.project_mismatch.items()):
            out.write('  file list of %s does not match the project: added %s; removed %s\n' % (
                name, ', '.join(added) or 'none', ', '.join(removed) or 'none'))
        if self.swift.not_compared:
            out.write('  file lists not compared with a project (built by another Xcode project): %s\n' % ', '.join(
                self.swift.not_compared))
        out.write('  compiler: %s\n' % (self.swift.compiler or 'unknown'))
        rows = self.con.execute('SELECT module, assertion_count, unresolved_count, underivable_count FROM swift_unit '
                                'ORDER BY module').fetchall() if swiftdb.has_swift_tables(self.con) else []
        asserts = ['%s %d' % (m, a) for m, a, _, _ in rows if a]
        out.write('  compiler assertion failures passed with -Xllvm -assert-continue: %s\n' % (
            ', '.join(asserts) or 'none'))
        unknown_sel = self.con.execute("SELECT count(*) FROM swift_ref WHERE kind = 'selector-expr' AND selector IS "
                                       "NULL").fetchone()[0] if rows else 0
        underivable = sum(r[3] for r in rows)
        unresolved = sum(r[2] for r in rows)
        out.write('  #selector expressions whose selector is unknown: %d; Swift declarations visible to Objective-C '
                  'whose selector is unknown: %d; references without a type (unresolved, not recorded): %d\n' % (
                      unknown_sel, underivable, unresolved))
        unknown_access = dict(self.con.execute(
            "SELECT u.module, count(*) FROM swift_ref r JOIN swift_unit u ON u.id = r.unit WHERE r.access = 'unknown' "
            "GROUP BY u.module").fetchall()) if rows else {}
        causes = dict((m, a) for m, _, a in self.swift_unknowns())
        out.write('  property references whose access is unknown (counted as both read and write): %s\n' % (
            ', '.join('%s %d%s' % (m, n, ' (by the parent that is not classified: %s)' % causes[m] if causes.get(m)
                                   else '') for m, n in sorted(unknown_access.items())) or 'none'))
        kinds = ['%s: %s' % (m, k) for m, k, _ in self.swift_unknowns() if k]
        out.write('  node kinds the reader does not know: %s\n' % ('; '.join(kinds) or 'none'))
        undetermined = self.con.execute(
            'SELECT u.module, count(DISTINCT i.file) FROM swift_inactive i JOIN swift_unit u ON u.id = i.unit WHERE '
            'i.undetermined = 1 GROUP BY u.module ORDER BY u.module').fetchall() if rows else []
        out.write('  Swift files whose inactive #if regions could not be determined (reach searches them whole): '
                  '%s\n' % (', '.join('%s %d' % r for r in undetermined) or 'none'))
        if self.swift.excluded:
            out.write('  excluded: %s (their files are outside the repository: Swift package checkouts)\n' % ', '.join(
                m.name for m in self.swift.excluded))
        groups = swiftdb.uncaptured_swift_files(self.paths.root, self.swift.modules + self.swift.excluded,
                                                lambda: repository_files(self.paths.root))
        out.write('  Swift files in the repository that no captured module compiles (not in this database): %d%s\n'
                  % (sum(groups.values()), ' (%s)' % ', '.join('%s %d' % kv for kv in sorted(groups.items()))
                     if groups else ''))

    def write_status(self, out, rows_printed, rows_marked, rows_outside):
        spec = self.spec
        self.rows_printed = rows_printed
        by_state, errors = self.counts()
        incomplete = self.incomplete_lines() + self.warning_lines()
        out.write('\n--- status ---\n')
        for line in incomplete:
            out.write(line + '\n')
        if not rows_printed and self.not_parsed_count():
            out.write('No rows does not mean no callers: %d implementation files in the repository are not parsed '
                      '(see Not parsed)\n' % self.not_parsed_count())
        out.write('database: %s\n' % self.paths.db)
        if self.index is None:
            out.write('compile database: none: no compile database at %s\n' % self.paths.cdb)
        else:
            out.write('compile database: %s (%d units)\n' % (self.paths.cdb, len(self.index)))
        in_db = sum(1 for s in self.states.values() if s.tu is not None)
        out.write('units: %s in the compile database, %d in the database\n' % (
            '?' if self.index is None else len(self.index), in_db))
        stale_kinds = collections.Counter(s.reason.split(':')[0] for s in self.states.values() if s.state == STALE)
        for state, label in STATE_LABELS.items():
            detail = ''
            if state == STALE and stale_kinds:
                detail = ' (%s)' % ', '.join('%s %d' % kv for kv in sorted(stale_kinds.items()))
            out.write('  %s: %d%s\n' % (label, by_state[state], detail))
        out.write('  recorded with parse errors: %d\n' % errors)
        for state, label in STATE_LABELS.items():
            if state == CURRENT or not by_state[state]:
                continue
            units = [s for s in sorted(self.states.values()) if s.state == state]
            out.write('  %s, first %d of %d:\n' % (label, UNITS_LISTED, len(units)))
            for s in units[:UNITS_LISTED]:
                show_reason = state in (STALE, FAILED)
                out.write('    %s %s%s\n' % (s.target, s.file, ': ' + s.reason if show_reason else ''))
        if errors:
            units = [s for s in sorted(self.states.values()) if s.errors]
            out.write('  recorded with parse errors, first %d of %d:\n' % (UNITS_LISTED, len(units)))
            for s in units[:UNITS_LISTED]:
                out.write('    %s %s: %d errors\n' % (s.target, s.file, s.errors))
        if spec.declarations:
            out.write('declarations: %s\n' % ('every file that current units read has them recorded' if not self.gaps
                                              else '%d files that current units read have none recorded' %
                                              len(self.gaps)))
            for path, target in self.gaps[:UNITS_LISTED]:
                out.write('    %s (%s)\n' % (path, target))
        self.write_coverage(out)
        out.write('rows printed: %d; from units that are not current: %d%s\n' % (
            rows_printed, rows_marked, ' (marked)' if rows_marked else ''))
        if rows_outside:
            out.write("rows outside the migration's scope (marked): %d\n" % rows_outside)
        out.write(SCOPE_STATEMENT + '\n')
        configs = self.con.execute('SELECT DISTINCT coalesce(configuration, "?"), coalesce(arch, "?"), '
                                   'coalesce(sdk_path, "?"), coalesce(sdk_version, "?"), clang_version '
                                   'FROM tu').fetchall()
        for c in configs:
            out.write('extracted: configuration %s, architecture %s, SDK %s (%s), %s\n' % c)
        if self.meta and self.meta.get('captured_at'):
            out.write('captured: %s, SDK %s (%s), build settings as of the capture%s\n' % (
                self.meta['captured_at'], self.meta.get('captured_sdk_path'), self.meta.get('captured_sdk_version'),
                ' (adopted with codedb.py adopt-capture)' if self.meta.get('capture_record_adopted') else ''))
        out.write(SDK_MODULE_NOTE + '\n')
        out.write(EXTRA_ROWS_NOTE + '\n')
        if spec.declarations:
            out.write(DECLARATIONS_NOTE + '\n')
        self.write_swift_status(out)
        out.write('Not in this database:\n')
        for item in self.not_in_items(spec.not_in):
            out.write('  - %s\n' % item)
        projects = [p for p, _ in self.coverage.not_parsed['other_projects']] if self.coverage is not None else []
        out.write('  - code built by other Xcode projects and Swift packages, which is not parsed, and code under '
                  'submodules/ (see Not parsed): %s\n' % (', '.join(projects) or 'none in this repository'))
        out.write(spec.exit_text + '\n')
        for line in incomplete:
            out.write(line + '\n')

    def write_coverage(self, out):
        c = self.coverage
        if c is None:
            return
        if c.project is None:
            out.write('compile database coverage: not checked: no project file at %s\n' % project_file(self.paths.root))
        elif coverage_out_of_date(c):
            out.write('compile database coverage: DOES NOT COVER THE PROJECT\n')
        else:
            out.write('compile database coverage: complete\n')
        if c.not_covered:
            out.write('  not covered by the compile database, first %d of %d:\n' % (UNITS_LISTED, len(c.not_covered)))
            for f, targets in c.not_covered[:UNITS_LISTED]:
                out.write('    %s (%s)\n' % (f, ','.join(targets)))
        if c.extra:
            out.write('  in the compile database, not in the project, first %d of %d:\n' % (UNITS_LISTED, len(c.extra)))
            for f, target in c.extra[:UNITS_LISTED]:
                out.write('    %s (%s)\n' % (f, target))
        np = c.not_parsed
        by_target = collections.Counter(t for _, targets in np['main_project'] for t in targets)
        for target, files in c.uncaptured:
            out.write('  note: project target %s compiles %d file(s) and was not captured; %d of them no captured '
                      'target compiles, so they are not parsed (Not parsed, class c)\n' % (
                          target, len(files), by_target[target]))
        for target, n in c.unchecked:
            out.write('  note: captured target %s is not in the project (a Swift package target); its %d units are '
                      'not compared with the project\n' % (target, n))
        if c.settings_changed:
            out.write('  build settings: CHANGED since the compile commands were captured\n')
        for name, project, units in c.others['captured']:
            changed = [w for w, k in (('build settings', 'settings_changed'), ('capture spec', 'spec_changed'))
                       if name in c.others[k]]
            out.write('  other project %s (%s): captured, %d units (targets %s:...)%s\n' % (
                name, project, units, name, '; %s CHANGED since its capture' % ' and '.join(changed) if changed
                else ''))
        for name, project in c.others['not_captured']:
            out.write('  other project %s (%s): not captured, so its files are not parsed (%s)\n' % (
                name, project, OTHER_CAPTURE_HINT))
        for name, project in c.others['not_checked_out']:
            out.write('  other project %s (%s): not captured: %s is not checked out here\n' % (
                name, project, os.path.dirname(project)))
        self.write_not_parsed(out)

    def write_not_parsed(self, out):
        np = self.coverage.not_parsed
        uncaptured = set(t for t, _ in self.coverage.uncaptured)
        out.write(NOT_PARSED_HEADING + '\n')
        out.write('  %d implementation files (%s) in the repository are in no unit of the compile database:\n' % (
            not_parsed_count(np), ', '.join(C_FAMILY_EXTENSIONS)))
        out.write('  (a) built by another Xcode project or Swift package: %d\n' % sum(
            len(fs) for _, fs in np['other_projects']))
        for project, files in np['other_projects']:
            out.write('    %s: %d\n' % (project, len(files)))
        out.write('  (b) under submodules/: %d\n' % len(np['submodules']))
        out.write('  (c) compiled by a target of %s, but in no unit: %d\n' % (
            os.path.basename(os.path.dirname(project_file(self.paths.root))), len(np['main_project'])))
        by_target = collections.Counter(t for _, targets in np['main_project'] for t in targets)
        for target, n in sorted(by_target.items()):
            out.write('    %s: %d (%s)\n' % (target, n, 'not captured' if target in uncaptured else
                                              'captured; such files are listed as not covered above'))
        out.write('  (d) compiled by no target of any project found: %d\n' % len(np['no_project']))
        for f in np['no_project'][:NOT_PARSED_LISTED]:
            out.write('    %s\n' % f)
        if len(np['no_project']) > NOT_PARSED_LISTED:
            out.write('    ... and %d more\n' % (len(np['no_project']) - NOT_PARSED_LISTED))
        out.write("  files under %s are the migration's own tools and fixtures and are not listed\n" %
                  MIGRATION_TOOLS_DIR)
        if self.matches:
            out.write('%s: %d%s\n' % (TEXT_MATCHES_HEADING, len(self.matches),
                                      ' (the search stopped at %d matches)' % len(self.matches)
                                      if self.matches_stopped else ''))
            out.write((self.search_forms_text or self.spec.search_forms) + '\n')
            for f, n, forms, line in self.matches:
                out.write('    %s:%d (%s): %s\n' % (f, n, forms, line))

    search_forms_text = None

    def exit_status(self, rows_printed):
        self.rows_printed = rows_printed
        if self.incomplete():
            return 3
        return 0 if rows_printed else 1

    def close(self):
        self.con.close()


def group_rows(rows, key_len):
    """Rows whose last two columns are (tu, target), grouped by the first
    key_len columns in order: [(key, {'tus': {tu: rows}, 'targets': set})]."""
    groups = {}
    order = []
    for r in rows:
        key = r[:key_len]
        if key not in groups:
            groups[key] = {'tus': {}, 'targets': set()}
            order.append(key)
        g = groups[key]
        g['tus'][r[-2]] = g['tus'].get(r[-2], 0) + 1
        g['targets'].add(r[-1])
    return [(key, groups[key]) for key in order]


def macro_text(macro, role, mfile, mline, eline, ecol):
    return 'macro %s %s(defined %s:%s, used at %s:%s)' % (macro, role + ' ' if role else '', mfile or '?', mline,
                                                          eline, ecol)


class RowWriter:
    """Writes rows, appending what every query appends (targets, test code,
    marks, scope) and counting the marked rows and those outside the
    migration's scope."""

    def __init__(self, q, out, indent=''):
        self.q, self.out, self.indent = q, out, indent
        self.written = self.marked = self.outside = 0

    def write(self, parts, g, migration, multiplicity=True):
        n = max(g['tus'].values())
        if multiplicity and n > 1:
            parts.append('%d sends at this location' % n)
        parts.append('targets ' + ','.join(sorted(g['targets'])))
        if self.q.coverage is not None and g['targets'] <= set(self.q.coverage.test_targets):
            parts.append('test code')
        marks = self.q.marks(g['tus'])
        if marks:
            self.marked += 1
            parts += marks
        if not migration:
            self.outside += 1
            parts.append("outside the migration's scope")
        self.written += 1
        self.out.write(self.indent + '  '.join(parts) + '\n')


SEND_ROW_SQL = ('SELECT s.file, s.line, s.col, s.enclosing_name, s.receiver_kind, s.receiver_type, '
                's.macro_name, s.macro_file, s.macro_line, s.macro_role, s.expansion_line, s.expansion_col, '
                's.implicit_accessor, s.in_block, s.in_migration_scope, s.tu, t.target '
                'FROM send s JOIN tu t ON t.id = s.tu WHERE s.selector = ? '
                'ORDER BY s.file, s.line, s.col')


def write_send_rows(q, writer, selector):
    for key, g in group_rows(q.con.execute(SEND_ROW_SQL, (selector,)).fetchall(), 15):
        (file, line, col, enclosing, rkind, rtype, macro, mfile, mline, role, eline, ecol,
         implicit, in_block, migration) = key
        parts = ['%s:%d:%d' % (file, line, col), enclosing or '(file scope)',
                 'receiver %s%s' % (rtype or '?', '' if rkind == 'instance' else ' (%s)' % rkind)]
        if macro:
            parts.append(macro_text(macro, role, mfile, mline, eline, ecol))
        if implicit == 1:
            parts.append('dot-syntax accessor')
        elif implicit == 2:
            parts.append('subscript accessor')
        if in_block:
            parts.append('in block')
        writer.write(parts, g, migration)


class SwiftRowWriter:
    """Writes Swift rows with the marks every query appends (test code, the
    module's state, scope), counting the marked rows and those outside the
    migration's scope."""

    def __init__(self, q, out, indent='  '):
        self.q, self.out, self.indent = q, out, indent
        self.written = self.marked = self.outside = 0

    def write(self, parts, unit, migration, target):
        if self.q.coverage is not None and target in set(self.q.coverage.test_targets):
            parts.append('test code')
        marks = self.q.swift_marks(unit)
        if marks:
            self.marked += 1
            parts += marks
        if not migration:
            self.outside += 1
            parts.append("outside the migration's scope")
        self.written += 1
        self.out.write(self.indent + '  '.join(parts) + '\n')


def swift_targets(q):
    return dict((s.unit, s.target) for s in (q.swift_states or {}).values() if s.unit is not None)


def write_swift_refs(q, out, selector, sends_only=False, heading=None):
    """The Swift reference group: its heading, then its rows. Returns the
    writer, or None when the Swift side is not in the database."""
    if q.swift_states is None:
        return None
    buf = io.StringIO()
    writer = SwiftRowWriter(q, buf)
    if swiftdb.has_swift_tables(q.con):
        targets = swift_targets(q)
        for d in swiftdb.swift_refs_for(q.con, selector, sends_only=sends_only):
            writer.write(swiftdb.describe_ref(d), d['unit'], d['in_migration_scope'], targets.get(d['unit']))
    out.write('%s: %d\n' % ((heading or SWIFT_REFS_HEADING) % selector, writer.written))
    out.write(buf.getvalue())
    return writer


def write_swift_decls(q, out, selector):
    if q.swift_states is None:
        return None
    buf = io.StringIO()
    writer = SwiftRowWriter(q, buf)
    if swiftdb.has_swift_tables(q.con):
        targets = swift_targets(q)
        for d in swiftdb.swift_decls_for(q.con, selector):
            writer.write(swiftdb.describe_decl(d, selector), d['unit'], d['in_migration_scope'],
                         targets.get(d['unit']))
    out.write('%s: %d\n' % (SWIFT_DECLS_HEADING % selector, writer.written))
    out.write(buf.getvalue())
    return writer


def sends(paths, selector, out=None):
    out = out or sys.stdout
    q = QueryContext(paths)
    try:
        q.search_not_parsed(selector)
        writer = RowWriter(q, out)
        write_send_rows(q, writer, selector)
        written, marked, outside = writer.written, writer.marked, writer.outside
        swift = write_swift_refs(q, out, selector, sends_only=True, heading=SWIFT_SENDS_HEADING)
        if swift is not None:
            written += swift.written
            marked += swift.marked
            outside += swift.outside
        q.write_status(out, written, marked, outside)
        return q.exit_status(written)
    finally:
        q.close()


SWIFTREFS_SPEC = QuerySpec(*SWIFTREFS_SPEC_ARGS)


def swiftrefs(paths, selector, out=None):
    """Only the Swift side of reach: the Swift references to selector and
    the Swift declarations with it."""
    out = out or sys.stdout
    q = QueryContext(paths, SWIFTREFS_SPEC)
    try:
        if q.swift_states is None:
            out.write('The capture in %s kept no Swift inputs, so Swift references are not in this database. Run '
                      'codedb.py adopt-swift-capture once, or capture again, then codedb.py update.\n'
                      % paths.fragments)
            q.write_status(out, 0, 0, 0)
            return 3
        refs = write_swift_refs(q, out, selector)
        decls = write_swift_decls(q, out, selector)
        if swiftdb.has_swift_tables(q.con):
            swiftdb.write_protocol_witnesses(q.con, selector, out)
            swiftdb.write_inactive_search(q.con, paths.root, selector, out)
        total = refs.written + decls.written
        out.write('Not covered:\n')
        for item in REACH_SWIFT_NOT_COVERED_WITH_SWIFT:
            out.write('  - %s\n' % item)
        out.write('  - Objective-C callers: ask codedb.py reach %s\n' % selector)
        q.write_status(out, total, refs.marked + decls.marked, refs.outside + decls.outside)
        return q.exit_status(total)
    finally:
        q.close()


METHOD_ROW_SQL = ('SELECT m.file, m.line, m.col, m.is_class_method, m.container_name, m.selector, m.container_kind, '
                  'm.is_definition, m.is_implicit, m.is_synthesized_accessor, m.is_optional, m.property_usr, '
                  'm.macro_name, m.macro_file, m.macro_line, m.macro_role, m.expansion_line, m.expansion_col, '
                  'm.in_migration_scope, m.tu, t.target FROM objc_method m JOIN tu t ON t.id = m.tu '
                  'WHERE m.selector = ? ORDER BY m.file, m.line, m.col, m.container_kind, m.is_class_method')


def method_description(kind, is_definition, is_implicit, synthesized, optional, property_usr):
    prop = property_name_of_usr(property_usr)
    if synthesized:
        text = '%s synthesized accessor' % kind
        if prop:
            text += ' of property %s' % prop
    else:
        text = '%s %s' % (kind, 'definition' if is_definition else 'declaration')
        if is_implicit:
            text += ' (implicit)'
        if prop:
            text += ', accessor of property %s' % prop
    if optional:
        text += ', optional'
    return text


# Container kinds whose rows are declarations, recorded once per target,
# content and view of their file (decl_source).
DECLARATION_KINDS = ('interface', 'protocol', 'category', 'extension')


def view_note(q, file, g):
    """For a declaration row (grouped, g) of file: the note that it was
    recorded in only some of the views of the file in a target, naming the
    units that recorded it; None when it is in every view."""
    by_target = {}
    for tu in g['tus']:
        by_target.setdefault(q.by_tu[tu].target, set()).add(tu)
    segments = []
    for target in sorted(by_target):
        claimers = set(tu for (tu,) in q.con.execute('SELECT DISTINCT tu FROM decl_source WHERE path = ? AND '
                                                     'target = ? AND via_module = 0', (file, target)))
        have = by_target[target] & claimers
        if len(claimers) > 1 and have and have != claimers:
            segments.append('%d of %d views of this file in %s (recorded by %s)' % (
                len(have), len(claimers), target, ', '.join(sorted(q.by_tu[t].file for t in have))))
    return 'in ' + '; '.join(segments) if segments else None


def methods(paths, selector, out=None):
    """Where selector is declared and defined, in every class, category and
    protocol, with synthesized and macro-generated methods."""
    out = out or sys.stdout
    q = QueryContext(paths, METHODS_SPEC)
    try:
        q.search_not_parsed(forms=search_forms_methods(selector), skip_definitions=False)
        writer = RowWriter(q, out)
        for key, g in group_rows(q.con.execute(METHOD_ROW_SQL, (selector,)).fetchall(), 19):
            (file, line, col, is_class, container, sel, kind, is_def, implicit, synth, optional, prop_usr,
             macro, mfile, mline, role, eline, ecol, migration) = key
            parts = ['%s:%d:%d' % (file, line, col), '%s[%s %s]' % ('+' if is_class else '-', container, sel),
                     method_description(kind, is_def, implicit, synth, optional, prop_usr)]
            if macro:
                parts.append(macro_text(macro, role, mfile, mline, eline, ecol))
            note = view_note(q, file, g) if kind in DECLARATION_KINDS else None
            if note:
                parts.append(note)
            writer.write(parts, g, migration, multiplicity=False)
        outside_text, outside_writer, inside_text, inside_writer = override_groups(
            q, selector, METHODS_INSIDE_OVERRIDES_NOTE % selector)
        if outside_writer.written:
            out.write(outside_text)
        if inside_writer.written:
            out.write(inside_text)
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


SELECTOR_REF_ROW_SQL = ('SELECT r.file, r.line, r.col, r.enclosing_name, r.selector, r.macro_name, r.macro_file, '
                        'r.macro_line, r.macro_role, r.expansion_line, r.expansion_col, r.in_block, '
                        'r.in_migration_scope, r.tu, t.target FROM selector_ref r JOIN tu t ON t.id = r.tu '
                        'WHERE r.selector = ? ORDER BY r.file, r.line, r.col')
REFLECTIVE_COLUMNS = ('c.file, c.line, c.col, c.enclosing_name, c.function_or_selector, c.argument_index, c.kind, '
                      'c.argument_kind, c.argument_text, c.argument_constant, c.resolved_class, c.receiver_type, '
                      'c.macro_name, c.macro_file, c.macro_line, c.macro_role, c.expansion_line, c.expansion_col, '
                      'c.in_block, c.in_migration_scope, c.tu, t.target')
REFLECTIVE_KEY_LEN = 20


def argument_description(name, index, kind, argument_kind, text, constant, resolved_class):
    if argument_kind in ('dynamic', 'nil', 'self-selector'):
        value = '%s %s' % (argument_kind, text or '?')
    elif argument_kind == 'selector-expr':
        value = 'selector-expr %s' % text
    else:
        value = '%s %s' % (argument_kind, json.dumps(text, ensure_ascii=False))
        if constant:
            value += ' (%s)' % constant
    out = '%s argument %d (%s): %s' % (name, index, kind, value)
    if resolved_class and kind not in ('class', 'protocol'):
        out += ', class %s' % resolved_class
    return out


def reflective_parts(key):
    """The parts of a reflective_call row (REFLECTIVE_COLUMNS, grouped)."""
    (file, line, col, enclosing, name, index, kind, argument_kind, text, constant, resolved_class, rtype,
     macro, mfile, mline, role, eline, ecol, in_block, migration) = key
    parts = ['%s:%d:%d' % (file, line, col), enclosing or '(file scope)',
             argument_description(name, index, kind, argument_kind, text, constant, resolved_class)]
    if rtype:
        parts.append('receiver %s' % rtype)
    if macro:
        parts.append(macro_text(macro, role, mfile, mline, eline, ecol))
    if in_block:
        parts.append('in block')
    return parts, migration


def write_selector_refs(q, writer, selector):
    """@selector expressions and reflective calls whose resolved selector is
    selector, in order of place."""
    rows = []
    for key, g in group_rows(q.con.execute(SELECTOR_REF_ROW_SQL, (selector,)).fetchall(), 13):
        (file, line, col, enclosing, sel, macro, mfile, mline, role, eline, ecol, in_block, migration) = key
        parts = ['%s:%d:%d' % (file, line, col), enclosing or '(file scope)', '@selector(%s)' % sel]
        if macro:
            parts.append(macro_text(macro, role, mfile, mline, eline, ecol))
        if in_block:
            parts.append('in block')
        rows.append(((file, line, col, 0), parts, g, migration))
    sql = ('SELECT %s FROM reflective_call c JOIN tu t ON t.id = c.tu WHERE c.resolved_selector = ? '
           'ORDER BY c.file, c.line, c.col, c.argument_index' % REFLECTIVE_COLUMNS)
    for key, g in group_rows(q.con.execute(sql, (selector,)).fetchall(), REFLECTIVE_KEY_LEN):
        parts, migration = reflective_parts(key)
        rows.append(((key[0], key[1], key[2], 1), parts, g, migration))
    rows.sort(key=lambda r: r[0])
    for _, parts, g, migration in rows:
        writer.write(parts, g, migration, multiplicity=False)


def selrefs(paths, selector, out=None):
    out = out or sys.stdout
    q = QueryContext(paths, SELREFS_SPEC)
    try:
        q.search_not_parsed(forms=search_forms_selrefs(selector))
        writer = RowWriter(q, out)
        write_selector_refs(q, writer, selector)
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


def reflective_table(paths):
    """The table of recognized reflective calls, as the extractor prints it,
    or a CodeDBError when the extractor is not built from these sources."""
    if binary_digest(paths.extractor) != extractor_source_digest():
        raise CodeDBError('the extractor at %s is not built from the current sources; run codedb.py update'
                          % paths.extractor)
    return subprocess.run([paths.extractor, '--reflective-table'], capture_output=True, text=True, check=True,
                          timeout=60).stdout


def reflective(paths, everything=False, kind=None, out=None):
    """Reflective call sites, grouped by file: by default those whose argument
    is dynamic, with everything every one; with kind, only those whose
    argument names that kind."""
    out = out or sys.stdout
    q = QueryContext(paths, REFLECTIVE_SPEC)
    try:
        where, args = [], []
        if not everything:
            where.append("c.argument_kind = 'dynamic'")
        if kind:
            where.append('c.kind = ?')
            args.append(kind)
        sql = ('SELECT %s FROM reflective_call c JOIN tu t ON t.id = c.tu %s '
               'ORDER BY c.file, c.line, c.col, c.argument_index' % (
                   REFLECTIVE_COLUMNS, ('WHERE ' + ' AND '.join(where)) if where else ''))
        groups = group_rows(q.con.execute(sql, args).fetchall(), REFLECTIVE_KEY_LEN)
        by_file = collections.OrderedDict()
        for key, g in groups:
            by_file.setdefault(key[0], []).append((key, g))
        writer = RowWriter(q, out, indent='  ')
        names = collections.Counter()
        for file, items in by_file.items():
            out.write('%s: %d\n' % (file, len(items)))
            for key, g in items:
                names[key[4]] += 1
                parts, migration = reflective_parts(key)
                writer.write(parts, g, migration, multiplicity=False)
        if names:
            out.write('by call: %s\n' % ', '.join('%s %d' % kv for kv in sorted(names.items(),
                                                                               key=lambda kv: (-kv[1], kv[0]))))
        if not everything and (names or kind is None):
            # Arguments that name nothing (nil) or the enclosing method's own
            # selector (_cmd) need no reading; they are counted, not listed.
            count_sql = ('SELECT count(*) FROM reflective_call c WHERE c.argument_kind = ?' +
                         (' AND c.kind = ?' if kind else ''))
            nil, cmd = [q.con.execute(count_sql, [k] + args).fetchone()[0] for k in ('nil', 'self-selector')]
            out.write('not listed: %d arguments that are nil, NULL or 0 (argument kind nil) and %d that %s _cmd '
                      '(argument kind self-selector); codedb.py reflective --all lists them\n' % (
                          nil, cmd, 'is' if cmd == 1 else 'are'))
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


OVERRIDE_ROW_SQL = ('SELECT m.file, m.line, m.col, m.is_class_method, m.container_name, m.selector, '
                    'o.overridden_container, o.overridden_container_kind, o.is_optional_requirement, '
                    'o.outside_repository, o.owner_parsed, o.overridden_file, o.overridden_line, o.overridden_class, '
                    'o.overridden_class_parsed, m.in_migration_scope, m.tu, t.target '
                    'FROM objc_method m JOIN objc_method_override o ON o.method = m.id JOIN tu t ON t.id = m.tu '
                    'WHERE m.selector = ? AND (m.is_definition = 1 OR m.is_synthesized_accessor = 1) '
                    'AND (o.outside_repository = 1 OR o.owner_parsed = 0) = ? '
                    'ORDER BY m.file, m.line, m.col, o.overridden_container')
OUTSIDE_CALLERS_HEADING = 'May be called by code outside this database'
INSIDE_OVERRIDES_HEADING = 'Methods in this repository that it overrides or protocol requirements it satisfies'
# The note on that group in reach, and in methods, which prints no sends.
INSIDE_OVERRIDES_NOTE = ('Objective-C sends to the class or protocol are among the message sends above; Swift callers '
                         'are not in this database')
METHODS_INSIDE_OVERRIDES_NOTE = 'run codedb.py reach %s for its senders'
# What reach prints when the only rows are in that group.
NO_OBJC_CALLER = ('No Objective-C caller found. This selector satisfies or overrides declarations in this repository '
                  '(listed above); callers written in Swift, or reaching it through a xib, are not in this database.')
# The same two texts when the Swift side is in the database.
INSIDE_OVERRIDES_NOTE_WITH_SWIFT = ('Objective-C sends to the class or protocol are among the message sends above, and '
                                    'Swift references among the Swift references above')
NO_CALLER_WITH_SWIFT = ('No Objective-C or Swift caller found. This selector satisfies or overrides declarations in '
                        'this repository (listed above); callers reaching it through a xib are not in this database.')
SWIFT_REFS_HEADING = 'Swift references to %s'
SWIFT_DECLS_HEADING = 'Swift declarations with the selector %s (definitions that a send of it can reach)'
SWIFT_SENDS_HEADING = ('Swift sends of %s (made from Swift; the compiler sends the message): calls, initializers, '
                       'dynamic lookups, property accesses that call this accessor (a read calls the getter, a '
                       'write the setter) and key path components, which may call either')


def override_description(is_class, selector, container, container_kind, optional, outside, owner_parsed, file, line,
                         sdk_dirs, cls=None, class_parsed=None):
    """What a definition overrides or satisfies, and where that is declared."""
    sign = '+' if is_class else '-'
    if container_kind == 'protocol':
        text = 'satisfies %s %s%s (%s)' % (container, sign, selector, 'optional' if optional else 'required')
    else:
        text = 'overrides %s %s%s' % (container, sign, selector)
    if not outside and owner_parsed:
        return text + ', declared at %s:%s' % (file, line)
    if not outside:
        # In the repository, but the code that owns it is not parsed (see
        # objc_method_override.owner_parsed).
        bundle = next((part for part in (file or '').split('/') if part.endswith('.framework')), None)
        if bundle:
            return text + ', declared in %s, whose code is not in this database' % bundle
        if (file or '').endswith('-Swift.h'):
            return text + ', declared by Swift code, which is not in this database (%s)' % os.path.basename(file)
        if class_parsed == 0:
            # A category or class extension on a class whose code is not in
            # this database. Its code calls the method only if it is its own:
            # a category may also add a method for this repository's use.
            what = 'class extension' if container_kind == 'extension' else 'category'
            return text + (', declared in this repository at %s:%s as a %s %s %s, a class whose code is not in this '
                           'database; code there calls it only if the selector is its own, as when the %s redeclares '
                           'a private method' % (file, line, what, 'of' if what == 'class extension' else 'on', cls,
                                                 what))
        return text + (', declared at %s:%s, in a header read only through a compiled module, whose code may not be '
                       'in this database' % (file, line))
    for d in sdk_dirs:
        if file and file.startswith(d):
            return text + ', declared in the SDK (%s)' % file[len(d):]
    return text + ', declared outside the repository in %s' % (file or '?')


def override_groups(q, selector, inside_note=INSIDE_OVERRIDES_NOTE):
    """The two groups of what the definitions of selector override: methods
    and protocol requirements declared in code that is not in this database
    (outside the repository, or in it but not parsed: code there may call
    them), and those declared in parsed code of the repository, whose caption
    ends with inside_note. Returns (text, writer) for each."""
    sdk_dirs = []
    for (p,) in q.con.execute('SELECT DISTINCT sdk_path FROM tu WHERE sdk_path IS NOT NULL'):
        for d in (p, os.path.realpath(p)):
            d = d.rstrip('/') + '/'
            if d not in sdk_dirs:
                sdk_dirs.append(d)
    result = []
    for outside in (1, 0):
        buf = io.StringIO()
        writer = RowWriter(q, buf, indent='  ')
        for key, g in group_rows(q.con.execute(OVERRIDE_ROW_SQL, (selector, outside)).fetchall(), 16):
            (file, line, col, is_class, container, sel, ocontainer, okind, optional, oout, oparsed, ofile, oline,
             ocls, ocls_parsed, migration) = key
            parts = ['%s:%d:%d' % (file, line, col), '%s[%s %s]' % ('+' if is_class else '-', container, sel),
                     override_description(is_class, sel, ocontainer, okind, optional, oout, oparsed, ofile, oline,
                                          sdk_dirs, ocls, ocls_parsed)]
            writer.write(parts, g, migration, multiplicity=False)
        if outside:
            heading = '%s: %d\n' % (OUTSIDE_CALLERS_HEADING, writer.written)
        else:
            heading = '%s: %d (%s)\n' % (INSIDE_OVERRIDES_HEADING, writer.written, inside_note)
        result += [heading + buf.getvalue(), writer]
    return tuple(result)


def reach_keys(q, selector):
    """The keys that reach selector through key-value coding: its shapes
    (kvc_keys) and the properties it is an accessor of."""
    keys = kvc_keys(selector)
    for (name,) in q.con.execute('SELECT DISTINCT name FROM objc_property WHERE getter_selector = ? OR '
                                 'setter_selector = ? ORDER BY name', (selector, selector)):
        if name not in keys:
            keys.append(name)
    return keys


def reach(paths, selector, out=None):
    """Every way selector is reached from the Objective-C in this database:
    its sends, its @selector expressions and reflective calls, and the key-value
    coding of the keys it is an accessor of."""
    out = out or sys.stdout
    q = QueryContext(paths, REACH_SPEC)
    try:
        keys = reach_keys(q, selector)
        forms = search_forms_sends(selector) + search_forms_selrefs(selector) + search_forms_keys(keys)
        q.search_not_parsed(forms=forms)
        q.search_forms_text = '\n'.join((TEXT_SEARCH_FORMS, SELREFS_SEARCH_FORMS, KEYS_SEARCH_FORMS))
        total = marked = outside = 0
        sections = []

        def section(title, fill):
            buf = io.StringIO()
            writer = RowWriter(q, buf, indent='  ')
            fill(writer)
            sections.append((title, writer, buf.getvalue()))
            return writer

        section('Message sends of %s' % selector, lambda w: write_send_rows(q, w, selector))
        section('@selector expressions and reflective calls resolving to %s' % selector,
                lambda w: write_selector_refs(q, w, selector))

        def write_keys(w):
            if not keys:
                return
            placeholders = ','.join('?' * len(keys))
            sql = ("SELECT %s FROM reflective_call c JOIN tu t ON t.id = c.tu WHERE c.argument_kind IN "
                   "('selector-expr', 'string-literal', 'constant') "
                   "AND c.kind IN ('key', 'key-path', 'predicate-format') AND (c.argument_text IN (%s) OR "
                   "c.kind != 'key') ORDER BY c.file, c.line, c.col, c.argument_index" % (REFLECTIVE_COLUMNS,
                                                                                          placeholders))
            rows = [r for r in q.con.execute(sql, keys).fetchall() if key_matches(r[6], r[8], keys)]
            for key, g in group_rows(rows, REFLECTIVE_KEY_LEN):
                parts, migration = reflective_parts(key)
                w.write(parts, g, migration, multiplicity=False)

        section('Key-value coding and key paths naming %s' % (', '.join(keys) if keys else 'no key: %s is not an '
                                                              'accessor of a property or a key-value coding shape'
                                                              % selector), write_keys)
        for title, writer, text in sections:
            out.write('%s: %d\n' % (title, writer.written))
            out.write(text)
            total += writer.written
            marked += writer.marked
            outside += writer.outside
        # The Swift references and declarations, when the Swift side is in
        # the database.
        for w in (write_swift_refs(q, out, selector), write_swift_decls(q, out, selector)):
            if w is not None:
                total += w.written
                marked += w.marked
                outside += w.outside
        if q.swift_states is not None and swiftdb.has_swift_tables(q.con):
            swiftdb.write_protocol_witnesses(q.con, selector, out)
            swiftdb.write_inactive_search(q.con, paths.root, selector, out)
        with_swift = q.swift_states is not None
        # Methods declared in code that is not in this database that the
        # definitions override count as rows; those declared in parsed code
        # of the repository are reached through the sends above.
        outside_text, outside_writer, inside_text, inside_writer = override_groups(
            q, selector, inside_note=INSIDE_OVERRIDES_NOTE_WITH_SWIFT if with_swift else INSIDE_OVERRIDES_NOTE)
        out.write(outside_text)
        out.write(inside_text)
        total += outside_writer.written
        marked += outside_writer.marked
        outside += outside_writer.outside
        if not total and inside_writer.written:
            out.write((NO_CALLER_WITH_SWIFT if with_swift else NO_OBJC_CALLER) + '\n')

        # Every reflective call whose argument is dynamic, by kind.
        dynamic = dict(q.con.execute("SELECT kind, count(*) FROM reflective_call WHERE argument_kind = 'dynamic' "
                                     "GROUP BY kind").fetchall())
        kinds = sorted(dynamic, key=lambda k: (REFLECTIVE_KINDS.index(k) if k in REFLECTIVE_KINDS
                                               else len(REFLECTIVE_KINDS), k))
        out.write('Not covered by reach:\n')
        out.write('  - %d reflective calls whose argument is not a literal%s can reach any selector, class or key: '
                  'codedb.py reflective lists them\n' % (
                      sum(dynamic.values()),
                      ' (%s)' % ', '.join('%d %s' % (dynamic[k], k) for k in kinds) if kinds else ''))
        for item in REACH_NOT_COVERED + [FRAMEWORK_CALLERS_NOT_COVERED]:
            if item == REACH_SWIFT_NOT_COVERED and with_swift:
                for swift_item in REACH_SWIFT_NOT_COVERED_WITH_SWIFT:
                    out.write('  - %s\n' % swift_item)
                continue
            if with_swift:
                item = item.replace('(prebuilt frameworks in the repository, Swift)',
                                    '(prebuilt frameworks in the repository)')
            out.write('  - %s\n' % item)
        skipped_search_incomplete(q, write_skipped_search(q, out, [selector.split(':')[0]], 'references'), total)
        q.write_status(out, total, marked, outside)
        return q.exit_status(total)
    finally:
        q.close()


LOCK_FD = 9


# --- State: ivars and statics -------------------------------------------------

STATE_NOT_IN_DATABASE = NOT_IN_DATABASE_COMMON + [
    'Swift: Swift imports no Objective-C ivar (docs/swift-migration/objc-state.md section 1), and the Swift tables '
    'hold no reference to one; Swift reaches this state only through properties and methods (counted as Swift '
    'property references where an ivar backs a property). Swift references to C globals and statics are not '
    'recorded either (the Swift tables hold only references to Objective-C declarations)',
    'ivars reached by name at run time: key-value coding with an ivar name (valueForKey: when '
    'accessInstanceVariablesDirectly), object_getIvar, object_setIvar, ivar_getOffset, class_copyIvarList, @defs; '
    'codedb.py reflective lists the recognized reflective calls',
    'accesses through a pointer taken earlier (int *p = &_x; *p = 1 is one address-taken reference) and through '
    'aliases',
    'ivars of classes declared outside the repository (the SDK), and references to them',
    'C++ member function calls and operator calls on a C++ ivar or static other than assignment and ++/--: '
    'they are counted as reads',
    'ownership qualifiers written in a unit compiled with manual reference counting other than __weak: the '
    'compiler drops __strong, __unsafe_unretained and __autoreleasing from the type there, so they are not '
    'recorded as written (the retain hint of an ivar of such a class is a hint from its sends, not proof)',
    'locks other than @synchronized: lock and unlock function or method pairs (os_unfair_lock_lock, '
    'pthread_mutex_lock, [NSLock lock]) are not recognized, so a reference they guard has no lock; a reference in a '
    'block inside a @synchronized body is recorded under its lock although the block can run later',
    'references in the argument of __builtin_object_size (which does not evaluate it; the SDK\'s fortified '
    'memcpy, memmove and memset pass their destination to it a second time)',
]
STATE_ACCESS_ORDER = ('read', 'write', 'rmw', 'address', 'byref', 'synchronized', 'once-token', 'unevaluated')
# Accesses that can change the value: a write, a read-modify-write, an
# address taken or passed by reference.
STATE_WRITES = ('write', 'rmw', 'address', 'byref')
IVARS_SEARCH_FORMS = ('  searched: @interface or @implementation of the class, and the class in a category '
                      '(@interface CLASS ( or @implementation CLASS (); not searched: classes declared by macros')
REFS_SEARCH_FORMS = '  searched: the name as a whole word; not searched: names built by macros (token pasting)'
IVARS_SPEC = QuerySpec('ivars', STATE_NOT_IN_DATABASE, exit_text('ivars printed', True, True), IVARS_SEARCH_FORMS,
                       True)
IVARREFS_SPEC = QuerySpec('ivarrefs', STATE_NOT_IN_DATABASE, exit_text('references printed', True, True),
                          REFS_SEARCH_FORMS, True)
STATICS_SPEC = QuerySpec('statics', STATE_NOT_IN_DATABASE, exit_text('statics printed', True, False), None, True)
STATICREFS_SPEC = QuerySpec('staticrefs', STATE_NOT_IN_DATABASE,
                            exit_text('declarations or references printed', True, True), REFS_SEARCH_FORMS, True)
MODE_NAMES = {1: 'ARC', 0: 'manual reference counting'}
BASE_TEXT = {'implicit-self': 'implicit self', 'self': 'self', 'weak-strong-local': 'weak-strong local',
             'local': 'local', 'parameter': 'parameter', 'other': 'other object'}


def search_forms_word(name, label):
    return [(name, label, re.compile(r'(?<![A-Za-z0-9_$])%s(?![A-Za-z0-9_$])' % re.escape(name)))]


def search_forms_class(cls):
    return [(cls, 'class ' + cls, re.compile(r'@(?:interface|implementation)\s+%s\b' % re.escape(cls)))]


def access_breakdown(counter):
    """'read 2, write 1' in STATE_ACCESS_ORDER, without zeros."""
    return ', '.join('%s %d' % (a, counter[a]) for a in STATE_ACCESS_ORDER if counter[a])


def class_description(type_class, object_class, protocols, record, has_objects, bit_width):
    if type_class == 'object':
        return 'object %s%s' % (object_class or '?', '<%s>' % protocols if protocols else '')
    if type_class == 'bit-field':
        return 'bit-field width %s' % bit_width
    if type_class in ('struct', 'union', 'cxx-object'):
        text = '%s %s' % ('C++ object' if type_class == 'cxx-object' else type_class, record or '(anonymous)')
        return text + (', holds objects' if has_objects else '')
    return type_class


def views_description(views, retainable_only=False, gov=None):
    """The type and ownership of a declaration, from its rows (one per unit
    that recorded it): {(arc, type, ownership, class description):
    [main files]}. When every row agrees but for the ARC mode's own
    spelling, one description. Otherwise, with gov (governing_modes) for an
    ivar: the row of the mode the class's own @implementation is compiled
    with is the ownership, and the other mode's row is how units of that mode
    see the header; a class implemented in both modes shows both as
    governing. Without gov, or when no @implementation of the class is in
    the database, a CONFLICT naming each row."""
    combos = sorted(views)
    kinds = set((t, o) for _, t, o, _ in combos)
    modes = sorted(set(a for a, _, _, _ in combos), reverse=True)
    mode_text = ' and '.join(MODE_NAMES[m] for m in modes)
    if len(kinds) == 1:
        _, t, o, cdesc = combos[0]
        if retainable_only and o == 'none':
            return '%s, %s' % (t, cdesc)
        return '%s, %s, %s (%s)' % (t, cdesc, o, mode_text)

    def row_text(c):
        a, t, o, cdesc = c
        return '%s: %s, %s (recorded by %s)' % (MODE_NAMES[a], t, o, ', '.join(sorted(set(views[c]))))

    ordered = [c for arc in modes for c in combos if c[0] == arc]
    if gov is None or not gov['modes']:
        prefix = 'CONFLICT: units disagree: '
        if gov is not None:
            prefix += '%s, so which row governs is not known: ' % gov['text']
        return prefix + '; '.join(row_text(c) for c in ordered)
    if len(gov['modes']) == 2:
        return 'CONFLICT: %s: %s' % (gov['text'], '; '.join(row_text(c) for c in ordered))
    (mode,) = gov['modes']
    governing = [c for c in combos if c[0] == mode]
    others = [c for c in ordered if c[0] != mode]
    if len(governing) != 1:
        return 'CONFLICT: %s, which governs: %s' % (gov['text'], '; '.join(row_text(c) for c in ordered))
    _, t, o, cdesc = governing[0]
    head = '%s, %s, %s (%s, the class\'s own code)' % (t, cdesc, o, MODE_NAMES[mode])
    if not others:
        return head
    return head + '  CONFLICT: %s, which governs; as seen by units of the other mode (not the class\'s own code): ' \
                  '%s' % (gov['text'], '; '.join(row_text(c) for c in others))


def governing_modes(q, cls):
    """Where CLASS's @implementation and category @implementations are, and
    the ARC mode of the units that compile them: {'impls': [(file, category,
    arc)], 'modes': set of arc, 'text': the sentence, 'mrc_mains': main
    files of the units that compile one without ARC}."""
    rows = q.con.execute('SELECT DISTINCT i.file, i.category, i.arc, t.main_file FROM objc_impl i JOIN tu t ON '
                         't.id = i.tu WHERE i.class_name = ? ORDER BY i.file, i.category, i.arc DESC',
                         (cls,)).fetchall()
    impls = sorted(set((f, c, a) for f, c, a, _ in rows), key=lambda r: (r[0], r[1] or '', -r[2]))
    modes = set(a for _, _, a in impls)
    if not impls:
        text = 'no @implementation of %s is in this database' % cls
    elif len(modes) == 1:
        text = '%s is implemented in %s, compiled with %s' % (
            cls, ', '.join(f + (' (category %s)' % c if c else '') for f, c, _ in impls), MODE_NAMES[impls[0][2]])
    else:
        text = '%s is implemented in both modes: %s; each governs the references in its own file' % (
            cls, ', '.join('%s (%s%s)' % (f, 'category %s, ' % c if c else '', MODE_NAMES[a]) for f, c, a in impls))
    return {'impls': impls, 'modes': modes, 'text': text, 'mrc_mains': set(m for _, _, a, m in rows if not a)}


MRC_NOTE = ('note: manual reference counting: the compiler drops __strong, __unsafe_unretained and __autoreleasing '
            'from the types there, so an ivar written __unsafe_unretained cannot be told from one retained by hand; '
            'the retain hint of each object ivar comes from the class\'s own code compiled that way')
STATE_LIMITS_LINE = ('limits: accesses through a pointer or reference taken earlier (int *p = &_x; *p = 1) and other '
                     'aliases are not followed; C++ member function calls on a C++ ivar or static count as reads; '
                     'lock and unlock function pairs (os_unfair_lock_lock, pthread_mutex_lock, [NSLock lock]) are not '
                     'recognized, only @synchronized bodies are; an array or address passed as a pointer to non-const '
                     'counts as a possible write (byref)')
STATE_SWIFT_LINE_STATICS = ('Swift: references from Swift to C globals and statics are not in this database (the Swift '
                            'tables record only references to Objective-C declarations); a static declared in a .m '
                            'file is invisible to Swift')
HINT_ORDER = (('assigned-owned', 'assigned an owned result'), ('retain', 'retain'), ('copy', 'copy'),
              ('release', 'release'), ('autorelease', 'autorelease'))


def group_by_tu(rows, key, tu_index, target_index):
    """{key(row): {'tus': {tu: count}, 'targets': set}} in first-seen order."""
    groups = collections.OrderedDict()
    for r in rows:
        k = key(r)
        g = groups.setdefault(k, {'tus': {}, 'targets': set(), 'rows': []})
        g['tus'][r[tu_index]] = g['tus'].get(r[tu_index], 0) + 1
        g['targets'].add(r[target_index])
        g['rows'].append(r)
    return groups


def multiplicity(g):
    return max(g['tus'].values())


IVAR_DECL_SQL = ('SELECT i.name, i.file, i.line, i.col, i.container_kind, i.access, i.type, i.type_class, '
                 'i.object_class, i.object_protocols, i.record_name, i.record_has_objects, i.bit_width, i.ownership, '
                 'i.arc, i.is_iboutlet, i.synthesized_by, i.property_name, i.macro_name, i.macro_file, i.macro_line, '
                 'i.macro_role, i.expansion_line, i.expansion_col, i.in_migration_scope, i.usr, t.main_file, i.tu, '
                 't.target FROM objc_ivar i JOIN tu t ON t.id = i.tu WHERE i.class_name = ? %s '
                 'ORDER BY i.file, i.line, i.col, i.name, i.arc DESC')
IVAR_REF_SQL = ('SELECT r.ivar_name, r.file, r.line, r.col, r.enclosing_name, r.enclosing_class, r.kind, r.access, '
                'r.partial, r.base_kind, r.in_block, r.in_once_block, r.macro_name, r.macro_file, r.macro_line, '
                'r.macro_role, r.expansion_line, r.expansion_col, r.in_migration_scope, r.in_lambda, r.retain_hint, '
                'r.sync_lock, t.main_file, r.ivar_class, r.tu, t.target FROM ivar_ref r JOIN tu t ON t.id = r.tu '
                'WHERE %s ORDER BY r.file, r.line, r.col, r.enclosing_name')
REF_KEY = slice(0, 22)
R_LAMBDA, R_HINT, R_LOCK, R_MAIN, R_CLASS = 19, 20, 21, 22, 23


def ivar_line(q, writer, name, g, gov=None):
    """Writes the line of one ivar (its rows grouped across units). Returns
    the names of the properties it backs and their attributes."""
    first = g['rows'][0]
    (_, file, line, col, container, access, _, _, _, _, _, _, _, _, _, outlet, synth, prop, macro, mfile, mline,
     role, eline, ecol, migration) = first[:25]
    views = {}
    for r in g['rows']:
        cdesc = class_description(r[7], r[8], r[9], r[10], r[11], r[12])
        views.setdefault((r[14], r[6], r[13], cdesc), []).append(r[26])
    parts = ['%s  %s:%d:%d' % (name, file, line, col), '%s, %s' % (container, access), views_description(views, gov=gov)]
    backing = q.con.execute("SELECT name, attributes, is_implicit FROM objc_property WHERE kind = 'synthesize' AND "
                            "class_name = ? AND ivar_name = ? ORDER BY name", (q.state_class, name)).fetchall()
    for pname, attrs, implicit in sorted(set(backing)):
        if synth:
            parts.append('synthesized %s for property %s (%s)' % (
                'automatically' if synth == 'automatic' else 'by @synthesize', pname, attrs))
        else:
            parts.append('backs property %s (%s) %s' % (pname, attrs, 'synthesized automatically' if implicit
                                                        else 'by @synthesize'))
    if synth and not backing:
        parts.append('synthesized %s for property %s' % ('automatically' if synth == 'automatic' else
                                                         'by @synthesize', prop))
    if outlet:
        parts.append('IBOutlet')
    if macro:
        parts.append(macro_text(macro, role, mfile, mline, eline, ecol))
    writer.write(parts, g, migration, multiplicity=False)
    return [(p, a) for p, a, _ in sorted(set(backing))]


def ivar_ref_summary(refs, cls, impl_mains):
    """The counts line and the by-method line of one ivar's references,
    grouped by location (refs: group_by_tu groups)."""
    total = collections.Counter()
    by_method = collections.OrderedDict()
    n = direct = synthesized = in_block = self_strong = weak_strong = other_objects = other_classes = 0
    functions = other_files = 0
    for key, g in refs.items():
        r = g['rows'][0]
        k = multiplicity(g)
        enclosing, enclosing_class, kind, access, base, block = r[4], r[5], r[6], r[7], r[9], r[10]
        n += k
        total[access] += k
        if kind == 'direct':
            direct += k
        else:
            synthesized += k
        if block:
            in_block += k
            if base in ('implicit-self', 'self'):
                self_strong += k
            elif base == 'weak-strong-local':
                weak_strong += k
        if base in ('parameter', 'local', 'other'):
            other_objects += k
        if enclosing_class is None:
            functions += k
        elif enclosing_class != cls:
            other_classes += k
        if r[R_MAIN] not in impl_mains:
            other_files += k
        by_method.setdefault(enclosing or '(file scope)', collections.Counter())[access] += k
    text = '    references %d' % n
    if n:
        text += ': %s; direct %d, synthesized accessor %d; in blocks %d%s; from other objects %d; from other ' \
                'classes %d; from other files %d' % (
                    access_breakdown(total), direct, synthesized, in_block,
                    ' (capture self strongly %d, through a weak-strong local %d)' % (self_strong, weak_strong)
                    if in_block else '', other_objects, other_classes, other_files)
        if functions:
            text += '; from C functions %d' % functions
    lines = [text]
    if by_method:
        ordered = sorted(by_method.items(), key=lambda kv: (-sum(kv[1].values()), kv[0]))
        lines.append('    by method: ' + '; '.join('%s %d (%s)' % (m, sum(c.values()), access_breakdown(c))
                                                  for m, c in ordered))
    return lines


def lock_name(q, desc, cls):
    """How a sync_lock value reads: the ivar's name (with its class when it
    is not cls), the static's name, self, class NAME, or the source text."""
    kind, _, rest = desc.partition(' ')
    if kind == 'ivar':
        row = q.con.execute('SELECT class_name, name FROM objc_ivar WHERE usr = ? LIMIT 1', (rest,)).fetchone()
        if row:
            return row[1] if row[0] == cls else '%s.%s' % row
        return rest
    if kind == 'static':
        row = q.con.execute('SELECT name FROM c_static WHERE usr = ? LIMIT 1', (rest,)).fetchone()
        return row[0] if row else rest
    if kind == 'other':
        return rest
    return desc


def retain_hint_line(refs, cls, gov, backing):
    """The retain hint of an object ivar of a class compiled with manual
    reference counting: from its references in that code (refs:
    group_by_tu groups) and the synthesized setter of a retain or copy
    property it backs."""
    counts = collections.Counter()
    for g in refs.values():
        r = g['rows'][0]
        if r[R_HINT] and r[5] == cls and r[R_MAIN] in gov['mrc_mains']:
            counts[r[R_HINT]] += multiplicity(g)
    parts = []
    n = sum(counts.values())
    if n:
        parts.append('retained or released by hand in %d place%s (%s)' % (
            n, '' if n == 1 else 's', ', '.join('%s %d' % (label, counts[h]) for h, label in HINT_ORDER if counts[h])))
    for pname, attrs in backing:
        if set((attrs or '').split(',')) & {'retain', 'copy', 'strong'}:
            parts.append('retained by the synthesized setter of property %s (%s)' % (pname, attrs))
    if not parts:
        parts.append('never retained or released in this class (effectively an unretained reference)')
    return '    retain hint (a hint, not proof): ' + '; '.join(parts)


def sync_lines(q, refs, cls, usr, lock_users):
    """For one ivar: how many of its references are inside a @synchronized
    body and on which locks; for a lock ivar, the ivars accessed under it."""
    lines = []
    locks = collections.OrderedDict()
    inside = blocks = n = 0
    for g in refs.values():
        r = g['rows'][0]
        k = multiplicity(g)
        n += k
        if r[R_LOCK]:
            inside += k
            locks[r[R_LOCK]] = locks.get(r[R_LOCK], 0) + k
            if r[10]:
                blocks += k
    if inside:
        lines.append('    inside @synchronized bodies: %d of %d references (on %s%s)' % (
            inside, n, ', '.join('%s %d' % (lock_name(q, d, cls), c) for d, c in locks.items()),
            '; %d of them in a block, which can run after the lock is released' % blocks if blocks else ''))
    users = lock_users.get('ivar ' + (usr or ''))
    if users:
        lines.append('    used as the lock of @synchronized bodies that access: %s' % ', '.join(
            '%s %d' % (name, c) for name, c in users.items()))
    return lines


def accessor_sends_line(q, cls, prop):
    """Sends of the accessors of a backed property, and Swift references to
    it."""
    usrs = q.con.execute("SELECT DISTINCT usr FROM objc_property WHERE class_name = ? AND name = ?",
                         (cls, prop)).fetchall()
    parts = []
    for (pusr,) in usrs:
        for sel, n in q.con.execute(
                'SELECT m.selector, count(DISTINCT s.file || ":" || s.line || ":" || s.col) FROM objc_method m '
                'JOIN send s ON s.target_usr = m.usr WHERE m.property_usr = ? GROUP BY m.selector ORDER BY 1',
                (pusr,)).fetchall():
            parts.append('%s %d' % (sel, n))
        swift = 0
        if q.swift_states is not None and swiftdb.has_swift_tables(q.con):
            swift = q.con.execute("SELECT count(DISTINCT file || ':' || line || ':' || col) FROM swift_ref WHERE "
                                  "kind = 'property' AND usr = ?", (pusr,)).fetchone()[0]
        swift_text = '%d' % swift if q.swift_states is not None else 'not in this database'
        return ('    property %s: Objective-C sends to its accessors: %s (codedb.py sends); Swift property '
                'references: %s' % (prop, ', '.join(parts) or 'none', swift_text))
    return None


def ivars(paths, cls, out=None):
    """The ivar table of one class: each ivar with its type, ownership,
    backing property and the counts of its references."""
    out = out or sys.stdout
    q = QueryContext(paths, IVARS_SPEC)
    q.state_class = cls
    try:
        q.search_not_parsed(forms=search_forms_class(cls), skip_definitions=False)
        q.search_forms_text = IVARS_SEARCH_FORMS
        gov = governing_modes(q, cls)
        decls = group_by_tu(q.con.execute(IVAR_DECL_SQL % '', (cls,)).fetchall(),
                            lambda r: (r[0], r[1], r[2], r[3]), -2, -1)
        refs = q.con.execute(IVAR_REF_SQL % 'r.ivar_class = ?', (cls,)).fetchall()
        by_ivar = collections.defaultdict(list)
        for r in refs:
            by_ivar[r[0]].append(r)
        # The ivars accessed under each lock, from the references in the
        # methods of this class and of others.
        lock_users = collections.defaultdict(collections.OrderedDict)
        lock_usrs = set(u for (u,) in q.con.execute('SELECT DISTINCT usr FROM objc_ivar WHERE class_name = ?', (cls,)))
        for key, g in group_by_tu(q.con.execute(IVAR_REF_SQL % "r.sync_lock LIKE 'ivar %'").fetchall(),
                                  lambda r: r[REF_KEY], -2, -1).items():
            r = g['rows'][0]
            if r[R_LOCK][5:] not in lock_usrs:
                continue
            name = r[0] if r[R_CLASS] == cls else '%s.%s' % (r[R_CLASS], r[0])
            users = lock_users[r[R_LOCK]]
            users[name] = users.get(name, 0) + multiplicity(g)
        impl_mains = set(m for (m,) in q.con.execute(
            "SELECT DISTINCT t.main_file FROM objc_method m JOIN tu t ON t.id = m.tu WHERE m.class_name = ? AND "
            "m.container_kind = 'implementation'", (cls,)))
        buf = io.StringIO()
        writer = RowWriter(q, buf)
        for (name, _, _, _), g in decls.items():
            backing = ivar_line(q, writer, name, g, gov)
            grouped = group_by_tu(by_ivar.get(name, []), lambda r: r[REF_KEY], -2, -1)
            for line in ivar_ref_summary(grouped, cls, impl_mains):
                buf.write(line + '\n')
            first = g['rows'][0]
            if 0 in gov['modes'] and first[7] in ('object', 'block') and first[8] != 'Class':
                buf.write(retain_hint_line(grouped, cls, gov, backing) + '\n')
            for line in sync_lines(q, grouped, cls, first[25], lock_users):
                buf.write(line + '\n')
            for prop, _ in backing:
                line = accessor_sends_line(q, cls, prop)
                if line:
                    buf.write(line + '\n')
        out.write('Ivars of %s: %d\n' % (cls, writer.written))
        out.write(gov['text'] + '\n')
        if 0 in gov['modes']:
            out.write(MRC_NOTE + '\n')
        out.write(buf.getvalue())
        foreign = q.con.execute(IVAR_REF_SQL % "r.enclosing_class = ? AND r.ivar_class != ? AND r.kind = 'direct'",
                                (cls, cls)).fetchall()
        by_method = collections.OrderedDict()
        for key, g in group_by_tu(foreign, lambda r: r[REF_KEY], -2, -1).items():
            r = g['rows'][0]
            by_method.setdefault(r[4], collections.OrderedDict()).setdefault(
                '%s.%s' % (r[R_CLASS], r[0]), collections.Counter())[r[7]] += multiplicity(g)
        out.write('Methods of %s that reach ivars of other classes directly: %d\n' % (cls, len(by_method)))
        for method in sorted(by_method):
            out.write('  %s: %s\n' % (method, '; '.join('%s (%s)' % (iv, access_breakdown(c))
                                                       for iv, c in by_method[method].items())))
        out.write(STATE_LIMITS_LINE + '\n')
        names = [cls] + [n for (n,) in q.con.execute('SELECT DISTINCT name FROM objc_ivar WHERE class_name = ? '
                                                     'ORDER BY name', (cls,))]
        skipped_search_incomplete(q, write_skipped_search(q, out, names, 'declarations of or references to the '
                                                                         'class or its ivars'), writer.written)
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


def ivar_ref_parts(q, r, ivar_class=None):
    (_, file, line, col, enclosing, enclosing_class, kind, access, partial, base, block, once, macro, mfile, mline,
     role, eline, ecol) = r[:18]
    parts = ['%s:%d:%d' % (file, line, col), enclosing or '(file scope)', access + (' (part)' if partial else '')]
    if kind == 'direct':
        parts.append('base ' + BASE_TEXT.get(base, base))
    else:
        parts.append(kind.replace('-', ' '))
    if block:
        parts.append('in block (captures self strongly)' if base in ('implicit-self', 'self') else 'in block')
    if once:
        parts.append('in dispatch_once block')
    if r[R_LAMBDA]:
        parts.append('in lambda (%s)' % r[R_LAMBDA])
    if r[R_HINT]:
        parts.append('assigned an owned result' if r[R_HINT] == 'assigned-owned' else 'receives ' + r[R_HINT])
    if r[R_LOCK]:
        parts.append('under @synchronized (%s)' % lock_name(q, r[R_LOCK], ivar_class))
    if macro:
        parts.append(macro_text(macro, role, mfile, mline, eline, ecol))
    if ivar_class and enclosing_class and enclosing_class != ivar_class:
        parts.append('from class %s' % enclosing_class)
    return parts


def ivarrefs(paths, cls, name, out=None):
    """Every reference to one ivar."""
    out = out or sys.stdout
    q = QueryContext(paths, IVARREFS_SPEC)
    q.state_class = cls
    try:
        q.search_not_parsed(forms=search_forms_word(name, 'ivar ' + name))
        q.search_forms_text = REFS_SEARCH_FORMS
        gov = governing_modes(q, cls)
        decls = group_by_tu(q.con.execute(IVAR_DECL_SQL % 'AND i.name = ?', (cls, name)).fetchall(),
                            lambda r: (r[0], r[1], r[2], r[3]), -2, -1)
        decl_buf = io.StringIO()
        decl_writer = RowWriter(q, decl_buf, indent='  ')
        for (n, _, _, _), g in decls.items():
            ivar_line(q, decl_writer, n, g, gov)
        out.write('Ivar %s.%s: %d declaration%s\n' % (cls, name, decl_writer.written,
                                                       '' if decl_writer.written == 1 else 's'))
        out.write(gov['text'] + '\n')
        out.write(decl_buf.getvalue())
        refs = q.con.execute(IVAR_REF_SQL % 'r.ivar_class = ? AND r.ivar_name = ?', (cls, name)).fetchall()
        buf = io.StringIO()
        writer = RowWriter(q, buf)
        for key, g in group_by_tu(refs, lambda r: r[REF_KEY], -2, -1).items():
            parts = ivar_ref_parts(q, g['rows'][0], cls)
            if multiplicity(g) > 1:
                parts.append('%d references at this location' % multiplicity(g))
            writer.write(parts, g, g['rows'][0][18], multiplicity=False)
        out.write('References: %d\n' % writer.written)
        out.write(buf.getvalue())
        for (prop,) in q.con.execute("SELECT DISTINCT name FROM objc_property WHERE kind = 'synthesize' AND "
                                     "class_name = ? AND ivar_name = ?", (cls, name)).fetchall():
            line = accessor_sends_line(q, cls, prop)
            if line:
                out.write(line.strip() + '\n')
        out.write(STATE_LIMITS_LINE + '\n')
        total = writer.written + decl_writer.written
        q.write_status(out, total, writer.marked + decl_writer.marked, writer.outside + decl_writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


STATIC_DECL_SQL = ('SELECT s.usr, s.name, s.kind, s.enclosing_name, s.file, s.line, s.col, s.type, s.type_class, '
                   's.object_class, s.object_protocols, s.record_name, s.record_has_objects, s.ownership, s.arc, '
                   's.is_const, s.pointee_const, s.init_kind, s.thread_local, s.macro_name, s.macro_file, '
                   's.macro_line, s.macro_role, s.expansion_line, s.expansion_col, s.in_migration_scope, t.main_file, '
                   's.tu, t.target FROM c_static s JOIN tu t ON t.id = s.tu WHERE s.usr = ? %s '
                   'ORDER BY s.kind = \'extern\', s.file, s.line, s.col, s.arc DESC')
STATIC_REF_SQL = ('SELECT r.var_usr, r.file, r.line, r.col, r.enclosing_name, r.access, r.partial, r.in_block, '
                  'r.in_once_block, r.macro_name, r.macro_file, r.macro_line, r.macro_role, r.expansion_line, '
                  'r.expansion_col, r.enclosing_class, r.in_lambda, r.in_migration_scope, r.tu, t.target '
                  'FROM static_ref r JOIN tu t ON t.id = r.tu WHERE r.var_usr = ? %s ORDER BY r.file, r.line, r.col')
STATIC_REF_KEY = slice(0, 17)
SOURCE_EXTENSIONS = C_FAMILY_EXTENSIONS + ('.h', '.hh', '.hpp', '.pch', '.def', '.inc')


def static_write_text(refs):
    """How a static is written, from its references (group_by_tu groups).
    An address taken or a by-reference use (an array passed as a pointer to
    non-const included) counts as a possible write."""
    writes = [g['rows'][0] for g in refs.values() if g['rows'][0][5] in STATE_WRITES]
    if not writes:
        return 'no write, address-of or by-reference use recorded after its initialization'
    if all(r[8] for r in writes):
        return 'every write, address-of or by-reference use recorded is in a dispatch_once block'
    functions = set(r[4] or '(file scope)' for r in writes)
    return 'written (counting address-of and by-reference uses) from %d function%s' % (
        len(functions), '' if len(functions) == 1 else 's')


def static_lines(q, writer, usr, refs, out_refs=None, target=None, defining_targets=(), per_unit=False):
    """Writes the declaration of one static (its rows grouped across units),
    its other declarations, and its references per function, or each
    reference to out_refs (a RowWriter) when given. target: only the rows of
    that target (a global defined in several targets, defining_targets).
    per_unit: also the references of each unit. Returns False when the
    database has no declaration of it."""
    where, args = ('AND t.target = ?', (usr, target)) if target else ('', (usr,))
    rows = q.con.execute(STATIC_DECL_SQL % where, args).fetchall()
    if not rows:
        return False
    decls = group_by_tu(rows, lambda r: (r[2], r[4], r[5], r[6]), -2, -1)
    (kind, file, line, col), g = next(iter(decls.items()))
    first = g['rows'][0]
    views = {}
    for r in g['rows']:
        cdesc = class_description(r[8], r[9], r[10], r[11], r[12], None)
        views.setdefault((r[14], r[7], r[13], cdesc), []).append(r[26])
    parts = ['%s  %s:%d:%d' % (first[1], file, line, col),
             kind + (' in %s' % first[3] if first[3] else ''), views_description(views, retainable_only=True)]
    const, pointee = first[15], first[16]
    if const:
        parts.append('const' + {1: ', pointee const', 0: ', pointee not const'}.get(pointee, ''))
    elif pointee == 1:
        parts.append('pointee const')
    parts.append('initializer %s' % first[17])
    if first[18]:
        parts.append('thread-local')
    if kind in ('file-static', 'local-static') and not file.endswith(C_FAMILY_EXTENSIONS):
        n = q.con.execute('SELECT count(DISTINCT tu) FROM tu_input WHERE path = ?', (file,)).fetchone()[0]
        parts.append('defined in a header: each including unit has its own copy; %d unit%s include%s it' % (
            n, '' if n == 1 else 's', 's' if n == 1 else ''))
    if target:
        parts.append('in target %s (%d targets define %s: each has its own)' % (target, len(defining_targets),
                                                                                first[1]))
    if kind != 'extern':
        parts.append(static_write_text(refs))
    if first[19]:
        parts.append(macro_text(first[19], first[22], first[20], first[21], first[23], first[24]))
    writer.write(parts, g, first[25], multiplicity=False)
    for (k, f, l, c), _ in list(decls.items())[1:]:
        writer.out.write('%s    also declared: %s at %s:%d:%d\n' % (writer.indent, k, f, l, c))
    if out_refs is None:
        by_function = collections.OrderedDict()
        for key, rg in refs.items():
            r = rg['rows'][0]
            by_function.setdefault(r[4] or '(file scope)', collections.Counter())[r[5]] += multiplicity(rg)
        for function in sorted(by_function):
            writer.out.write('%s    %s: %s\n' % (writer.indent, function, access_breakdown(by_function[function])))
    else:
        for key, rg in refs.items():
            r = rg['rows'][0]
            p = ['%s:%d:%d' % (r[1], r[2], r[3]), r[4] or '(file scope)', r[5] + (' (part)' if r[6] else '')]
            if r[7]:
                p.append('in block')
            if r[8]:
                p.append('in dispatch_once block')
            if r[16]:
                p.append('in lambda (%s)' % r[16])
            if r[9]:
                p.append(macro_text(r[9], r[12], r[10], r[11], r[13], r[14]))
            if multiplicity(rg) > 1:
                p.append('%d references at this location' % multiplicity(rg))
            out_refs.write(p, rg, r[17], multiplicity=False)
    if per_unit:
        units = collections.defaultdict(lambda: collections.OrderedDict())
        for key, rg in refs.items():
            r = rg['rows'][0]
            for tu, count in rg['tus'].items():
                units[tu].setdefault(r[4] or '(file scope)', collections.Counter())[r[5]] += count
        names = dict((tu, (m, t)) for tu, m, t in q.con.execute(
            'SELECT id, main_file, target FROM tu WHERE id IN (%s)' % ','.join('?' * len(units)),
            list(units)).fetchall()) if units else {}
        for tu in sorted(units, key=lambda u: names.get(u, ('', ''))):
            m, t = names.get(tu, ('?', '?'))
            writer.out.write('%s    in unit %s (target %s): %s\n' % (writer.indent, m, t, '; '.join(
                '%s: %s' % (f, access_breakdown(c)) for f, c in units[tu].items())))
    return True


def static_refs_of(q, usr, target=None):
    where, args = ('AND t.target = ?', (usr, target)) if target else ('', (usr,))
    return group_by_tu(q.con.execute(STATIC_REF_SQL % where, args).fetchall(), lambda r: r[STATIC_REF_KEY], -2, -1)


def static_targets(q, usr):
    """The targets that define a global whose name several targets define
    (each has its own variable, though they share a usr); () otherwise. A
    static defined in a header is one copy per unit, not per target."""
    rows = q.con.execute("SELECT DISTINCT s.kind, s.file, t.target FROM c_static s JOIN tu t ON t.id = s.tu WHERE "
                         "s.usr = ? AND s.kind = 'global'", (usr,)).fetchall()
    targets = sorted(set(t for _, _, t in rows))
    return tuple(targets) if len(targets) > 1 else ()


def write_static(q, writer, usr, out_refs=None, per_unit=False):
    """static_lines for one usr, once per defining target when several
    targets define it. Returns False when there is no declaration."""
    targets = static_targets(q, usr)
    if not targets:
        return static_lines(q, writer, usr, static_refs_of(q, usr), out_refs=out_refs, per_unit=per_unit)
    found = False
    for t in targets:
        found = static_lines(q, writer, usr, static_refs_of(q, usr, t), out_refs=out_refs, target=t,
                             defining_targets=targets, per_unit=per_unit) or found
    return found


def statics(paths, what, out=None):
    """The statics and globals a file declares or uses, or that a class's
    methods use, with their reads and writes per function."""
    out = out or sys.stdout
    q = QueryContext(paths, STATICS_SPEC)
    try:
        is_file = '/' in what or what.endswith(SOURCE_EXTENSIONS)
        if is_file:
            usrs = [u for (u,) in q.con.execute(
                'SELECT usr FROM c_static WHERE file = ? UNION SELECT var_usr FROM static_ref WHERE file = ?',
                (what, what))]
            readers = q.con.execute('SELECT count(*) FROM tu_input WHERE path = ?', (what,)).fetchone()[0]
            if not readers:
                q.extra_incomplete.append('INCOMPLETE: no unit in this database reads %s (it is not parsed, or not a '
                                          'file of the repository)' % what)
        else:
            usrs = [u for (u,) in q.con.execute('SELECT DISTINCT var_usr FROM static_ref WHERE enclosing_class = ?',
                                                (what,))]
        names = dict(q.con.execute('SELECT usr, name FROM c_static WHERE usr IN (%s)' % ','.join('?' * len(usrs)),
                                   usrs).fetchall()) if usrs else {}
        buf = io.StringIO()
        writer = RowWriter(q, buf)
        missing = []
        for usr in sorted(usrs, key=lambda u: (names.get(u, ''), u or '')):
            if usr is None or not write_static(q, writer, usr):
                missing.append(usr)
        out.write('Statics %s %s: %d\n' % ('declared or used in' if is_file else 'used by the methods of', what,
                                           writer.written))
        out.write(buf.getvalue())
        if missing:
            out.write('referenced, with no declaration in this database: %s\n' % ', '.join(str(m) for m in missing))
        out.write(STATE_LIMITS_LINE + '\n')
        out.write(STATE_SWIFT_LINE_STATICS + '\n')
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


def staticrefs(paths, name, out=None, per_unit=False):
    """Every declaration of the statics and globals named name, and every
    reference to them (with per_unit, also each unit's references: a static
    defined in a header has a copy in each)."""
    out = out or sys.stdout
    q = QueryContext(paths, STATICREFS_SPEC)
    try:
        q.search_not_parsed(forms=search_forms_word(name, name))
        q.search_forms_text = REFS_SEARCH_FORMS
        usrs = [u for (u,) in q.con.execute('SELECT usr FROM c_static WHERE name = ? UNION SELECT var_usr FROM '
                                            'static_ref WHERE name = ?', (name, name))]
        buf = io.StringIO()
        writer = RowWriter(q, buf)
        refs_writer = RowWriter(q, buf, indent='  ')
        for usr in sorted(u for u in usrs if u is not None):
            if not write_static(q, writer, usr, out_refs=refs_writer, per_unit=per_unit):
                buf.write('%s: no declaration in this database\n' % usr)
        out.write('Statics named %s: %d; references: %d\n' % (name, writer.written, refs_writer.written))
        out.write(buf.getvalue())
        out.write(STATE_LIMITS_LINE + '\n')
        out.write(STATE_SWIFT_LINE_STATICS + '\n')
        total = writer.written + refs_writer.written
        q.write_status(out, total, writer.marked + refs_writer.marked, writer.outside + refs_writer.outside)
        return q.exit_status(total)
    finally:
        q.close()


# --- Macros and conditional compilation ---------------------------------------
#
# The tables macro_def, macro_undef, macro_ast_fact, macro_expansion,
# macro_use_count, pp_condition and pp_skipped (extract_sends.cpp, "Macros and
# conditional compilation"), the queries macros, macrouses and skipped, the
# search of code that no unit compiles for reach and ivars, and the lint of
# docs/swift-migration/hidden-callers.md section 6 (macrolint).

PP_TABLES = ('macro_def', 'macro_undef', 'macro_ast_fact', 'macro_expansion', 'macro_use_count', 'pp_condition',
             'pp_skipped')

# The kinds of macro in the table of hidden-callers.md section 6, each decided
# by facts (the words of macro_def.facts from the replacement tokens, and the
# facts of macro_ast_fact from the AST of expansions): (description, token
# facts, AST facts). A macro is of the kind when it has any of them.
MACRO_CLASSES = collections.OrderedDict([
    ('send', ('sends a message', ('send',), ('send',))),
    ('stringify', ('stringifies an argument', ('stringify',), ())),
    # As the section's table counts: any of these keywords in the body. The
    # facts return, break, continue and goto say which of them leave the
    # code around the use (those in a block, or in a method or function the
    # macro defines, do not).
    ('control-flow', ('contains return, break, continue or goto', ('control-flow-keyword',), ())),
    ('context', ('uses _cmd, __FILE__, __LINE__, __func__ or the like', ('cmd', 'file-line'), ('cmd',))),
    ('method', ('defines or declares a method', ('method-definition',), ('method',))),
    ('paste', ('pastes tokens into a name', ('paste',), ())),
    ('class', ('defines a class, category or protocol', ('class-definition',), ('class',))),
    ('method-family', ('applies a method-family or ownership attribute', ('method-family-attribute',), ())),
])

MACRO_READING_NOTE = (
    'needs reading (not decided by facts): what each expansion reaches (the selectors and methods to enter in the '
    'reflective-site registry), whether a stringified or pasted name is persisted (stored-state.md) or names a Swift '
    'member, and whether an argument is evaluated conditionally (DLog does not evaluate its arguments when logging is '
    'off); multiple-evaluation and unevaluated-parameter count the text only')

MACROS_NOT_IN_DATABASE = NOT_IN_DATABASE_COMMON + [
    'definitions in ranges that every unit skips (inactive #if branches; macros searches them as text for --name), '
    'and macros that no unit reads',
    'how a macro expands in a configuration that was not captured (another target, Release, the other '
    'architecture): only the views of the captured units are recorded',
    'facts from the AST of a macro that no unit expands (only the facts from its tokens)',
]
MACROS_SPEC = QuerySpec('macros', MACROS_NOT_IN_DATABASE, exit_text('definitions printed', True, False), None, True)
MACROUSES_SPEC = QuerySpec('macrouses', MACROS_NOT_IN_DATABASE,
                           exit_text('expansions printed', True, True), None, True)
SKIPPED_SPEC = QuerySpec('skipped', NOT_IN_DATABASE_COMMON, exit_text('skipped ranges printed', True, False), None,
                         True)
MACRO_DEFINE_FORMS = '  searched: #define NAME at the start of a line'
MACRO_USE_FORMS = '  searched: NAME as a whole word'
LINT_EXIT_TEXT = ('exit status: 0 every macro of these kinds is registered with a reading and the database is '
                  'complete, 1 a macro is missing, changed or no longer exists, or (without --allow-unreviewed) a '
                  'registered one is UNREVIEWED, whether or not the database is complete, 3 no failure found but '
                  'the database is incomplete (see INCOMPLETE), 2 error')
LINT_COVERAGE_TEXT = ('coverage: the lint covers the macros of these kinds that a captured unit reads, in the captured '
                      'configuration; it does not see macros in code that no unit compiles (inactive #if branches, '
                      'files no captured unit reads, listed below) or in other build configurations')
NOT_SEEN_MARK = 'not-seen-in-this-run'

CLASSIFICATION_FILE = os.path.join('docs', 'swift-migration', 'macro-classification.tsv')
UNREVIEWED = 'UNREVIEWED'
CLASSIFICATION_COLUMNS = ('name', 'file', 'line', 'digest', 'classes', 'facts', 'reading')
CLASSIFICATION_HEADER = (
    '# Classification of the repository\'s macros (docs/swift-migration/hidden-callers.md section 6).\n'
    '# One row per macro that the migration\'s scope defines or expands and that is of a kind in that section\'s\n'
    '# table. codedb.py macrolint fails when such a macro has no row, when its definition changed (digest), or\n'
    '# when a row names a macro that no longer exists. name, file, line, digest, classes and facts come from the\n'
    '# code database (codedb.py macrolint --write writes them, keeping each reading whose digest is unchanged).\n'
    '# classes: the kinds, each followed by "(via M)" when the macro has it only through the macros M it\n'
    '# expands, to any depth. facts beginning not-seen-in-this-run: a row kept by --write for a macro the run\n'
    '# did not see (--prune removes it). reading is written by a person who read the macro: what it expands\n'
    '# to and reaches. UNREVIEWED marks a row nobody has read yet. Tab-separated.\n')


def without_swift(q):
    """The preprocessor queries answer from the Objective-C side only: the
    state of the Swift modules neither changes their answer nor makes it
    incomplete."""
    q.swift_states = None


def macro_classes(token_facts, ast_facts):
    """The kinds of MACRO_CLASSES a macro is by its own facts, from its token
    facts and AST facts (sets of fact names), in table order."""
    return [c for c, (_, tokens, ast) in MACRO_CLASSES.items()
            if set(tokens) & token_facts or set(ast) & ast_facts]


# A kind a macro has only through a macro it expands is labelled with the
# macros it comes through: 'send (via DEFINE_BOILERPLATE)', several joined by
# '+'. A label is the kind alone when the macro's own facts give it.
KIND_LABEL_RE = re.compile(r'^([a-z-]+)(?: \(via ([^()]+)\))?$')


def kind_label(kind, via):
    return kind if not via else '%s (via %s)' % (kind, '+'.join(sorted(via)))


def parse_kind_label(label):
    """(kind, [macros it comes through]) from a kind_label."""
    m = KIND_LABEL_RE.match(label.strip())
    if not m:
        return label.strip(), []
    return m.group(1), (m.group(2).split('+') if m.group(2) else [])


SDK_SEND_SQL = ("SELECT macro_name, macro_file, count(*), count(DISTINCT selector) FROM send WHERE macro_role IN "
                "('body', 'pasted') AND macro_name IS NOT NULL GROUP BY macro_name, macro_file")
IDENTIFIER_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
STRING_OR_CHAR_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')


class MacroKinds:
    """The kinds of every repository macro definition, over the transitive
    closure of the macros it expands (hidden-callers.md section 6: a wrapper
    of a macro of a kind is of that kind).

    A definition's own kinds come from its facts (macro_classes). Its edges,
    to any depth, with cycles allowed, are to the macros its replacement text
    names: the token fact uses-macro (repository macros defined when it is),
    the AST fact expands (repository macros its expansions expanded, one
    level), and every identifier of the body outside string and character
    literals that names a repository macro (any definition of that name; a
    name the preprocessor expands at the use may be defined after the
    wrapper) or a macro defined outside the repository that sends. The body
    of a macro outside the repository is not recorded, so those macros are
    kind sources of one kind only, send, and only when the database has the
    evidence: a send row with macro_role body or pasted whose outermost
    macro is that macro (sdk_senders). A name resolves to every repository
    definition of it, a conservative choice where a name has several. A
    body that was truncated (body_truncated) contributes the names in its
    first 1,000 bytes only."""

    def __init__(self, q):
        con = q.con
        self.own = {}
        self.edges = collections.defaultdict(set)
        self.by_name = collections.defaultdict(set)
        bodies = {}
        for name, file, line, digest, facts, detail, body in con.execute(
                'SELECT DISTINCT name, file, line, body_digest, facts, fact_detail, body FROM macro_def'):
            key = (name, file, line, digest)
            self.own[key] = set((facts or '').split())
            self.by_name[name].add(key)
            uses = _json_detail(detail).get('uses-macro') or []
            self.edges[key].update(u for u in uses if isinstance(u, str))
            bodies[key] = body or ''
        self.ast = collections.defaultdict(set)
        expands = collections.defaultdict(set)
        for name, file, line, fact, detail in con.execute(
                'SELECT DISTINCT name, def_file, def_line, fact, CASE WHEN fact = \'expands\' THEN detail ELSE \'\' END '
                'FROM macro_ast_fact'):
            self.ast[(name, file, line)].add(fact)
            if fact == 'expands' and detail:
                expands[(name, file, line)].add(detail)
        self.sdk_senders = collections.OrderedDict()
        for name, file, sends, selectors in con.execute(SDK_SEND_SQL):
            if file and os.path.isabs(file) and name not in self.by_name:
                prev = self.sdk_senders.get(name, (set(), 0, 0))
                prev[0].add(file)
                self.sdk_senders[name] = (prev[0], prev[1] + sends, prev[2] + selectors)
        for key, body in bodies.items():
            self.edges[key].update(expands.get(key[:3], ()))
            for ident in IDENTIFIER_RE.findall(STRING_OR_CHAR_RE.sub(' ', body)):
                if ident in self.by_name or ident in self.sdk_senders:
                    self.edges[key].add(ident)
            self.edges[key].discard(key[0])
        self.kinds = {}
        self._close()

    def own_kinds(self, key):
        return macro_classes(self.own.get(key, set()), self.ast.get(key[:3], set()))

    def _close(self):
        """kinds[key]: {kind: set of the macros it comes through (empty for
        the definition's own kinds)}, the least fixed point, which a cycle
        cannot inflate: a kind only reaches a definition from a definition
        that has it by its own facts."""
        kinds = dict((key, dict((k, set()) for k in self.own_kinds(key))) for key in self.own)
        own = dict((key, set(v)) for key, v in kinds.items())
        sdk = dict((name, {'send': set()}) for name in self.sdk_senders)
        changed = True
        while changed:
            changed = False
            for key, names in self.edges.items():
                mine = kinds[key]
                for name in names:
                    sources = [kinds[k] for k in self.by_name.get(name, ())] + ([sdk[name]] if name in sdk else [])
                    for source in sources:
                        for kind in source:
                            if kind in own[key]:
                                continue
                            via = mine.setdefault(kind, set())
                            if name not in via:
                                via.add(name)
                                changed = True
        self.kinds = kinds

    def of(self, key):
        """[(kind, via)] in table order; via is the set of macros the kind
        comes through, empty for an own kind."""
        k = self.kinds.get(key, {})
        return [(c, k[c]) for c in MACRO_CLASSES if c in k]

    def labels(self, key):
        return [kind_label(c, via) for c, via in self.of(key)]

    def names(self, key):
        return [c for c, _ in self.of(key)]

    def inherited_only(self, key):
        """Whether every kind of the definition comes through other macros."""
        got = self.of(key)
        return bool(got) and all(via for _, via in got)


def macro_kinds(q):
    """The MacroKinds of q's database, computed once per query."""
    mk = getattr(q, 'macro_kinds', None)
    if mk is None:
        mk = q.macro_kinds = MacroKinds(q)
    return mk


def _json_detail(text):
    try:
        d = json.loads(text or '{}')
        return d if isinstance(d, dict) else {}
    except ValueError:
        return {}


MacroDef = collections.namedtuple('MacroDef', 'name file line col kind params variadic body truncated digest '
                                              'facts detail previous scope g views')


def macro_definitions(q, where='1', params=()):
    """Definitions in macro_def, one per name, file, line and digest, with
    their rows grouped across the units that recorded them:
    {key: MacroDef}, in file and line order."""
    defs = collections.OrderedDict()
    sql = ('SELECT d.name, d.file, d.line, d.col, d.kind, d.params, d.variadic, d.body, d.body_truncated, '
           'd.body_digest, d.facts, d.fact_detail, d.previous_def, d.in_migration_scope, d.view, d.tu, t.target '
           'FROM macro_def d JOIN tu t ON t.id = d.tu WHERE %s ORDER BY d.file, d.line, d.name' % where)
    for r in q.con.execute(sql, params):
        key = (r[0], r[1], r[2], r[9])
        d = defs.get(key)
        if d is None:
            detail = _json_detail(r[11])
            d = MacroDef(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], set((r[10] or '').split()),
                         detail, set(), r[13], {'tus': {}, 'targets': set()}, set())
            defs[key] = d
        d.g['tus'][r[15]] = 1
        d.g['targets'].add(r[16])
        d.views.add(r[14])
        if r[12]:
            d.previous.add(r[12])
    return defs


def macro_ast_facts(q, name, file, line):
    """{fact: {detail: (count, units)}} from macro_ast_fact for one
    definition."""
    out = collections.defaultdict(dict)
    for fact, detail, count, units in q.con.execute(
            'SELECT fact, detail, sum(count), count(DISTINCT tu) FROM macro_ast_fact WHERE name = ? AND def_file = ? '
            'AND def_line = ? GROUP BY fact, detail ORDER BY fact, detail', (name, file, line)):
        out[fact][detail] = (count, units)
    return out


EXPANSION_SITE_SQL = ('SELECT DISTINCT file, line, col, nesting, outer_line, outer_col, in_migration_scope '
                      'FROM macro_expansion WHERE name = ? AND def_file = ? AND def_line = ?')


def expansion_counts(q, name, file, line):
    """(sites, sites in the migration's scope, files) of a definition's
    expansions, each site counted once however many units recorded it."""
    sites = q.con.execute(EXPANSION_SITE_SQL, (name, file, line)).fetchall()
    return len(sites), sum(1 for s in sites if s[6]), len(set(s[0] for s in sites))


def name_conflicts(q, name):
    """The distinct definitions of name, [(file, line, digest, targets,
    units)], where units is the set of units that see the definition: those
    that read its file with a view in which it was recorded."""
    rows = q.con.execute('SELECT d.file, d.line, d.body_digest, group_concat(DISTINCT t.target), '
                         'group_concat(DISTINCT coalesce(d.view, \'\')) FROM macro_def d JOIN tu t ON t.id = d.tu '
                         'WHERE d.name = ? GROUP BY d.file, d.line, d.body_digest ORDER BY d.file, d.line',
                         (name,)).fetchall()
    out = []
    for f, l, digest, targets, views in rows:
        units = set()
        for view in (views or '').split(','):
            units.update(tu for (tu,) in q.con.execute('SELECT tu FROM tu_input WHERE path = ? AND '
                                                       'coalesce(view, \'\') = ?', (f, view)))
        out.append((f, l, digest, targets, units))
    return out


def conflicting(defs):
    """Whether two of the definitions (name_conflicts) with different bodies
    are seen by disjoint sets of units: units disagree on what the name means.
    Definitions seen by the same units are a redefinition (or an #undef and a
    new definition) within those units."""
    for i, a in enumerate(defs):
        for b in defs[i + 1:]:
            if a[2] != b[2] and not (a[4] & b[4]):
                return True
    return False


def write_macro_definition(q, writer, buf, d, verbose=True):
    ast = macro_ast_facts(q, d.name, d.file, d.line)
    key = (d.name, d.file, d.line, d.digest)
    classes = macro_kinds(q).names(key)
    labels = macro_kinds(q).labels(key)
    signature = d.name + ('(%s)' % (d.params or '') if d.kind == 'function' else '')
    parts = ['%s:%d:%d' % (d.file, d.line, d.col), '#define %s' % signature,
             'kinds: %s' % (', '.join(labels) if labels else 'none of the kinds in hidden-callers.md section 6')]
    writer.write(parts, d.g, d.scope, multiplicity=False)
    ind = '    '
    buf.write('%sbody: %s%s\n' % (ind, d.body, ' (truncated)' if d.truncated else ''))
    if d.facts:
        words = []
        for f in sorted(d.facts):
            det = d.detail.get(f)
            words.append('%s (%s)' % (f, ', '.join(det)) if det else f)
        buf.write('%sfacts from its tokens: %s\n' % (ind, '; '.join(words)))
    else:
        buf.write('%sfacts from its tokens: none\n' % ind)
    if ast:
        words = []
        for fact in sorted(ast):
            details = ast[fact]
            shown = ['%s%s' % (det or '', ' x%d' % c if c > 1 else '') for det, (c, _) in sorted(details.items())]
            words.append('%s (%s)' % (fact, ', '.join(x for x in shown if x)) if any(shown) else fact)
        buf.write('%sfacts from the AST of its expansions: %s\n' % (ind, '; '.join(words)))
    else:
        buf.write('%sfacts from the AST of its expansions: none (or not expanded in any unit)\n' % ind)
    total, in_scope, files = expansion_counts(q, d.name, d.file, d.line)
    buf.write('%sexpansions: %d sites in %d files (%d in the migration\'s scope); codedb.py macrouses %s lists them\n'
              % (ind, total, files, in_scope, d.name))
    if d.previous:
        buf.write('%sredefines: %s\n' % (ind, ', '.join(sorted(d.previous))))
    undefs = q.con.execute('SELECT DISTINCT file, line FROM macro_undef WHERE name = ? AND def_file = ? AND '
                           'def_line = ? ORDER BY file, line', (d.name, d.file, d.line)).fetchall()
    if undefs:
        buf.write('%sundefined at: %s\n' % (ind, ', '.join('%s:%d' % u for u in undefs)))
    others = name_conflicts(q, d.name)
    digests = set(r[2] for r in others)
    if len(others) > 1:
        if conflicting(others):
            label = 'CONFLICT: units see different definitions of %s (%d bodies)' % (d.name, len(digests))
        elif len(digests) > 1:
            label = 'redefined: %d definitions with different bodies, seen by the same units in turn' % len(others)
        else:
            label = 'defined at %d places with the same body' % len(others)
        buf.write('%s%s: %s\n' % (ind, label, '; '.join('%s:%d (targets %s, %d units)' % (f, l, t, len(u))
                                                         for f, l, _, t, u in others)))
    return classes


def macro_text_search(root, files_ranges, pattern, limit=TEXT_MATCHES_MAX):
    """Search ranges of files as text: files_ranges is {file: [(start, end)]};
    returns [(file, line, text)]."""
    found = []
    for f, ranges in sorted(files_ranges.items()):
        try:
            with open(os.path.join(root, f), 'r', encoding='utf-8', errors='replace') as fh:
                lines = fh.read().split('\n')
        except OSError:
            continue
        for start, end in ranges:
            for n in range(max(1, start), min(end, len(lines)) + 1):
                if pattern.search(lines[n - 1]):
                    found.append((f, n, lines[n - 1].strip()[:200]))
                    if len(found) >= limit:
                        return found
    return found


def file_views(q, path):
    """{view: {tu: target}} of the units that read path themselves (not
    through a module)."""
    views = collections.defaultdict(dict)
    for view, tu, target in q.con.execute('SELECT coalesce(i.view, \'\'), i.tu, t.target FROM tu_input i JOIN tu t '
                                          'ON t.id = i.tu WHERE i.path = ?', (path,)):
        views[view][tu] = target
    return views


def skipped_segments(q, path):
    """The lines of path that some unit skips (the lines between the
    directives that begin and end a skipped range), in segments of lines skipped by
    the same views: [(start, end, views skipping, all views, [skip rows])].
    Include guards are left out. A view whose rows nobody recorded (a claim
    gap) counts as skipping nothing; such gaps make the answer incomplete."""
    views = file_views(q, path)
    rows = q.con.execute('SELECT DISTINCT coalesce(view, \'\'), start_line, end_line, directive, condition, '
                         'chain_line FROM pp_skipped WHERE file = ? AND include_guard = 0', (path,)).fetchall()
    by_line = collections.defaultdict(set)
    for view, start, end, _, _, _ in rows:
        # The lines between the directive that begins the range and the one
        # that ends it.
        for n in range(start + 1, end):
            by_line[n].add(view)
    segments = []
    for n in sorted(by_line):
        vs = frozenset(by_line[n])
        if segments and segments[-1][1] == n - 1 and segments[-1][2] == vs:
            segments[-1][1] = n
        else:
            segments.append([n, n, vs])
    out = []
    for start, end, vs in segments:
        overlapping = sorted(set((r[1], r[2], r[3], r[4], r[5]) for r in rows if r[1] + 1 <= end and
                                 r[2] - 1 >= start and r[0] in vs))
        out.append((start, end, vs, frozenset(views), overlapping))
    return out, views


def skipped_everywhere(q):
    """{file: [(start, end)]}: the line ranges of repository files that every
    unit reading the file skips (include guards left out), from pp_skipped
    and tu_input."""
    rows = q.con.execute('SELECT DISTINCT file, coalesce(view, \'\'), start_line, end_line FROM pp_skipped WHERE '
                         'include_guard = 0 ORDER BY file').fetchall()
    by_file = collections.defaultdict(list)
    for f, view, start, end in rows:
        by_file[f].append((view, start, end))
    out = {}
    for f, ranges in by_file.items():
        views = set(v for (v,) in q.con.execute('SELECT DISTINCT coalesce(view, \'\') FROM tu_input WHERE path = ?',
                                                (f,)))
        lines = None
        for view in views:
            mine = set()
            for v, start, end in ranges:
                if v == view:
                    mine.update(range(start + 1, end))
            lines = mine if lines is None else lines & mine
            if not lines:
                break
        if lines:
            segs = []
            for n in sorted(lines):
                if segs and segs[-1][1] == n - 1:
                    segs[-1][1] = n
                else:
                    segs.append([n, n])
            out[f] = [tuple(s) for s in segs]
    return out


def write_skipped_search(q, out, words, label):
    """The section reach and ivars print for Objective-C code that no unit
    compiles: a text search of the ranges every unit skips for words (whole
    words). Returns the number of matches."""
    ranges = skipped_everywhere(q)
    count = sum(len(v) for v in ranges.values())
    words = [w for w in words if w]
    pattern = re.compile(r'(?<![A-Za-z0-9_])(%s)(?![A-Za-z0-9_])' % '|'.join(re.escape(w) for w in words)) \
        if words else None
    matches = macro_text_search(q.paths.root, ranges, pattern) if pattern else []
    out.write('Objective-C code that is not compiled: %d ranges in %d files are skipped by every unit that reads them '
              '(inactive #if branches; include guards left out); a text search of them for %s finds %d lines '
              '(possible %s)%s\n' % (count, len(ranges), ', '.join(words) or 'nothing', len(matches), label,
                                     ':' if matches else ''))
    for f, n, text in matches:
        out.write('  %s:%d  in a range no unit compiles: %s\n' % (f, n, text))
    return len(matches)


def skipped_search_incomplete(q, matches, rows):
    if matches and not rows:
        q.extra_incomplete.append('INCOMPLETE: no rows, but code that no unit compiles mentions the name (text '
                                  'matches: %d, listed under Objective-C code that is not compiled).' % matches)


def macros(paths, file=None, name=None, cls=None, out=None):
    """Definitions of repository macros with their facts, kinds, expansion
    counts and conflicts: those in FILE, named NAME, or of kind C."""
    out = out or sys.stdout
    q = QueryContext(paths, MACROS_SPEC)
    without_swift(q)
    try:
        if cls is not None and cls not in MACRO_CLASSES:
            raise CodeDBError('unknown kind %s; one of %s' % (cls, ', '.join(MACRO_CLASSES)))
        if file is not None:
            defs = macro_definitions(q, 'd.file = ?', (file,))
            if not q.con.execute('SELECT 1 FROM tu_input WHERE path = ? LIMIT 1', (file,)).fetchone():
                q.extra_incomplete.append('INCOMPLETE: no unit in this database reads %s (it is not parsed, or not '
                                          'a file of the repository)' % file)
        elif name is not None:
            defs = macro_definitions(q, 'd.name = ?', (name,))
        else:
            defs = macro_definitions(q)
        buf = io.StringIO()
        writer = RowWriter(q, buf)
        by_class = collections.Counter()
        for d in defs.values():
            if cls is not None and cls not in macro_kinds(q).names((d.name, d.file, d.line, d.digest)):
                continue
            for c in write_macro_definition(q, writer, buf, d):
                by_class[c] += 1
        title = ('in %s' % file if file is not None else 'named %s' % name if name is not None else
                 'of kind %s (%s)' % (cls, MACRO_CLASSES[cls][0]) if cls is not None else 'in the repository')
        out.write('Macro definitions %s: %d\n' % (title, writer.written))
        out.write(buf.getvalue())
        if by_class:
            out.write('by kind: %s\n' % ', '.join('%s %d' % (c, by_class[c]) for c in MACRO_CLASSES if by_class[c]))
        out.write(MACRO_READING_NOTE + '\n')
        if name is not None:
            others = q.con.execute('SELECT def_file, def_line, sum(count), count(DISTINCT file) FROM macro_use_count '
                                   'WHERE name = ? GROUP BY def_file, def_line', (name,)).fetchall()
            for f, l, n, files in others:
                out.write('defined outside the repository at %s:%d; expanded %d times (summed over units) in %d '
                          'repository files: codedb.py macrouses %s\n' % (f, l, n, files, name))
            pattern = re.compile(r'^\s*#\s*define\s+%s(?![A-Za-z0-9_])' % re.escape(name))
            matches = macro_text_search(paths.root, skipped_everywhere(q), pattern)
            out.write('definitions in code that no unit compiles (ranges every unit skips, searched as text): %d%s\n'
                      % (len(matches), ':' if matches else ''))
            for f, n, text in matches:
                out.write('  %s:%d  %s\n' % (f, n, text))
            q.search_not_parsed(forms=[(name, 'a #define of the name', pattern)], skip_definitions=False)
            q.search_forms_text = MACRO_DEFINE_FORMS
            if not writer.written and matches:
                q.extra_incomplete.append('INCOMPLETE: no definition is recorded, but code that no unit compiles '
                                          'defines %s (listed above).' % name)
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


EXPANSION_ROW_SQL = ('SELECT x.file, x.line, x.col, x.nesting, x.parent_name, x.outer_name, x.outer_line, x.outer_col, '
                     'x.enclosing_name, x.in_condition, x.args, x.args_truncated, x.def_file, x.def_line, '
                     'x.in_migration_scope, x.name, x.tu, t.target FROM macro_expansion x JOIN tu t ON t.id = x.tu '
                     'WHERE %s ORDER BY x.file, x.line, x.col')


def write_expansion_rows(q, writer, rows, show_name=False):
    for key, g in group_rows(rows, 16):
        (file, line, col, nesting, parent, outer, oline, ocol, enclosing, in_cond, args, truncated, dfile, dline,
         migration, name) = key
        parts = ['%s:%d:%d' % (file, line, col)]
        if show_name:
            parts.append('%s (defined %s:%d)' % (name, dfile, dline))
        parts.append('#if condition' if in_cond else (enclosing or '(file scope)'))
        if nesting == 'argument':
            parts.append('in an argument of %s at %d:%d' % (outer, oline, ocol))
        elif nesting == 'body':
            parts.append('made by the body of %s (outermost %s at %d:%d)' % (parent or 'a macro outside the '
                                                                                       'repository', outer, oline,
                                                                       ocol))
        if args:
            try:
                parts.append('arguments %s%s' % (' | '.join(json.loads(args)), ' (truncated)' if truncated else ''))
            except ValueError:
                pass
        writer.write(parts, g, migration, multiplicity=False)


def macrouses(paths, name, out=None):
    """Every expansion of the macro NAME with its enclosing function; or, when
    NAME is a method (-[Class sel], +[Class sel]), a function or a class, the
    macros its code expands."""
    out = out or sys.stdout
    q = QueryContext(paths, MACROUSES_SPEC)
    without_swift(q)
    try:
        buf = io.StringIO()
        writer = RowWriter(q, buf)
        is_macro = bool(q.con.execute('SELECT 1 FROM macro_def WHERE name = ? LIMIT 1', (name,)).fetchone() or
                        q.con.execute('SELECT 1 FROM macro_use_count WHERE name = ? LIMIT 1', (name,)).fetchone())
        if is_macro:
            rows = q.con.execute(EXPANSION_ROW_SQL % 'x.name = ?', (name,)).fetchall()
            write_expansion_rows(q, writer, rows)
            out.write('Expansions of %s: %d\n' % (name, writer.written))
            out.write(buf.getvalue())
            counts = q.con.execute('SELECT file, def_file, def_line, max(count), in_migration_scope FROM '
                                   'macro_use_count WHERE name = ? GROUP BY file, def_file, def_line ORDER BY file',
                                   (name,)).fetchall()
            if counts:
                total = sum(c[3] for c in counts)
                out.write('%s is defined outside the repository (%s); its expansions are counted per file, not '
                          'listed: %d in %d files (the largest count any unit recorded for each file); sends in it '
                          'are send rows with macro %s\n' % (name, ', '.join(sorted(set(
                              '%s:%d' % (c[1], c[2]) for c in counts))), total, len(counts), name))
                for f, _, _, n, migration in counts:
                    out.write('  %s: %d%s\n' % (f, n, '' if migration else "  outside the migration's scope"))
            written = writer.written + len(counts)
            pattern = re.compile(r'(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])' % re.escape(name))
            q.search_not_parsed(forms=[(name, 'the name', pattern)], skip_definitions=False)
            q.search_forms_text = MACRO_USE_FORMS
            matches = write_skipped_search(q, out, [name], 'uses')
            skipped_search_incomplete(q, matches, written)
        else:
            m = re.match(r'^([-+])\[([A-Za-z_][A-Za-z0-9_]*)(\([A-Za-z0-9_]*\))? (.+)\]$', name)
            definers = []
            if m:
                where, params, what = 'x.enclosing_name = ?', (name,), 'the method %s' % name
                definers = q.con.execute("SELECT DISTINCT name, def_file, def_line, detail FROM macro_ast_fact "
                                         "WHERE fact = 'method' AND detail IN (?, ?) ORDER BY name",
                                         (name + ' definition', name + ' declaration')).fetchall()
            elif re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', name) and q.con.execute(
                    'SELECT 1 FROM objc_impl WHERE class_name = ? LIMIT 1', (name,)).fetchone():
                where = "(x.enclosing_name LIKE ? OR x.enclosing_name LIKE ? OR x.enclosing_name LIKE ? OR " \
                        "x.enclosing_name LIKE ?)"
                params = ('-[%s %%' % name, '+[%s %%' % name, '-[%s(%%' % name, '+[%s(%%' % name)
                what = 'the methods of %s (its @implementation and categories)' % name
                definers = q.con.execute("SELECT DISTINCT name, def_file, def_line, detail FROM macro_ast_fact "
                                         "WHERE fact = 'method' AND (detail LIKE ? OR detail LIKE ? OR detail LIKE ? "
                                         "OR detail LIKE ?) ORDER BY name, detail", params).fetchall()
            else:
                where, params, what = 'x.enclosing_name = ?', (name,), 'the function %s' % name
            rows = q.con.execute(EXPANSION_ROW_SQL % where, params).fetchall()
            write_expansion_rows(q, writer, rows, show_name=True)
            out.write('Macro expansions in %s: %d\n' % (what, writer.written))
            out.write(buf.getvalue())
            used = collections.OrderedDict()
            for r in rows:
                used.setdefault((r[15], r[12], r[13]), set()).add((r[0], r[1], r[2]))
            if used:
                out.write('Macros a port must translate (each with its kinds; codedb.py macros --name NAME for its '
                          'facts):\n')
                for (mname, dfile, dline), sites in sorted(used.items()):
                    d = next(iter(macro_definitions(q, 'd.name = ? AND d.file = ? AND d.line = ?',
                                                    (mname, dfile, dline)).values()), None)
                    classes = macro_kinds(q).labels((d.name, d.file, d.line, d.digest)) if d else []
                    out.write('  %s (%s:%d): %d sites; kinds: %s\n' % (mname, dfile, dline, len(sites),
                                                                      ', '.join(classes) or 'none'))
            if definers:
                out.write('Methods made by macros (the macro is used outside any method; its expansions are '
                          'listed by codedb.py macrouses MACRO):\n')
                for mname, dfile, dline, detail in definers:
                    out.write('  %s (%s:%d) makes %s\n' % (mname, dfile, dline, detail))
            written = writer.written + len(definers)
        q.write_status(out, written, writer.marked, writer.outside)
        return q.exit_status(written)
    finally:
        q.close()


def skipped(paths, path, out=None):
    """The ranges of FILE that are not compiled in some or all units, with
    their conditions and which units skip them."""
    out = out or sys.stdout
    q = QueryContext(paths, SKIPPED_SPEC)
    without_swift(q)
    try:
        segments, views = skipped_segments(q, path)
        if not views:
            q.extra_incomplete.append('INCOMPLETE: no unit in this database reads %s (it is not parsed, or not a file '
                                      'of the repository)' % path)
        all_units = set(tu for v in views.values() for tu in v)
        conds = collections.defaultdict(lambda: collections.defaultdict(set))
        texts = {}
        for line, directive, condition, view, value in q.con.execute(
                'SELECT line, directive, condition, coalesce(view, \'\'), value FROM pp_condition WHERE file = ? AND '
                'include_guard = 0', (path,)):
            texts[line] = (directive, condition)
            for v in value.split(','):
                conds[line][v].add(view)
        buf = io.StringIO()
        writer = RowWriter(q, buf)

        def units_of(vs):
            return dict((tu, t) for v in vs for tu, t in views.get(v, {}).items())

        for start, end, vs, all_views, overlapping in segments:
            skipping = units_of(vs)
            compiling = units_of(all_views - vs)
            g = {'tus': dict((tu, 1) for tu in skipping), 'targets': set(skipping.values())}
            if not compiling:
                where = 'skipped in every unit that reads it (%d)' % len(skipping)
            else:
                where = 'skipped in %d of %d units, compiled in the others (targets %s)' % (
                    len(skipping), len(skipping) + len(compiling), ','.join(sorted(set(compiling.values()))))
            directives = []
            for s, e, directive, condition, chain in overlapping:
                text = '#%s %s at %d' % (directive, condition or '', s) if directive not in ('else',) else \
                    '#else at %d of #%s %s at %d' % (s, texts.get(chain, ('if', ''))[0],
                                                       texts.get(chain, ('', ''))[1] or '', chain)
                text = ' '.join(text.split())
                if text not in directives:
                    directives.append(text)
            parts = ['%s:%d-%d' % (path, start, end), where, 'by %s' % '; '.join(directives)]
            if g['tus']:
                writer.write(parts, g, in_migration_scope(path), multiplicity=False)
            else:
                writer.written += 1
                buf.write('  '.join(parts) + '\n')
        out.write('Ranges of %s not compiled in some or all units: %d\n' % (path, writer.written))
        out.write(buf.getvalue())
        out.write('Units that read %s: %d, in %d views (a view: the language, ARC and the ranges skipped)\n' % (
            path, len(all_units), len(views)))
        if conds:
            out.write('Conditions (value per view; a view\'s units are those of tu_input):\n')
            for line in sorted(conds):
                directive, condition = texts[line]
                values = conds[line]
                out.write('  %d: #%s %s: %s\n' % (line, directive, condition or '', '; '.join(
                    '%s in %d units' % (v, len(units_of(values[v]))) for v in sorted(values))))
        guards = q.con.execute('SELECT DISTINCT line, condition FROM pp_condition WHERE file = ? AND include_guard = 1',
                               (path,)).fetchall()
        for line, condition in guards:
            out.write('include guard (not listed): #ifndef %s at %d\n' % (condition, line))
        q.write_status(out, writer.written, writer.marked, writer.outside)
        return q.exit_status(writer.written)
    finally:
        q.close()


# --- The macro lint ------------------------------------------------------------

def read_classification(path):
    """{(name, file, digest): row dict} from the classification file, and the
    list of rows in file order."""
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding='utf-8') as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            if fields == list(CLASSIFICATION_COLUMNS):
                continue
            if len(fields) != len(CLASSIFICATION_COLUMNS):
                raise CodeDBError('%s:%d: expected %d tab-separated fields (%s), found %d' % (
                    path, n, len(CLASSIFICATION_COLUMNS), ', '.join(CLASSIFICATION_COLUMNS), len(fields)))
            rows.append(dict(zip(CLASSIFICATION_COLUMNS, fields), source_line=n))
    return rows


def lint_subjects(q):
    """The macros the lint covers: every definition in a file of the
    migration's scope, and every repository macro expanded in a file of the
    scope. [(MacroDef, kind labels (MacroKinds, own and inherited), facts
    text)] in name and file order."""
    defs = macro_definitions(q)
    expanded = set(q.con.execute('SELECT DISTINCT name, def_file, def_line FROM macro_expansion WHERE '
                                 'in_migration_scope = 1'))
    out = []
    for d in defs.values():
        if not (d.scope or (d.name, d.file, d.line) in expanded):
            continue
        ast = macro_ast_facts(q, d.name, d.file, d.line)
        classes = macro_kinds(q).labels((d.name, d.file, d.line, d.digest))
        words = sorted(d.facts | set('ast:' + a for a in ast))
        out.append((d, classes, ' '.join(words)))
    out.sort(key=lambda x: (x[0].name, x[0].file, x[0].line))
    return out


def write_classification(path, subjects, existing, prune=False):
    """Writes the classification file: one row per subject that has a kind,
    keeping the reading of an existing row with the same name, file and
    digest; UNREVIEWED otherwise (a row whose digest changed is replaced, so
    its reading is reset). An existing row whose name and file no subject
    with a kind has (a macro this run did not see: gone, of no kind any
    more, or seen only by units that failed or are missing) is kept with its
    reading, its facts marked NOT_SEEN_MARK, unless prune. Returns (rows
    written, rows kept that this run did not see)."""
    keep = dict(((r['name'], r['file'], r['digest']), r['reading']) for r in existing)
    lines = [CLASSIFICATION_HEADER, '\t'.join(CLASSIFICATION_COLUMNS) + '\n']
    seen = set()
    names = set()
    rows = []
    for d, classes, words in subjects:
        key = (d.name, d.file, d.digest)
        if not classes or key in seen:
            continue
        seen.add(key)
        names.add((d.name, d.file))
        rows.append((d.name, d.file, str(d.line), d.digest, ','.join(classes), words, keep.get(key, UNREVIEWED)))
    kept = 0
    if not prune:
        for r in existing:
            if (r['name'], r['file']) in names:
                continue
            facts = r['facts'] if r['facts'].startswith(NOT_SEEN_MARK) else (NOT_SEEN_MARK + ' ' + r['facts']).strip()
            rows.append((r['name'], r['file'], r['line'], r['digest'], r['classes'], facts, r['reading']))
            kept += 1
    rows.sort(key=lambda r: (r[0], r[1], r[3]))
    lines.extend('\t'.join(r) + '\n' for r in rows)
    tmp = path + '.tmp'
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(tmp, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    os.replace(tmp, path)
    return len(rows), kept


DEFINE_LINE_RE = re.compile(r'^\s*#\s*define\s+[A-Za-z_][A-Za-z0-9_]*')


def uncompiled_definitions(q):
    """The #define lines in code of the migration's scope that no captured
    unit compiles: [(file, line, where, text)], from the ranges every unit
    that reads a file skips (skipped_everywhere) and from the files that are
    not parsed (coverage), searched as text."""
    found = []
    ranges = dict((f, r) for f, r in skipped_everywhere(q).items() if in_migration_scope(f))
    for f, n, text in macro_text_search(q.paths.root, ranges, DEFINE_LINE_RE, limit=10 ** 6):
        found.append((f, n, 'in a range every unit skips', text))
    if q.coverage is not None:
        files = [f for f in not_parsed_files(q.coverage.not_parsed) if in_migration_scope(f)]
        headers = set()
        for f in files:
            # A file no unit compiles, and the header of the same name beside
            # it when no unit reads that header either.
            stem = os.path.splitext(f)[0] + '.h'
            if os.path.exists(os.path.join(q.paths.root, stem)) and not q.con.execute(
                    'SELECT 1 FROM tu_input WHERE path = ? LIMIT 1', (stem,)).fetchone():
                headers.add(stem)
        for f in sorted(set(files) | headers):
            for g, n, text in macro_text_search(q.paths.root, {f: [(1, 10 ** 9)]}, DEFINE_LINE_RE, limit=10 ** 6):
                found.append((g, n, 'in a file no captured unit reads', text))
    return sorted(found)


def macrolint(paths, classification=None, write=False, allow_unreviewed=False, prune=False, out=None):
    """The lint of hidden-callers.md section 6: every macro that the
    migration's scope defines or expands and that is of a kind in that
    section's table (MACRO_CLASSES, decided by facts, through the macros it
    expands: MacroKinds) has a row in the classification file with its
    current digest and a reading."""
    out = out or sys.stdout
    path = classification or os.path.join(paths.root, CLASSIFICATION_FILE)
    q = QueryContext(paths, QuerySpec('macrolint', MACROS_NOT_IN_DATABASE, LINT_EXIT_TEXT, None, True))
    without_swift(q)
    try:
        incomplete = q.incomplete_lines()
        if prune and incomplete:
            raise CodeDBError('macrolint --prune needs a complete database: rows of macros seen only by units that '
                              'are not current would be removed with their readings (%s)' % incomplete[0])
        if prune and not write:
            raise CodeDBError('macrolint --prune is an option of --write')
        mk = macro_kinds(q)
        subjects = lint_subjects(q)
        existing = read_classification(path)
        if write:
            n, kept = write_classification(path, subjects, existing, prune=prune)
            existing = read_classification(path)
            out.write('wrote %s: %d macros%s\n' % (
                path, n, '; kept %d rows not seen in this run (marked %s in facts; --prune removes them)' % (
                    kept, NOT_SEEN_MARK) if kept else ''))
        by_key = dict(((r['name'], r['file'], r['digest']), r) for r in existing)
        by_name = collections.defaultdict(list)
        for r in existing:
            by_name[(r['name'], r['file'])].append(r)
        missing, changed, unreviewed, classes_changed, moved = [], [], [], [], []
        # {(name, file, digest): [(definition, row)]}: an identical
        # redefinition is a second definition with the row's digest.
        lines_of = {}
        required = set()
        plain = 0
        inherited = 0
        for d, classes, _ in subjects:
            if not classes:
                plain += 1
                continue
            if mk.inherited_only((d.name, d.file, d.line, d.digest)):
                inherited += 1
            key = (d.name, d.file, d.digest)
            required.add(key)
            r = by_key.get(key)
            if r is None:
                (changed if by_name.get((d.name, d.file)) else missing).append((d, classes))
                continue
            if r['classes'] != ','.join(classes):
                classes_changed.append((d, classes, r))
            if r['reading'].strip() in ('', UNREVIEWED) and key not in lines_of:
                unreviewed.append((d, classes))
            lines_of.setdefault(key, []).append((d, r))
        for pairs in lines_of.values():
            if not any(r['line'] == str(d.line) for d, r in pairs):
                moved.append(pairs[0])
        required_names = set((k[0], k[1]) for k in required)
        vanished = [r for r in existing if (r['name'], r['file'], r['digest']) not in required and (
            (r['name'], r['file']) not in required_names or
            any((o['name'], o['file'], o['digest']) in required for o in by_name[(r['name'], r['file'])]))]
        counts = collections.Counter(parse_kind_label(c)[0] for _, classes, _ in subjects for c in classes)
        out.write('Macros the migration\'s scope defines or expands: %d (of a kind in hidden-callers.md section 6: '
                  '%d; of no such kind: %d)\n' % (len(subjects), len(required), plain))
        out.write('by kind: %s\n' % (', '.join('%s %d' % (c, counts[c]) for c in MACRO_CLASSES if counts[c]) or
                                     'none'))
        out.write('of which a kind only through the macros they expand: %d\n' % inherited)
        out.write('macros defined outside the repository that send (send rows with macro_role body or pasted whose '
                  'outermost macro is defined outside the repository): %d%s\n' % (
                      len(mk.sdk_senders), (': ' + ', '.join(sorted(mk.sdk_senders))) if mk.sdk_senders else ''))
        out.write(LINT_COVERAGE_TEXT + '\n')
        uncompiled = uncompiled_definitions(q)
        out.write('#define in code that no captured unit compiles (not failures; read them by hand): %d\n'
                  % len(uncompiled))
        for f, n, where, text in uncompiled:
            out.write('  %s:%d  %s: %s\n' % (f, n, where, text))
        out.write('classification file: %s (%d rows)\n' % (path, len(existing)))
        failures = 0
        for title, items in (('NOT REGISTERED (add a row: codedb.py macrolint --write, then read it)', missing),
                             ('DEFINITION CHANGED since it was registered (read it again; --write keeps no reading '
                              'for a new digest)', changed)):
            if items:
                out.write('%s: %d\n' % (title, len(items)))
                for d, classes in items:
                    out.write('  %s %s:%d  kinds %s\n' % (d.name, d.file, d.line, ','.join(classes)))
                failures += len(items)
        if classes_changed:
            out.write('KINDS CHANGED (the facts of its expansions changed; run --write and check the reading): %d\n'
                      % len(classes_changed))
            for d, classes, r in classes_changed:
                out.write('  %s %s:%d  kinds now %s, registered %s\n' % (d.name, d.file, d.line, ','.join(classes),
                                                                         r['classes']))
            failures += len(classes_changed)
        if vanished:
            out.write('NO LONGER A MACRO OF THESE KINDS IN SCOPE (remove the row: codedb.py macrolint --write --prune, '
                      'on a complete database): %d\n' % len(vanished))
            for r in vanished:
                out.write('  %s %s (line %d of the classification file)%s\n' % (
                    r['name'], r['file'], r['source_line'],
                    '; not seen in this run' if r['facts'].startswith(NOT_SEEN_MARK) else ''))
            failures += len(vanished)
        if moved:
            # The digest is the same, so the reading still holds; only the
            # row's pointer to the definition is out of date.
            out.write('LINE MOVED (the definition is now at another line; not a failure: codedb.py macrolint --write '
                      'updates the line and keeps the reading): %d\n' % len(moved))
            for d, r in moved:
                out.write('  %s %s: row line %s, definition line %d\n' % (d.name, d.file, r['line'], d.line))
        out.write('registered and UNREVIEWED (nobody has read it yet): %d%s\n' % (
            len(unreviewed), '' if allow_unreviewed or not unreviewed else ' (fails the lint; --allow-unreviewed '
                                                                            'while the reading pass is under way)'))
        for d, classes in unreviewed[:NOT_PARSED_LISTED]:
            out.write('  %s %s:%d  kinds %s\n' % (d.name, d.file, d.line, ','.join(classes)))
        if len(unreviewed) > NOT_PARSED_LISTED:
            out.write('  ... and %d more\n' % (len(unreviewed) - NOT_PARSED_LISTED))
        out.write(MACRO_READING_NOTE + '\n')
        for line in incomplete:
            out.write(line + '\n')
        if unreviewed and not allow_unreviewed:
            failures += len(unreviewed)
        if failures and incomplete:
            out.write('failures found (%d); the database is also incomplete (see INCOMPLETE), so there may be '
                      'more\n' % failures)
        out.write(LINT_EXIT_TEXT + '\n')
        if failures:
            return 1
        if incomplete:
            return 3
        return 0
    finally:
        q.close()


def hold_lock_and_exec(paths, label, program):
    """Take the lock, then replace this process with program, holding the
    lock on fd LOCK_FD. The pid (and so the lock file's pid and start time)
    stays the same. CODEDB_LOCK_TOKEN is set to that pid, so that the
    program can tell it was started this way. Returns only on error."""
    if program and program[0] == '--':
        program = program[1:]
    if not program:
        raise CodeDBError('hold-lock: no program to run')
    lock = Lock(paths.lock, label, log=lambda m: print(m, file=sys.stderr, flush=True))
    lock.acquire()
    os.dup2(lock.fd, LOCK_FD)
    env = dict(os.environ, CODEDB_LOCK_TOKEN=str(os.getpid()))
    try:
        os.execve(program[0], program, env)
    except OSError:
        lock.release()
        os.close(LOCK_FD)
        raise


class Terminated(KeyboardInterrupt):
    pass


def on_terminate(signum, frame):
    raise Terminated()


# --- Classes and the SDK -------------------------------------------------------
#
# The tables objc_class and objc_adoption (the repository's classes, their
# superclasses and the protocols they list) and sdk_method, sdk_class and
# sdk_adoption (declarations outside the repository, one row per distinct
# declaration: each module's are recorded by the unit that holds its claim in
# sdk_claim), extract_sends.cpp "Classes and the SDK"; the queries sdkmethods
# and classinfo.

SDK_NOT_IN_DATABASE = [
    'methods the SDK declares only in its private headers or implements without declaring',
    'declarations in headers that no unit reads',
    'Swift-only SDK declarations (not visible to Objective-C)',
]
SDKMETHODS_SPEC = QuerySpec('sdkmethods', SDK_NOT_IN_DATABASE, exit_text('declarations printed', False, False), None,
                            False)
CLASSINFO_SPEC = QuerySpec('classinfo', NOT_IN_DATABASE_COMMON, exit_text('the class was found', True, False), None,
                           True)


def note_sdk_gaps(q):
    """An INCOMPLETE line when some module's declarations outside the
    repository are recorded by no unit (SDK_GAPS_SQL)."""
    gaps = sdk_gaps(q.con)
    if gaps:
        q.extra_incomplete.append('INCOMPLETE: the declarations outside the repository of %d modules that units load '
                                  'are recorded by no unit (the unit that held the claim was removed), first: %s. '
                                  'Run codedb.py update.' % (len(gaps), gaps[0][0]))


def sdk_method_text(kind, container, is_class, framework, optional, action):
    text = '%s[%s %%s]  %s %s, %s' % ('+' if is_class else '-', container, 'in', kind, framework)
    if optional:
        text += ', optional'
    if action:
        text += ', IBAction'
    return text


def sdkmethods(paths, selector, out=None):
    """Who outside the repository (the SDK) declares selector, as a method or
    a property's getter or setter."""
    out = out or sys.stdout
    q = QueryContext(paths, SDKMETHODS_SPEC)
    without_swift(q)
    try:
        note_sdk_gaps(q)
        rows = q.con.execute('SELECT DISTINCT container_kind, container, is_class_method, framework, is_optional, '
                             'is_action FROM sdk_method WHERE selector = ? ORDER BY framework, container, '
                             'is_class_method', (selector,)).fetchall()
        out.write('Declarations of %s outside the repository: %d\n' % (selector, len(rows)))
        for row in rows:
            out.write('  ' + sdk_method_text(*row) % selector + '\n')
        q.write_status(out, len(rows), 0, 0)
        return q.exit_status(len(rows))
    finally:
        q.close()


def same_class_sql(column):
    """SQL matching column to a class or to a category of it: ? is the class
    name, given twice."""
    return '(%s = ? OR substr(%s, 1, length(?) + 1) = ? || \'(\')' % (column, column)


SWIFT_CLASS = 'declared in Swift: superclass and adoptions are not in this database'


def class_chain(con, cls):
    """[(name, where, superclasses)] from cls up its superclass chain:
    where is 'repository FILE:LINE', 'SDK FRAMEWORK', SWIFT_CLASS (a class
    the Swift tables have members of: objc_class records only Objective-C
    classes, and the Swift tables hold no superclass) or 'not recorded';
    superclasses is the set of superclasses recorded for it (more than one
    when views disagree)."""
    swift = 'swift_objc_decl' in table_names(con)
    chain = []
    seen = set()
    name = cls
    while name and name not in seen:
        seen.add(name)
        rows = con.execute('SELECT DISTINCT superclass, file, line FROM objc_class WHERE name = ? ORDER BY file, line',
                           (name,)).fetchall()
        if rows:
            supers = set(r[0] for r in rows)
            chain.append((name, 'repository %s:%d' % (rows[0][1], rows[0][2]), supers))
            name = sorted(supers, key=lambda x: (x is None, x or ''))[0]
            continue
        rows = con.execute('SELECT DISTINCT superclass, framework FROM sdk_class WHERE name = ? ORDER BY framework',
                           (name,)).fetchall()
        if rows:
            supers = set(r[0] for r in rows)
            chain.append((name, 'SDK %s' % rows[0][1], supers))
            name = sorted(supers, key=lambda x: (x is None, x or ''))[0]
            continue
        if swift and con.execute('SELECT 1 FROM swift_objc_decl WHERE class_name = ? LIMIT 1', (name,)).fetchone():
            chain.append((name, SWIFT_CLASS, set()))
            break
        chain.append((name, 'not recorded', set()))
        break
    return chain


def direct_adoptions(con, cls):
    """{protocol: set of the containers (the class, its categories and
    extensions) that list it}, from the repository and the SDK."""
    out = collections.defaultdict(set)
    for container, proto in con.execute(
            'SELECT DISTINCT class_or_category, protocol FROM objc_adoption WHERE container_kind != \'protocol\' AND '
            + same_class_sql('class_or_category'), (cls, cls, cls)):
        out[proto].add(container)
    for container, proto in con.execute(
            'SELECT DISTINCT container, protocol FROM sdk_adoption WHERE container_kind != \'protocol\' AND '
            + same_class_sql('container'), (cls, cls, cls)):
        out[proto].add(container)
    return out


def protocol_parents(con, proto):
    rows = con.execute('SELECT DISTINCT protocol FROM objc_adoption WHERE container_kind = \'protocol\' AND '
                       'class_or_category = ? UNION SELECT DISTINCT protocol FROM sdk_adoption WHERE container_kind = '
                       '\'protocol\' AND container = ?', (proto, proto)).fetchall()
    return sorted(r[0] for r in rows)


def swiftimports(paths, name=None, header=None, not_importable=None, module=None, out=None):
    """How Swift imports Objective-C declarations through a bridging header
    (swiftimports.py): by name or USR, by header, or the declarations of a
    class that it does not import, with the reason."""
    import swiftimports as imports
    return imports.swiftimports(sys.modules[__name__], paths, name=name, header=header,
                                not_importable=not_importable, module=module, out=out)


def classinfo(paths, cls, out=None):
    """The superclass chain of a class into the SDK, and every protocol it
    adopts: directly (the class, its categories and extensions), through a
    superclass, and through protocol inheritance."""
    out = out or sys.stdout
    q = QueryContext(paths, CLASSINFO_SPEC)
    without_swift(q)
    try:
        note_sdk_gaps(q)
        chain = class_chain(q.con, cls)
        found = chain[0][1] != 'not recorded'
        out.write('Class %s: %s\n' % (cls, chain[0][1]))
        out.write('superclass chain: %s\n' % ' -> '.join('%s (%s)' % (n, w) for n, w, _ in chain))
        for n, _, supers in chain:
            if len(supers) > 1:
                out.write('  note: %s has more than one recorded superclass: %s\n' % (
                    n, ', '.join(sorted(x or '(none)' for x in supers))))
        direct = {}
        for n, _, _ in chain:
            for proto, containers in direct_adoptions(q.con, n).items():
                direct.setdefault(proto, (n, containers))
        out.write('protocols listed by the class or a superclass (and their categories and extensions): %d\n'
                  % len(direct))
        for proto in sorted(direct):
            n, containers = direct[proto]
            out.write('  %s  by %s\n' % (proto, ', '.join(sorted(containers))))
        inherited = {}
        todo = sorted(direct)
        while todo:
            p = todo.pop(0)
            for parent in protocol_parents(q.con, p):
                if parent not in direct and parent not in inherited:
                    inherited[parent] = p
                    todo.append(parent)
        out.write('protocols inherited through protocols: %d\n' % len(inherited))
        for proto in sorted(inherited):
            out.write('  %s  through %s\n' % (proto, inherited[proto]))
        q.write_status(out, 1 if found else 0, 0, 0)
        return q.exit_status(1 if found else 0)
    finally:
        q.close()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--root', default=REPO_ROOT)
    p.add_argument('--db')
    p.add_argument('--cdb')
    p.add_argument('--fragments')
    p.add_argument('--other-fragments', help='the other projects\' captures, one directory per project (default: '
                                             'tmp/codedb/other-fragments)')
    p.add_argument('--extractor')
    p.add_argument('--module-cache', help='the Objective-C side\'s compiler module cache, in place of the one the '
                                          'compile database names (default: tmp/codedb/modcache); not part of a '
                                          'unit\'s command digest, so a copy of the database can use its own')
    p.add_argument('--swift-work', help='the Swift side\'s work directory, with the compiler\'s module cache '
                                        '(DIR/modcache) (default: tmp/codedb/swift)')
    p.add_argument('--swift-reader', help='the Swift reader binary, built there when its sources changed (default: '
                                          'tmp/codedb/bin/swift_refs)')
    sub = p.add_subparsers(dest='command', required=True)
    c = sub.add_parser('cdb')
    c.add_argument('--accept-removals', action='store_true')
    u = sub.add_parser('update')
    u.add_argument('--file')
    u.add_argument('--force', action='store_true')
    u.add_argument('--accept-removals', action='store_true')
    sides = u.add_mutually_exclusive_group()
    sides.add_argument('--objc-only', action='store_true', help='update only the Objective-C units')
    sides.add_argument('--swift-only', action='store_true', help='update only the Swift side: the Swift modules '
                                                                  'and the swift_import rows')
    sides.add_argument('--imports-only', action='store_true',
                       help='update only the swift_import rows of the modules with a bridging header (what Swift '
                            'imports, swiftimports.py), not the Objective-C units or the Swift references')
    u.add_argument('--swift-module', action='append', dest='swift_modules', metavar='MODULE',
                   help='update only this Swift module (repeatable); implies --swift-only')
    u.add_argument('--accept-compiler-version', action='store_true',
                   help="read the dump of a Swift compiler whose major and minor version are not the reader's")
    sc = sub.add_parser('swift-capture', help='capture_compile_commands.sh runs this after a successful build: keep '
                                              "the build log's SwiftDriver commands and each module's file list")
    sc.add_argument('--log', required=True)
    sc.add_argument('--into', required=True)
    ad = sub.add_parser('adopt-swift-capture', help='one time only: keep the Swift inputs of a capture made before '
                                                    'captures kept them, from its build log and the file lists '
                                                    'under Build/')
    ad.add_argument('--log', help='the capture\'s build log (default: tmp/codedb/capture-build.log)')
    ad.add_argument('--accept-edited-files', action='store_true',
                    help='assert that no Swift file was added to or removed from a module since the capture, '
                         'although some listed files were modified after it')
    h = sub.add_parser('hold-lock', help='take the lock, then run a program holding it on fd 9 '
                                         '(capture_compile_commands.sh runs itself this way)')
    h.add_argument('--label', default='capture_compile_commands.sh', help='the command recorded in the lock')
    h.add_argument('program', nargs=argparse.REMAINDER)
    cr = sub.add_parser('capture-record', help="print the capture record (the project's build settings digest, the "
                                               'SDK and the date, as of now) as JSON; capture_compile_commands.sh '
                                               'runs this before its build')
    cr.add_argument('--project', metavar='NAME', help='the record of the other project NAME of other_projects.json '
                                                      '(its own build settings, and the digest of its entry)')
    sub.add_parser('other-projects', help='print the other projects of other_projects.json that are in the tree, '
                                          'one per line: name, project, configuration, targets and extra build '
                                          'settings (space-separated), separated by tabs; capture_compile_commands.sh '
                                          '--other-projects reads it')
    a = sub.add_parser('adopt-capture', help='one time only: write a capture record, from the project as it is '
                                             'now, for fragments captured before captures wrote one')
    a.add_argument('--i-know-the-project-is-unchanged-since', dest='asserted', action='store_true', required=True,
                   help='assert that the build settings have not changed since the capture was made')
    s = sub.add_parser('sends')
    s.add_argument('--update', action='store_true',
                   help='run update first (under the lock and the watchdog), then answer')
    s.add_argument('selector')
    for name, help_text in (('methods', 'where a selector is declared and defined'),
                            ('selrefs', '@selector expressions and reflective calls that resolve to a selector'),
                            ('reach', 'every way a selector is reached: sends, selrefs, key-value coding and Swift'),
                            ('swiftrefs', 'the Swift references that reach a selector')):
        q = sub.add_parser(name, help=help_text)
        q.add_argument('--update', action='store_true',
                       help='run update first (under the lock and the watchdog), then answer')
        q.add_argument('selector')
    for name, help_text, arguments in (
            ('ivars', 'the ivar table of a class: types, ownership, backing properties, reference counts',
             ('class_name',)),
            ('ivarrefs', 'every reference to one ivar of a class', ('class_name', 'ivar')),
            ('statics', 'the statics and globals a file declares or uses, or that the methods of a class use',
             ('file_or_class',)),
            ('staticrefs', 'every declaration of and reference to the statics and globals with a name', ('name',))):
        q = sub.add_parser(name, help=help_text)
        q.add_argument('--update', action='store_true',
                       help='run update first (under the lock and the watchdog), then answer')
        for a in arguments:
            q.add_argument(a)
        if name == 'staticrefs':
            q.add_argument('--per-unit', action='store_true',
                           help='also list the references of each unit (a static defined in a header has a copy in '
                                'each unit that includes it)')
    cs = sub.add_parser('classstate', help='the ivar and static table of a class (objc-state.md): types, ownership, '
                                           'importability, users and references from outside its own code')
    cs.add_argument('--update', action='store_true',
                    help='run update first (under the lock and the watchdog), then answer')
    cs.add_argument('--json', action='store_true', help='print one JSON document')
    cs.add_argument('--runtime-methods', action='append', default=[], metavar='FILE',
                    help='a run-time method list (sdk_selectors.py --runtime-methods), consulted for accessor names '
                         'that a framework superclass implements privately; repeatable. Without it, an accessor not '
                         'found in the repository or the SDK headers says private methods were not consulted')
    cs.add_argument('class_name')
    vi = sub.add_parser('verifyinventory', help="compare the inventory's parsed classes with the database, and a "
                                                'runtime snapshot with the database')
    vi.add_argument('--update', action='store_true',
                    help='run update first (under the lock and the watchdog), then answer')
    vi.add_argument('--snapshot', help='a runtime snapshot written by runtime_snapshot.sh (format 2)')
    vi.add_argument('--only-snapshot', action='store_true', help='compare only the snapshot, not the inventory')
    vi.add_argument('classes', nargs='*', metavar='CLASS')
    mc = sub.add_parser('macros', help='repository macro definitions with their facts, kinds, expansion counts and '
                                       'conflicts')
    mc.add_argument('--update', action='store_true',
                    help='run update first (under the lock and the watchdog), then answer')
    which = mc.add_mutually_exclusive_group()
    which.add_argument('--file', help='the definitions in this file (relative to the repository)')
    which.add_argument('--name', help='the definitions of this macro')
    which.add_argument('--class', dest='macro_class', choices=list(MACRO_CLASSES),
                       help='the definitions of this kind (hidden-callers.md section 6)')
    mu = sub.add_parser('macrouses', help='every expansion of a macro, or the macros a method, function or class '
                                          'expands')
    mu.add_argument('--update', action='store_true',
                    help='run update first (under the lock and the watchdog), then answer')
    mu.add_argument('name', help='a macro; or -[Class selector], +[Class selector], a function or a class')
    sk = sub.add_parser('skipped', help='the ranges of a file that some or all units do not compile, with their '
                                        'conditions')
    sk.add_argument('--update', action='store_true',
                    help='run update first (under the lock and the watchdog), then answer')
    sk.add_argument('file', help='a path relative to the repository')
    ml = sub.add_parser('macrolint', help='the lint of hidden-callers.md section 6: every macro of its kinds that the '
                                          "migration's scope defines or expands is registered in the classification "
                                          'file with a reading')
    ml.add_argument('--classification', help='the classification file (default: %s)' % CLASSIFICATION_FILE)
    ml.add_argument('--write', action='store_true',
                    help='write the classification file from the database first, keeping each reading whose '
                         'digest is unchanged and marking the rest UNREVIEWED; rows of macros this run did not see '
                         'are kept, marked %s' % NOT_SEEN_MARK)
    ml.add_argument('--prune', action='store_true',
                    help='with --write, remove the rows of macros this run did not see (refused when the database is '
                         'incomplete)')
    ml.add_argument('--allow-unreviewed', action='store_true',
                    help='do not fail on rows marked UNREVIEWED (while the reading pass is under way)')
    xc = sub.add_parser('crosscheck', help="compare each Objective-C unit's selectors sent, methods and ivars "
                                           'with its object file under Build/ (crosscheck.py)')
    xc.add_argument('--target', help='only the units of this target')
    xc.add_argument('--file', help='only the units of this file (relative to the repository)')
    xc.add_argument('--list-explained', action='store_true', help='also list every difference a rule explains')
    xc.add_argument('--build-root', action='append', metavar='DIR',
                    help='look up object files under DIR (a directory that holds Intermediates.noindex, as Build/ '
                         'does) in place of the captured location; repeat to try several in order')
    for name, help_text, argument in (
            ('sdkmethods', 'who outside the repository (the SDK) declares a selector', 'selector'),
            ('classinfo', 'the superclass chain of a class into the SDK and the protocols it adopts', 'class_name')):
        q = sub.add_parser(name, help=help_text)
        q.add_argument('--update', action='store_true',
                       help='run update first (under the lock and the watchdog), then answer')
        q.add_argument(argument)
    si = sub.add_parser('swiftimports', help='how Swift imports Objective-C declarations through a bridging header, '
                                             'and the reason for each it does not import (swiftimports.py)')
    si.add_argument('--update', action='store_true',
                    help='run update first (under the lock and the watchdog), then answer')
    si.add_argument('--module', help='the Swift module whose bridging header (default: the only one)')
    form = si.add_mutually_exclusive_group(required=True)
    form.add_argument('name', nargs='?', help='a selector, -[Class sel], Class.property, a class, global or macro '
                                              'name, a Swift name, or a USR')
    form.add_argument('--header', help='every declaration the database has for this header (relative to the '
                                       'repository), imported or not')
    form.add_argument('--not-importable', metavar='CLASS',
                      help='the declarations of a class or protocol that Swift does not import, with the reason')
    r = sub.add_parser('reflective', help='reflective call sites, grouped by file; by default those whose argument '
                                          'is dynamic')
    r.add_argument('--update', action='store_true',
                   help='run update first (under the lock and the watchdog), then answer')
    shown = r.add_mutually_exclusive_group()
    shown.add_argument('--dynamic', action='store_true', help='only sites whose argument is dynamic (the default)')
    shown.add_argument('--all', action='store_true', help='every site, whatever its argument')
    r.add_argument('--kind', choices=REFLECTIVE_KINDS, help='only sites whose argument names this')
    r.add_argument('--list', action='store_true', help='print the table of recognized calls and exit')
    args = p.parse_args(argv)
    paths = Paths(args.root, db=args.db, cdb=args.cdb, fragments=args.fragments, extractor=args.extractor,
                  swift_reader=args.swift_reader, swift_work=args.swift_work, module_cache=args.module_cache,
                  other_fragments=args.other_fragments)
    # SIGTERM and SIGHUP unwind like Ctrl-C, so that the lock is released and
    # a running extraction's process group is killed.
    previous = {}
    if argv is None:
        for sig in (signal.SIGTERM, signal.SIGHUP):
            previous[sig] = signal.signal(sig, on_terminate)
    try:
        if args.command == 'cdb':
            with Lock(paths.lock, 'codedb.py cdb'):
                build_cdb_for(paths, accept_removals=args.accept_removals)
                return 1 if check_cdb_against_project(paths.root, paths.cdb, other_projects=default_other_projects(
                    paths.root, paths.other_spec)) else 0
        if args.command == 'update':
            return update(paths, only_file=args.file, force=args.force, accept_removals=args.accept_removals,
                          log=lambda m: print(m, flush=True),
                          objc=not (args.swift_only or args.swift_modules or args.imports_only),
                          swift=not (args.objc_only or args.imports_only),
                          accept_compiler_version=args.accept_compiler_version, swift_modules=args.swift_modules,
                          imports=not args.objc_only)
        if args.command == 'swift-capture':
            try:
                swiftdb.write_swift_capture(args.log, args.into,
                                            project_swift=project_swift_sources(os.path.realpath(args.root)))
            except (swiftdb.CaptureError, OSError) as e:
                raise CodeDBError(str(e))
            return 0
        if args.command == 'adopt-swift-capture':
            with Lock(paths.lock, 'codedb.py adopt-swift-capture'):
                try:
                    swiftdb.adopt_swift_capture(paths.fragments, args.log or os.path.join(
                        os.path.dirname(paths.cdb), 'capture-build.log'), accept_edited=args.accept_edited_files)
                except swiftdb.CaptureError as e:
                    raise CodeDBError(str(e))
            return 0
        if args.command == 'hold-lock':
            return hold_lock_and_exec(paths, args.label, args.program)
        if args.command == 'capture-record':
            if args.project:
                found = [x for x in read_other_projects(paths.other_spec) if x.name == args.project]
                if not found:
                    raise CodeDBError('no other project %s in %s' % (args.project, paths.other_spec))
                print(json.dumps(other_capture_record(paths.root, found[0])))
            else:
                print(json.dumps(capture_record(paths.root)))
            return 0
        if args.command == 'other-projects':
            spec = read_other_projects(paths.other_spec)
            for x, d in absent_other_projects(paths.root, spec):
                print('%s: not captured: %s is not checked out here' % (x.name, d), file=sys.stderr)
            for x in present_other_projects(paths.root, spec):
                if stale_copy_differs(paths.root, x):
                    print('warning: %s differs from %s (the project captured for %s); it is not what the app '
                          'embeds' % (x.stale_copy, os.path.dirname(x.project), x.name), file=sys.stderr)
                print('\t'.join((x.name, x.project, x.configuration, ' '.join(x.targets), ' '.join(x.settings))))
            return 0
        if args.command == 'adopt-capture':
            with Lock(paths.lock, 'codedb.py adopt-capture'):
                adopt_capture(paths)
            return 0
        if args.command == 'reflective' and args.list:
            sys.stdout.write(reflective_table(paths))
            return 0
        if args.command == 'crosscheck':
            import crosscheck
            return crosscheck.crosscheck(sys.modules[__name__], paths, target=args.target, file=args.file,
                                         list_explained=args.list_explained, build_roots=args.build_root)
        if args.command == 'macrolint':
            return macrolint(paths, classification=args.classification, write=args.write,
                             allow_unreviewed=args.allow_unreviewed, prune=args.prune)
        if args.command in ('classstate', 'verifyinventory'):
            if args.update:
                update(paths, log=lambda m: print(m, file=sys.stderr, flush=True))
            if args.command == 'classstate':
                import classstate
                return classstate.classstate(sys.modules[__name__], paths, args.class_name, as_json=args.json,
                                             runtime_methods=args.runtime_methods)
            import verify_inventory
            return verify_inventory.verifyinventory(sys.modules[__name__], paths, classes=args.classes,
                                                    snapshot=args.snapshot, only_snapshot=args.only_snapshot)
        if args.command == 'swiftimports':
            if args.update:
                update(paths, log=lambda m: print(m, file=sys.stderr, flush=True))
            return swiftimports(paths, name=args.name, header=args.header, not_importable=args.not_importable,
                                module=args.module)
        if args.command in ('sends', 'methods', 'selrefs', 'reach', 'reflective', 'swiftrefs', 'ivars', 'ivarrefs',
                            'statics', 'staticrefs', 'macros', 'macrouses', 'skipped', 'sdkmethods', 'classinfo'):
            if args.update:
                # Progress goes to stderr so that stdout is only the answer.
                # Failed units are reported by the answer's status block.
                update(paths, log=lambda m: print(m, file=sys.stderr, flush=True))
            if args.command == 'reflective':
                return reflective(paths, everything=args.all, kind=args.kind)
            if args.command == 'ivars':
                return ivars(paths, args.class_name)
            if args.command == 'ivarrefs':
                return ivarrefs(paths, args.class_name, args.ivar)
            if args.command == 'statics':
                return statics(paths, args.file_or_class)
            if args.command == 'staticrefs':
                return staticrefs(paths, args.name, per_unit=args.per_unit)
            if args.command == 'macros':
                return macros(paths, file=args.file, name=args.name, cls=args.macro_class)
            if args.command == 'macrouses':
                return macrouses(paths, args.name)
            if args.command == 'skipped':
                return skipped(paths, args.file)
            if args.command == 'sdkmethods':
                return sdkmethods(paths, args.selector)
            if args.command == 'classinfo':
                return classinfo(paths, args.class_name)
            return {'sends': sends, 'methods': methods, 'selrefs': selrefs, 'reach': reach,
                    'swiftrefs': swiftrefs}[args.command](
                paths, args.selector)
    except (CodeDBError, sqlite3.Error, OSError, subprocess.CalledProcessError) as e:
        print('codedb: error: %s' % e, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print('codedb: interrupted', file=sys.stderr)
        return 130
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    return 2


if __name__ == '__main__':
    sys.exit(main())
