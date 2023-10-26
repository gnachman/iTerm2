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
        _jobTreeViewController.font = [NSFont it_toolbeltFont];
        _jobTreeViewController.animateChanges = NO;
        [self addSubview:_jobTreeViewController.view];
        [self relayout];
    }
    return self;
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
    [pbItem setString:aString forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
}

- (CGFloat)minimumHeight {
    return 76;
}

- (void)updateJobs {
    _jobTreeViewController.pid = [self.toolWrapper.delegate.delegate toolbeltCurrentShellProcessId];
    _jobTreeViewController.processInfoProvider = [self.toolWrapper.delegate.delegate toolbeltCurrentShellProcessInfoProvider];
}

@end
