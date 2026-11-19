#import "Widget.h"

void WidgetTest(iTermWidget *widget) {
    [widget go];
    [widget declaredOnly];
}

NSString *const WidgetTestSelectorName = @"macroCalled";
