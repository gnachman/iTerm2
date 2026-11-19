#import "Widget.h"

void PSMCaller(id thing) {
    [thing biggerFont:nil];
}

void PSMDynamic(NSString *name, id target) {
    [target performSelector:NSSelectorFromString(name)];
}

@interface PSMThing : NSObject
- (void)go;
@end

@implementation PSMThing
- (void)go {
}
- (void)windowDidResize:(NSNotification *)notification {
}
- (void)setUp:(NSComboBox *)box {
    box.delegate = (id)self;
}
- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
}
@end
