![ochamcrest](http://hamcrest.org/images/logo.jpg)

What is OCHamcrest?
===================

OCHamcrest is:

* a library of "matcher" objects that let you declare rules for whether a given
  object matches the criteria or not.
* a framework for writing your own matchers.

Matchers are useful for a variety of purposes, such as UI validation. But
they're most commonly used for writing unit tests that are expressive and
flexible.

OCHamcrest is used for both iOS or OS X development, and is compatible with:

* OCUnit (SenTestingKit)
* Kiwi
* Cedar
* GHUnit
* Google Toolbox for Mac (GTM)
* OCMock
* OCMockito


How do I add OCHamcrest to my project?
======================================

__Building:__

If you want to build OCHamcrest yourself, clone the repo, then

```sh
$ git submodule update --init
$ cd Source
$ ./MakeDistribution.sh
```

Or just use the pre-built release available at
[QualityCoding.org](http://qualitycoding.org/resources/).

__iOS Project Setup:__

Add OCHamcrestIOS.framework to your project.

Add:

    #define HC_SHORTHAND
    #import <OCHamcrestIOS/OCHamcrestIOS.h>

__OS X Project Setup:__

Add OCHamcrest.framework to your project.

Add a Copy Files build phase to copy OCHamcrest.framework to your Products
Directory. For unit test bundles, make sure this Copy Files phase comes before
the Run Script phase that executes tests.

Add:

    #define HC_SHORTHAND
    #import <OCHamcrest/OCHamcrest.h>

Note: If your Console shows

    otest[57510:203] *** NSTask: Task create for path '...' failed: 22, "Invalid argument".  Terminating temporary process.

double-check your Copy Files phase.


My first OCHamcrest test
========================

We'll start by writing a very simple Xcode unit test, but instead of using
OCUnit's ``STAssertEqualObjects`` function, we'll use OCHamcrest's
``assertThat`` construct and a predefined matcher:

```obj-c
#import <SenTestingKit/SenTestingKit.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

@interface BiscuitTest : SenTestCase
@end

@implementation BiscuitTest

- (void)testEquals
{
    Biscuit* theBiscuit = [Biscuit biscuitNamed:@"Ginger"];
    Biscuit* myBiscuit = [Biscuit biscuitNamed:@"Ginger"];
    assertThat(theBiscuit, equalTo(myBiscuit));
}

@end
```

The ``assertThat`` function is a stylized sentence for making a test assertion.
In this example, the subject of the assertion is the object ``theBiscuit``,
which is the first method parameter. The second method parameter is a matcher
for ``Biscuit`` objects, here a matcher that checks one object is equal to
another using the ``-isEqual:`` method. The test passes since the ``Biscuit``
class defines an ``-isEqual:`` method.

OCHamcrest's functions are actually declared with an "HC" package prefix (such
as ``HC_assertThat`` and ``HC_equalTo``) to avoid name clashes. To make test
writing faster and test code more legible, shorthand macros are provided if
``HC_SHORTHAND`` is defined before including the OCHamcrest header. For example,
instead of writing ``HC_assertThat``, simply write ``assertThat``.


Predefined matchers
===================

OCHamcrest comes with a library of useful matchers:

* Object

  * ``conformsTo`` - match object that conforms to protocol
  * ``equalTo`` - match equal object
  * ``hasDescription`` - match object's ``-description``
  * ``hasProperty`` - match return value of method with given name
  * ``instanceOf`` - match object type
  * ``isA`` - match object type precisely, no subclasses
  * ``nilValue``, ``notNilValue`` - match ``nil``, or not ``nil``
  * ``sameInstance`` - match same object

* Number

  * ``closeTo`` - match number close to a given value
  * equalTo&lt;TypeName&gt; - match number equal to a primitive number (such as
  ``equalToInt`` for an ``int``)
  * ``greaterThan``, ``greaterThanOrEqualTo``, ``lessThan``,
  ``lessThanOrEqualTo`` - match numeric ordering

* Text

  * ``containsString`` - match part of a string
  * ``endsWith`` - match the end of a string
  * ``equalToIgnoringCase`` - match the complete string but ignore case
  * ``equalToIgnoringWhitespace`` - match the complete string but ignore
  extra whitespace
  * ``startsWith`` - match the beginning of a string
  * ``stringContainsInOrder`` - match parts of a string, in relative order

* Logical

  * ``allOf`` - "and" together all matchers
  * ``anyOf`` - "or" together all matchers
  * ``anything`` - match anything (useful in composite matchers when you don't
  care about a particular value)
  * ``isNot`` - negate the matcher

* Collection

  * ``contains`` - exactly match the entire collection
  * ``containsInAnyOrder`` - match the entire collection, but in any order
  * ``empty`` - match empty collection
  * ``hasCount`` - match number of elements against another matcher
  * ``hasCountOf`` - match collection with given number of elements
  * ``hasEntries`` - match dictionary with list of key-value pairs
  * ``hasEntry`` - match dictionary containing a key-value pair
  * ``hasItem`` - match if given item appears in the collection
  * ``hasItems`` - match if all given items appear in the collection, in any order
  * ``hasKey`` - match dictionary with a key
  * ``hasValue`` - match dictionary with a value
  * ``onlyContains`` - match if collection's items appear in given list

* Decorator

  * ``describedAs`` - give the matcher a custom failure description
  * ``is`` - decorator to improve readability - see `Syntactic sugar` below

The arguments for many of these matchers accept not just a matching value, but
another matcher, so matchers can be composed for greater flexibility. For
example, ``only_contains(endsWith(@"."))`` will match any collection where
every item is a string ending with period.


Syntactic sugar
===============

OCHamcrest strives to make your tests as readable as possible. For example, the
``is`` matcher is a wrapper that doesn't add any extra behavior to the
underlying matcher. The following assertions are all equivalent:

```obj-c
assertThat(theBiscuit, equalTo(myBiscuit));
assertThat(theBiscuit, is(equalTo(myBiscuit)));
assertThat(theBiscuit, is(myBiscuit));
```

The last form is allowed since ``is`` wraps non-matcher arguments with
``equalTo``. Other matchers that take matchers as arguments provide similar
shortcuts, wrapping non-matcher arguments in ``equalTo``.


Writing custom matchers
=======================

OCHamcrest comes bundled with lots of useful matchers, but you'll probably find
that you need to create your own from time to time to fit your testing needs.
This commonly occurs when you find a fragment of code that tests the same set of
properties over and over again (and in different tests), and you want to bundle
the fragment into a single assertion. By writing your own matcher you'll
eliminate code duplication and make your tests more readable!

Let's write our own matcher for testing if a calendar date falls on a Saturday.
This is the test we want to write:

```obj-c
- (void)testDateIsOnASaturday
{
    NSCalendarDate* date = [NSCalendarDate dateWithString:@"26 Apr 2008" calendarFormat:@"%d %b %Y"];
    assertThat(date, is(onASaturday()))
}
```

Here's the interface:

```obj-c
#import <OCHamcrest/HCBaseMatcher.h>
#import <objc/objc-api.h>

@interface IsGivenDayOfWeek : HCBaseMatcher
{
    NSInteger day;      // Sunday is 0, Saturday is 6
}

+ (id)isGivenDayOfWeek:(NSInteger)dayOfWeek;
- (id)initWithDay:(NSInteger)dayOfWeek;

@end

OBJC_EXPORT id <HCMatcher> onASaturday();
```

The interface consists of two parts: a class definition, and a factory function
(with C binding). Here's what the implementation looks like:

```obj-c
#import "IsGivenDayOfWeek.h"
#import <OCHamcrest/HCDescription.h>

@implementation IsGivenDayOfWeek

+ (id)isGivenDayOfWeek:(NSInteger)dayOfWeek
{
    return [[self alloc] initWithDay:dayOfWeek];
}

- (id)initWithDay:(NSInteger)dayOfWeek
{
    self = [super init];
    if (self)
        day = dayOfWeek;
    return self;
}

// Test whether item matches.
- (BOOL)matches:(id)item
{
    if (![item respondsToSelector:@selector(dayOfWeek)])
        return NO;

    return [item dayOfWeek] == day;
}

// Describe the matcher.
- (void)describeTo:(id <HCDescription>)description
{
    NSString* dayAsString[] =
        { @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" };
    [[description appendText:@"calendar date falling on "] appendText:dayAsString[day]];
}

@end


id <HCMatcher> onASaturday()
{
    return [IsGivenDayOfWeek isGivenDayOfWeek:6];
}
```

For our Matcher implementation we implement the ``-matches:`` method (which
calls ``-dayOfWeek`` after confirming that the argument has such a method) and
the ``-describe_to:`` method (which is used to produce a failure message when a
test fails). Here's an example of how the failure message looks:

    NSCalendarDate* date = [NSCalendarDate dateWithString: @"6 April 2008" calendarFormat: @"%d %B %Y"];
    assertThat(date, is(onASaturday()));

fails with the message

    Expected: is calendar date falling on Saturday, got: <06 April 2008>

and Xcode shows it as a build error. Clicking the error message takes you to the
assertion that failed.

Even though the ``onASaturday`` function creates a new matcher each time it is
called, you should not assume this is the only usage pattern for your matcher.
Therefore you should make sure your matcher is stateless, so a single instance
can be reused between matches.


More resources
==============

* [Documentation](http://hamcrest.org/OCHamcrest/)
* [Sources](https://github.com/hamcrest/OCHamcrest)
* [Hamcrest](http://hamcrest.org)
* [Quality Coding](http://qualitycoding.org/) - Tools, tips &
techniques for _building quality in_ to iOS development
