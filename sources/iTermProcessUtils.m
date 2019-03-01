const int kNumFileDescriptorsToDup = NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER;

void iTermFileDescriptorServerLog(char *format, ...) {
    va_list args;
    va_start(args, format);
    char temp[1000];
    snprintf(temp, sizeof(temp) - 1, "%s(%d) %s", gRunningServer ? "Server" : "ParentServer", getpid(), format);
    vsyslog(LOG_DEBUG, temp, args);
    va_end(args);
}

void iTermFileDescriptorServerLogError(char *format, ...) {
    va_list args;
    va_start(args, format);
    char temp[1000];
    snprintf(temp, sizeof(temp) - 1, "%s(%d) %s", gRunningServer ? "Server" : "ParentServer", getpid(), format);
    vsyslog(LOG_ERR, temp, args);
    va_end(args);
}

// Like login_tty but makes fd 0 the master, fd 1 the slave, fd 2 an open unix-domain socket
// for transferring file descriptors, and fd 3 the write end of a pipe that closes when the server
// dies.
// IMPORTANT: This runs between fork and exec. Careful what you do.
void MyLoginTTY(int master, int slave, int serverSocketFd, int deadMansPipeWriteEnd) {
    setsid();
    ioctl(slave, TIOCSCTTY, NULL);

    // This array keeps track of which file descriptors are in use and should not be dup2()ed over.
    // It has |inuseCount| valid elements. inuse must have inuseCount + arraycount(orig) elements.
    int inuse[3 * kNumFileDescriptorsToDup] = {
       0, 1, 2, 3,  // FDs get duped to the lowest numbers so reserve them
       master, slave, serverSocketFd, deadMansPipeWriteEnd,  // FDs to get duped, which mustn't be overwritten
       -1, -1, -1, -1 };  // Space for temp values to ensure they don't get reused
    int inuseCount = 2 * kNumFileDescriptorsToDup;

    // File descriptors get dup2()ed to temporary numbers first to avoid stepping on each other or
    // on any of the desired final values. Their temporary values go in here. The first is always
    // master, then slave, then server socket.
    int temp[kNumFileDescriptorsToDup];

    // The original file descriptors to renumber.
    int orig[kNumFileDescriptorsToDup] = { master, slave, serverSocketFd, deadMansPipeWriteEnd };

    for (int o = 0; o < sizeof(orig) / sizeof(*orig); o++) {  // iterate over orig
        int original = orig[o];

        // Try to find a candidate file descriptor that is not important to us (i.e., does not belong
        // to the inuse array).
        for (int candidate = 0; candidate < sizeof(inuse) / sizeof(*inuse); candidate++) {
            BOOL isInUse = NO;
            for (int i = 0; i < sizeof(inuse) / sizeof(*inuse); i++) {
                if (inuse[i] == candidate) {
                    isInUse = YES;
                    break;
                }
            }
            if (!isInUse) {
                // t is good. dup orig[o] to t and close orig[o]. Save t in temp[o].
                inuse[inuseCount++] = candidate;
                temp[o] = candidate;
                dup2(original, candidate);
                close(original);
                break;
            }
        }
    }

    // Dup the temp values to their desired values (which happens to equal the index in temp).
    // Close the temp file descriptors.
    for (int i = 0; i < sizeof(orig) / sizeof(*orig); i++) {
        dup2(temp[i], i);
        close(temp[i]);
    }
}

// Just like forkpty but fd 0 the master and fd 1 the slave.
int MyForkPty(int *amaster,
              iTermTTYState *ttyState,
              int serverSocketFd,
              int deadMansPipeWriteEnd) {
    int master;
    int slave;

    iTermFileDescriptorServerLog("Calling openpty");
    if (openpty(&master, &slave, ttyState->tty, &ttyState->term, &ttyState->win) == -1) {
        NSLog(@"openpty failed: %s", strerror(errno));
        return -1;
    }

    iTermFileDescriptorServerLog("Calling fork");
    pid_t pid = fork();
    switch (pid) {
        case -1:
            // error
            iTermFileDescriptorServerLogError(@"Fork failed: %s", strerror(errno));
            return -1;

        case 0:
            // child
            MyLoginTTY(master, slave, serverSocketFd, deadMansPipeWriteEnd);
            return 0;

        default:
            // parent
            *amaster = master;
            close(slave);
            close(serverSocketFd);
            close(deadMansPipeWriteEnd);
            return pid;
    }
}


