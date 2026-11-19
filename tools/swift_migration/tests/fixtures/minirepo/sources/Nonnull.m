#import <Foundation/Foundation.h>
#import "Base.h"

#define DECLARE_GENERATED(t) \
@interface t : Base \
@end

DECLARE_GENERATED(Generated)

NS_ASSUME_NONNULL_BEGIN

static BOOL NonnullIsValid(NSString *s) {
    return s.length > 0;
}

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
static int sNonnullCount;
NS_ASSUME_NONNULL_END

BOOL NonnullCheck(NSString *s) {
    sNonnullCount++;
    return NonnullIsValid(s);
}
