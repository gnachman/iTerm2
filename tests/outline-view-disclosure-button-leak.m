// Reproducer: NSOutlineView never releases its disclosure buttons.
//
//   clang -fobjc-arc -framework Cocoa \
//     -o /tmp/leak tests/outline-view-disclosure-button-leak.m && /tmp/leak
//
// A stock NSOutlineView with 20 collapsed expandable rows, and a timer calling
// -reloadData four times a second. No subclass, no overrides. Layout and
// display are left entirely to the normal runloop.
//
// It prints its pid. Watch this grow without bound, ~20 per reload:
//
//   heap <pid> | grep -E 'NSOutlineButtonCell|NSTableRowView'
//
// NSTableRowView holds steady the whole time, so row and cell view recycling
// works. Only the disclosure control leaks.
//
// Use heap, not leaks. The buttons stay reachable from a
// CFXNotificationRegistrar, so leaks reports no leaks at all while thousands
// are stranded.
//
// The window must stay frontmost. An occluded window runs no display cycles,
// so AppKit never asks for the row views and nothing leaks.
//
// The stranded button's strong referencer is a block from
// -[NSOutlineView _makeOutlineControl], retained by a CFXNotificationRegistrar:
// a per button notification observer that is never unregistered. The button
// therefore never deallocates, so the observer -[NSView _commonAwake] puts on
// it is never removed either, and each reload permanently grows the
// notification center by two entries. That is what makes this expensive: AppKit
// unregisters a dying view with a sweep whose cost grows with the size of the
// center, so this slows view teardown application wide.
//
// -reloadItem:reloadChildren: leaks identically. The batch update API,
// -insertItemsAtIndexes:inParent:withAnimation: and -removeItemsAtIndexes:,
// does not.
//
// Reproduced on macOS 26A428 and 26B5091g, arm64.

#import <Cocoa/Cocoa.h>

@interface Driver : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, weak) NSOutlineView *outlineView;
@end

@implementation Driver

// 20 expandable parents, each with one leaf. Items are small NSNumbers, so they
// are tagged pointers: unique and identical across reloads.
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) {
        return 20;
    }
    return [item integerValue] < 1000 ? 1 : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return item ? @([item integerValue] + 1000) : @(index);
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item integerValue] < 1000;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView
     viewForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item {
    NSTextField *field = [outlineView makeViewWithIdentifier:@"c" owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = @"c";
    }
    field.objectValue = item;
    return field;
}

- (void)reload:(NSTimer *)timer {
    [self.outlineView reloadData];
}

@end

int main(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 450)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"NSOutlineView disclosure button leak";

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
    NSOutlineView *outlineView = [[NSOutlineView alloc] initWithFrame:scrollView.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    [outlineView addTableColumn:column];
    outlineView.outlineTableColumn = column;

    Driver *driver = [[Driver alloc] init];
    driver.outlineView = outlineView;
    outlineView.dataSource = driver;
    outlineView.delegate = driver;

    scrollView.documentView = outlineView;
    [window.contentView addSubview:scrollView];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    printf("pid %d    heap %d | grep -E 'NSOutlineButtonCell|NSTableRowView'\n",
           getpid(), getpid());
    fflush(stdout);

    [NSTimer scheduledTimerWithTimeInterval:0.25
                                     target:driver
                                   selector:@selector(reload:)
                                   userInfo:nil
                                    repeats:YES];
    [NSApp run];
    return 0;
}
