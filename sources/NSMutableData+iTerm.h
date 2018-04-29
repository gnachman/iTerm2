//
//  NSMutableData+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableData (iTerm)

+ (instancetype)uninitializedDataWithLength:(NSUInteger)length;

- (instancetype)initWithUninitializedLength:(NSUInteger)length;
- (void)appendBytes:(unsigned char *)bytes length:(int)length excludingCharacter:(char)exclude;
- (NSInteger)it_replaceOccurrencesOfData:(NSData *)target withData:(NSData *)replacement;

@end
