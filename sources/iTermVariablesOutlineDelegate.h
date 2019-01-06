//
//  iTermVariablesOutlineDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

@interface iTermVariablesOutlineDelegate : NSObject<NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)initWithScope:(nullable iTermVariableScope *)scope;
- (NSString *)selectedPathForOutlineView:(NSOutlineView *)outlineView;
- (void)selectPath:(NSString *)path inOutlineView:(NSOutlineView *)outlineView;
- (void)copyPath:(id)sender;
- (void)copyValue:(id)sender;

@end

NS_ASSUME_NONNULL_END
