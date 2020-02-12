//
//  iTermProcessInspector.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermProcessInspector : NSObject

// Short name describing the requester.
@property (nonatomic, readonly) NSString *humanReadableName;

- (instancetype)initWithProcessIDs:(NSArray<NSNumber *> *)pids NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
