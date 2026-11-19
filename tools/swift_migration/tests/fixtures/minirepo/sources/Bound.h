#import <Foundation/Foundation.h>
@protocol BoundReading
@property (nonatomic, readonly) id thing;
@end

@protocol BoundWriting <BoundReading>
@property (nonatomic, strong) id thing;
@end

@interface Bound : NSObject <BoundWriting, BoundReading>
@property (nonatomic) BOOL hasSelection;
@property (nonatomic) BOOL watched;
@property (nonatomic) BOOL sorted;
@property (nonatomic) BOOL quiet;
@end
