// -*- mode:objc -*-
/*
 **  DVRIndexEntry.h
 **
 **  Copyright 20101
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Descriptor for a single DVR frame.
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

typedef struct {
    // Number of cells wide, tall
    int width;
    int height;

    // 0-based cursor position
    int cursorX;
    int cursorY;

    // Time in us since 1970 of frame.
    long long timestamp;

    // Value from DVRFrameType enum.
    int frameType;
} DVRFrameInfo;

@interface DVRIndexEntry : NSObject
{
@public
    // Frame metadata.
    DVRFrameInfo info;

    // Position in DVRBuffer's store.
    long long position;

    // Number of bytes in buffer.
    int frameLength;
}

+ (instancetype)entryFromDictionaryValue:(NSDictionary *)dict;

@property (nonatomic, readonly) NSDictionary *dictionaryValue;

@end
