#import <Foundation/Foundation.h>
#include <vector>
#import "iTermStrictWarnings.h"
int ok(void) { std::vector<int> v; v.push_back(1); return v[0]; }
