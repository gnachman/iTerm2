//
//  iTermProfileSearchWindowController.h
//  iTerm2SharedARC
//
//  Created by OpenAI on 7/23/26.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermProfileSearchWindowController : NSWindowController

@property(nonatomic, copy, nullable) void (^profileSelected)(NSString *guid);

- (void)showSearchWindow:(id _Nullable)sender;

@end

NS_ASSUME_NONNULL_END
