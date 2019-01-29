//
//  iTermBacktrace.cpp
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//
// Most of the interesting parts of this code came from the openlierox project. Its copyright messages are:
/*
 *  Debug_GetCallstack.cpp
 *  OpenLieroX
 *
 *  Created by Albert Zeyer on 06.04.12.
 *  code under LGPL
 *
 */
/*
 *  Debug_GetPCFromUContext.cpp
 *  OpenLieroX
 *
 *  Created by Albert Zeyer on 06.04.12.
 *  code under LGPL
 *
 */


#import <Foundation/Foundation.h>
#import "NSArray+iTerm.h"
#import "RegexKitLite.h"
extern "C" {
#include "iTermBacktrace.h"
#import "iTermBacktraceFrame.h"
}
#include <memory>
#include <string>
#include <cxxabi.h>

/*
 About the POSIX solution:

 Initially, I wanted to implement something similar as suggested
 here <http://stackoverflow.com/a/4778874/133374>, i.e. getting
 somehow the top frame pointer of the thread and unwinding it
 manually (the linked source is derived from Apples `backtrace`
 implementation, thus might be Apple-specific, but the idea is
 generic).

 However, to have that safe (and the source above is not and
 may even be broken anyway), you must suspend the thread while
 you access its stack. I searched around for different ways to
 suspend a thread and found:
 - http://stackoverflow.com/questions/2208833/how-do-i-suspend-another-thread-not-the-current-one
 - http://stackoverflow.com/questions/6367308/sigstop-and-sigcont-equivalent-in-threads
 - http://stackoverflow.com/questions/2666059/nptl-sigcont-and-thread-scheduling
 Basically, there is no really good way. The common hack, also
 used by the Hotspot JAVA VM (<http://stackoverflow.com/a/2221906/133374>),
 is to use signals and sending a custom signal to your thread via
 `pthread_kill` (<http://pubs.opengroup.org/onlinepubs/7908799/xsh/pthread_kill.html>).

 So, as I would need such signal-hack anyway, I can have it a bit
 simpler and just use `backtrace` inside the called signal handler
 which is executed in the target thread (as also suggested here:
 <http://stackoverflow.com/a/6407683/133374>). This is basically
 what this implementation is doing.

 If you are also interested in printing the backtrace, see:
 - backtrace_symbols_str() in Debug_extended_backtrace.cpp
 - DumpCallstack() in Debug_DumpCallstack.cpp
 */

#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>

#include <signal.h>
#include <pthread.h>

static pthread_t targetThread = 0;
static void** threadCallstackBuffer = NULL;
static int threadCallstackBufferSize = 0;
static int threadCallstackCount = 0;
static dispatch_group_t gBacktraceGroup;

#define CALLSTACK_SIG SIGUSR2

#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <ctype.h>
#include <unistd.h>

#if defined(__linux__) || defined(__APPLE__)
/* get REG_EIP / REG_RIP from ucontext.h */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif
#include <ucontext.h>
#endif

#ifndef EIP
#define EIP     14
#endif

#if (defined (__x86_64__))
#ifndef REG_RIP
#define REG_RIP REG_INDEX(rip) /* seems to be 16 */
#endif
#endif


void *GetPCFromUContext(void *secret) {
    // See this article for further details: (thanks also for some code snippets)
    // http://www.linuxjournal.com/article/6391

    void *pnt = NULL;
    // This bit is x86-64 specific. Have fun fixing this when ARM Macs come out next year :)
    // This might possibly be right: ucp->m_context.ctx.arm_pc
    ucontext_t* uc = (ucontext_t*) secret;
    pnt = (void*) uc->uc_mcontext->__ss.__rip ;


    return pnt;
}


__attribute__((noinline))
static void _callstack_signal_handler(int signr, siginfo_t *info, void *secret) {
    pthread_t myThread = (pthread_t)pthread_self();
    if (myThread != targetThread) {
        return;
    }
    threadCallstackCount = backtrace(threadCallstackBuffer, threadCallstackBufferSize);

    // Search for the frame origin.
    for (int i = 1; i < threadCallstackCount; ++i) {
        if (threadCallstackBuffer[i] != NULL) {
            continue;
        }

        // Found it at stack[i]. Thus remove the first i.
        const int numberOfTopmostFramesToIgnore = i;
        threadCallstackCount -= numberOfTopmostFramesToIgnore;
        memmove(threadCallstackBuffer, threadCallstackBuffer + numberOfTopmostFramesToIgnore, threadCallstackCount * sizeof(void*));
        threadCallstackBuffer[0] = GetPCFromUContext(secret); // replace by real PC ptr
        break;
    }

    // continue calling thread
    dispatch_group_leave(gBacktraceGroup);
}

static void _setup_callstack_signal_handler() {
    struct sigaction sa;
    sigfillset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = _callstack_signal_handler;
    sigaction(CALLSTACK_SIG, &sa, NULL);
}

__attribute__((noinline))
int InternalGetCallstack(pthread_t threadId, void **buffer, int size) {
    if (threadId == 0 || threadId == (pthread_t)pthread_self()) {
        int count = backtrace(buffer, size);
        static const int numberOfTopmostFramesToIgnore = 1; // remove this `GetCallstack` frame
        if (count > numberOfTopmostFramesToIgnore) {
            count -= numberOfTopmostFramesToIgnore;
            memmove(buffer, buffer + numberOfTopmostFramesToIgnore, count * sizeof(void*));
        }
        return count;
    }

    static id callstackMutex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        callstackMutex = [[NSObject alloc] init];
        gBacktraceGroup = dispatch_group_create();
    });
    @synchronized (callstackMutex) {
        targetThread = threadId;
        threadCallstackBuffer = buffer;
        threadCallstackBufferSize = size;

        _setup_callstack_signal_handler();

        // call _callstack_signal_handler in target thread
        dispatch_group_enter(gBacktraceGroup);
        if (pthread_kill((pthread_t)threadId, CALLSTACK_SIG) != 0) {
            // something failed ...
            dispatch_group_leave(gBacktraceGroup);
            return 0;
        }
        dispatch_group_wait(gBacktraceGroup, DISPATCH_TIME_FOREVER);

        threadCallstackBuffer = NULL;
        threadCallstackBufferSize = 0;
        return threadCallstackCount;
    }
}

NSString *DumpCallstack(void*const* buffer, int size) {
    NSMutableArray<NSString *> *frames = [NSMutableArray array];
    char **strs = backtrace_symbols(buffer, size);
    for(int i = 0; i < size; ++i) {
        if (!strs[i]) {
            break;
        }
        [frames addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    return [frames componentsJoinedByString:@"\n"];
}

extern "C" {
    int GetCallstack(pthread_t threadId, void **buffer, int size) {
        return InternalGetCallstack(threadId, buffer, size);
    }

    static NSString *iTermDemangleCppSymbol(NSString *mangledString) {
        int status = -1;
        const char *name = mangledString.UTF8String;
        std::unique_ptr<char, void(*)(void*)> res {
            abi::__cxa_demangle(name, NULL, NULL, &status), std::free
        };
        if (status == 0) {
            char *cstr = res.get();
            return [NSString stringWithUTF8String:cstr];
        } else {
            return mangledString;
        }
    }

    NSString *iTermDemangle(NSString *mangledString) {
        static NSRegularExpression *compiledRegex;
        static dispatch_once_t onceToken;
        static NSString *regex = @"^(.*?0x(?:[0-9a-f]{16}) )([^ ]+)( \\+ [0-9]+)$";
        dispatch_once(&onceToken, ^{
            compiledRegex = [NSRegularExpression regularExpressionWithPattern:regex
                                                                      options:0
                                                                        error:NULL];
        });
        NSArray *components = [mangledString captureComponentsMatchedByRegex:regex];
        if (components.count == 0) {
            return mangledString;
        }
        NSArray<NSTextCheckingResult *> *matches = [compiledRegex matchesInString:mangledString options:0 range:NSMakeRange(0, mangledString.length)];
        if (matches.count) {
            NSTextCheckingResult *result = matches.firstObject;
            NSString *possibleCppSymbol = [mangledString substringWithRange:[result rangeAtIndex:2]];
            NSString *replacementTemplate = [NSString stringWithFormat:@"$1%@$3", iTermDemangleCppSymbol(possibleCppSymbol)];
            return [compiledRegex stringByReplacingMatchesInString:mangledString
                                                           options:0
                                                             range:NSMakeRange(0, mangledString.length)
                                                      withTemplate:replacementTemplate];
        } else {
            return mangledString;
        }
    }

    static void PopulateBacktraceFrames(void **buffer, NSMutableArray<iTermBacktraceFrame *> *frames, size_t size) {
        char** strs = backtrace_symbols(buffer, size);
        for(int i = 0; i < size; ++i) {
            if (!strs[i]) {
                break;
            }
            iTermBacktraceFrame *frame = [[iTermBacktraceFrame alloc] initWithString:iTermDemangle([NSString stringWithUTF8String:strs[i]])];
            [frames insertObject:frame atIndex:0];
        }
        free(strs);
    }

    NSArray<iTermBacktraceFrame *> *GetBacktraceFrames(pthread_t threadId) {
        const size_t size = 1024;
        void *buffer[size];
        int n = InternalGetCallstack(threadId, buffer, 1024);
        NSMutableArray<iTermBacktraceFrame *> *frames = [NSMutableArray array];
        PopulateBacktraceFrames(buffer, frames, n);
        return frames;
    }
}

