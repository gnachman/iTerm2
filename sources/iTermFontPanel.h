//
//  iTermFontPanel.h
//  iTerm
//
//  Created by George Nachman on 3/18/12.
//  Copyright (c) 2012 Georgetech. All rights reserved.
//

#import <AppKit/AppKit.h>

#define kValidModesForFontPanel (NSFontPanelFaceModeMask | NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask)
@interface iTermFontPanel : NSFontPanel

+ (void)makeDefault;

@end
