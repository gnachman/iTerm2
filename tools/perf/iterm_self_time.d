#!/usr/sbin/dtrace -s
/*
 * iTerm2 Self-Time Profiler
 *
 * Uses DTrace profile provider to sample the stack at fixed intervals.
 * Aggregates by the bottom frame (actual executing function) to get self-time.
 * This shows which functions actually burn CPU, not just which are high in
 * the call stack.
 *
 * Usage: sudo dtrace -p PID -s iterm_self_time.d [DURATION_SECONDS]
 *        Duration defaults to 0 (run until Ctrl-C)
 *
 * Output:
 *   - Top self-time functions (functions spending the most CPU time themselves)
 *   - Top call stacks (for understanding execution context)
 */

#pragma D option quiet
#pragma D option ustackframes=100
#pragma D option bufsize=16m

dtrace:::BEGIN
{
    start = timestamp;
    seconds = 0;
    duration = $1 > 0 ? $1 : 0;
    printf("Sampling iTerm2 self-time at 997Hz...\n");
    printf("Duration: %s\n", duration > 0 ? "$$1 seconds" : "until Ctrl-C");
    printf("Press Ctrl-C to stop and see results.\n\n");
}

tick-1sec
{
    seconds++;
    printf("\r  Elapsed: %d sec", seconds);
}

tick-1sec
/duration > 0 && seconds >= duration/
{
    exit(0);
}

/*
 * Profile at 997Hz (prime number to avoid aliasing with periodic events).
 * Only sample when the target process is on-CPU.
 *
 * ustack(1) captures just the currently executing function - this is
 * what gives us "self time" since it's the function actually on CPU
 * when the sample fires.
 */
profile-997
/pid == $target/
{
    /* Count by single bottom frame for self-time */
    @self_time[ustack(1)] = count();

    /* Also collect deeper stacks for context (top 15 frames) */
    @stacks[ustack(15)] = count();
}

dtrace:::END
{
    duration_ns = timestamp - start;
    duration_sec = duration_ns / 1000000000;

    printf("\n\n");
    printf("============================================================\n");
    printf("iTerm2 Self-Time Profile\n");
    printf("============================================================\n");
    printf("Duration: %d seconds (997Hz sampling)\n", duration_sec);
    printf("\n");

    printf("--- TOP SELF-TIME FUNCTIONS ---\n");
    printf("(Functions that spend the most CPU time in their own code,\n");
    printf(" not counting time in functions they call)\n\n");

    /* Show top 40 self-time entries */
    trunc(@self_time, 40);
    printa(@self_time);

    printf("\n--- TOP CALL STACKS ---\n");
    printf("(Most frequent execution paths for context)\n\n");

    /* Show top 15 full stacks */
    trunc(@stacks, 15);
    printa(@stacks);

    printf("\n============================================================\n");
    printf("Interpretation:\n");
    printf("  - High self-time = function does significant work itself\n");
    printf("  - Filter out: objc_msgSend, malloc/free (see analyze_self_time.py)\n");
    printf("  - Focus on: iTerm2/PTY/VT100/Metal symbols for optimization\n");
    printf("============================================================\n");
}
