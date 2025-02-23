//
//  Keychain.m
//  Hermes
//
//  Created by Alex Crichton on 11/19/11.
//

#import "Keychain.h"
#import <Security/Security.h>


BOOL KeychainSetItem(NSString* username, NSString* password) {
    if (!username || !password) {
        return NO;
    }
    
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    
    // Create dictionary of search parameters
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kSecClassGenericPassword, kSecClass,
        @KEYCHAIN_SERVICE_NAME, kSecAttrService,
        username, kSecAttrAccount,
        nil];
    
    // First, check if the item already exists
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, NULL);
    
    if (status == errSecSuccess) {
        // Item exists, update it
        NSDictionary *attributesToUpdate = [NSDictionary dictionaryWithObjectsAndKeys:
            passwordData, kSecValueData,
            nil];
        
        status = SecItemUpdate((CFDictionaryRef)query,
                             (CFDictionaryRef)attributesToUpdate);
    } else if (status == errSecItemNotFound) {
        // Item doesn't exist, create it
        NSMutableDictionary *newItem = [query mutableCopy];
        [newItem setObject:passwordData forKey:(id)kSecValueData];
        
        status = SecItemAdd((CFDictionaryRef)newItem, NULL);
        [newItem release];
    }
    
    return status == errSecSuccess;
}

NSString *KeychainGetPassword(NSString* username) {
    if (!username) {
        return nil;
    }
    
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kSecClassGenericPassword, kSecClass,
        @KEYCHAIN_SERVICE_NAME, kSecAttrService,
        username, kSecAttrAccount,
        (id)kCFBooleanTrue, kSecReturnData,
        kSecMatchLimitOne, kSecMatchLimit,
        nil];
    
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);
    
    if (status != errSecSuccess) {
        return nil;
    }
    
    NSData *passwordData = (NSData *)result;
    NSString *password = [[[NSString alloc] initWithData:passwordData
                                              encoding:NSUTF8StringEncoding] autorelease];
    CFRelease(result);
    
    return password;

/*  SecKeychainItemRef item = nil;
  OSStatus result = SecKeychainFindGenericPassword(
    NULL,
    strlen(KEYCHAIN_SERVICE_NAME),
    KEYCHAIN_SERVICE_NAME,
    (UInt32)[username length],
    [username UTF8String],
    NULL,
    NULL,
    &item);

  if (result == noErr) {
    result = SecKeychainItemModifyContent(item, NULL, (UInt32)[password length],
                                          [password UTF8String]);
  } else {
    result = SecKeychainAddGenericPassword(
      NULL,
      strlen(KEYCHAIN_SERVICE_NAME),
      KEYCHAIN_SERVICE_NAME,
      (UInt32)[username length],
      [username UTF8String],
      (UInt32)[password length],
      [password UTF8String],
      NULL);
  }

  if (item) {
    CFRelease(item);
  }
  return result == noErr;
}

NSString *KeychainGetPassword(NSString* username) {
  void *passwordData = NULL;
  UInt32 length;
  OSStatus result = SecKeychainFindGenericPassword(
    NULL,
    strlen(KEYCHAIN_SERVICE_NAME),
    KEYCHAIN_SERVICE_NAME,
    (UInt32)[username length],
    [username UTF8String],
    &length,
    &passwordData,
    NULL);

  if (result != noErr) {
    return nil;
  }
  
  NSString *password = [[NSString alloc] initWithBytes:passwordData
                                           length:length
                                         encoding:NSUTF8StringEncoding];
  SecKeychainItemFreeContent(NULL, passwordData);

  return password;
 
 */

}
