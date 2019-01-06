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

- (instancetype)initWithScope:(iTermVariableScope *)scope;

@end

NS_ASSUME_NONNULL_END
