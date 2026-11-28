# On Intel Macs the app always believes the fn key is up

**Intel only.** On Apple silicon the code gives the right answer.

**Where:** `sources/AppKit/iTermApplication.m`, `-handleFlagsChangedEvent:` (near line 720).

**What happens:** `_functionPressed` is always NO on x86_64. It feeds `it_functionModifierPreviouslyPressed` (read by `iTermModernKeyMapper` when it reports key events), `it_functionModifierPressed` on later key events, `-[iTermModifierRemapper physicalFnKeyDown]` and `-it_functionPressed`. So on Intel every use of the fn key's state through these is wrong, on every press of fn.

**Why:**

```objc
_functionPressed = event.modifierFlags & NSEventModifierFlagFunction;
```

On x86_64 `BOOL` is `signed char`. The flag is bit 23, and converting the masked value to `signed char` keeps only the low byte, which is always zero. On arm64 `BOOL` is `bool` and any nonzero value becomes YES. The compiled x86_64 code is `xorl %eax,%eax`.

**How to see it:** compile `BOOL f(unsigned long x) { return x & (1UL << 23); }` for `x86_64-apple-macos13.0` and read the assembly. Not run on Intel hardware.

**Suggested fix:** `_functionPressed = (event.modifierFlags & NSEventModifierFlagFunction) != 0;`

**Found:** 2026-11-20, by a survey of compiler warnings (`-Wobjc-signed-char-bool`) and the generated code.

**Checked against the tree:** 2026-11-27. The assignment is unchanged near line 720 of `iTermApplication.m`.
