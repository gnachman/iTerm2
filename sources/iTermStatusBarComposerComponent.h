//
//  iTermStatusBarComposerComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarComposerComponent;

@protocol iTermStatusBarComposerComponentDelegate<NSObject>
- (void)statusBarComposerComponentDidEndEditing:(iTermStatusBarComposerComponent *)component;
@end

@interface iTermStatusBarComposerComponent : iTermStatusBarBaseComponent
@property (nonatomic, weak) id<iTermStatusBarComposerComponentDelegate> composerDelegate;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, readonly) NSRect cursorFrameInScreenCoordinates;

- (void)makeFirstResponder;
- (void)deselect;
- (void)insertText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
