//
//  iTermSocket.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermSocket.h"

#import "DebugLogging.h"
#import "iTermSocketAddress.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>

@implementation iTermSocket {
    iTermSocketAddress *_boundAddress;
    dispatch_queue_t _acceptQueue;
    int _addressFamily;
    // Write end of the pipe that wakes the accept loop. -1 when there is none.
    int _wakeWriteFd;
    // Once the accept loop starts it owns _fd and closes it when it exits.
    BOOL _loopOwnsFd;
}

+ (instancetype)unixDomainSocket {
    return [[self alloc] initWithAddressFamily:AF_UNIX socketType:SOCK_STREAM];
}

- (instancetype)initWithAddressFamily:(int)addressFamily
                           socketType:(int)socketType {
    self = [super init];
    if (self) {
        _addressFamily = addressFamily;
        _wakeWriteFd = -1;
        _fd = socket(addressFamily, socketType, 0);
        if (_fd < 0) {
            RLog(@"socket failed with %s", strerror(errno));
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)setReuseAddr:(BOOL)reuse {
    if (_addressFamily == AF_UNIX) {
        return;
    }
    int optionValue = reuse ? 1 : 0;
    int rc = setsockopt(_fd,
                        SOL_SOCKET,
                        SO_REUSEADDR,
                        (const void *)&optionValue,
                        sizeof(optionValue));
    if (rc) {
        RLog(@"setsockopt failed with %s", strerror(errno));
    }
}

- (BOOL)bindToAddress:(iTermSocketAddress *)address {
    if (bind(_fd, address.sockaddr, address.sockaddrSize) == 0) {
        _boundAddress = [address copy];
        return YES;
    } else {
        RLog(@"bind failed with %s", strerror(errno));
    }
    return NO;
}

// Waits until the wake pipe is readable (meaning -close was called) or the timeout elapses.
// Returns YES only if -close was called. If poll() itself fails (for example with EAGAIN, which it
// returns when it can't allocate memory) this still waits out the timeout, so callers retrying in a
// loop don't spin, and returns NO so they retry. -close can't interrupt that fallback wait, but
// that only delays the loop's exit, since the loop owns the descriptors it uses.
static BOOL iTermSocketWaitForWake(int wakeFd, int timeoutMillis) {
    struct pollfd pfd = { .fd = wakeFd, .events = POLLIN, .revents = 0 };
    int rc;
    do {
        rc = poll(&pfd, 1, timeoutMillis);
    } while (rc == -1 && errno == EINTR);
    if (rc < 0) {
        usleep((useconds_t)timeoutMillis * 1000);
        return NO;
    }
    return rc > 0;
}

- (BOOL)listenWithBacklog:(int)backlog accept:(void (^)(int, iTermSocketAddress *, NSNumber *))acceptBlock {
    if (!_boundAddress) {
        return NO;
    }
    if (_acceptQueue) {
        return NO;
    }
    if (listen(_fd, backlog) < 0) {
        RLog(@"listen failed with %s", strerror(errno));
        return NO;
    }

    // -close wakes the accept loop by writing to this pipe. The loop, not -close,
    // closes the listening descriptor. Otherwise -close could free its number while the loop was
    // about to call accept() on it, and if the number were reused by another listening socket
    // (such as a new API server's) the old loop would steal that socket's connections.
    int wakePipe[2];
    if (pipe(wakePipe) < 0) {
        RLog(@"pipe failed with %s", strerror(errno));
        return NO;
    }
    fcntl(wakePipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(wakePipe[1], F_SETFD, FD_CLOEXEC);
    // Nonblocking so accept() can't block if a pending connection goes away between poll() and
    // accept(). The loop waits in poll() instead.
    const int listenFlags = fcntl(_fd, F_GETFL);
    if (listenFlags >= 0) {
        fcntl(_fd, F_SETFL, listenFlags | O_NONBLOCK);
    }

    _wakeWriteFd = wakePipe[1];
    _loopOwnsFd = YES;
    _acceptQueue = dispatch_queue_create("com.iterm2.accept", NULL);

    const int fd = _fd;
    const int wakeReadFd = wakePipe[0];
    dispatch_async(_acceptQueue, ^{
        // State for backing off while out of resources. Logging is limited to the start and end
        // of an episode so a long one doesn't flood RLog's ring buffer and push out the lines
        // explaining how it began.
        __block BOOL backingOff = NO;
        __block NSInteger backoffRetries = 0;
        __block int backoffDelayMillis = 0;
        const int initialBackoffDelayMillis = 100;
        const int maxBackoffDelayMillis = 1000;
        // Waits before the next attempt after running out of resources. Returns YES if -close was
        // called meanwhile.
        BOOL (^backOff)(NSString *, int) = ^BOOL(NSString *operation, int error) {
            if (!backingOff) {
                RLog(@"%@ failed with %s; backing off and retrying", operation, strerror(error));
                backingOff = YES;
                backoffRetries = 0;
                backoffDelayMillis = initialBackoffDelayMillis;
            }
            backoffRetries += 1;
            const BOOL closed = iTermSocketWaitForWake(wakeReadFd, backoffDelayMillis);
            backoffDelayMillis = MIN(backoffDelayMillis * 2, maxBackoffDelayMillis);
            return closed;
        };
        BOOL done = NO;
        while (!done) {
            @autoreleasepool {
                struct pollfd pfds[2] = {
                    { .fd = fd, .events = POLLIN, .revents = 0 },
                    { .fd = wakeReadFd, .events = POLLIN, .revents = 0 }
                };
                const int pollRC = poll(pfds, 2, -1);
                if (pollRC < 0) {
                    const int savedErrno = errno;
                    if (savedErrno == EINTR) {
                        continue;
                    }
                    if (savedErrno == EAGAIN) {
                        // poll() couldn't allocate memory. Like running out of descriptors, this
                        // passes, so back off rather than stop accepting for good.
                        if (backOff(@"poll", savedErrno)) {
                            DLog(@"Accept loop woken by close while backing off");
                            break;
                        }
                        continue;
                    }
                    RLog(@"poll on listening socket failed with %s", strerror(savedErrno));
                    break;
                }
                if (pfds[1].revents) {
                    DLog(@"Accept loop woken by close");
                    break;
                }

                uid_t euid = (uid_t)-1;
                gid_t egid = (gid_t)-1;
                struct sockaddr sockaddr;
                socklen_t clientAddressLength = sizeof(sockaddr);
                const int acceptFd = accept(fd, &sockaddr, &clientAddressLength);
                if (acceptFd < 0) {
                    const int savedErrno = errno;
                    switch (savedErrno) {
                        case EINTR:
                        case EWOULDBLOCK:
                        case ECONNABORTED:
                            // Transient, or the peer gave up before we got to it.
                            continue;
                        case EMFILE:
                        case ENFILE:
                        case ENOBUFS:
                        case ENOMEM:
                            // Out of descriptors or memory. Returning here would stop accepting
                            // for the life of the process (connections would be refused even after
                            // resources free up), so back off and try again. The kernel drops the
                            // connection that failed, but while clients keep arriving the listening
                            // socket stays readable, so wait on the wake pipe alone to avoid
                            // spinning (and logging) on every one of them.
                            if (backOff(@"accept", savedErrno)) {
                                DLog(@"Accept loop woken by close while backing off");
                                done = YES;
                            }
                            continue;
                        default:
                            RLog(@"accept failed with %s", strerror(savedErrno));
                            done = YES;
                            continue;
                    }
                }
                if (backingOff) {
                    RLog(@"Accepting again after %@ retries", @(backoffRetries));
                    backingOff = NO;
                }
                // On macOS the accepted socket inherits O_NONBLOCK from the listening socket.
                // Connections expect blocking descriptors, as they got before.
                const int acceptedFlags = fcntl(acceptFd, F_GETFL);
                if (acceptedFlags >= 0) {
                    fcntl(acceptFd, F_SETFL, acceptedFlags & ~O_NONBLOCK);
                }

                // The man page for getpeereid appears to contain a lie.
                //   "The argument s must be a UNIX-domain socket (unix(4)) of type SOCK_STREAM on
                //    which either connect(2) or listen(2) have been called"
                // Well, we called listen on `fd`, but `getpeereid` gives "Socket is not connected"
                // when you pass that to it. If you give it `acceptFd`, it works fine.
                // ¯\_(ツ)_/¯
                NSNumber *uidNumber = nil;
                if (getpeereid(acceptFd, &euid, &egid) == 0) {
                    uidNumber = @(euid);
                }
                acceptBlock(acceptFd, [iTermSocketAddress socketAddressWithSockaddr:sockaddr], uidNumber);
            }
        }
        // This loop owns these descriptors once it starts, so no one else can close them while
        // it might still use them.
        close(fd);
        close(wakeReadFd);
    });
    return YES;
}

- (void)close {
    if (_loopOwnsFd) {
        // Wake the accept loop, which closes the listening socket itself. Write a byte rather
        // than relying on close() alone, since a child forked before it execs holds a copy of
        // the write end and would keep the read end from seeing EOF.
        if (_wakeWriteFd >= 0) {
            const char byte = 0;
            ssize_t rc;
            do {
                rc = write(_wakeWriteFd, &byte, 1);
            } while (rc == -1 && errno == EINTR);
            close(_wakeWriteFd);
            _wakeWriteFd = -1;
        }
    } else if (_fd >= 0) {
        close(_fd);
    }
    _fd = -1;
}

@end
