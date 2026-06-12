//
//  iTermHamburgerButton.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/30/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermHamburgerButton : NSButton
@property (nonatomic, strong) NSMenu *(^menuProvider)(void);

- (instancetype)initWithMenuProvider:(NSMenu *(^)(void))menuProvider NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
