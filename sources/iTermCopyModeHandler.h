//
//  iTermCopyModeHandler.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermCopyModeHandler;
@protocol iTermCopyModeStateProtocol;
@class NSEvent;
@class PTYTextView;

#define NOT_COPY_FAMILY __attribute__((objc_method_family( none )))

@protocol iTermCopyModeHandlerDelegate<NSObject>

- (void)copyModeHandlerDidChangeEnabledState:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY;

- (void)copyModeHandlerRedraw:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY;

- (id<iTermCopyModeStateProtocol>)copyModeHandlerCreateState:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY;

- (void)copyModeHandler:(iTermCopyModeHandler *)handler
revealCurrentLineInState:(id<iTermCopyModeStateProtocol>)state NOT_COPY_FAMILY;

- (void)copyModeHandlerShowFindPanel:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY;

- (void)copyModeHandlerCopySelection:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY;

@end

@interface iTermCopyModeHandler : NSObject
@property (nonatomic, weak) id<iTermCopyModeHandlerDelegate> delegate;
@property (nonatomic) BOOL enabled;
@property (nullable, nonatomic, readonly) id<iTermCopyModeStateProtocol> state;

- (BOOL)handleEvent:(NSEvent *)event;
- (void)handleAsyncEvent:(NSEvent *)event completion:(void (^)(BOOL))completion;
- (void)handleAutoEnteringEvent:(NSEvent *)event;
- (BOOL)wouldHandleEvent:(NSEvent *)event;
- (BOOL)shouldAutoEnterWithEvent:(NSEvent *)event;
- (void)setEnabledWithoutCleverness:(BOOL)copyMode;

@end

@protocol iTermShortcutNavigationModeHandlerDelegate<NSObject>
- (void (^)(NSEvent *))shortcutNavigationActionForKeyEquivalent:(NSString *)characters;
- (void)shortcutNavigationDidComplete;
- (void)shortcutNavigationDidBegin;
- (BOOL)shortcutNavigationCharactersAreCommandPrefix:(NSString *)characters;
- (void)shortcutNavigationDidSetPrefix:(NSString *)prefix;
@end

@interface iTermShortcutNavigationModeHandler: NSObject
@property (nonatomic, weak) id<iTermShortcutNavigationModeHandlerDelegate> delegate;
@end

typedef NS_ENUM(NSUInteger, iTermSessionMode) {
    iTermSessionModeDefault,
    iTermSessionModeCopy,
    iTermSessionModeShortcutNavigation
};

@interface iTermSessionModeHandler: NSObject
@property (nonatomic, weak) id<iTermCopyModeHandlerDelegate, iTermShortcutNavigationModeHandlerDelegate> delegate;
@property (nonatomic) iTermSessionMode mode;
- (iTermCopyModeHandler *)copyModeHandler NOT_COPY_FAMILY;
@property (nonatomic, readonly) iTermShortcutNavigationModeHandler *shortcutNavigationModeHandler;
@property (nonatomic) BOOL clearSelectionsOnExit;

- (BOOL)wouldHandleEvent:(NSEvent *)event;
- (void)enterCopyModeWithoutCleverness;

- (BOOL)handleEvent:(NSEvent *)event;
- (BOOL)shouldAutoEnterWithEvent:(NSEvent *)event;
- (BOOL)previousMark;
- (BOOL)nextMark;

@end

NS_ASSUME_NONNULL_END
