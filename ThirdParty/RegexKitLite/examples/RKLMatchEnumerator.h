#import <Foundation/NSEnumerator.h>
#import <Foundation/NSString.h>
#import "RegexKitLite.h"
#include <stddef.h>

@interface NSString (RegexKitLiteEnumeratorAdditions)
// matchEnumeratorWithRegex: is deprecated in favor of componentsMatchedByRegex:
- (NSEnumerator *)matchEnumeratorWithRegex:(NSString *)regex RKL_DEPRECATED_ATTRIBUTE;
@end
