// Read by Probe.m but not by the bridging header.
#import <Foundation/Foundation.h>

@interface ProbeHidden : NSObject
- (void)secret;
@end
