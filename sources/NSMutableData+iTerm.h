//
//  NSMutableData+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableData (iTerm)

- (void)appendBytes:(unsigned char *)bytes length:(int)length excludingCharacter:(char)exclude;

@end
