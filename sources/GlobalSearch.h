// -*- mode:objc -*-
/*
 **  GlobalSearchView.h
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Logic and custom NSView subclass for searching all tabs
 **    simultaneously.
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
#import "FutureMethods.h"

@interface GlobalSearchView : NSView


- (void)drawRect:(NSRect)rect;

@end

@class iTermSearchField;
@class PTYSession;

@protocol GlobalSearchDelegate <NSObject>

- (void)globalSearchSelectionChangedToSession:(PTYSession*)theSession;
- (void)globalSearchOpenSelection;
- (void)globalSearchViewDidResize:(NSRect)origSize;
- (void)globalSearchCanceled;

@end

@interface GlobalSearch : NSViewController <NSTableViewDataSource>

@property(nonatomic, readonly) int numResults;

- (void)setDelegate:(id<GlobalSearchDelegate>)delegate;
- (void)abort;

@end
