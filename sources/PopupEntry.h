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
@property double score;
@property (copy) NSString *prefix;
@property (copy) NSString *mainValue;
- (BOOL)isEqual:(id)o;
- (NSComparisonResult)compare:(id)otherObject;
// Update the hit multiplier for a new hit and return its new value
- (double)advanceHitMult;

@end
