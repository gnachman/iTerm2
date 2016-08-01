//
//  iTermMutableAttributedStringBuilder.h
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermMutableAttributedStringBuilder : NSObject

@property(nonatomic, readonly) NSMutableAttributedString *attributedString;
@property(nonatomic, copy) NSDictionary *attributes;
@property(nonatomic, readonly) NSInteger length;
@property(nonatomic, readonly) CTLineRef lineRef;

// User data
@property(nonatomic, assign) int xCoordinate;
@property(nonatomic, assign) int indexIntoPositions;

- (void)appendString:(NSString *)string;
- (void)appendCharacter:(unichar)code;
- (void)buildAsynchronously:(void (^)())completion;

@end
