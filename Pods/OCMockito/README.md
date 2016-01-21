![mockito](http://docs.mockito.googlecode.com/hg/latest/org/mockito/logo.jpg)

OCMockito is an Objective-C implementation of Mockito, supporting creation,
verification and stubbing of mock objects.

Key differences from other mocking frameworks:

* Mock objects are always "nice," recording their calls instead of throwing
  exceptions about unspecified invocations. This makes tests less fragile.

* No expect-run-verify, making tests more readable. Mock objects record their
  calls, then you verify the methods you want.

* Verification failures are reported as unit test failures, identifying specific
  lines instead of throwing exceptions. This makes it easier to identify
  failures. (It also keeps the pre-iOS 5 Simulator from crashing.)


Adding OCMockito to your project
================================

__Building:__

If you want to build OCMockito yourself, cd to the Source folder, then

    $ ./MakeDistribution.sh

Or just use the pre-built release available in
[Downloads](https://github.com/jonreid/OCMockito/downloads).

__Mac Project Setup:__

Add both OCHamcrest.framework and OCMockito.framework and to your project.

Add a Copy Files build phase to copy both OCHamcrest.framework and
OCMockito.framework and to your Products Directory. For unit test bundles, make
sure this Copy Files phase comes before the Run Script phase that executes
tests.

Add:

    #define HC_SHORTHAND
    #import <OCHamcrest/OCHamcrest.h>

    #define MOCKITO_SHORTHAND
    #import <OCMockito/OCMockito.h>

Note: If your Console shows

    otest[57510:203] *** NSTask: Task create for path '...' failed: 22, "Invalid argument". Terminating temporary process.

double-check your Copy Files phase.

__iOS Project Setup:__

Add both OCHamcrestIOS.framework and OCMockitoIOS.framework to your project.

Add:

    #define HC_SHORTHAND
    #import <OCHamcrestIOS/OCHamcrestIOS.h>

    #define MOCKITO_SHORTHAND
    #import <OCMockitoIOS/OCMockitoIOS.h>


Let's verify some behavior!
===========================

    // mock creation
    NSMutableArray *mockArray = mock([NSMutableArray class]);

    // using mock object
    [mockArray addObject:@"one"];
    [mockArray removeAllObjects];

    // verification
    [verify(mockArray) addObject:@"one"];
    [verify(mockArray) removeAllObjects];

Once created, the mock will remember all interactions. Then you can selectively
verify whatever interactions you are interested in.


How about some stubbing?
========================

    // mock creation
    NSArray *mockArray = mock([NSArray class]);

    // stubbing
    [given([mockArray objectAtIndex:0]) willReturn:@"first"];

    // following prints "(null)" because objectAtIndex:999 was not stubbed
    NSLog(@"%@", [mockArray objectAtIndex:999]);


How do you mock a class object?
===============================

    Class mockStringClass = mockClass([NSString class]);


How do you mock a protocol?
===========================

    id <MyDelegate> delegate = mockProtocol(@protocol(MyDelegate));


How do you mock an object that also implements a protocol?
==========================================================

    UIViewController <CustomProtocol> *controller =
        mockObjectAndProtocol([UIViewController class], @protocol(CustomProtocol));


How do you stub methods that return non-objects?
================================================

To stub methods that return non-object types, specify ``willReturn<type>``,
like this:

    [given([mockArray count]) willReturnUnsignedInteger:3];


Argument matchers
=================

OCMockito verifies argument values by testing for equality. But when extra
flexibility is required, you can specify
 [OCHamcrest](https://github.com/hamcrest/OCHamcrest) matchers.

    // mock creation
    NSMutableArray *mockArray = mock([NSMutableArray class]);

    // using mock object
    [mockArray removeObject:@"This is a test"];

    // verification
    [verify(mockArray) removeObject:startsWith(@"This is")];

OCHamcrest matchers can be specified as arguments for both verification and
stubbing.


How do you specify matchers for primitive arguments?
====================================================

To stub a method that takes a primitive argument but specify a matcher, invoke
the method with a dummy argument, then call ``-withMatcher:forArgument:``

    [[given([mockArray objectAtIndex:0]) withMatcher:anything() forArgument:0]
     willReturn:@"foo"];

Use the shortcut ``-withMatcher:`` to specify a matcher for a single argument:

    [[given([mockArray objectAtIndex:0]) withMatcher:anything()]
     willReturn:@"foo"];


Verifying exact number of invocations / at least x / never
==========================================================

    // using mock
    [mockArray addObject:@"once"];

    [mockArray addObject:@"twice"];
    [mockArray addObject:@"twice"];

    // the following two verifications work exactly the same
    [verify(mockArray) addObject:@"once"];
    [verifyCount(mockArray, times(1)) addObject:@"once"];

    // verify exact number of invocations
    [verifyCount(mockArray, times(2)) addObject:@"twice"];
    [verifyCount(mockArray, times(3)) addObject:@"three times"];

    // verify using never(), which is an alias for times(0)
    [verifyCount(mockArray, never()) addObject:@"never happened"];

    // verify using atLeast
    [verifyCount(mockArray, atLeastOnce()) addObject:@"at least once"];
    [verifyCount(mockArray, atLeast(2)) addObject:@"at least twice"];


More resources
==============

* [Sources](https://github.com/jonreid/OCMockito)
* [OCHamcrest](https://github.com/hamcrest/OCHamcrest)
* [Quality Coding](http://qualitycoding.org/) - Tools, tips &
techniques for _building quality in_ to iOS development.
