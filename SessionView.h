// -*- mode:objc -*-
/*
 **  SessionView.h
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: This view contains a session's scrollview.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <Cocoa/Cocoa.h>
#import "FindViewController.h"
#import "PTYSession.h"
#import "SessionTitleView.h"

@class PTYSession;
@class SplitSelectionView;
@class SessionTitleView;

@interface SessionView : NSView <SessionTitleViewDelegate> {
    PTYSession* session_;
    BOOL dim_;
    BOOL backgroundDimmed_;

    float currentDimmingAmount_;
    NSDate* previousUpdate_;
    float changePerSecond_;
    float targetDimmingAmount_;
    NSTimer* timer_;
    BOOL shuttingDown_;

    // Find window
    FindViewController* findView_;

    // Unique per-process id of view, used for ordering them in PTYTab.
    int viewId_;

    // Saved size for unmaximizing.
    NSSize savedSize_;

    // When moving a pane, a view is put over all sessions to help the user
    // choose how to split the destination.
    SplitSelectionView *splitSelectionView_;

    BOOL showTitle_;
    SessionTitleView *title_;
}

+ (NSDate*)lastResizeDate;
+ (void)windowDidResize;
- (id)initWithFrame:(NSRect)frame session:(PTYSession*)session;
- (void)dealloc;
- (PTYSession*)session;
- (void)setSession:(PTYSession*)session;
- (void)setDimmed:(BOOL)isDimmed;
- (void)cancelTimers;
- (FindViewController*)findViewController;
- (int)viewId;
- (void)setViewId:(int)id;
- (void)setBackgroundDimmed:(BOOL)backgroundDimmed;
- (void)updateDim;
- (BOOL)backgroundDimmed;
- (void)saveFrameSize;
- (void)restoreFrameSize;
- (void)setSplitSelectionMode:(SplitSelectionMode)mode;
- (BOOL)setShowTitle:(BOOL)value;
- (void)setTitle:(NSString *)title;

@end
