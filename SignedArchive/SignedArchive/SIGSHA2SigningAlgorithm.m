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
    SecTransformRef _readTransform;
    SecTransformRef _dataDigestTransform;
    SecTransformRef _dataSignTransform;
    SecGroupTransformRef _group;
}

+ (NSString *)name {
    return @"SHA2";
}

- (void)dealloc {
    if (_readTransform) {
        CFRelease(_readTransform);
    }
    if (_dataDigestTransform) {
        CFRelease(_dataDigestTransform);
    }
    if (_dataSignTransform) {
        CFRelease(_dataSignTransform);
    }
    if (_group) {
        CFRelease(_group);
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
    
    _readTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)readStream);
    if (!_readTransform) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create read transform"];
        }
        return nil;
    }
    
    _dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA2,
                                                   256,
                                                   &err);
    if (!_dataDigestTransform) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create SHA2 digest transform"];
        }
        return nil;
    }
    
    _dataSignTransform = SecSignTransformCreate(privateKey.secKey,
                                               &err);
    if (!_dataSignTransform) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to create private key transform"];
        }
        return nil;
    }
    
    SecTransformSetAttribute(_dataSignTransform,
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
    
    SecTransformSetAttribute(_dataSignTransform,
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
    
    SecTransformSetAttribute(_dataSignTransform,
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
    
    _group = SecTransformCreateGroupTransform();
    SecTransformConnectTransforms(_readTransform,
                                  kSecTransformOutputAttributeName,
                                  _dataDigestTransform,
                                  kSecTransformInputAttributeName,
                                  _group,
                                  &err);
    if (err != nil) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to conenct read to digest transform"];
        }
        return nil;
    }
    
    SecTransformConnectTransforms(_dataDigestTransform,
                                  kSecTransformOutputAttributeName,
                                  _dataSignTransform,
                                  kSecTransformInputAttributeName,
                                  _group,
                                  &err);
    if (err != nil) {
        if (error) {
            *error = [SIGError errorWrapping:(__bridge NSError *)err
                                      code:SIGErrorCodeAlgorithmCreationFailed
                                      detail:@"Failed to connect digest to sign transform"];
        }
        return nil;
    }
    
    NSData *signature = (__bridge_transfer NSData *)SecTransformExecute(_group, &err);
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
