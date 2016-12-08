//
//  ServiceProvider.h
//  iTerm2
//
//  Created by liupeng on 08/12/2016.
//
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
@interface ServiceProvider : NSObject
- (void)openTab:(NSPasteboard*)pasteboard : (NSString*) error;
- (void)openWindow:(NSPasteboard*)pasteboard : (NSString*) error;
@end
