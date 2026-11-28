# An OSC or APC string longer than 1 MiB is cut off and the rest is printed as text

**Where:** `sources/VT100/VT100XtermParser.m`, `+parseNextCharsInStringFromContext:...` (near line 256).

**What happens:** the parser stops collecting an OSC or APC string at 1,048,576 bytes and ends the sequence there. The bytes that follow, up to and including the string terminator, are then parsed as ordinary output and appear on screen as a wall of base64 or other text. Any program that sends one long string is affected: for example a kitty graphics command sent without chunking (the protocol asks remote clients to chunk at 4096 bytes, so well-behaved clients do not hit this), or a large OSC 52 clipboard write. iTerm2's own `OSC 1337 ; File=` images are not affected, because they are parsed as a header followed by separate parts.

**Why:**

```objc
const NSUInteger maxLength = 1048576;
if (data.length >= maxLength) {
    DLog(@"Truncate very long OSC");
    nextState = kXtermParserFinishedState;
}
```

The limit is reasonable; ending the sequence instead of discarding the rest of it is the problem.

**How to see it:** `printf '\e]52;c;%s\a' "$(head -c 900000 /dev/zero | base64)"` should print the tail of the base64 text into the session. Seen by reading the code; not run.

**Suggested fix:** once the limit is reached, keep consuming bytes without storing them until the string terminator, and then drop the sequence (or deliver it truncated, as now, but without printing the rest).

**Found:** 2026-11-21, hardening of the kitty graphics protocol, and its review.

**Checked against the tree:** 2026-11-27. The limit and the transition to the finished state are unchanged.
