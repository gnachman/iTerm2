//
//  ToolJobs.m
//  iTerm
//
//  Created by George Nachman on 9/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolJobs.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermCompetentTableRowView.h"
#import "iTermJobTreeViewController.h"
#import "iTermProcessCache.h"
#import "iTermToolWrapper.h"
#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTask.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kMargin = 0;

@interface ToolJobs ()
@property(nonatomic, assign) BOOL killable;
@end

@implementation ToolJobs {
    iTermJobTreeViewController *_jobTreeViewController;
    NSArray<iTermProcessInfo *> *_processInfos;
    BOOL shutdown_;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _jobTreeViewController = [[iTermJobTreeViewController alloc] initWithProcessID:1
                                                                   processInfoProvider:[iTermProcessCache sharedInstance]];
        _jobTreeViewController.animateChanges = NO;
        // The toolbelt provides its own background, so suppress the visual
        // effect view (set before -font, which loads the view).
        _jobTreeViewController.useVisualEffectView = NO;
        // Space is at a premium in the toolbelt: anchor the 22pt-tall controls
        // flush to the bottom with 6pt above them and none below.
        _jobTreeViewController.toolbarHeight = 28;
        _jobTreeViewController.controlsBottomMargin = 0;
        _jobTreeViewController.font = [NSFont it_toolbeltFont];
        // The session's root pid and provider can change without the toolbelt hearing of it, as
        // a tmux pane on an SSH Integration host's do when its connection starts framing or
        // recovers. Follow them. QA finding F-612.
        __weak __typeof(self) weakSelf = self;
        _jobTreeViewController.willRefresh = ^(iTermJobTreeViewController *controller) {
            [weakSelf updateJobs];
        };
        [self addSubview:_jobTreeViewController.view];
        [self relayout];
    }
    return self;
}

+ (ProfileType)supportedProfileTypes {
    return ProfileTypeTerminal;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.bounds;
    frame.size.height -= kMargin;
    _jobTreeViewController.view.frame = frame;
    [_jobTreeViewController sizeOutlineViewToFit];
}

- (void)shutdown {
    shutdown_ = YES;
}

- (void)fixCursor {
    if (!shutdown_) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
    }
}

- (BOOL)isFlipped {
    return YES;
}

- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    NSString *aString = [@(_processInfos[row].processID) stringValue];
    [pbItem setString:aString forType:UTTypeUTF8PlainText.identifier];
    return pbItem;
}

- (CGFloat)minimumHeight {
    return 76;
}

- (void)updateJobs {
    id<iTermToolbeltViewDelegate> delegate = self.toolWrapper.delegate.delegate;
    if (!delegate) {
        return;
    }
    // Each setter refreshes the tree only when its value changed.
    const pid_t pid = [delegate toolbeltCurrentShellProcessId];
    id<ProcessInfoProvider> provider = [delegate toolbeltCurrentShellProcessInfoProvider];
    if (pid != _jobTreeViewController.pid || provider != _jobTreeViewController.processInfoProvider) {
        DLog(@"Jobs tool: pid %@ from provider %@ (has it: %@)",
             @(pid), provider, @([provider processInfoForPid:pid] != nil));
    }
    _jobTreeViewController.pid = pid;
    _jobTreeViewController.processInfoProvider = provider;
}

@end
