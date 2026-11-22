# iTermColorSuggester (light path)

**What it is.** `sources/TryingTooHard/iTermColorSuggester.{h,m}`, 74 lines.
An `NSObject` whose initializer picks a seeded random text and background
color pair in L\*a\*b\*: `srand48(seed)` on the process-wide generator, two
`drand48` draws per attempt (lightness folded away from 50, hue angle), text
from them, background from the complementary lightness and the angle plus
pi/2, both clamped to sRGB by a round trip, retried until the background's
lightness is `minimumDifference` from the default background's. The default
text color is ignored. Results are two readonly properties.

**Who uses it.** Only `PTYSession.m:16431`,
`-openAddTriggerViewControllerWithText:` (seed `[text hash]`, minimum 0.25,
colors from `-[iTermColorMap colorForKey:]`, unannotated, nil for a missing
key). Reached from `-textViewAddTrigger:` (text view context menu,
PseudoTerminal `addTrigger:`) and `-addTrigger`: UI actions, main thread.
`codedb.py sends` and `reach`: one send of the initializer, one per getter.

**Qualifying checks** (`tmp/pilot2/qualify.py iTermColorSuggester
--max-lines 150`, exit 0): PASS size 74; PASS outside users 1; PASS no xib,
storyboard, sdef, plist, json, strings, model; PASS not in
reflective-sites.md; PASS no class-name strings, KVC or KVO; PASS no C++,
`+load`, `+initialize`, associated object, swizzling, atomic property,
`-dealloc`; PASS no lock, queue, thread API; PASS no defaults, profile,
arrangement, file; PASS not hot; MANUAL caller thread: main, as above.

**Objective-C interface** (`NS_ASSUME_NONNULL`).
`@property (nonatomic, readonly) NSColor *suggestedTextColor;` and
`suggestedBackgroundColor`;
`-initWithDefaultTextColor:defaultBackgroundColor:minimumDifference:seed:`
(`NSColor *`, `NSColor *`, `CGFloat`, `long`), designated; `-init`
`NS_UNAVAILABLE`.

**Planned Swift.** `@objc(iTermColorSuggester) class iTermColorSuggester:
NSObject` with `@objc let suggestedTextColor: NSColor`, likewise the
background, and
`@objc(initWithDefaultTextColor:defaultBackgroundColor:minimumDifference:seed:)
init(defaultTextColor: NSColor?, defaultBackgroundColor: NSColor?,
minimumDifference: CGFloat, seed: Int)`. The colors become nullable because
the Objective-C messaged a nil background (zero struct, lightness 0) and the
caller can pass nil. No `init()`. A main-thread `it_betaAssert` at entry.
No integer arithmetic. `srand48`/`drand48` kept: the shared state is
observable.

**Tests.** `ModernTests/iTermColorSuggesterTests.swift`: golden sRGB values
(4 cases); same inputs same colors, different seeds different; the default
text color is ignored; background lightness at least the minimum from the
default (black, white, gray; 20 seeds); one attempt takes exactly two
`drand48` numbers after reseeding; results in gamut and opaque.
`ModernTests/iTermColorSuggesterNilTests.m` (class declared locally): nil
background acts as black; nil text color accepted.

**Open questions.** A minimum the default leaves no room for (1 or more, or
over about 0.46 on gray) never terminates; preserved, untested.
`-[NSColor labColor]` swaps green and blue (bugs.md); not this unit's code.
