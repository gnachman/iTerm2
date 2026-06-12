// -*- mode:objc -*-
/*
 **  FontSizeEstimator.h
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Attempts to measure font metrics because the OS's metrics
 **    are sometimes unreliable.
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


@interface FontSizeEstimator : NSObject {
    NSSize size;
    double baseline;
}

@property (nonatomic, assign) NSSize size;

// Returns a text container and layout manager that are ready to measure a capital W.
+ (NSTextContainer *)textContainer;
+ (NSLayoutManager *)layoutManagerForFont:(NSFont *)aFont textContainer:(NSTextContainer *)textContainer;

+ (instancetype)fontSizeEstimatorForFont:(NSFont *)aFont;

@end
