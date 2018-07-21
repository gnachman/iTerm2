//
//  iTermCPUUtilization.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import <Foundation/Foundation.h>

typedef void (^iTermCPUUtilizationObserver)(double);

@interface iTermCPUUtilization : NSObject
@property (nonatomic) NSTimeInterval cadence;

+ (instancetype)sharedInstance;
- (void)addSubscriber:(id)subscriber block:(iTermCPUUtilizationObserver)block;

@end
