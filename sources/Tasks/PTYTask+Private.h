//
//  PTYTask+Private.h
//  iTerm2
//
//  Created by George Nachman on 5/20/22.
//

#import "PTYTask.h"
#import "TaskNotifier.h"

@interface PTYTask()<iTermTask> {
    BOOL _haveBumpedProcessCache;
}

@property(atomic, assign) BOOL hasMuteCoprocess;
@property(atomic, readwrite) int fd;
@property(atomic, weak) iTermLoggingHelper *loggingHelper;
@property(atomic, strong) id<iTermJobManager> jobManager;

@end
