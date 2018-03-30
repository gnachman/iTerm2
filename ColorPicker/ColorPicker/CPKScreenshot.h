//
//  CPKScreenshot.h
//  ColorPicker
//
//  Created by George Nachman on 3/29/18.
//  Copyright © 2018 Google. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface CPKScreenshot : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic) CGSize size;

+ (instancetype)grabFromScreen:(NSScreen *)screen;
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y;

@end

