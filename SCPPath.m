//
//  SCPPath.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "SCPPath.h"

@implementation SCPPath

- (void)dealloc {
    [_path release];
    [_hostname release];
    [_username release];
    [super dealloc];
}

@end
