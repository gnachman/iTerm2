// Fixture: a send outside any function or method, and a header outside the repository.
#import "widget.h"
#import "outside.h"
static Widget *gWidget;
static void (^gBlock)(void) = ^{ [gWidget doThing]; };
