//
//  UnitTests.m
//
//  Created by Nick Lockwood on 12/01/2012.
//  Copyright (c) 2012 Charcoal Design. All rights reserved.
//


#import <XCTest/XCTest.h>
#import "GZIP.h"


static NSData *createRandomNSData()
{
    NSUInteger size = 10 * 1024 * 1024; // 10mb
    NSMutableData *data = [NSMutableData dataWithLength:size];
    u_int32_t *bytes = (u_int32_t *)data.mutableBytes;
    for (NSUInteger index = 0; index < size/sizeof(u_int32_t); index++)
    {
        bytes[index] = arc4random();
    }
    return data;
}


@interface UnitTests : XCTestCase

@end


@implementation UnitTests

- (void)testOutputEqualsInput
{
    //set up data
    NSString *inputString = @"Hello World!";
    NSData *inputData = [inputString dataUsingEncoding:NSUTF8StringEncoding];

    //compress
    NSData *compressedData = [inputData gzippedData];

    //decode
    NSData *outputData = [compressedData gunzippedData];
    NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(outputString, inputString);
}

- (void)testUnzipNonZippedData
{
    //set up data
    NSString *inputString = @"Hello World!";
    NSData *inputData = [inputString dataUsingEncoding:NSUTF8StringEncoding];

    //decode
    NSData *outputData = [inputData gunzippedData];
    NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(outputString, inputString);
}

- (void)testRezipZippedData
{
    //set up data
    NSString *inputString = @"Hello World!";
    NSData *inputData = [inputString dataUsingEncoding:NSUTF8StringEncoding];

    //compress
    NSData *compressedData = [inputData gzippedData];

    //compress again
    NSData *outputData = [compressedData gzippedData];
    XCTAssertEqualObjects(compressedData, outputData);
}

- (void)testZeroLengthInput
{
    NSData *data = [[NSData data] gzippedData];
    XCTAssertEqual(data.length, 0);

    data = [[NSData data] gunzippedData];
    XCTAssertEqual(data.length, 0);
}

- (void)testCompressionPerformance
{
    NSData *inputData = createRandomNSData();
    [self measureBlock:^{
        __unused NSData *compressedData = [inputData gzippedData];
    }];
}

- (void)testDecompressionPerformance
{
    NSData *inputData = createRandomNSData();
    NSData *compressedData = [inputData gzippedData];
    [self measureBlock:^{
        __unused NSData *outputData = [compressedData gunzippedData];
    }];
}

@end
