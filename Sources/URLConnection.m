#import "PreferencesController.h"
#import "URLConnection.h"

NSString * const URLConnectionProxyValidityChangedNotification = @"URLConnectionProxyValidityChangedNotification";
static const NSTimeInterval kURLConnectionTimeoutSeconds = 15.0;

@implementation URLConnection

- (void)dealloc {
  [self->dataTask cancel];
  [self->timeoutTimer invalidate];
  self->timeoutTimer = nil;
}

+ (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = kURLConnectionTimeoutSeconds;
    config.timeoutIntervalForResource = 45.0;
    return config;
}

- (void)beginTimeout {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->timeoutTimer invalidate];
        if (!self->started || self->cb == nil) {
            return;
        }
        self->timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kURLConnectionTimeoutSeconds
                                                              target:self
                                                            selector:@selector(connectionTimedOut)
                                                            userInfo:nil
                                                             repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:self->timeoutTimer forMode:NSRunLoopCommonModes];
    });
}

- (void)invalidateTimeout {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->timeoutTimer invalidate];
        self->timeoutTimer = nil;
    });
}

- (void)connectionTimedOut {
    if (!self->started) {
        return;
    }
    self->started = NO;
    [self->dataTask cancel];
    URLConnectionCallback callback = self->cb;
    self->cb = nil;
    [self invalidateTimeout];
    if (callback) {
        NSError *timeoutError = [NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorTimedOut
                                                userInfo:@{ NSLocalizedDescriptionKey: @"Connection timed out." }];
        callback(nil, timeoutError);
    }
}

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb {
    URLConnection *c = [[self alloc] init];
    c->cb = [cb copy];
    c->bytes = [NSMutableData dataWithCapacity:100];
    
    // Create session configuration
    NSURLSessionConfiguration *config = [self sessionConfiguration];
    [self setHermesProxy:config];  // Use the class method to set proxy
    
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
      // Dispatch callback to main thread to avoid UI thread issues
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf->started = NO;
            [strongSelf invalidateTimeout];
            URLConnectionCallback callback = strongSelf->cb;
            strongSelf->cb = nil;
            if (!callback) {
                return;
            }
            if (error) {
                callback(nil, error);
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
                callback(nil, httpError);
                return;
            }

            if (data != nil) {
                [strongSelf->bytes appendData:data];
            }
            callback(strongSelf->bytes, nil);
        });
    }];
    
    return c;
}

- (void)start {
    started = YES;
    [self beginTimeout];
    [dataTask resume];
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
    NSURLSessionConfiguration *config = [[self class] sessionConfiguration];
    [[self class] setHermesProxy:config];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // Create new data task with the same request
    dataTask = [session dataTaskWithRequest:currentRequest
                         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self invalidateTimeout];
            URLConnectionCallback callback = self->cb;
            self->cb = nil;
            self->started = NO;
            if (!callback) {
                return;
            }

            if (error) {
                callback(nil, error);
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
                callback(nil, httpError);
                return;
            }

            if (data != nil) {
                [self->bytes appendData:data];
            }
            callback(self->bytes, nil);
        });
    }];
    
    // Resume the new task if we were already started
    if (self->started) {
        [dataTask resume];
        [self beginTimeout];
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
