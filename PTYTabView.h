/*
 **  PTYTabView.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: NSTabView subclass. Implements drag and drop.
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@protocol PTYTabViewDelegateProtocol
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)index;
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView;
- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem;
- (NSDragOperation)tabView:(NSTabView *)tabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)sender;
- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender;
- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;
@end

@interface PTYTabView : NSTabView {
    BOOL isModifierPressed;
    BOOL wereTabsNavigatedWithMRU;
    NSMutableArray* mruTabs;
    // Modifiers that are being used for cycling tabs. Only valid if
    // isModifierPressed is true.
    NSUInteger tabMRUModifierMask_;
}

// Class methods that Apple should have provided
+ (NSSize)contentSizeForFrameSize:(NSSize)frameSize tabViewType:(NSTabViewType)type controlSize:(NSControlSize)controlSize;
+ (NSSize)frameSizeForContentSize:(NSSize)contentSize tabViewType:(NSTabViewType)type controlSize:(NSControlSize)controlSize;

- (id)initWithFrame:(NSRect)aFrame;
- (void)dealloc;
- (BOOL)acceptsFirstResponder;
- (void)drawRect:(NSRect)rect;

// NSTabView methods overridden
- (void)addTabViewItem:(NSTabViewItem *)aTabViewItem;
- (void)removeTabViewItem:(NSTabViewItem *)aTabViewItem;
- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)theIndex;

// selects a tab from the contextual menu
- (void)selectTab:(id)sender;

- (void)nextTab:(id)sender;
- (void)previousTab:(id)sender;

// selects next most recently used tab (MRU)
- (BOOL)processMRUEvent:(NSEvent*)event;

// Override setDelegate so that it accepts PSMTabBarControl without warning
- (void)setDelegate:(id<PTYTabViewDelegateProtocol>)anObject;

@end
