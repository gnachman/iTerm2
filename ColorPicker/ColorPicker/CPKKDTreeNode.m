#import "CPKKDTreeNode.h"

@implementation CPKKDTreeNode

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p object=%@ key=%@ left=%p right=%p>",
               NSStringFromClass([self class]),
               self,
               self.object,
               self.keyDescription,
               self.leftChild,
               self.rightChild];
}

- (double)distanceTo:(NSArray *)key {
    NSAssert(key.count == self.key.count, @"Keys differ in dimensionality");
    double sumOfSquares;
    for (NSInteger i = 0; i < key.count; i++) {
        double difference = [key[i] doubleValue] - [self.key[i] doubleValue];
        sumOfSquares += difference * difference;
    }
    return sqrt(sumOfSquares);
}

- (NSString *)keyDescription {
    NSMutableArray *components = [NSMutableArray array];
    for (NSNumber *n in self.key) {
        [components addObject:[NSString stringWithFormat:@"%.2f", n.doubleValue]];
    }
    return [components componentsJoinedByString:@","];
}

- (NSString *)dot {
    NSMutableString *result = [NSMutableString string];
    if (self.leftChild) {
        [result appendFormat:@"\"%@ @ %@\" -> \"%@ @ %@\"\n",
            self.object, self.keyDescription, self.leftChild.object, self.leftChild.keyDescription];
        [result appendString:self.leftChild.dot];
    }
    if (self.rightChild) {
        [result appendFormat:@"\"%@ @ %@\" -> \"%@ @ %@\"\n",
            self.object, self.keyDescription, self.rightChild.object,
            self.rightChild.keyDescription];
        [result appendString:self.rightChild.dot];
    }
    return result;
}

@end
