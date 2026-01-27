#!/usr/sbin/dtrace -s

/*
 * iTerm2 UX Metrics - User-focused performance measurement
 *
 * Measures:
 * 1. Update cadence - UI refresh rate from cadence controller
 * 2. Latency - time from PTY read to refresh (approximate)
 * 3. Lock contention - time in performBlockWithJoinedThreads
 *
 * Usage: dtrace -s script.d DURATION -p PID
 * Pass DURATION=0 for no auto-exit (Ctrl-C to stop).
 */

#pragma D option quiet

dtrace:::BEGIN {
    start = timestamp;
    seconds = 0;
    printf("Tracing iTerm2 UX metrics... Ctrl-C to stop.\n");
}

tick-1sec {
    seconds++;
}

tick-1sec
/$1 > 0 && seconds >= $1/ {
    exit(0);
}

/* ============================================================
 * 1. UPDATE CADENCE
 * Count content changes vs cadence-driven refreshes
 * ============================================================ */

/* Content actually changed (lines marked dirty) */
objc$target:PTYTextView:-setNeedsDisplayOnLine*:entry {
    @content_frames = count();
}

/* Total refresh calls (cadence-driven) */
objc$target:PTYTextView:-refresh:entry {
    @refreshes = count();
}

/* Metal frames handed to GPU */
objc$target:iTermMetalFrameData:-willHandOffToGPU:entry {
    @metal_frames = count();
}

/* ============================================================
 * 2. ADAPTIVE FRAME RATE MODE
 * See which cadence path is being used
 * ============================================================ */

objc$target:iTermUpdateCadenceController:-fastAdaptiveInterval:entry {
    @["60fps mode"] = count();
}

objc$target:iTermUpdateCadenceController:-slowAdaptiveInterval*:entry {
    @["30fps mode"] = count();
}

objc$target:iTermUpdateCadenceController:-backgroundInterval:entry {
    @["1fps mode"] = count();
}

/* ============================================================
 * 3. LATENCY (approximate)
 * Time from PTY read to next refresh
 * ============================================================ */

objc$target:PTYTask:-readTask*:entry {
    self->read_time = timestamp;
}

objc$target:PTYTextView:-refresh:return
/self->read_time/ {
    this->lat = timestamp - self->read_time;
    @latency_avg = avg(this->lat);
    @latency_min = min(this->lat);
    @latency_max = max(this->lat);
    self->read_time = 0;
}

/* ============================================================
 * 4. LOCK CONTENTION - Joined threads
 * Time spent with mutation queue paused
 * ============================================================ */

/* VT100Screen has the joined threads methods */
objc$target:VT100Screen:-performBlockWithJoinedThreads*:entry {
    self->join_start = timestamp;
}

objc$target:VT100Screen:-performBlockWithJoinedThreads*:return
/self->join_start/ {
    this->jt = timestamp - self->join_start;
    @join_time_total = sum(this->jt);
    @join_time_avg = avg(this->jt);
    @join_calls = count();
    self->join_start = 0;
}

/* Also track lightweight variant */
objc$target:VT100Screen:-performLightweightBlockWithJoinedThreads*:entry {
    self->light_join_start = timestamp;
}

objc$target:VT100Screen:-performLightweightBlockWithJoinedThreads*:return
/self->light_join_start/ {
    this->ljt = timestamp - self->light_join_start;
    @light_join_time = sum(this->ljt);
    @light_join_calls = count();
    self->light_join_start = 0;
}

/* ============================================================
 * 5. SYNC OPERATIONS
 * ============================================================ */

objc$target:VT100Screen*:-synchronize*:entry {
    @syncs = count();
}

/* ============================================================
 * 6. FAIRNESS SCHEDULER
 * These only fire when FairnessScheduler is active (not legacy path)
 * Swift methods require pid provider, not objc provider
 * ============================================================ */

pid$target:iTerm2:*FairnessScheduler?register*:entry {
    @fairness_register = count();
}

pid$target:iTerm2:*FairnessScheduler?sessionDidEnqueueWork*:entry {
    @fairness_enqueue = count();
}

pid$target:iTerm2:*TokenExecutor?executeTurn*:entry {
    @fairness_execute_turn = count();
}

/* ============================================================
 * OUTPUT
 * ============================================================ */

dtrace:::END {
    duration_ns = timestamp - start;
    duration_sec = duration_ns / 1000000000;

    printf("\n");
    printf("============================================================\n");
    printf("iTerm2 UX Metrics (duration: %d sec)\n", duration_sec);
    printf("============================================================\n");

    printf("\n--- UPDATE CADENCE ---\n");
    printa("  Content frames (setNeedsDisplay): %@d\n", @content_frames);
    printa("  Total refreshes (cadence):        %@d\n", @refreshes);
    printa("  Metal frames (GPU):               %@d\n", @metal_frames);

    printf("\n--- ADAPTIVE MODE ---\n");
    printa("  %s calls: %@d\n", @);

    printf("\n--- LATENCY (PTY read -> refresh) ---\n");
    printa("  Avg: %@d ns\n", @latency_avg);
    printa("  Min: %@d ns\n", @latency_min);
    printa("  Max: %@d ns\n", @latency_max);

    printf("\n--- JOINED THREAD CONTENTION ---\n");
    printa("  Full join calls:      %@d\n", @join_calls);
    printa("  Full join total time: %@d ns\n", @join_time_total);
    printa("  Full join avg time:   %@d ns\n", @join_time_avg);
    printa("  Light join calls:     %@d\n", @light_join_calls);
    printa("  Light join time:      %@d ns\n", @light_join_time);

    printf("\n--- SYNC OPERATIONS ---\n");
    printa("  Syncs: %@d\n", @syncs);

    printf("\n--- FAIRNESS SCHEDULER (0 = legacy path) ---\n");
    printa("  Register calls:         %@d\n", @fairness_register);
    printa("  SessionDidEnqueueWork:  %@d\n", @fairness_enqueue);
    printa("  ExecuteTurn calls:      %@d\n", @fairness_execute_turn);

    printf("\n--- RATES ---\n");
    normalize(@content_frames, duration_sec);
    normalize(@refreshes, duration_sec);
    normalize(@metal_frames, duration_sec);
    printa("  Content frames/sec: %@d\n", @content_frames);
    printa("  Refreshes/sec:      %@d\n", @refreshes);
    printa("  Metal frames/sec:   %@d\n", @metal_frames);

    printf("\n--- EFFICIENCY ---\n");
    printf("  (Content frames / Refreshes = how often refresh found new content)\n");
}
