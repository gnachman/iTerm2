#import "AATreeNode.h"


@implementation AATreeNode

@synthesize left;
@synthesize right;
@synthesize level;
@synthesize data;
@synthesize key;


- (id) initWithData:(id)aDataObject boundToKey:(id)aKey {

	if (self = [super init]) {
		self.data = aDataObject;
		self.key = aKey;
		self.level = 1;
	}

	return self;
}

- (NSString *)spaces:(int)n {
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < n; i++) {
    [s appendString:@" "];
  }
  return s;
}

- (NSString *)description {
  static int indent;
  indent += 2;
  NSString *result = [NSString stringWithFormat:@"<%@: %p key=%@ data=%@\n%@left=%p\n%@right=%p>",
                      self.class, self, self.key, self.data, [self spaces:indent], self.left, [self spaces:indent], self.right];
  indent -= 2;
  return result;
}

- (void) addKeyToArray:(NSMutableArray *)anArray {

	[left addKeyToArray:anArray];
	[anArray addObject:[[key copy] autorelease]];
	[right addKeyToArray:anArray];
}


- (id) copyWithZone:(NSZone *)zone {

	AATreeNode *copy = [[AATreeNode alloc] initWithData:data boundToKey:key];
	copy.left = [[left copy] autorelease];
	copy.right = [[right copy] autorelease];
	copy.level = level;
	return copy;
}


- (void) printWithIndent:(int)indent {

	if (right) [right printWithIndent:(indent+1)];

	NSMutableString *pre = [[NSMutableString alloc] init];
	for (int i=0; i<indent; i++) [pre appendString:@"   "];
	NSLog(@"%@%@-%@(%i)", pre, key, data, level);
	[pre release];

	if (left) [left printWithIndent:(indent+1)];
}

- (NSString *)stringWithIndent:(int)indent
                 dataFormatter:(NSString *(^NS_NOESCAPE)(NSString *, id data))dataFormatter {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    if (right) {
        NSString *s = [right stringWithIndent:(indent+1) dataFormatter:dataFormatter];
        if (s.length) {
            [parts addObject:s];
        }
    }

    NSMutableString *pre = [[NSMutableString alloc] init];
    for (int i=0; i<indent; i++) {
        [pre appendString:@"   "];
    }
    [parts addObject:[NSString stringWithFormat:@"%@%@- (%i)\n%@", pre, key, level, dataFormatter([pre stringByAppendingString:@" |-"], data)]];
    [pre release];

    if (left) {
        NSString *s = [left stringWithIndent:(indent+1) dataFormatter:dataFormatter];
        if (s.length) {
            [parts addObject:s];
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

#if DEBUG
- (void)setLeft:(AATreeNode *)newValue {
    @synchronized (self) {
        if ((newValue || self.right) && newValue == self.right) {
            NSLog(@"Setting left equal to right");
        }
        [left autorelease];
        left = [newValue retain];
    }
}

- (AATreeNode *)left {
    @synchronized (self) {
        return left;
    }
}

- (void)setRight:(AATreeNode *)newValue {
    @synchronized (self) {
        if ((newValue || self.left) && newValue == self.left) {
            NSLog(@"Setting right equal to left");
        }

        [right autorelease];
        right = [newValue retain];
    }
}

- (AATreeNode *)right {
    @synchronized (self) {
        return right;
    }
}
#endif

- (void) dealloc
{
	[left release];
	[right release];
	[data release];
	[key release];
    data = nil;
    key = nil;
	[super dealloc];
}


@end
