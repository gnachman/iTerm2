//
//  iTermBaseHotKey.h
//  iTerm2
//
//  Created by George Nachman on 5/22/16.
//
//

#import <Cocoa/Cocoa.h>

@class iTermProfileHotKey;

@protocol iTermHotKeyDelegate<NSObject>
- (void)didFinishRollingOutProfileHotKey:(iTermProfileHotKey *)profileHotKey;
- (void)suppressHideApp;
- (void)storePreviouslyActiveApp;
- (void)willHideOrCloseProfileHotKey:(iTermProfileHotKey *)profileHotKey;
@end

// Abstract base class.
@interface iTermBaseHotKey : NSObject

@property(nonatomic, assign) NSUInteger keyCode;
@property(nonatomic, assign) NSEventModifierFlags modifiers;
@property(nonatomic, assign) id<iTermHotKeyDelegate> delegate;

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)register;
- (void)unregister;

@end

@interface iTermBaseHotKey(Internal)
- (BOOL)keyDownEventTriggers:(NSEvent *)event;
- (void)simulatePress;
@end
