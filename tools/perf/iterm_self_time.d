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
 * Output format (machine-parseable):
 *   Section markers: ===SECTION_NAME===
 *   Each entry: stack frames (one per line), then count on its own line
 *   Frame format: module`symbol+offset
 *   Count format: whitespace + number
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
    printf("===HEADER===\n");
    printf("duration_sec=%d\n", duration_sec);
    printf("sample_hz=997\n");
    printf("===END_HEADER===\n");

    printf("\n===SELF_TIME===\n");
    /* Show top 50 self-time entries */
    trunc(@self_time, 50);
    printa(@self_time);
    printf("===END_SELF_TIME===\n");

    printf("\n===STACKS===\n");
    /* Show top 20 full stacks */
    trunc(@stacks, 20);
    printa(@stacks);
    printf("===END_STACKS===\n");
}
