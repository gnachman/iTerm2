//
//  ToolNotes.m
//  iTerm
//
//  Created by George Nachman on 9/19/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolNotes.h"

#import "iTermSetFindStringNotification.h"
#import "iTermToolWrapper.h"
#import "NSFileManager+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYTab.h"
#import "PTYWindow.h"
#import "PseudoTerminal.h"
#import "iTerm2SharedARC-Swift.h"

static NSString *kToolNotesSetTextNotification = @"kToolNotesSetTextNotification";

typedef NS_ENUM(NSInteger, ToolNotesMode) {
    ToolNotesModeGlobal = 0,
    ToolNotesModeSession = 1,
};

@interface iTermUnformattedTextView : NSTextView
@end

@implementation iTermUnformattedTextView

- (void)paste:(id)sender {
    [self pasteAsPlainText:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(performFindPanelAction:)) {
        if (menuItem.tag == NSFindPanelActionSetFindString) {
            return self.selectedRanges.count > 0 || self.selectedRange.length > 0;
        }
    }
    return [super validateMenuItem:menuItem];
}

- (void)performFindPanelAction:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        return;
    }
    if (menuItem.tag == NSFindPanelActionSetFindString) {
        NSString *string = [self.string substringWithRange:self.selectedRange];
        if (string.length == 0) {
            return;
        }
        [[iTermSetFindStringNotification notificationWithString:string] post];
    }
    [super performFindPanelAction:sender];
}

@end

@interface ToolNotes () {
    NSSegmentedControl *modeControl_;
    NSScrollView *scrollView_;
    ToolNotesMode mode_;
    iTermSessionNoteModel *sessionNoteModel_;
    BOOL ignoreSessionNoteNotification_;
}
- (NSString *)filename;
@end

@implementation ToolNotes

- (BOOL)isFlipped {
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        filemanager_ = [[NSFileManager alloc] init];
        mode_ = ToolNotesModeGlobal;

        // Mode selector
        modeControl_ = [NSSegmentedControl segmentedControlWithLabels:@[@"Global", @"Session"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(modeChanged:)];
        [modeControl_ retain];
        modeControl_.selectedSegment = 0;
        modeControl_.controlSize = NSControlSizeSmall;
        [modeControl_ sizeToFit];
        [self addSubview:modeControl_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        if (@available(macOS 10.16, *)) {
            [scrollView_ setBorderType:NSLineBorder];
            scrollView_.scrollerStyle = NSScrollerStyleOverlay;
        } else {
            [scrollView_ setBorderType:NSBezelBorder];
        }
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        scrollView_.drawsBackground = NO;

        NSSize contentSize = [scrollView_ contentSize];
        textView_ = [[iTermUnformattedTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        [textView_ setAllowsUndo:YES];
        [textView_ setRichText:NO];
        [textView_ setImportsGraphics:NO];
        [textView_ setMinSize:NSMakeSize(0.0, contentSize.height)];
        [textView_ setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        [textView_ setVerticallyResizable:YES];
        [textView_ setHorizontallyResizable:NO];
        [textView_ setAutoresizingMask:NSViewWidthSizable];

        [[textView_ textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
        [[textView_ textContainer] setWidthTracksTextView:YES];
        [textView_ setDelegate:self];

        [textView_ readRTFDFromFile:[self filename]];
        textView_.font = [NSFont it_toolbeltFont];
        textView_.automaticSpellingCorrectionEnabled = NO;
        textView_.automaticDashSubstitutionEnabled = NO;
        textView_.automaticQuoteSubstitutionEnabled = NO;
        textView_.automaticDataDetectionEnabled = NO;
        textView_.automaticLinkDetectionEnabled = NO;
        textView_.smartInsertDeleteEnabled = NO;

        [scrollView_ setDocumentView:textView_];
        [self addSubview:scrollView_];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self
               selector:@selector(windowAppearanceDidChange:)
                   name:iTermWindowAppearanceDidChange
                 object:nil];
        [nc addObserver:self
               selector:@selector(globalTextDidChange:)
                   name:kToolNotesSetTextNotification
                 object:nil];
        [nc addObserver:self
               selector:@selector(activeSessionDidChange:)
                   name:iTermSessionBecameKey
                 object:nil];
        [nc addObserver:self
               selector:@selector(sessionNoteModelTextDidChange:)
                   name:iTermSessionNoteModel.textDidChangeNotification
                 object:nil];

        [self relayout];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (mode_ == ToolNotesModeGlobal) {
        [textView_ writeRTFDToFile:[self filename] atomically:NO];
    }
    [modeControl_ release];
    [scrollView_ release];
    [sessionNoteModel_ release];
    [filemanager_ release];
    [super dealloc];
}

+ (ProfileType)supportedProfileTypes {
    return ProfileTypeBrowser | ProfileTypeTerminal;
}

- (NSString *)filename {
    return [NSString stringWithFormat:@"%@/notes.rtfd", [filemanager_ applicationSupportDirectory]];
}

#pragma mark - Layout

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;
    CGFloat controlHeight = modeControl_.frame.size.height;
    CGFloat kMargin = 4;
    modeControl_.frame = NSMakeRect(0, 0, frame.size.width, controlHeight);
    CGFloat scrollY = controlHeight + kMargin;
    scrollView_.frame = NSMakeRect(0, scrollY, frame.size.width,
                                   frame.size.height - scrollY);
}

#pragma mark - Mode Switching

- (void)modeChanged:(NSSegmentedControl *)sender {
    ToolNotesMode newMode = (ToolNotesMode)sender.selectedSegment;
    if (newMode == mode_) {
        return;
    }
    mode_ = newMode;
    [[textView_ undoManager] removeAllActions];
    if (mode_ == ToolNotesModeGlobal) {
        [self loadGlobalNote];
    } else {
        [self loadSessionNote];
    }
}

- (void)loadGlobalNote {
    [sessionNoteModel_ release];
    sessionNoteModel_ = nil;
    [textView_ readRTFDFromFile:[self filename]];
    textView_.font = [NSFont it_toolbeltFont];
}

- (void)loadSessionNote {
    [sessionNoteModel_ release];
    id<iTermToolbeltViewDelegate> delegate = [[self toolWrapper] delegate].delegate;
    sessionNoteModel_ = [[delegate toolbeltCurrentSessionNoteModel] retain];
    [textView_ setString:sessionNoteModel_.text ?: @""];
    textView_.font = [NSFont it_toolbeltFont];
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)aNotification {
    if (mode_ == ToolNotesModeGlobal) {
        // Avoid saving huge files because of the slowdown it would cause.
        if ([[textView_ textStorage] length] < 100 * 1024) {
            [textView_ writeRTFDToFile:[self filename] atomically:NO];
            ignoreNotification_ = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:kToolNotesSetTextNotification
                                                                object:nil];
            ignoreNotification_ = NO;
        }
    } else {
        if (!sessionNoteModel_) {
            id<iTermToolbeltViewDelegate> delegate = [[self toolWrapper] delegate].delegate;
            sessionNoteModel_ = [[delegate toolbeltEnsureCurrentSessionNoteModel] retain];
        }
        if (sessionNoteModel_) {
            ignoreSessionNoteNotification_ = YES;
            sessionNoteModel_.text = textView_.string;
            ignoreSessionNoteNotification_ = NO;
        }
    }
    [textView_ breakUndoCoalescing];
}

#pragma mark - Notifications

- (void)globalTextDidChange:(NSNotification *)aNotification {
    if (mode_ != ToolNotesModeGlobal) {
        return;
    }
    if (!ignoreNotification_) {
        [textView_ readRTFDFromFile:[self filename]];
    }
}

- (void)activeSessionDidChange:(NSNotification *)notification {
    if (mode_ != ToolNotesModeSession) {
        return;
    }
    id<iTermToolbeltViewDelegate> delegate = [[self toolWrapper] delegate].delegate;
    iTermSessionNoteModel *newModel = [delegate toolbeltCurrentSessionNoteModel];
    if (newModel == sessionNoteModel_) {
        return;
    }
    [self loadSessionNote];
}

- (void)sessionNoteModelTextDidChange:(NSNotification *)notification {
    if (mode_ != ToolNotesModeSession) {
        return;
    }
    if (ignoreSessionNoteNotification_) {
        return;
    }
    iTermSessionNoteModel *model = notification.object;
    if (model != sessionNoteModel_) {
        return;
    }
    [textView_ setString:model.text ?: @""];
}

#pragma mark - ToolbeltTool

- (void)shutdown {
}

- (CGFloat)minimumHeight {
    return 68;
}

#pragma mark - Appearance

- (void)updateAppearance {
    if (!self.window) {
        return;
    }
    textView_.drawsBackground = NO;
    textView_.textColor = [NSColor textColor];
}

- (void)viewDidMoveToWindow {
    [self updateAppearance];
}

- (void)windowAppearanceDidChange:(NSNotification *)notification {
    [self updateAppearance];
}

@end
