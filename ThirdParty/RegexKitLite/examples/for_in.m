#import <Foundation/Foundation.h>
#import "RegexKitLite.h"

int main(int argc, char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSString   *searchString = @"one\ntwo\n\nfour\n";
  NSString   *regexString  = @"(?m)^.*$";
  NSUInteger  line         = 0UL;

  NSLog(@"searchString: '%@'", searchString);
  NSLog(@"regexString : '%@'", regexString);

  for(NSString *matchedString in [searchString componentsMatchedByRegex:regexString]) {
    NSLog(@"%lu: %lu '%@'", (u_long)++line, (u_long)[matchedString length], matchedString);
  }

  [pool release];
  return(0);
}
