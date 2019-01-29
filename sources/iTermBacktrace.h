//
//  iTermBacktrace.hpp
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#ifndef iTermBacktrace_h
#define iTermBacktrace_h

#include <stdio.h>

@class iTermBacktraceFrame;

int GetCallstack(pthread_t threadId, void **buffer, int size);
NSArray<iTermBacktraceFrame *> *GetBacktraceFrames(pthread_t threadId);

#endif  // iTermBacktrace_h
