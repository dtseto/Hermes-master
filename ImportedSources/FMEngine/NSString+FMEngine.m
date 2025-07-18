//
//  NSString+UUID.m
//  LastFMAPI
//
//  Created by Nicolas Haunold on 4/26/09.
//  Copyright 2009 Tapolicious Software. All rights reserved.
//

//#import <CommonCrypto/CommonDigest.h>
// For CryptoKit approach (iOS 13+/macOS 10.15+):
//#import <CryptoKit/CryptoKit.h>

// Thanks to Sam Steele / c99koder for -[NSString md5sum];

#import "NSString+FMEngine.h"
#import <CommonCrypto/CommonDigest.h>

@implementation NSString (FMEngineAdditions)

+ (NSString *)stringWithNewUUID {
    // Fix: Use modern NSUUID instead of deprecated CFUUID functions
    NSUUID *uuid = [NSUUID UUID];
    return [uuid UUIDString];
}

- (NSString*)urlEncoded {
    // Define the characters that are allowed in the URL
    NSCharacterSet *allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:
                                       @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    
    // Use modern URL encoding method
    return [self stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters];
}

- (NSString *)md5sum {
    // Suppress deprecation warnings for MD5 functions
    // MD5 is still needed for API compatibility despite being deprecated
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    
    const char *cStr = [self UTF8String];
    NSUInteger length = strlen(cStr);
    
    CC_MD5_CTX md5Context;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    
    CC_MD5_Init(&md5Context);
    CC_MD5_Update(&md5Context, cStr, (CC_LONG)length);
    CC_MD5_Final(digest, &md5Context);
    
#pragma clang diagnostic pop
    
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", digest[i]];
    }
    
    return [result copy];
}
@end
