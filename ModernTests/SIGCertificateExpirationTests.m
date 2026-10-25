//
//  SIGCertificateExpirationTests.m
//  ModernTests
//
//  Tangential finding T-97: -[SIGCertificate expirationDate] asked for the invalidity
//  date extension (kSecOIDInvalidityDate) rather than the validity period's Not After
//  date, relying on Security synthesizing an “Expires” entry for it. A failed trust
//  evaluation was also reported with SIGErrorCodeTrust (“Error creating trust object”)
//  instead of SIGErrorCodeTrustFailed.
//

#import <XCTest/XCTest.h>

#import "SIGCertificate.h"
#import "SIGError.h"
#import "SIGPolicy.h"
#import "SIGTrust.h"

// A self-signed P-256 certificate, CN=Expiration Test, valid from
// 2020-01-01 00:00:00 UTC through 2038-01-19 03:14:07 UTC. Generated with:
// openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes
//   -subj "/CN=Expiration Test" -not_before 20200101000000Z
//   -not_after 20380119031407Z -outform DER
static NSString *const SIGCertificateExpirationTestsCertificate =
    @"MIIBaTCCAQ6gAwIBAgIUYDIrzhN8/ww6gIthJ0dAkQfJgsMwCgYIKoZIzj0EAwIwGjEYMBYGA1UE"
    @"AwwPRXhwaXJhdGlvbiBUZXN0MB4XDTIwMDEwMTAwMDAwMFoXDTM4MDExOTAzMTQwN1owGjEYMBYG"
    @"A1UEAwwPRXhwaXJhdGlvbiBUZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAERjR1Vtj84sXB"
    @"1z6cUEQ0y24a4dSxo3uYzzOKsFLHHz1dC7S0DEh2fG1Wkt6VYkKTBNbuiYP9iHi+dW9tYugbgaMy"
    @"MDAwHQYDVR0OBBYEFMIqGudiRdDm4+zTkrYyOtcI1Ti+MA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZI"
    @"zj0EAwIDSQAwRgIhAPPZsygeKpCq8LJ/IYInLrRZTMLeAWBNfhHxo+FcqQtKAiEAxWXpMhoZD9Jo"
    @"XdtRtuwNaLxVuXRm/MbixttWJRzn2nY=";

@interface SIGCertificateExpirationTests : XCTestCase
@end

@implementation SIGCertificateExpirationTests

- (SIGCertificate *)certificate {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:SIGCertificateExpirationTestsCertificate
                                                       options:0];
    XCTAssertNotNil(data);
    SIGCertificate *certificate = [[SIGCertificate alloc] initWithData:data];
    XCTAssertNotNil(certificate);
    return certificate;
}

- (void)testExpirationDateIsNotAfter {
    NSDate *actual = [[self certificate] expirationDate];
    XCTAssertNotNil(actual);
    XCTAssertEqualWithAccuracy(actual.timeIntervalSince1970, 2147483647, 0.001);
}

// The certificate is not trusted, so evaluation fails, and the error must say so rather
// than claim the trust object could not be created.
- (void)testUntrustedCertificateReportsTrustFailed {
    NSError *error = nil;
    SIGTrust *trust = [[SIGTrust alloc] initWithCertificates:@[ [self certificate] ]
                                                    policies:@[ [[SIGX509Policy alloc] init] ]
                                                       error:&error];
    XCTAssertNotNil(trust);
    XCTAssertNil(error);

    XCTestExpectation *done = [self expectationWithDescription:@"evaluation completes"];
    __block BOOL trusted = YES;
    __block NSError *evaluationError = nil;
    [trust evaluateWithCompletion:^(BOOL ok, NSError *innerError) {
        trusted = ok;
        evaluationError = innerError;
        [done fulfill];
    }];
    [self waitForExpectations:@[ done ] timeout:30];

    XCTAssertFalse(trusted);
    XCTAssertEqual(evaluationError.code, SIGErrorCodeTrustFailed);
}

@end
