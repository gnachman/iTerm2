//
//  iTermGitStringMaker.h
//  iTerm2
//
//  Created by George Nachman on 4/16/26.
//

#import <AppKit/AppKit.h>

@class iTermGitPoller;
@class iTermGitState;
@class iTermVariableScope;

NS_ASSUME_NONNULL_BEGIN

@protocol iTermGitStringMakerDelegate
@property (nonatomic, readonly, nullable) NSFont *gitFont;
@property (nonatomic, readonly, nullable) NSColor *gitTextColor;
@end

@interface iTermGitStringMaker: NSObject
@property (nonatomic, weak) id<iTermGitStringMakerDelegate> delegate;
@property (nullable, nonatomic, copy) NSString *status;
@property (nonatomic, strong) iTermGitPoller *gitPoller;
@property (nonatomic, readonly, strong) iTermVariableScope *scope;
@property (nonatomic, readonly) BOOL onLocalhost;
@property (nonatomic, readonly, nullable) NSString *branch;
@property (nonatomic, readonly, nullable) NSString *xcode;
@property (nonatomic, readonly, nullable) iTermGitState *currentState;

- (instancetype)initWithScope:(iTermVariableScope *)scope gitPoller:(iTermGitPoller *)gitPoller
NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (NSArray<NSAttributedString *> *)attributedStringVariants;
- (void)didFinishCommand;
- (nullable NSAttributedString *)attributedStringValueForBranch:(NSString *)branchString;
@end

@protocol iTermAutoGitStringDelegate
- (void)gitStringDidChange;
@end

@interface iTermAutoGitString: NSObject
@property (nonatomic, readonly) iTermGitStringMaker *maker;
@property (nonatomic, weak) id<iTermAutoGitStringDelegate> delegate;

- (instancetype)initWithStringMaker:(iTermGitStringMaker *)maker NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;


@end

NS_ASSUME_NONNULL_END
