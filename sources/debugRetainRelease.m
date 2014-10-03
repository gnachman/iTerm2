id debugsession = 0;
- (id)retain
{
    id rv = [super retain];
    if (self == debugsession) 
        NSLog(@"Session %@ retained. rc=%d. \n%@", self, [self retainCount], [NSThread callStackSymbols]);
    return rv;
}

- (oneway void)release
{
    if (self == debugsession) 
        NSLog(@"Session %@ released. rc=%d. \n%@", self, [self retainCount]-1, [NSThread callStackSymbols]);
    [super release];
}

- (id)autorelease
{
    id rv = [super autorelease];
    if (self == debugsession) 
        NSLog(@"Session %@ autoreleased. rc=%d. \n%@", self, [self retainCount], [NSThread callStackSymbols]);
    return rv;
}

