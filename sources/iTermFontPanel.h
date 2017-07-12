//
//  iTermFontPanel.h
//  iTerm
//
//  Created by George Nachman on 3/18/12.
//  Copyright (c) 2012 Georgetech. All rights reserved.
//

#import <AppKit/AppKit.h>

#define kValidModesForFontPanel (NSFontPanelFaceModeMask | NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask)

#if !defined(__MAC_10_13)
#define NSFontPanelModeMask NSUInteger
#endif

@interface iTermFontPanel : NSFontPanel

+ (void)makeDefault;

@end
