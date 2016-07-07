#import "PTYWindow+Scripting.h"
#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermController.h"
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

