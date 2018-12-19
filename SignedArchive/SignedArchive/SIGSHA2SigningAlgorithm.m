//
//  SIGSHA2SigningAlgorithm.m
//  SignedArchive
//
//  Created by George Nachman on 12/18/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGSHA2SigningAlgorithm.h"

#import "SIGError.h"
#import "SIGIdentity.h"
#import "SIGKey.h"

@implementation SIGSHA2SigningAlgorithm {
    SecTransformRef readTransform;
    SecTransformRef dataDigestTransform;
    SecTransformRef dataSignTransform;
    SecGroupTransformRef group;
}

+ (NSString *)name {
    return @"SHA2";
}

- (void)dealloc {
    if (readTransform) {
        CFRelease(readTransform);
    }
    if (dataDigestTransform) {
        CFRelease(dataDigestTransform);
    }
    if (dataSignTransform) {
        CFRelease(dataSignTransform);
    }
    if (group) {
        CFRelease(group);
    }
}

- (NSData *)signatureForInputStream:(NSInputStream *)readStream
                      usingIdentity:(SIGIdentity *)identity
                              error:(out NSError **)error {
    CFErrorRef err = NULL;
    
    SIGKey *privateKey = identity.privateKey;
    if (!privateKey) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPrivateKey];
        }
        return nil;
    }
    
    readTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)readStream);
    if (!readTransform) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create read transform"];
        }
        return nil;
    }
    
    dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA2,
                                                   256,
                                                   &err);
    if (!dataDigestTransform) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create SHA2 digest transform"];
        }
        return nil;
    }
    
    dataSignTransform = SecSignTransformCreate(privateKey.secKey,
                                               &err);
    if (!dataSignTransform) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create private key transform"];
        }
        return nil;
    }
    
    SecTransformSetAttribute(dataSignTransform,
                             kSecInputIsAttributeName,
                             kSecInputIsDigest,
                             &err);
    if (err) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to set is-digest attribute"];
        }
        return nil;
    }
    
    SecTransformSetAttribute(dataSignTransform,
                             kSecDigestTypeAttribute,
                             kSecDigestSHA2,
                             &err);
    if (err) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to set digest-type attribute"];
        }
        return nil;
    }
    
    SecTransformSetAttribute(dataSignTransform,
                             kSecDigestLengthAttribute,
                             (__bridge CFTypeRef _Nonnull)@256,
                             &err);
    if (err) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to set digest-length attribute"];
        }
        return nil;
    }
    
    group = SecTransformCreateGroupTransform();
    SecTransformConnectTransforms(readTransform,
                                  kSecTransformOutputAttributeName,
                                  dataDigestTransform,
                                  kSecTransformInputAttributeName,
                                  group,
                                  &err);
    if (err != nil) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to conenct read to digest transform"];
        }
        return nil;
    }
    
    SecTransformConnectTransforms(dataDigestTransform,
                                  kSecTransformOutputAttributeName,
                                  dataSignTransform,
                                  kSecTransformInputAttributeName,
                                  group,
                                  &err);
    if (err != nil) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to connect digest to sign transform"];
        }
        return nil;
    }
    
    NSData *signature = (__bridge_transfer NSData *)SecTransformExecute(group, &err);
    if (err != nil) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Execution of signature algorithm failed"];
        }
        return nil;
    }
    
    return signature;
}

@end
