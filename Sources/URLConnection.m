#import "PreferencesController.h"
#import "URLConnection.h"

NSString * const URLConnectionProxyValidityChangedNotification = @"URLConnectionProxyValidityChangedNotification";

@implementation URLConnection

- (void)dealloc {
//    [timeout invalidate];
//    [dataTask cancel];
  [self->dataTask cancel];
  [self->timeout invalidate];

}

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb {
    URLConnection *c = [[URLConnection alloc] init];
    c->cb = [cb copy];
    c->bytes = [NSMutableData dataWithCapacity:100];
    
    // Create session configuration
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    [URLConnection setHermesProxy:config];  // Use the class method to set proxy
    
  // Add Create weak reference to avoid retain cycle and crashes
  __weak URLConnection *weakSelf = c;

    // Create session and data task
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    c->dataTask = [session dataTaskWithRequest:request
                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      
      // Strong reference inside block - safe to use
      __strong URLConnection *strongSelf = weakSelf;
      if (!strongSelf) {
          // Object was deallocated, safely exit
          return;
      }
      
      // First, invalidate the timeout timer
      [strongSelf->timeout invalidate];
      strongSelf->timeout = nil;

      // First, invalidate the timeout timer to prevent it from firing after we've received a response
//      [c->timeout invalidate];
//      c->timeout = nil;

      
      // Dispatch callback to main thread to avoid UI thread issues
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
              strongSelf->cb(nil, error); //strong
              //  c->cb(nil, error);
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode >= 400) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]
                };
                NSError *httpError = [NSError errorWithDomain:@"HTTPError"
                                                       code:httpResponse.statusCode
                                                   userInfo:userInfo];
              strongSelf->cb(nil, httpError);
              //c->cb(nil, httpError);
                return;
            }
            
          [strongSelf->bytes appendData:data];
          strongSelf->cb(strongSelf->bytes, nil);

           // [c->bytes appendData:data];
          //  c->cb(c->bytes, nil);
        });
    }];
    
    return c;
}

- (void)start {
    events = 0;
    [dataTask resume];
    
    timeout = [NSTimer scheduledTimerWithTimeInterval:10
                                             target:self
                                           selector:@selector(checkTimeout)
                                           userInfo:nil
                                            repeats:YES];
}

- (void)checkTimeout {
    if (events > 0 || cb == nil || dataTask == nil) {
        events = 0;
        return;
    }
    
    [dataTask cancel];
    NSError *error = [NSError errorWithDomain:@"Connection timeout."
                                       code:NSURLErrorTimedOut
                                   userInfo:nil];
    cb(nil, error);
    cb = nil;
}

- (void)setHermesProxy {

  if (!dataTask) {
      // If dataTask doesn't exist yet, just return - we'll handle proxy settings elsewhere
      return;
  }

    // Get current request from existing data task
    NSURLRequest *currentRequest = dataTask.currentRequest;
    [dataTask cancel]; // Cancel existing task
    
    // Create new configuration and session
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    [URLConnection setHermesProxy:config];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // Create new data task with the same request
    dataTask = [session dataTaskWithRequest:currentRequest
                         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            self->cb(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]
            };
            NSError *httpError = [NSError errorWithDomain:@"HTTPError"
                                                   code:httpResponse.statusCode
                                               userInfo:userInfo];
            self->cb(nil, httpError);
            return;
        }
        
        [self->bytes appendData:data];
        self->cb(self->bytes, nil);
    }];
    
    // Resume the new task if we were already started
    if (self->events > 0) {
        [dataTask resume];
    }
}

+ (void)setHermesProxy:(NSURLSessionConfiguration*)config {
    if (!config) return;
    
    switch (PREF_KEY_INT(ENABLED_PROXY)) {
        case PROXY_HTTP: {
            NSString *host = PREF_KEY_VALUE(PROXY_HTTP_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_HTTP_PORT);
            [self setHTTPProxy:config host:host port:port];
            break;
        }
        case PROXY_SYSTEM:
        default:
            [self setSystemProxy:config];
            break;
    }
}

+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port {
    static BOOL wasValid = YES;
    
    if (!host || !*host || [*host length] == 0) {
        NSLog(@"Invalid proxy host: null or empty");
        return NO;
    }
    
    *host = [*host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    
    if (port <= 0 || port > 65535) {
        NSLog(@"Invalid proxy port: %ld", (long)port);
        return NO;
    }
    
    NSHost *proxyHost = [NSHost hostWithName:*host];
    BOOL isValid = (proxyHost.address != nil);
    
    if (!isValid) {
        NSLog(@"Cannot resolve proxy host: %@", *host);
    } else {
        NSLog(@"Proxy host resolved to: %@", proxyHost.address);
    }
    
    if (isValid != wasValid) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:URLConnectionProxyValidityChangedNotification
            object:nil
            userInfo:@{@"isValid": @(isValid)}];
        wasValid = isValid;
    }
    
    return isValid;
}

+ (BOOL)setHTTPProxy:(NSURLSessionConfiguration*)config host:(NSString*)host port:(NSInteger)port {
    if (!config || ![self validProxyHost:&host port:port]) {
        return NO;
    }
    
    NSLog(@"Setting HTTP proxy to %@:%ld", host, (long)port);
    
    config.connectionProxyDictionary = @{
        @"HTTPEnable": @YES,
        @"HTTPProxy": host,
        @"HTTPPort": @(port),
        @"HTTPSEnable": @YES,
        @"HTTPSProxy": host,
        @"HTTPSPort": @(port)
    };
    
    return YES;
}

+ (void)setSystemProxy:(NSURLSessionConfiguration*)config {
    if (!config) return;
    config.connectionProxyDictionary = CFBridgingRelease(CFNetworkCopySystemProxySettings());
}

@end
