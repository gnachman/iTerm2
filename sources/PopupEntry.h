//
//  PopupEntry.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Foundation/Foundation.h>

@interface PopupEntry : NSObject

@property(nonatomic, assign) double score;
@property(nonatomic, copy) NSString *prefix;
@property(nonatomic, copy) NSString *mainValue;

+ (PopupEntry*)entryWithString:(NSString*)s score:(double)score;
- (BOOL)isEqual:(id)o;
- (NSComparisonResult)compare:(id)otherObject;
// Update the hit multiplier for a new hit and return its new value
- (double)advanceHitMult;

@end
