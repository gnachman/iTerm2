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

#import "DVRIndexEntry.h"


@implementation DVRIndexEntry

+ (instancetype)entryFromDictionaryValue:(NSDictionary *)dict {
    DVRIndexEntry *entry = [[[self alloc] init] autorelease];
    entry->position = [dict[@"position"] longLongValue];
    entry->frameLength = [dict[@"frameLength"] intValue];

    NSDictionary *infoDict = dict[@"info"];
    entry->info.width = [infoDict[@"width"] intValue];
    entry->info.height = [infoDict[@"height"] intValue];
    entry->info.cursorX = [infoDict[@"cursorX"] intValue];
    entry->info.cursorY = [infoDict[@"cursorY"] intValue];
    entry->info.timestamp = [infoDict[@"timestamp"] longLongValue];
    entry->info.frameType = [infoDict[@"frameType"] intValue];

    return entry;
}

- (NSDictionary *)dictionaryValue {
    return @{ @"info": @{ @"width": @(info.width),
                          @"height": @(info.height),
                          @"cursorX": @(info.cursorX),
                          @"cursorY": @(info.cursorY),
                          @"timestamp": @(info.timestamp),
                          @"frameType": @(info.frameType) },
              @"position": @(position),
              @"frameLength": @(frameLength) };
}

@end
