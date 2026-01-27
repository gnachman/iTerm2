#!/usr/sbin/dtrace -s

/* DTrace script for iTerm2 performance metrics - CSV output for parsing */

#pragma D option quiet

dtrace:::BEGIN
{
    start = timestamp;
}

objc$target:PTYSession:-updateDisplayBecause*:entry
{
    @updates = count();
}

objc$target:PTYTextView:-refresh:entry
{
    @refreshes = count();
}

objc$target:VT100Screen*:-sync*:entry
{
    @syncs = count();
}

dtrace:::END
{
    duration_sec = (timestamp - start) / 1000000000;

    /* Output CSV format: duration,updates,refreshes,syncs */
    printa("%d,", @updates);
    printa("%d,", @refreshes);
    printa("%d\n", @syncs);

    /* Also output human-readable summary to stderr */
    printf("duration_sec=%d\n", duration_sec);
}
