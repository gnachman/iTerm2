//
//  iTermKeyBindingAction.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermKeyBindingDictionaryKeyAction;
extern NSString *const iTermKeyBindingDictionaryKeyParameter;
extern NSString *const iTermKeyBindingDictionaryKeyLabel;
extern NSString *const iTermKeyBindingDictionaryKeyVersion;
extern NSString *const iTermKeyBindingDictionaryKeyEscaping;

typedef NS_ENUM(NSUInteger, iTermSendTextEscaping) {
    iTermSendTextEscapingNone = 0,  // Send literal text
    iTermSendTextEscapingCompatibility = 1,  // Escape only n, e, a, and t. Used in many places prior to 3.4.5beta2.
    iTermSendTextEscapingCommon = 2,  // Use stringByReplacingCommonlyEscapedCharactersWithControls
    iTermSendTextEscapingVim = 3,  // Use stringByExpandingVimSpecialCharacters;
    iTermSendTextEscapingVimAndCompatibility = 4,  // Use stringByExpandingVimSpecialCharacters FOLLOWED BY n, e, a, t. Bugward compatibility.
};

// Actions for key bindings
typedef NS_ENUM(int, KEY_ACTION) {
    KEY_ACTION_INVALID = -1,

    KEY_ACTION_NEXT_SESSION = 0,
    KEY_ACTION_NEXT_WINDOW = 1,
    KEY_ACTION_PREVIOUS_SESSION = 2,
    KEY_ACTION_PREVIOUS_WINDOW = 3,
    KEY_ACTION_SCROLL_END = 4,
    KEY_ACTION_SCROLL_HOME = 5,
    KEY_ACTION_SCROLL_LINE_DOWN = 6,
    KEY_ACTION_SCROLL_LINE_UP = 7,
    KEY_ACTION_SCROLL_PAGE_DOWN = 8,
    KEY_ACTION_SCROLL_PAGE_UP = 9,
    KEY_ACTION_ESCAPE_SEQUENCE = 10,
    KEY_ACTION_HEX_CODE = 11,
    KEY_ACTION_TEXT = 12,
    KEY_ACTION_IGNORE = 13,
    KEY_ACTION_IR_FORWARD = 14,  // Deprecated
    KEY_ACTION_IR_BACKWARD = 15,
    KEY_ACTION_SEND_C_H_BACKSPACE = 16,
    KEY_ACTION_SEND_C_QM_BACKSPACE = 17,
    KEY_ACTION_SELECT_PANE_LEFT = 18,
    KEY_ACTION_SELECT_PANE_RIGHT = 19,
    KEY_ACTION_SELECT_PANE_ABOVE = 20,
    KEY_ACTION_SELECT_PANE_BELOW = 21,
    KEY_ACTION_DO_NOT_REMAP_MODIFIERS = 22,
    KEY_ACTION_TOGGLE_FULLSCREEN = 23,
    KEY_ACTION_REMAP_LOCALLY = 24,
    KEY_ACTION_SELECT_MENU_ITEM = 25,
    KEY_ACTION_NEW_WINDOW_WITH_PROFILE = 26,
    KEY_ACTION_NEW_TAB_WITH_PROFILE = 27,
    KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE = 28,
    KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE = 29,
    KEY_ACTION_NEXT_PANE = 30,
    KEY_ACTION_PREVIOUS_PANE = 31,
    KEY_ACTION_NEXT_MRU_TAB = 32,
    KEY_ACTION_MOVE_TAB_LEFT = 33,
    KEY_ACTION_MOVE_TAB_RIGHT = 34,
    KEY_ACTION_RUN_COPROCESS = 35,
    KEY_ACTION_FIND_REGEX = 36,
    KEY_ACTION_SET_PROFILE = 37,
    KEY_ACTION_VIM_TEXT = 38,
    KEY_ACTION_PREVIOUS_MRU_TAB = 39,
    KEY_ACTION_LOAD_COLOR_PRESET = 40,
    KEY_ACTION_PASTE_SPECIAL = 41,
    KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION = 42,
    KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING = 43,
    KEY_ACTION_UNDO = 44,
    KEY_ACTION_MOVE_END_OF_SELECTION_LEFT = 45,
    KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT = 46,
    KEY_ACTION_MOVE_START_OF_SELECTION_LEFT = 47,
    KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT = 48,
    KEY_ACTION_DECREASE_HEIGHT = 49,
    KEY_ACTION_INCREASE_HEIGHT = 50,
    KEY_ACTION_DECREASE_WIDTH = 51,
    KEY_ACTION_INCREASE_WIDTH = 52,
    KEY_ACTION_SWAP_PANE_LEFT = 53,
    KEY_ACTION_SWAP_PANE_RIGHT = 54,
    KEY_ACTION_SWAP_PANE_ABOVE = 55,
    KEY_ACTION_SWAP_PANE_BELOW = 56,
    KEY_FIND_AGAIN_DOWN = 57,
    KEY_FIND_AGAIN_UP = 58,
    KEY_ACTION_TOGGLE_MOUSE_REPORTING = 59,
    KEY_ACTION_INVOKE_SCRIPT_FUNCTION = 60,
    KEY_ACTION_DUPLICATE_TAB = 61,
    KEY_ACTION_MOVE_TO_SPLIT_PANE = 62,
    KEY_ACTION_SEND_SNIPPET = 63,
    KEY_ACTION_COMPOSE = 64,
    KEY_ACTION_SEND_TMUX_COMMAND = 65,
    KEY_ACTION_SEQUENCE = 66,
    KEY_ACTION_SWAP_WITH_NEXT_PANE = 67,
    KEY_ACTION_SWAP_WITH_PREVIOUS_PANE = 68,
    KEY_ACTION_COPY_OR_SEND = 69,
    KEY_ACTION_PASTE_OR_SEND = 70
};

@interface iTermKeyBindingAction : NSObject
@property (nonatomic, readonly) KEY_ACTION keyAction;
@property (nonatomic, readonly) NSString *parameter;
@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) NSString *stringValue;
@property (nonatomic, readonly) BOOL sendsText;
@property (nonatomic, readonly) BOOL isActionable;
@property (nonatomic, readonly) iTermSendTextEscaping escaping;
@property (nonatomic, readonly) iTermSendTextEscaping vimEscaping;

+ (instancetype)withDictionary:(NSDictionary *)dictionary;

+ (instancetype)withAction:(KEY_ACTION)action
                 parameter:(NSString *)parameter
                  escaping:(iTermSendTextEscaping)escaping;

+ (instancetype)withAction:(KEY_ACTION)action
                 parameter:(NSString *)parameter
                     label:(NSString *)label
                  escaping:(iTermSendTextEscaping)escaping;

+ (instancetype)fromString:(NSString *)string;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface NSString(iTermKeyBindingAction)
+ (instancetype)parameterForKeyBindingActionSequence:(NSArray<iTermKeyBindingAction *> *)actions;
- (NSArray<iTermKeyBindingAction *> *)keyBindingActionsFromSequenceParameter;
@end

NS_ASSUME_NONNULL_END
