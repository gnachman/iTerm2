# Logging or printing a parsed expression made from a missing string aborts the app

**Where:** `sources/Language/iTermParsedExpression.m`, `-string` (near line 312) and `-description`, which calls `-string` for a string expression; the nil comes from `+[iTermExpressionParser parsedExpressionWithInterpolatedString:...]` (`iTermExpressionParser.m`, the all-literals return near line 403).

**What happens:** when the parser is given a nil interpolated string, as it is for semantic history's script in a profile where it was never edited (`iTermSemanticHistoryController.m`), it returns a string expression holding nil. `-object`, declared nonnull, returns nil for it, and `-string` and `-description` abort, since assertions are on in release builds. No live path calls them today: the evaluator reads `-object`, and the only log that would print the expression, `NSLog(@"Evaluate %@", _parsedExpression)` in `-[iTermExpressionEvaluator reallyEvaluateWithTimeout:...]`, runs only when the evaluator's `debug` property is set, which nothing sets. Adding a `DLog` of the expression, or turning that debug flag on, would crash the app. Printing it in the debugger aborts now.

**Why:**

```objc
return [[iTermParsedExpression alloc] initWithString:[swifty it_stringByExpandingBackslashEscapedCharacters]];
```

is nil when `swifty` is nil, and `-string` begins with `assert([_object isKindOfClass:[NSString class]])`.

**How to see it:** in a test, `[[iTermParsedExpression alloc] initWithString:nil].description` aborts. Seen by reading the code; not run.

**Suggested fix:** make the parser return its nil (empty) expression for a nil interpolated string, or make `-string` and `-description` tolerate nil.

**Found:** 2026-11-20, review of the nullability work on the expression language.

**Checked against the tree:** 2026-11-27. The assert in `-string` and the all-literals return in the parser are unchanged.
