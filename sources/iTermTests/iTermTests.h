//
//  iTermTests.h
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import <Foundation/Foundation.h>

// This macro can be used in tests to document a known bug. The first expression would evaluate to
// true if the bug were fixed. Until then, the second expression unfortunately does evaluate to true.
#define ITERM_TEST_KNOWN_BUG(expressionThatShouldBeTrue, expressionThatIsTrue) \
do { \
  assert(!(expressionThatShouldBeTrue)); \
  assert((expressionThatIsTrue)); \
  NSLog(@"Known bug: %s should be true, but %s is.", #expressionThatShouldBeTrue, #expressionThatIsTrue); \
} while(0)

@protocol iTermTestProtocol

@optional
- (void)setup;

@optional
- (void)teardown;

@end

@interface iTermTest : NSObject <iTermTestProtocol>
@end
