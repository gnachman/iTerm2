//
//  iTermData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/4/18.
//

#import <Foundation/Foundation.h>

// Like NSMutableData but quickly allocates uninitialized data without zeroing it. You can also
// set the length to a smaller value safe in the knowledge that it won't get realloced. It also
// supports aligned allocations (I couldn't get NSMutableData to do this; initWithBytesNoCopy somehow
// returns a different address than you give it)
@interface iTermData : NSObject
@property (nonatomic, readonly) unsigned char *mutableBytes;
@property (nonatomic, readonly) const void *bytes;
@property (nonatomic) NSUInteger length;
// Will be a multiple of requested alignment
@property (nonatomic, readonly) NSUInteger allocatedCapacity;
@property (nonatomic, readonly) NSString *bitRanges;

+ (instancetype)dataOfLength:(NSUInteger)length;
+ (instancetype)pageAlignedUninitializeDataOfLength:(NSUInteger)length;
+ (instancetype)unownedDataWithBytes:(void *)bytes length:(NSUInteger)length;

@end
