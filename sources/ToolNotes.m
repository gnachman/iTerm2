//
//  ToolNotes.m
//  iTerm
//
//  Created by George Nachman on 9/19/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolNotes.h"
#import "iTermSetFindStringNotification.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYWindow.h"
#import "PseudoTerminal.h"

static NSString *kToolNotesSetTextNotification = @"kToolNotesSetTextNotification";

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

@interface ToolNotes ()
- (NSString *)filename;
@end

@implementation ToolNotes

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        filemanager_ = [[NSFileManager alloc] init];

        NSScrollView *scrollview = [[[NSScrollView alloc]
                                     initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)] autorelease];
        [scrollview setBorderType:NSBezelBorder];
        [scrollview setHasVerticalScroller:YES];
        [scrollview setHasHorizontalScroller:NO];
        [scrollview setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        if (@available(macOS 10.14, *)) { } else {
            scrollview.drawsBackground = NO;
        }
        
        NSSize contentSize = [scrollview contentSize];
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
        textView_.automaticSpellingCorrectionEnabled = NO;
        textView_.automaticDashSubstitutionEnabled = NO;
        textView_.automaticQuoteSubstitutionEnabled = NO;
        textView_.automaticDataDetectionEnabled = NO;
        textView_.automaticLinkDetectionEnabled = NO;
        textView_.smartInsertDeleteEnabled = NO;

        [scrollview setDocumentView:textView_];

        [self addSubview:scrollview];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowAppearanceDidChange:)
                                                     name:iTermWindowAppearanceDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setText:)
                                                     name:kToolNotesSetTextNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [textView_ writeRTFDToFile:[self filename] atomically:NO];
    [filemanager_ release];
    [super dealloc];
}

- (NSString *)filename {
    return [NSString stringWithFormat:@"%@/notes.rtfd", [filemanager_ applicationSupportDirectory]];
}

- (void)textDidChange:(NSNotification *)aNotification
{
    // Avoid saving huge files because of the slowdown it would cause.
    if ([[textView_ textStorage] length] < 100 * 1024) {
        [textView_ writeRTFDToFile:[self filename] atomically:NO];
        ignoreNotification_ = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kToolNotesSetTextNotification
                                                            object:nil];
        ignoreNotification_ = NO;
    }
    [textView_ breakUndoCoalescing];
}

- (void)setText:(NSNotification *)aNotification
{
    if (!ignoreNotification_) {
        [textView_ readRTFDFromFile:[self filename]];
    }
}

- (void)shutdown {
}

- (CGFloat)minimumHeight
{
    return 15;
}

- (void)updateAppearance {
    if (!self.window) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        textView_.backgroundColor = [NSColor textBackgroundColor];
        textView_.textColor = [NSColor textColor];
    } else {
        if ([self.window.appearance.name isEqual:NSAppearanceNameVibrantDark]) {
            textView_.backgroundColor = [NSColor blackColor];
            textView_.textColor = [NSColor whiteColor];
        } else {
            textView_.backgroundColor = [NSColor whiteColor];
            textView_.textColor = [NSColor blackColor];
        }
    }
}

- (void)viewDidMoveToWindow {
    [self updateAppearance];
}

- (void)windowAppearanceDidChange:(NSNotification *)notification {
    [self updateAppearance];
}

@end
