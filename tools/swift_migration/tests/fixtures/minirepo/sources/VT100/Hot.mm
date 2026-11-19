#import "Hot.h"
#include <vector>

@implementation Hot {
    std::vector<int> _values;
}

- (void)add:(int)v {
    _values.push_back(v);
}

@end
