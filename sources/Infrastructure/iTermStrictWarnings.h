//
//  iTermStrictWarnings.h
//  iTerm2
//
//  The strict warning set of the Objective-C to Swift migration
//  (docs/swift-migration/warnings.md). An implementation file (.m, .mm or .c)
//  that is being prepared for porting imports this header as its LAST import:
//
//      #import "iTermStrictWarnings.h"
//
//  Each line below turns one warning on as an error. A diagnostic pragma
//  stays in effect after the header that contains it ends, so the flags apply
//  to the rest of the importing file and to nothing else: not to headers
//  imported before this one (their inline functions and declarations are not
//  diagnosed), but to every header imported after it, which is why it must
//  be the last import. Code from macros defined elsewhere is diagnosed where
//  the macro is expanded, so a macro expanded in the importing file is held
//  to these flags.
//
//  Never import this from a header: its pragmas would then apply to every
//  file that imports that header. The check below makes that an error.
//
//  The flags are the candidate strict set of warnings.md step 3, pending the
//  triage of the warning survey (step 2); a flag moved to the project-wide
//  group or to report-only is removed here. The static analyzer, also on that
//  list, is not a compiler warning and cannot be turned on by a pragma.
//  tools/swift_migration/warning_survey.py reads its flag list from this
//  file, so this is the only place the strict set is written; run
//  `warning_survey.py file <path>` to list what a file must fix first.
//

#if __INCLUDE_LEVEL__ != 1
#error "iTermStrictWarnings.h must be imported directly by an implementation file, as its last import, never by a header"
#endif

// Implicit conversions: each one becomes an explicit cast before the port.
#pragma clang diagnostic error "-Wconversion"
#pragma clang diagnostic error "-Wshorten-64-to-32"
#pragma clang diagnostic error "-Wsign-conversion"
#pragma clang diagnostic error "-Wfloat-conversion"
#pragma clang diagnostic error "-Wimplicit-float-conversion"
#pragma clang diagnostic error "-Wimplicit-int-conversion"
#pragma clang diagnostic error "-Wsign-compare"
#pragma clang diagnostic error "-Wobjc-signed-char-bool"

// Comparisons whose result is fixed by the types.
#pragma clang diagnostic error "-Wtautological-compare"
#pragma clang diagnostic error "-Wtautological-constant-in-range-compare"

// Messages and selectors the compiler cannot check.
#pragma clang diagnostic error "-Wobjc-messaging-id"
#pragma clang diagnostic error "-Wstrict-selector-match"
#pragma clang diagnostic error "-Wselector"

// Properties.
#pragma clang diagnostic error "-Wimplicit-atomic-properties"
#pragma clang diagnostic error "-Wobjc-property-assign-on-object-type"

// Enums.
#pragma clang diagnostic error "-Wswitch-enum"
#pragma clang diagnostic error "-Wassign-enum"

// Values and lifetimes.
#pragma clang diagnostic error "-Wconditional-uninitialized"
#pragma clang diagnostic error "-Warc-repeated-use-of-weak"
#pragma clang diagnostic error "-Wnullable-to-nonnull-conversion"

// Everything else on the candidate list.
#pragma clang diagnostic error "-Wformat-nonliteral"
#pragma clang diagnostic error "-Wcast-qual"
#pragma clang diagnostic error "-Wshadow"
#pragma clang diagnostic error "-Wfloat-equal"
