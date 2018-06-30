//
//  iTermStatusBarLayout.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarComponent.h"

@class iTermStatusBarLayout;

@protocol iTermStatusBarLayoutDelegate<NSObject>

- (void)statusBarLayoutDidChange:(iTermStatusBarLayout *)layout;

@end

@interface iTermStatusBarLayout : NSObject<NSSecureCoding>

@property (nonatomic, weak) id<iTermStatusBarLayoutDelegate> delegate;
@property (nonatomic, readonly) NSArray<id<iTermStatusBarComponent>> *components;

- (void)addComponent:(id<iTermStatusBarComponent>)component;
- (void)removeComponent:(id<iTermStatusBarComponent>)component;
- (void)insertComponent:(id<iTermStatusBarComponent>)component atIndex:(NSInteger)index;

@end
