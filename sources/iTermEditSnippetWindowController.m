//
//  iTermEditSnippetWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermEditSnippetWindowController.h"
#import "NSStringITerm.h"

@interface iTermEditSnippetWindowController ()

@end

@implementation iTermEditSnippetWindowController {
    IBOutlet NSTextField *_titleView;
    IBOutlet NSTextView *_valueView;
    NSString *_title;
    NSString *_value;
    NSString *_guid;
    BOOL _useCompatibilityEscaping;
    BOOL _canceled;
}

- (instancetype)initWithSnippet:(iTermSnippet *)snippet
                     completion:(void (^)(iTermSnippet * _Nullable snippet))completion {
    self = [super initWithWindowNibName:NSStringFromClass([self class])];
    if (self) {
        if (snippet) {
            _title = snippet.title;
            _value = snippet.value;
            _guid = snippet.guid;
            _useCompatibilityEscaping = snippet.useCompatibilityEscaping;
        } else {
            NSString *pasteboardString = [NSString stringFromPasteboard];
            if (pasteboardString) {
                _title = [pasteboardString ellipsizedDescriptionNoLongerThan:40];
                _value = pasteboardString;
            } else {
                _title = @"Untitled";
                _value = @"";
            }
            _guid = [[NSUUID UUID] UUIDString];
            _useCompatibilityEscaping = NO;
        }
        _completion = [completion copy];
    }
    return self;
}

- (iTermSnippet *)snippet {
    if (_canceled) {
        return nil;
    }
    return [[iTermSnippet alloc] initWithTitle:_title value:_value guid:_guid useCompatibilityEscaping:_useCompatibilityEscaping];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _titleView.stringValue = _title;
    _valueView.string  = _value;
}

- (IBAction)ok:(id)sender {
    _canceled = NO;
    _title = _titleView.stringValue.copy ?: @"";
    _value = _valueView.string.copy ?: @"";
    self.completion(self.snippet);
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)cancel:(id)sender {
    _canceled = YES;
    self.completion(nil);
    [self.window.sheetParent endSheet:self.window];
}

@end
