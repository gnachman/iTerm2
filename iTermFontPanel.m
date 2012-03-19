//
//  iTermFontPanel.m
//  iTerm
//
//  Created by George Nachman on 3/18/12.
//  Copyright (c) 2012 Georgetech. All rights reserved.
//

#import "iTermFontPanel.h"

@implementation iTermFontPanel

+ (void)makeDefault
{
    [NSFontManager setFontPanelFactory:[iTermFontPanel class]];
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}

@end
