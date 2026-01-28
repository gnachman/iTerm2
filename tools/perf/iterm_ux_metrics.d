#!/usr/sbin/dtrace -s

/*
 * User-experience focused metrics for iTerm2:
 * 1. Apparent frame rate - how often does the user see updated content?
 * 2. Latency - time from data sync to frame display
 * 3. Lock contention - time wasted waiting for locks
 */

#pragma D option quiet

dtrace:::BEGIN
{
    start = timestamp;
    printf("Tracing iTerm2 UX metrics... Ctrl-C to stop.\n");

    /* For latency tracking */
    last_sync_time = 0;

    /* For contention tracking */
    total_lock_wait_ns = 0;
    lock_acquisitions = 0;
}

/* ============================================================
 * 1. APPARENT FRAME RATE
 * Count actual frames handed to GPU for display
 * ============================================================ */

objc$target:iTermMetalFrameData:-willHandOffToGPU:entry
{
    @frames = count();
}

/* Also track drawRect for non-Metal path */
objc$target:PTYTextView:-drawRect?:entry
{
    @drawrect_frames = count();
}

/* ============================================================
 * 2. LATENCY - Time from data arrival to display
 * Track sync -> frame handoff timing
 * ============================================================ */

/* Record when sync happens (data is ready) */
objc$target:VT100Screen*:-sync*:entry
{
    self->sync_start = timestamp;
}

objc$target:VT100Screen*:-sync*:return
{
    last_sync_time = timestamp;
    @syncs = count();
}

/* Measure time from last sync to frame handoff */
objc$target:iTermMetalFrameData:-willHandOffToGPU:entry
/last_sync_time > 0/
{
    this->latency_ns = timestamp - last_sync_time;
    @latency_avg = avg(this->latency_ns);
    @latency_min = min(this->latency_ns);
    @latency_max = max(this->latency_ns);
    /* Histogram in milliseconds */
    @latency_hist = quantize(this->latency_ns / 1000000);
}

/* ============================================================
 * 3. LOCK CONTENTION - Time wasted waiting for locks
 * ============================================================ */

pid$target:libsystem_pthread.dylib:pthread_mutex_lock:entry
{
    self->lock_entry = timestamp;
}

pid$target:libsystem_pthread.dylib:pthread_mutex_lock:return
/self->lock_entry/
{
    this->wait_time = timestamp - self->lock_entry;
    /* Only count if we actually waited (> 1us suggests contention) */
    @lock_wait_total = sum(this->wait_time);
    @lock_calls = count();
    /* Track waits > 100us as "significant" contention */
    @significant_waits = sum(this->wait_time > 100000 ? 1 : 0);
    @significant_wait_time = sum(this->wait_time > 100000 ? this->wait_time : 0);
    self->lock_entry = 0;
}

/* ============================================================
 * Also track joined threads blocks (known contention point)
 * ============================================================ */

objc$target:VT100ScreenMutableState:-performBlockWithJoinedThreads*:entry
{
    self->joined_entry = timestamp;
    @joined_calls = count();
}

objc$target:VT100ScreenMutableState:-performBlockWithJoinedThreads*:return
/self->joined_entry/
{
    this->joined_time = timestamp - self->joined_entry;
    @joined_time_total = sum(this->joined_time);
    @joined_time_avg = avg(this->joined_time);
    self->joined_entry = 0;
}

/* ============================================================
 * OUTPUT
 * ============================================================ */

dtrace:::END
{
    duration_ns = timestamp - start;
    duration_sec = duration_ns / 1000000000;
    duration_ms = duration_ns / 1000000;

    printf("\n");
    printf("============================================================\n");
    printf("iTerm2 UX Metrics (duration: %d sec)\n", duration_sec);
    printf("============================================================\n");

    printf("\n--- APPARENT FRAME RATE ---\n");
    printa("  Metal frames:        %@d\n", @frames);
    printa("  drawRect frames:     %@d\n", @drawrect_frames);

    printf("\n--- LATENCY (sync -> frame) ---\n");
    printa("  Syncs:               %@d\n", @syncs);
    printa("  Avg latency:         %@d ns\n", @latency_avg);
    printa("  Min latency:         %@d ns\n", @latency_min);
    printa("  Max latency:         %@d ns\n", @latency_max);
    printf("\n  Latency distribution (ms):\n");
    printa("%@d\n", @latency_hist);

    printf("\n--- LOCK CONTENTION ---\n");
    printa("  Total lock calls:    %@d\n", @lock_calls);
    printa("  Total wait time:     %@d ns\n", @lock_wait_total);
    printa("  Significant waits:   %@d (>100us)\n", @significant_waits);
    printa("  Significant time:    %@d ns\n", @significant_wait_time);

    printf("\n--- JOINED THREADS (sync contention) ---\n");
    printa("  Joined block calls:  %@d\n", @joined_calls);
    printa("  Total joined time:   %@d ns\n", @joined_time_total);
    printa("  Avg joined time:     %@d ns\n", @joined_time_avg);

    printf("\n--- RATES ---\n");
    normalize(@frames, duration_sec);
    normalize(@syncs, duration_sec);
    printa("  Frames/sec:          %@d\n", @frames);
    printa("  Syncs/sec:           %@d\n", @syncs);
}
