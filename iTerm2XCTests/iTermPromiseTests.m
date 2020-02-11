//
//  iTermPromiseTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 2/10/20.
//

#import <XCTest/XCTest.h>
#import "iTermPromise.h"

@interface iTermPromiseTests : XCTestCase

@end

@implementation iTermPromiseTests {
    NSError *_standardError;
}

- (void)setUp {
    _standardError = [[NSError alloc] initWithDomain:@"com.iterm2.promise-tests"
                                                code:123
                                            userInfo:nil];
}

- (void)tearDown {
    [_standardError release];
}

- (void)testFulfillFollowedByThen {
    iTermPromise<NSNumber *> *promise = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        [seal fulfill:@123];
    }];
    __block BOOL ranThen = NO;
    [promise then:^(NSNumber * _Nonnull value) {
        XCTAssertEqualObjects(value, @123);
        ranThen = YES;
    }];
    XCTAssertTrue(ranThen);
}

- (void)testFulfillFollowedByCatchError {
    iTermPromise<NSNumber *> *promise = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        [seal reject:_standardError];
    }];
    __block BOOL ranThen = NO;
    [promise catchError:^(NSError *error) {
        XCTAssertEqual(error, _standardError);
        ranThen = YES;
    }];
    XCTAssertTrue(ranThen);
}

- (void)testThenFollowedByFulfill {
    __block id<iTermPromiseSeal> savedSeal = nil;
    iTermPromise<NSNumber *> *promise = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        savedSeal = [[seal retain] autorelease];
    }];

    __block BOOL ranThen = NO;
    [promise then:^(NSNumber * _Nonnull value) {
        XCTAssertEqualObjects(value, @123);
        ranThen = YES;
    }];

    XCTAssertFalse(ranThen);

    [savedSeal fulfill:@123];
    XCTAssertTrue(ranThen);
}

- (void)testThenFollowedByCatchError {
    __block id<iTermPromiseSeal> savedSeal = nil;
    iTermPromise<NSNumber *> *promise = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        savedSeal = [[seal retain] autorelease];
    }];

    __block BOOL ranThen = NO;
    [promise catchError:^(NSError *value) {
        XCTAssertEqual(value, _standardError);
        ranThen = YES;
    }];

    XCTAssertFalse(ranThen);

    [savedSeal reject:_standardError];
    XCTAssertTrue(ranThen);
}

- (void)testFulfillFollowedByChain {
    iTermPromise<NSNumber *> *promise1 = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        [seal fulfill:@123];
    }];
    __block int count = 0;
    iTermPromise<NSNumber *> *promise2 = [promise1 then:^(NSNumber *value) {
        XCTAssertEqualObjects(value, @123);
        count++;
    }];
    iTermPromise<NSNumber *> *promise3 = [promise2 then:^(NSNumber *value) {
        XCTAssertEqualObjects(value, @123);
        count++;
    }];
    iTermPromise<NSNumber *> *promise4 = [promise3 catchError:^(NSError *error) {
        XCTFail(@"%@", error);
    }];
    [promise4 then:^(NSNumber * value) {
        XCTAssertEqualObjects(value, @123);
        count++;
    }];
    XCTAssertEqual(count, 3);
}

- (void)testChainFollowedByFulfill {
    __block id<iTermPromiseSeal> savedSeal = nil;
    iTermPromise<NSNumber *> *promise1 = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        savedSeal = [[seal retain] autorelease];
    }];
    __block int count = 0;
    iTermPromise<NSNumber *> *promise2 = [promise1 then:^(NSNumber * _Nonnull value) {
        XCTAssertEqualObjects(value, @123);
        count++;
    }];
    iTermPromise<NSNumber *> *promise3 = [promise2 then:^(NSNumber *value) {
        XCTAssertEqualObjects(value, @123);
        count++;
    }];
    iTermPromise<NSNumber *> *promise4 = [promise3 catchError:^(NSError *error) {
        XCTFail(@"%@", error);
    }];
    [promise4 then:^(NSNumber * value) {
        XCTAssertEqualObjects(value, @123);
        count++;
    }];
    XCTAssertEqual(count, 0);

    [savedSeal fulfill:@123];
    XCTAssertEqual(count, 3);
}

- (void)testRejectFollowedByChain {
    iTermPromise<NSNumber *> *promise1 = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        [seal reject:_standardError];
    }];
    __block int count = 0;
    iTermPromise<NSNumber *> *promise2 = [promise1 then:^(NSNumber * _Nonnull value) {
        XCTFail(@"%@", value);
    }];
    iTermPromise<NSNumber *> *promise3 = [promise2 catchError:^(NSError *error) {
        XCTAssertEqual(error, _standardError);
        count++;
    }];
    iTermPromise<NSNumber *> *promise4 = [promise3 catchError:^(NSError *error) {
        XCTAssertEqual(error, _standardError);
        count++;
    }];
    [promise4 then:^(NSNumber * value) {
        XCTFail(@"Shouldn't be called");
    }];
    XCTAssertEqual(count, 2);
}

- (void)testChainFollowedByReject {
    __block id<iTermPromiseSeal> savedSeal = nil;
    iTermPromise<NSNumber *> *promise1 = [iTermPromise promise:^(id<iTermPromiseSeal> seal) {
        savedSeal = [[seal retain] autorelease];
    }];
    __block int count = 0;
    iTermPromise<NSNumber *> *promise2 = [promise1 then:^(NSNumber * _Nonnull value) {
        XCTFail(@"%@", value);
    }];
    iTermPromise<NSNumber *> *promise3 = [promise2 catchError:^(NSError *error) {
        XCTAssertEqual(error, _standardError);
        count++;
    }];
    iTermPromise<NSNumber *> *promise4 = [promise3 catchError:^(NSError *error) {
        XCTAssertEqual(error, _standardError);
        count++;
    }];
    [promise4 then:^(NSNumber * value) {
        XCTFail(@"Shouldn't be called");
    }];
    XCTAssertEqual(count, 0);

    [savedSeal reject:_standardError];
    XCTAssertEqual(count, 2);
}

@end
