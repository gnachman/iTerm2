//
//  iTermTmuxJobManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/20.
//

#import <Foundation/Foundation.h>
#import "PTYTask.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermTaskInputQueue;

@interface iTermTmuxJobManager : NSObject<iTermJobManager>
// Owns the read end of the pipe the session writes %output to. Unused with an input queue.
@property (atomic, strong, readwrite) iTermOwnedFileDescriptor *ownedFileDescriptor;
// What the session appends %output to when task I/O monitors are on, in place of the pipe.
@property (atomic, strong, readwrite, nullable) iTermTaskInputQueue *inputQueue;

@end

NS_ASSUME_NONNULL_END
