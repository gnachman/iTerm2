//
//  iTermStatusBarView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermTuple.h"

@interface iTermStatusBarView : NSView

// color, x offset
@property (nonatomic, copy) NSArray<iTermTuple<NSColor *, NSNumber *> *> *sections;

@end
