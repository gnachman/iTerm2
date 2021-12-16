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
@property (nonatomic, readonly) NSColorSpace *colorSpace;

+ (instancetype)grabFromScreen:(NSScreen *)screen colorSpace:(NSColorSpace *)colorSpace;
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y;

@end

