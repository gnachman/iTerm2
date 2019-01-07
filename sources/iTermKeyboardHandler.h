//
//  iTermKeyboardHandler.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/29/18.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermKeyMapper.h"

NS_ASSUME_NONNULL_BEGIN

#define NSLeftAlternateKeyMask  (0x000020 | NSEventModifierFlagOption)
#define NSRightAlternateKeyMask (0x000040 | NSEventModifierFlagOption)

typedef struct {
    BOOL hasActionableKeyMapping;
    iTermOptionKeyBehavior leftOptionKey;
    iTermOptionKeyBehavior rightOptionKey;
    BOOL autorepeatMode;
} iTermKeyboardHandlerContext;

@class iTermKeyboardHandler;

@protocol iTermKeyboardHandlerDelegate<NSObject>
- (BOOL)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    shouldHandleKeyDown:(NSEvent *)event;

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
            loadContext:(iTermKeyboardHandlerContext *)context
               forEvent:(NSEvent *)event;

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
     interpretKeyEvents:(NSArray<NSEvent *> *)events;

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
  sendEventToController:(NSEvent *)event;

- (NSRange)keyboardHandlerMarkedTextRange:(iTermKeyboardHandler *)keyboardhandler;

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
             insertText:(NSString *)aString;

@end

// This is responsible for the logic involving the NSTextInput insanity, including dealing with
// marked text special cases, routing around Cocoa bugs, emulating key bindings, and various other
// ugly little warts. It is all wrapped up in this pandora's box so the toxic shit doesn't touch
// anything else.
//
// Various NSTextInput methods (declared below) should be sent straight here. Awful things will
// happen and then it will turn around and call various delegate methods as needed, whose
// implementations are straight-forward enough for mere mortals to comprehend.
@interface iTermKeyboardHandler : NSObject

@property (nonatomic, weak) id<iTermKeyboardHandlerDelegate> delegate;
@property (nonatomic, readonly) BOOL keyIsARepeat;
@property (nonatomic, strong) id<iTermKeyMapper> keyMapper;

- (void)keyDown:(NSEvent *)event inputContext:(NSTextInputContext *)inputContext;
- (void)doCommandBySelector:(SEL)aSelector;
- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange;
- (BOOL)hasMarkedText;
- (void)flagsChanged:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
