#import "Widget.h"

#define CALL_IT(obj) [obj macroCalled]

@implementation iTermWidget

- (void)awakeFromNib {
    [super awakeFromNib];
}

- (void)windowDidResize:(NSNotification *)notification {
}

- (IBAction)biggerFont:(id)sender {
}

- (void)go {
    [self biggerFont:nil];
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerFired:) userInfo:nil repeats:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(noteChanged:) name:@"N" object:nil];
    [self performSelector:@selector(performedOnly)];
    [self performSelector:NSSelectorFromString(@"stringPerformed")];
    CALL_IT(self);
    self.fooBar = @"x";
    [self setValue:@"y" forKey:@"fooBar"];
    id<iTermWidgetDelegate> delegate = nil;
    [delegate widgetDidChange:self];
}

- (void)timerFired:(NSTimer *)timer {
}

- (void)noteChanged:(NSNotification *)note {
}

- (void)performedOnly {
}

- (void)stringPerformed {
}

- (void)macroCalled {
}

- (void)neverCalled {
}

- (void)contextMenuActionOpen:(id)sender {
}

- (void)swiftOnlyCalled {
}

- (void)openThing:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error {
}

- (void)widgetDidChange:(id)widget {
}

@end

@implementation iTermSubWidget

- (IBAction)biggerFont:(id)sender {
    [super biggerFont:sender];
}

@end

@implementation iTermThingMO
@end

void MenuMaker(void) {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Open"
                    action:@selector(contextMenuActionOpen:)
             keyEquivalent:@""];
}

void Registrar(iTermWidget *w) {
    [w.button sendAction:@selector(go) to:nil];
}
