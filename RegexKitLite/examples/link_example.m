#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSAutoreleasePool.h>
#import "RegexKitLite.h"

int main(int argc, char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  // Copyright COPYRIGHT_SIGN APPROXIMATELY_EQUAL_TO 2008
  // Copyright \u00a9 \u2245 2008

  char     *utf8CString =  "Copyright \xC2\xA9 \xE2\x89\x85 2008";
  NSString *regexString = @"Copyright (.*) (\\d+)";

  NSString *subjectString = [NSString stringWithUTF8String:utf8CString];
  NSString *matchedString = [subjectString stringByMatching:regexString capture:1L];

  NSLog(@"subject: \"%@\"", subjectString);
  NSLog(@"matched: \"%@\"", matchedString);

  [pool release];
  return(0);
}
