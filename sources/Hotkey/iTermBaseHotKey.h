//
//  iTermBaseHotKey.h
//  iTerm2
//
//  Created by George Nachman on 5/22/16.
//
//

#import <Cocoa/Cocoa.h>

#import "NSDictionary+iTerm.h"
#import "iTermShortcut.h"

@class iTermProfileHotKey;
@class iTermBaseHotKey;

@protocol iTermHotKeyDelegate<NSObject>
- (BOOL)willFinishRollingOutProfileHotKey:(iTermProfileHotKey *)profileHotKey
                         causedByKeypress:(BOOL)causedByKeypress;
- (void)suppressHideApp;
- (void)storePreviouslyActiveApp:(iTermProfileHotKey *)profileHotKey;
- (void)hotKeyWillCreateWindow:(iTermBaseHotKey *)hotKey;
- (void)hotKeyDidCreateWindow:(iTermBaseHotKey *)hotKey;
@end

// Abstract base class.
@interface iTermBaseHotKey : NSObject

@property(nonatomic, readonly) NSArray<iTermShortcut *> *shortcuts;
@property(nonatomic, readonly) BOOL hasModifierActivation;
@property(nonatomic, readonly) iTermHotKeyModifierActivation modifierActivation;
@property(nonatomic, readonly) NSArray<iTermHotKeyDescriptor *> *hotKeyDescriptors;
@property(nonatomic, readonly) iTermHotKeyDescriptor *modifierActivationDescriptor;
@property(nonatomic, assign) id<iTermHotKeyDelegate> delegate;

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
            hasModifierActivation:(BOOL)hasModifierActivation
               modifierActivation:(iTermHotKeyModifierActivation)modifierActivation NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)register;
- (void)unregister;
- (void)setShortcuts:(NSArray<iTermShortcut *> *)shortcuts
    hasModifierActivation:(BOOL)hasModifierActivation
      modifierActivation:(iTermHotKeyModifierActivation)modifierActivation;
@end

@interface iTermBaseHotKey(Internal)
- (BOOL)keyDownEventIsHotKeyShortcutPress:(NSEvent *)event;
- (void)simulatePress;
@end
