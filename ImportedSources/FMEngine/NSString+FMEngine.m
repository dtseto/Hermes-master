#import "NSString+FMEngine.h"
#import <CommonCrypto/CommonDigest.h>

@implementation NSString (FMEngineAdditions)

+ (NSString *)stringWithNewUUID {
    CFUUIDRef uuidObj = CFUUIDCreate(nil);
    NSString *newUUID = (__bridge_transfer NSString*)CFUUIDCreateString(nil, uuidObj);
    CFRelease(uuidObj);
    return newUUID;
}

- (NSString*)urlEncoded {
    // Create a character set with all characters that we want to escape
    NSCharacterSet *allowedCharacters = [[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"] invertedSet];
    
    // Use modern URL encoding method
    return [self stringByAddingPercentEncodingWithAllowedCharacters:
            [allowedCharacters invertedSet]];
}

- (NSString *)md5sum {
    unsigned char digest[CC_MD5_DIGEST_LENGTH], i;
    CC_MD5([self UTF8String], (uint32_t)[self lengthOfBytesUsingEncoding:NSUTF8StringEncoding], digest);
    NSMutableString *ms = [NSMutableString string];
    for (i=0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ms appendFormat: @"%02x", (int)(digest[i])];
    }
    return [ms copy];
}

@end
