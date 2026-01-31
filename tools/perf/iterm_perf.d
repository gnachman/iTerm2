#!/usr/sbin/dtrace -s

#pragma D option quiet

dtrace:::BEGIN
{
    printf("Tracing iTerm2 performance... Ctrl-C to stop.\n");
    start = timestamp;
}

objc$target:PTYSession:-updateDisplayBecause*:entry
{
    @updates = count();
}

objc$target:PTYSession:-refresh:entry
{
    @refreshes = count();
}

objc$target:PTYTextView:-refresh:entry
{
    @textview_refreshes = count();
}

objc$target:VT100Screen*:-sync*:entry
{
    @syncs = count();
}

objc$target:VT100ScreenMutableState:-performBlockWithJoinedThreads*:entry
{
    @joined_blocks = count();
}

dtrace:::END
{
    duration_sec = (timestamp - start) / 1000000000;
    printf("\n============================================================\n");
    printf("DTrace Performance Summary (duration: %d sec)\n", duration_sec);
    printf("============================================================\n");

    printa("  updateDisplayBecause:   %@d calls\n", @updates);
    printa("  PTYSession refresh:     %@d calls\n", @refreshes);
    printa("  PTYTextView refresh:    %@d calls\n", @textview_refreshes);
    printa("  VT100Screen sync:       %@d calls\n", @syncs);
    printa("  joinedThreads blocks:   %@d calls\n", @joined_blocks);

    normalize(@updates, duration_sec);
    normalize(@refreshes, duration_sec);
    normalize(@textview_refreshes, duration_sec);
    normalize(@syncs, duration_sec);

    printf("\nRates:\n");
    printa("  updateDisplay/sec:      %@d\n", @updates);
    printa("  PTYSession refresh/sec: %@d\n", @refreshes);
    printa("  PTYTextView refresh/sec:%@d\n", @textview_refreshes);
    printa("  sync/sec:               %@d\n", @syncs);
}
