//
//  SmartMatch.h
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import <Foundation/Foundation.h>

@interface SmartMatch : NSObject
@property(nonatomic, assign) double score;
@property(nonatomic, assign) int startX;
@property(nonatomic, assign) long long absStartY;
@property(nonatomic, assign) int endX;
@property(nonatomic, assign) long long absEndY;
@property(nonatomic, retain) NSDictionary *rule;

- (NSComparisonResult)compare:(SmartMatch *)aNumber;
@end

