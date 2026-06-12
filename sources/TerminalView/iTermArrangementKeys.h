#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Top-level window arrangement keys (defined in PseudoTerminal.m).
extern NSString *const TERMINAL_ARRANGEMENT_TABS;

// Tab arrangement keys (defined in PTYTab.m).
extern NSString *const TAB_ARRANGEMENT_ROOT;
extern NSString *const TAB_ARRANGEMENT_VIEW_TYPE;
extern NSString *const TAB_ARRANGEMENT_SESSION;
extern NSString *const SUBVIEWS;
extern NSString *const VIEW_TYPE_SPLITTER;
extern NSString *const VIEW_TYPE_SESSIONVIEW;
extern NSString *const TAB_ARRANGEMENT_SPLITTER_FRAME;
extern NSString *const TAB_ARRANGEMENT_SPLITTER_ID;
extern NSString *const TAB_ARRANGEMENT_SESSIONVIEW_FRAME;
extern NSString *const SPLITTER_IS_VERTICAL;
extern NSString *const TAB_ARRANGEMENT_TMUX_WINDOW_PANE;
extern NSString *const TAB_ARRANGEMENT_ID;
extern NSString *const TAB_X;
extern NSString *const TAB_Y;
extern NSString *const TAB_WIDTH;
extern NSString *const TAB_HEIGHT;

// Session arrangement keys (defined in PTYSession.m).
extern NSString *const SESSION_ARRANGEMENT_BOOKMARK;
extern NSString *const SESSION_ARRANGEMENT_PROGRAM;

// Keys inside the SESSION_ARRANGEMENT_PROGRAM dictionary.
extern NSString *const kProgramType;
extern NSString *const kProgramCommand;
extern NSString *const kProgramTypeCommand;
extern NSString *const kProgramTypeShellLauncher;
extern NSString *const kProgramTypeCustomShell;

NS_ASSUME_NONNULL_END
