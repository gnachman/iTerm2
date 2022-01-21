//
//  VT100WorkingDirectory.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@protocol VT100WorkingDirectoryReading<IntervalTreeImmutableObject>
@property(nonatomic, copy, readonly) NSString *workingDirectory;
@end

@interface VT100WorkingDirectory : NSObject <IntervalTreeObject, VT100WorkingDirectoryReading>

- (instancetype)initWithDirectory:(NSString*)directory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, copy, readonly) NSString *workingDirectory;

@end
