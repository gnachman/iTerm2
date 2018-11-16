#import "PTYWindow+Scripting.h"
#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermController.h"
#import "iTermHotKeyController.h"
#import "iTermScriptingWindow.h"
#import "NSArray+iTerm.h"
#import "PTYSession.h"
#import "PTYTab.h"

#define THE_CLASS iTermWindow
#include "iTermWindowScriptingImpl.m"
#undef THE_CLASS

#define THE_CLASS iTermPanel
#include "iTermWindowScriptingImpl.m"
#undef THE_CLASS

#define ENABLE_COMPACT_WINDOW_HACK 1
#define THE_CLASS iTermCompactWindow
#include "iTermWindowScriptingImpl.m"
#undef THE_CLASS

#define THE_CLASS iTermCompactPanel
#include "iTermWindowScriptingImpl.m"
#undef THE_CLASS

// NOTE: If you modify this file update PTYWindow.m similarly.
