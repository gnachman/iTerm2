//
//  iTermPollHelper.h
//  iTerm
//
//  Created by George Nachman on 3/26/14.
//
//

#import <Foundation/Foundation.h>

#define kiTermPollHelperFlagReadable (1 << 0)
#define kiTermPollHelperFlagWritable (1 << 1)

extern NSMutableString *gLog;
#define LOG(args...) \
do { \
[gLog appendFormat:args]; \
[gLog appendString:@"\n"]; \
} while (0);

@interface iTermPollHelper : NSObject

- (void)reset;
- (void)addFileDescriptor:(int)fd
               forReading:(BOOL)reading
                  writing:(BOOL)writing
               identifier:(NSObject *)identifier;
- (void)poll;
- (NSUInteger)flagsForFd:(int)fd;

@end
