//
//  iTermStatusBarLargeComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarLargeComposerViewController.h"

#import "CommandHistoryPopup.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "PasteboardHistory.h"
#import "SolidColorView.h"
#import "VT100RemoteHost.h"
#import "WindowControllerInterface.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermCommandHistoryEntryMO+CoreDataProperties.h"
#import "iTermPopupWindowController.h"
#import "iTermShellHistoryController.h"
#import "iTermSlowOperationGateway.h"
#import "iTermTextPopoverViewController.h"
#import "iTermWarning.h"

@interface iTermComposerView : NSView
@end
@implementation iTermComposerView {
    NSView *_backgroundView;
    IBOutlet NSTextView *_textView;
}

// I have no idea at all why I have to do this, but I tried everything and it's the only way for
// Select Matches to be enabled. See also -performFindPanelAction: below. It has to be in this
// class and only this class. Can't go in the text view or even in a custom field editor for
// the search field.
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    return [_textView validateMenuItem:menuItem];
}

- (IBAction)performFindPanelAction:(id)sender {
    [_textView performFindPanelAction:sender];
}

- (NSView *)newBackgroundViewWithFrame:(NSRect)frame {
    NSVisualEffectView *myView = [[NSVisualEffectView alloc] initWithFrame:frame];
    myView.appearance = self.appearance;
    return myView;
}

- (void )viewDidMoveToWindow {
    [self updateBackgroundView];
    [super viewDidMoveToWindow];
}

- (void)updateBackgroundView {
    if ([NSStringFromClass(self.window.class) containsString:@"Popover"]) {
        NSView *privateView = [[self.window contentView] superview];
        [_backgroundView removeFromSuperview];
        _backgroundView = [self newBackgroundViewWithFrame:privateView.bounds];
        _backgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [privateView addSubview:_backgroundView positioned:NSWindowBelow relativeTo:privateView];
    }
}

- (void)setAppearance:(NSAppearance *)appearance {
    if (appearance != self.appearance) {
        [super setAppearance:appearance];
        [self updateBackgroundView];
    }
}

@end

@interface iTermStatusBarLargeComposerViewController ()<PopupDelegate, iTermPopupWindowPresenter, NSTextViewDelegate>

@end

@interface iTermSearchPathsCacheEntry: NSObject
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic) BOOL ready;
@end

@implementation iTermSearchPathsCacheEntry
@end

@implementation iTermStatusBarLargeComposerViewController {
    IBOutlet NSButton *_help;
    IBOutlet NSView *_accessories;
    IBOutlet NSScrollView *_scrollView;
    CommandHistoryPopupWindowController *_historyWindowController;
    NSInteger _completionGeneration;
    iTermTextPopoverViewController *_popoverVC;
    AITermControllerObjC *_aitermController;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.textView.textColor = [NSColor textColor];
    self.textView.insertionPointColor = [NSColor textColor];
    self.textView.font = [NSFont fontWithName:@"Menlo" size:11];
}

- (NSMutableDictionary<NSString *, iTermSearchPathsCacheEntry *> *)cache {
    static NSMutableDictionary<NSString *, iTermSearchPathsCacheEntry *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

- (IBAction)pasteOptions:(id)sender {
    NSString *content = self.textView.string;
    if (!content) {
        return;
    }
    [self.textView.composerDelegate composerTextViewSendToAdvancedPaste:content];
}

- (void)setScope:(iTermVariableScope *)scope {
    _scope = scope;

    NSString *shell = [scope valueForVariableName:@"shell"] ?: @"zsh";
    iTermSearchPathsCacheEntry *entry = self.cache[shell];
    if (entry) {
        if ([NSDate it_timeSinceBoot] - entry.timestamp < 60) {
            return;
        }
    } else {
        entry = [[iTermSearchPathsCacheEntry alloc] init];
        entry.timestamp = [NSDate it_timeSinceBoot];
        self.cache[shell] = entry;
    }
    [[iTermSlowOperationGateway sharedInstance] exfiltrateEnvironmentVariableNamed:@"PATH"
                                                                             shell:shell
                                                                        completion:^(NSString * _Nonnull value) {
        NSArray<NSString *> *paths = [value componentsSeparatedByString:@":"];
        if (paths && !entry.ready) {
            entry.paths = paths;
            entry.ready = YES;
        }
    }];
}

- (NSString *)lineBeforeCursor {
    NSString *content = self.textView.stringExcludingPrefix;
    const NSRange selectedRange = [self.textView selectedRangeExcludingPrefix];
    if (selectedRange.location > content.length) {
        return @"";
    }

    NSInteger lowerBound = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                       options:NSBackwardsSearch
                                                         range:NSMakeRange(0, selectedRange.location)].location;
    if (lowerBound == NSNotFound) {
        lowerBound = 0;
    } else {
        lowerBound += 1;
    }
    const NSInteger upperBound = selectedRange.location;
    return [content substringWithRange:NSMakeRange(lowerBound, upperBound - lowerBound)];
}

- (NSString *)textAfterCursor {
    NSString *content = self.textView.string;
    const NSRange selectedRange = [self.textView selectedRange];
    if (selectedRange.location > content.length) {
        return @"";
    }

    const NSInteger upperBound = self.textView.selectedRange.location;
    return [content substringFromIndex:upperBound];
}

- (NSString *)lineAtCursor {
    NSString *content = self.textView.string;
    const NSRange selectedRange = [self.textView selectedRange];
    if (selectedRange.location > content.length) {
        return @"";
    }

    NSInteger lowerBound = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                       options:NSBackwardsSearch
                                                         range:NSMakeRange(0, selectedRange.location)].location;
    if (lowerBound == NSNotFound) {
        lowerBound = 0;
    } else {
        lowerBound += 1;
    }
    NSInteger upperBound = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                    options:0
                                                      range:NSMakeRange(lowerBound, content.length - lowerBound)].location;
    if (upperBound == NSNotFound) {
        upperBound = content.length;
    }
    return [content substringWithRange:NSMakeRange(lowerBound, upperBound - lowerBound)];
}

- (void)openCommandHistory:(id)sender {
    [self.textView setSuggestion:nil];
    if (!_historyWindowController) {
        _historyWindowController = [[CommandHistoryPopupWindowController alloc] initForAutoComplete:NO];
    }
    if ([[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        NSString *prefix;
        NSString *content = self.textView.stringExcludingPrefix;
        const NSRange selectedRange = self.textView.selectedRangeExcludingPrefix;
        if (selectedRange.location > content.length) {
            return;
        }
        const NSInteger newlineBefore = [content rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                                 options:NSBackwardsSearch
                                                                   range:NSMakeRange(0, selectedRange.location)].location;
        if (newlineBefore == NSNotFound) {
            prefix = [content substringToIndex:selectedRange.location];
        } else {
            prefix = [content substringWithRange:NSMakeRange(newlineBefore + 1, selectedRange.location - newlineBefore - 1)];
        }
        [_historyWindowController popWithDelegate:self inWindow:self.view.window];
        [_historyWindowController loadCommands:[_historyWindowController commandsForHost:self.host
                                                                          partialCommand:prefix
                                                                                  expand:YES]
                                partialCommand:prefix
                           sortChronologically:NO];
    } else {
        [iTermShellHistoryController showInformationalMessageInWindow:self.view.window];
    }
}

- (NSString *)aiPrompt {
    if (self.textView.selectedRange.length > 0) {
        return [self.textView.string substringWithRange:self.textView.selectedRange];
    } else {
        return self.textView.stringExcludingPrefixAndSuggestion;
    }
}

- (IBAction)performNaturalLanguageQuery:(id)sender {
    __weak __typeof(self) weakSelf = self;

    _aitermController = [[AITermControllerObjC alloc] initWithQuery:self.aiPrompt
                                                              scope:self.scope
                                                           inWindow:self.view.window
                                                         completion:^(NSArray<NSString *> *choices, NSString *error) {
        if (choices.count >= 1) {
            [weakSelf acceptSuggestion:choices[0]];
        } else if (error) {
            [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"There was a problem with the AI query: %@", error]
                                       actions:@[ @"OK" ]
                                     accessory:nil
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent
                                       heading:@"AI Error"
                                        window:weakSelf.view.window];
        }
    }];
}

- (void)acceptSuggestion:(NSString *)string {
    // It likes to spam whitespace around the command.
    NSMutableCharacterSet *trim = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];

    // Sometimes it'll give a command wrapped in markdown backticks. This could be too aggressive in some edge cases.
    [trim addCharactersInString:@"`"];

    [self.textView replaceSelectionOrWholeStringWithString:[string stringByTrimmingCharactersInSet:trim]];
}

- (IBAction)help:(id)sender {
    [_popoverVC.popover close];
    _popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    _popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [_popoverVC view];
    _popoverVC.textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _popoverVC.textView.drawsBackground = NO;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    const CGFloat tabStop = 75;
    style.tabStops = @[ [[NSTextTab alloc] initWithType:NSLeftTabStopType location:tabStop],
                        [[NSTextTab alloc] initWithType:NSLeftTabStopType location:tabStop * 2] ];
    style.defaultTabInterval = tabStop;
    _popoverVC.textView.defaultParagraphStyle = style;

    [_popoverVC appendString:
         @"^⇧↑\tAdd cursor above\n"
         @"^⇧↓\tAdd cursor below\n"
         @"^⇧-click\tAdd cursor\n"
         @"⌥-drag\tAdd cursors\n"
         @"⌘Y\tNatural language AI lookup\n"
         @"⌘F\tOpen Find bar\n"
         @"⌥⌘V\tOpen in Advanced Paste\n"
         @"⌘-click\tOpen in explainshell.com\n"
         @"⇧↩\tSend command\n"
         @"⌥⇧↩\tSend command at cursor\n"
         @"⌥↩\tEnqueue command at cursor\n"
         @"⇧⌘;\tView command history"
    ];
    [_popoverVC.textView.textStorage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, _popoverVC.textView.textStorage.string.length)];
    [_popoverVC sizeToFit];
    [_popoverVC.popover showRelativeToRect:_help.bounds
                                    ofView:_help
                             preferredEdge:NSRectEdgeMaxY];
}

#pragma mark - PopupDelegate

- (BOOL)popupWindowShouldAvoidChangingWindowOrderOnClose {
    return NO;
}

- (NSRect)popupScreenVisibleFrame {
    return self.view.window.screen.visibleFrame;
}

- (VT100Screen *)popupVT100Screen {
    return nil;
}

- (id<iTermPopupWindowPresenter>)popupPresenter {
    return self;
}

- (void)popupInsertText:(NSString *)text {
    [self.textView insertText:text replacementRange:self.textView.selectedRange];
}

- (void)popupPreview:(NSString *)text {
}

- (void)popupKeyDown:(NSEvent *)event {
    [self.textView keyDown:event];
}

- (BOOL)popupHandleSelector:(SEL)selector string:(NSString *)string currentValue:(NSString *)currentValue {
    return NO;
}

- (void)popupWillClose:(iTermPopupWindowController *)popup {
    _historyWindowController = nil;
}

- (BOOL)popupWindowIsInFloatingHotkeyWindow {
    id<iTermWindowController> windowController = (id<iTermWindowController>)self.view.window.delegate;
    if ([windowController conformsToProtocol:@protocol(iTermWindowController)]) {
        return [windowController isFloatingHotKeyWindow];
    }
    return NO;
}

- (void)popupIsSearching:(BOOL)searching {
}

- (BOOL)popupShouldTakePrefixFromScreen {
    return NO;
}

- (NSArray<NSString *> *)popupWordsBeforeInsertionPoint:(int)count {
    const NSRange insertionPoint = self.textView.selectedRangeExcludingPrefix;
    NSString *string = [[self.textView stringExcludingPrefix] substringToIndex:insertionPoint.location];
    return [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - iTermPopupWindowPresenter

- (void)popupWindowWillPresent:(iTermPopupWindowController *)popupWindowController {
}

- (NSRect)popupWindowOriginRectInScreenCoords {
    NSRange range = [self.textView selectedRange];
    range.length = 0;
    return [self.textView firstRectForCharacterRange:range actualRange:NULL];
}

#pragma mark - NSTextViewDelegate

- (void)textViewDidChangeSelection:(NSNotification *)notification {
    if (self.textView.isSettingSuggestion) {
        return;
    }
    _completionGeneration += 1;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.textView setSuggestion:nil];
    });
}

- (NSString *)historySuggestionForPrefix:(NSString *)prefix {
    return [[self historySuggestionsForPrefix:prefix maxResults:1 removePrefix:NO] firstObject];
}

- (NSArray<NSString *> *)historySuggestionsForPrefix:(NSString *)prefix
                                          maxResults:(NSInteger)maxResults
                                        removePrefix:(BOOL)removePrefix {
    NSArray<iTermCommandHistoryEntryMO *> *entries =
    [[iTermShellHistoryController sharedInstance] commandHistoryEntriesWithPrefix:prefix
                                                                           onHost:self.host];
    return [[entries subarrayToIndex:maxResults] mapWithBlock:^id _Nullable(iTermCommandHistoryEntryMO * _Nonnull entry) {
        if (removePrefix) {
            return [entry.command substringFromIndex:prefix.length];
        } else {
            return entry.command.copy;
        }
    }];
}

// NOTE: This must not change the suggestion directly. It has to do it in dispatch_async because
// otherwise NSTextView throws exceptions.
- (void)textDidChange:(NSNotification *)notification {
    DLog(@"textDidChange - pre");
    [_delegate largeComposerViewControllerTextDidChange:self];
    DLog(@"textDidChange - post");
    _completionGeneration += 1;
    if (self.textView.isSettingSuggestion) {
        return;
    }
    [self.textView setSuggestion:nil];
    if (!self.textView.isDoingSyntaxHighlighting) {
        [self.textView doSyntaxHighlighting];
    }

    NSString *command = [self lineBeforeCursor];
    if (command.length == 0) {
        return;
    }
    NSString *textAfterCursor = [self textAfterCursor];
    if (command.length > 0 &&
        ![command endsWithWhitespace] &&
        textAfterCursor.length > 0 &&
        ![textAfterCursor beginsWithWhitespace]) {
        return;
    }

    __weak __typeof(self) weakSelf = self;
    __block NSInteger generation = 0;
    generation = [self fetchCompletionsForCommand:command
                                         explicit:NO
                                    completion:^(NSArray<NSString *> *completions, NSArray<NSString *> *commands) {
        [weakSelf didFetchCompletions:completions commands:commands generation:generation];
    }];
}

- (void)fetchCompletions:(void (^)(NSString *, NSArray<NSString *> *))completionBlock {
    _completionGeneration += 1;
    NSString *command = [self lineBeforeCursor];
    [self fetchCompletionsForCommand:command
                            explicit:YES
                          completion:^(NSArray<NSString *> *completions, NSArray<NSString *> *commands) {
        NSArray<NSString *> *combined = [[[completions arrayByAddingObjectsFromArray:commands] sortedArrayUsingSelector:@selector(compare:)] uniq];
        completionBlock(command, combined);
    }];
}

- (void)didFetchCompletions:(NSArray<NSString *> *)completions
                   commands:(NSArray<NSString *> *)commands
                 generation:(NSInteger)generation {
    if (!completions && !commands) {
        [self.textView setSuggestion:nil];
        return;
    }
    if (!completions) {
        [self didFindCompletions:@[]
              historySuggestions:commands
                   forGeneration:generation
                          escape:NO];
    }
    [self didFindCompletions:completions
          historySuggestions:commands
               forGeneration:generation
                      escape:YES];
}

// completionBlock(filename completions, commands from history)
// If both are nil then autocomplete is not supported and no history was found.
// If filename completions is nil then autocomplete is not supported.
- (NSInteger)fetchCompletionsForCommand:(NSString *)command
                               explicit:(BOOL)explicit
                             completion:(void (^)(NSArray<NSString *> *, NSArray<NSString *> *))completionBlock {
    const BOOL autocompleteSupported = [self.delegate largeComposerViewControllerShouldFetchSuggestions:self forHost:self.host tmuxController:self.tmuxController];
    if (!autocompleteSupported) {
        NSString *historySuggestion = [[self historySuggestionForPrefix:command] stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet newlineCharacterSet]];

        if (historySuggestion) {
            const NSInteger generation = ++_completionGeneration;
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(nil, @[ [historySuggestion substringFromIndex:command.length] ]);
            });
            return generation;
        }

        completionBlock(nil, nil);
        return 0;
    }

    NSArray<NSString *> *words = [command componentsInShellCommand];
    const BOOL onFirstWord = words.count < 2;
    NSString *const prefix = [command hasSuffix:@" "] ? @"" : words.lastObject;
    const NSInteger generation = ++_completionGeneration;
    NSArray<NSString *> *directories;
    if (onFirstWord) {
        // TODO: Get search paths from remote host when ssh integration is in use.
        NSString *shell = [self.scope valueForVariableName:iTermVariableKeyTabID] ?: @"zsh";
        iTermSearchPathsCacheEntry *entry = self.cache[shell];
        NSArray<NSString *> *paths = nil;
        if (entry.ready) {
            paths = entry.paths;
        }
        directories = paths ?: @[self.workingDirectory ?: NSHomeDirectory()];
    } else {
        directories = @[self.workingDirectory ?: NSHomeDirectory()];
    }

    NSArray<NSString *> *historySuggestions = [self historySuggestionsForPrefix:command
                                                                     maxResults:32
                                                                   removePrefix:YES];
    iTermSuggestionRequest *request = [[iTermSuggestionRequest alloc] initWithPrefix:prefix
                                                                         directories:directories
                                                                    workingDirectory:self.workingDirectory
                                                                          executable:onFirstWord
                                                                               limit:explicit ? 256 : 64

                                                                          completion:^(NSArray<NSString *> *completions) {
        completionBlock(completions ?: @[], historySuggestions ?: @[]);
    }];
    [self.delegate largeComposerViewController:self fetchSuggestions:request];
    return generation;
}

- (void)didFindCompletions:(NSArray<NSString *> *)filenameCompletions
        historySuggestions:(NSArray<NSString *> *)historySuggestions
             forGeneration:(NSInteger)generation
                    escape:(BOOL)shouldEscape {
    NSArray<NSString *> *completions = [filenameCompletions arrayByAddingObjectsFromArray:historySuggestions];
    if ([_historyWindowController.window isVisible]) {
        return;
    }
    if (generation != _completionGeneration) {
        return;
    }
    if (completions.count == 0) {
        return;
    }
    // Pick the shortest suggestion because otherwise it's hard to traverse a deep path since the
    // suggestion will make it easy to skip over intermediate folders.
    NSString *suggestion = [completions longestCommonStringPrefix];
    // Only escape if there are filename completions as it doesn't make sense to escape a history item.
    if (shouldEscape && filenameCompletions.count > 0) {
        self.textView.suggestion = [suggestion stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
    } else {
        self.textView.suggestion = suggestion;
    }
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (self.textView.hasSuggestion &&
        commandSelector == @selector(insertTab:)) {
        [self.textView acceptSuggestion];
        return YES;
    }

    if (commandSelector == @selector(deleteForward:) ||
        commandSelector == @selector(deleteBackward:) ||
        commandSelector == @selector(deleteBackwardByDecomposingPreviousCharacter:) ||
        commandSelector == @selector(deleteWordForward:) ||
        commandSelector == @selector(deleteWordBackward:) ||
        commandSelector == @selector(deleteToBeginningOfLine:) ||
        commandSelector == @selector(deleteToEndOfLine:) ||
        commandSelector == @selector(deleteToBeginningOfParagraph:) ||
        commandSelector == @selector(deleteToEndOfParagraph:) ||
        commandSelector == @selector(deleteToMark:)) {
        [self.textView setSuggestion:nil];
        [self.textView doSyntaxHighlighting];
    }

    return NO;
}

- (void)setHideAccessories:(BOOL)hideAccessories {
    _hideAccessories = hideAccessories;
    _accessories.hidden = hideAccessories;
    _textView.autoMode = hideAccessories;

    if (hideAccessories) {
        const CGFloat sideMargin = 0;
        const CGFloat topMargin = 0;
        _scrollView.frame = NSMakeRect(sideMargin,
                                       topMargin,
                                       self.view.frame.size.width - sideMargin * 2,
                                       self.view.frame.size.height - topMargin * 2);
    } else {
        const CGFloat sideMargin = 5;
        const CGFloat topMargin = 11;
        const CGFloat bottomMargin = 19;
        _scrollView.frame = NSMakeRect(sideMargin,
                                       bottomMargin,
                                       self.view.frame.size.width - sideMargin * 2,
                                       self.view.frame.size.height - topMargin - bottomMargin);
    }
}

@end
