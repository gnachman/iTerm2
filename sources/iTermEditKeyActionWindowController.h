//
//  iTermEditKeyActionWindowController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>

#import "iTermVariableScope.h"

@class iTermAction;

@interface iTermEditKeyActionWindowController : NSWindowController

@property(nonatomic) BOOL titleIsInterpolated;
@property(nonatomic, copy) NSString *currentKeyCombination;
@property(nonatomic, copy) NSString *touchBarItemID;
@property(nonatomic, readonly) NSString *identifier;  // currentKeyCombination, touchBarItemId, or nil
@property(nonatomic, copy) NSString *parameterValue;
@property(nonatomic, copy) NSString *label;
@property(nonatomic) int action;
@property(nonatomic, readonly) BOOL ok;
@property(nonatomic, readonly) iTermVariablesSuggestionContext suggestContext;
@property(nonatomic, readonly) iTermAction *unboundAction;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithContext:(iTermVariablesSuggestionContext)context;

// Used by client to remember if this was opened to add a new mapping or edit an existing one.
@property(nonatomic) BOOL isNewMapping;

typedef NS_ENUM(NSUInteger, iTermEditKeyActionWindowControllerMode) {
    iTermEditKeyActionWindowControllerModeKeyboardShortcut = 0,
    iTermEditKeyActionWindowControllerModeTouchBarItem,
    iTermEditKeyActionWindowControllerModeUnbound
};

@property(nonatomic) iTermEditKeyActionWindowControllerMode mode;

@end
