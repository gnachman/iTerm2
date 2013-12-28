//
//  PopupEntry.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Foundation/Foundation.h>

@interface PopupEntry : NSObject

+ (PopupEntry*)entryWithString:(NSString*)s score:(double)score;
- (void)setMainValue:(NSString*)s;
- (void)setScore:(double)score;
- (void)setPrefix:(NSString*)prefix;
- (NSString*)prefix;
- (NSString*)mainValue;
- (double)score;
- (BOOL)isEqual:(id)o;
- (NSComparisonResult)compare:(id)otherObject;
// Update the hit multiplier for a new hit and return its new value
- (double)advanceHitMult;

@end
