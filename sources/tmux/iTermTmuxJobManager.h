//
//  iTermTmuxJobManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/20.
//

#import <Foundation/Foundation.h>
#import "PTYTask.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermTmuxJobManager : NSObject<iTermJobManager>
// Owns the read end of the pipe the session writes %output to.
@property (atomic, strong, readwrite) iTermOwnedFileDescriptor *ownedFileDescriptor;

@end

NS_ASSUME_NONNULL_END
