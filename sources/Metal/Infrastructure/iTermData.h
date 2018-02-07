//
//  iTermData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import <Foundation/Foundation.h>

// Like NSMutableData but quickly allocates uninitialized data without zeroing it. You can also
// set the length to a smaller value safe in the knowledge that it won't get realloced.
@interface iTermData : NSObject
@property (nonatomic, readonly) void *mutableBytes;
@property (nonatomic) NSUInteger length;

+ (instancetype)dataOfLength:(NSUInteger)length;

@end
