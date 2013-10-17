//
//  iTermTests.h
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import <Foundation/Foundation.h>

@protocol iTermTestProtocol

@optional
- (void)setup;

@optional
- (void)teardown;

@end

@interface iTermTest : NSObject <iTermTestProtocol>
@end