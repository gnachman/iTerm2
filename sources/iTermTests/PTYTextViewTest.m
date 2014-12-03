#import "iTermTests.h"
#import "iTermColorMap.h"
#import "PTYTextView.h"
#import "PTYTextViewTest.h"

@interface PTYTextViewTest ()<PTYTextViewDelegate, PTYTextViewDataSource>
@end

@interface PTYTextView (Internal)
- (void)paste:(id)sender;
- (void)pasteOptions:(id)sender;
- (void)pasteSelection:(id)sender;
- (void)pasteBase64Encoded:(id)sender;
@end

@implementation PTYTextViewTest {
    PTYTextView *_textView;
    iTermColorMap *_colorMap;
    NSString *_pasteboardString;
    NSMutableDictionary *_methodsCalled;
    BOOL _canPasteFile;
    screen_char_t _buffer[4];
}

- (void)setup {
    _colorMap = [[iTermColorMap alloc] init];
    _textView = [[PTYTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100) colorMap:_colorMap];
    _textView.delegate = self;
    _textView.dataSource = self;
    _methodsCalled = [[NSMutableDictionary alloc] init];
    _canPasteFile = NO;
}

- (void)teardown {
    [_textView release];
    [_colorMap release];
    [_methodsCalled release];
}

- (void)invokeMenuItemWithSelector:(SEL)selector {
    [self invokeMenuItemWithSelector:selector tag:0];
}

- (void)invokeMenuItemWithSelector:(SEL)selector tag:(NSInteger)tag {
    NSMenuItem *fakeMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Fake Menu Item"
                                                           action:selector
                                                    keyEquivalent:@""] autorelease];
    [fakeMenuItem setTag:tag];
    assert([_textView validateMenuItem:fakeMenuItem]);
    [_textView performSelector:selector withObject:fakeMenuItem];
}

- (void)registerCall:(SEL)selector {
    [self registerCall:selector argument:nil];
}

- (void)registerCall:(SEL)selector argument:(NSObject *)argument {
    NSString *name = NSStringFromSelector(selector);
    if (argument) {
        name = [name stringByAppendingString:[argument description]];
    }
    NSNumber *number = _methodsCalled[name];
    if (!number) {
        number = @0;
    }
    _methodsCalled[name] = @(number.intValue + 1);
}

- (void)testPaste {
    [self invokeMenuItemWithSelector:@selector(paste:)];
    assert([_methodsCalled[@"paste:"] intValue] == 1);
}

- (void)testPasteOptions {
    [self invokeMenuItemWithSelector:@selector(pasteOptions:)];
    assert([_methodsCalled[@"pasteOptions:"] intValue] == 1);
}

- (void)testPasteSelection {
    [_textView selectAll:nil];
    [self invokeMenuItemWithSelector:@selector(pasteSelection:) tag:1];
    assert([_methodsCalled[@"textViewPasteFromSessionWithMostRecentSelection:1"] intValue] == 1);
}

- (void)testPasteBase64Encoded {
    _canPasteFile = YES;
    [self invokeMenuItemWithSelector:@selector(pasteBase64Encoded:)];
    assert([_methodsCalled[@"textViewPasteFileWithBase64Encoding"] intValue] == 1);
}

- (int)width {
    return 4;
}

- (int)height {
    return 4;
}

- (int)numberOfLines {
    return 4;
}

- (screen_char_t *)getLineAtIndex:(int)theIndex {
    for (int i = 0; i < [self width]; i++) {
        memset(&_buffer[i], 0, sizeof(screen_char_t));
        _buffer[i].code = theIndex + '0';
    }
    return _buffer;
}

#pragma mark - PTYTextViewDelegate

- (void)paste:(id)sender {
    [self registerCall:_cmd];
}

- (void)pasteOptions:(id)sender {
    [self registerCall:_cmd];
}

- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags {
    [self registerCall:_cmd argument:@(flags)];
}

- (void)textViewPasteFileWithBase64Encoding {
    [self registerCall:_cmd];
}

- (BOOL)textViewCanPasteFile {
    return _canPasteFile;
}

- (void)refreshAndStartTimerIfNeeded {
    [self registerCall:_cmd];
}

@end
