#import "PreferencesController.h"
#import "URLConnection.h"

NSString * const URLConnectionProxyValidityChangedNotification = @"URLConnectionProxyValidityChangedNotification";

// Private interface extension for NSURLSession properties
@interface URLConnection () {
    NSURLSessionDataTask *_dataTask;
    NSURLSession *_session;
}
@end

@implementation URLConnection

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb {
    URLConnection *connection = [[URLConnection alloc] init];
    
    // Initialize instance variables as defined in the header
    connection->stream = NULL;
    connection->cb = [cb copy];
    connection->bytes = [NSMutableData dataWithCapacity:100];
    connection->events = 0;
    
    // Create session configuration with proxy settings
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    [connection setHermesProxy];  // This will configure the proxy settings
    
    // Create session
    connection->_session = [NSURLSession sessionWithConfiguration:configuration
                                                      delegate:nil
                                                 delegateQueue:[NSOperationQueue mainQueue]];
    
    // Create data task
    connection->_dataTask = [connection->_session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data,
                                                                   NSURLResponse * _Nullable response,
                                                                   NSError * _Nullable error) {
        if (error) {
            connection->cb(nil, error);
            return;
        }
        
        if (data) {
            [connection->bytes appendData:data];
        }
        connection->cb(connection->bytes, nil);
    }];
    
    return connection;
}

- (void)start {
    events = 0;  // Reset events counter
    
    // Start timeout timer
    timeout = [NSTimer scheduledTimerWithTimeInterval:10
                                             target:self
                                           selector:@selector(checkTimeout)
                                           userInfo:nil
                                            repeats:YES];
    
    // Start the data task
    [_dataTask resume];
}

- (void)checkTimeout {
    if (events > 0 || cb == nil || _dataTask == nil) {
        events = 0;
        return;
    }
    
    [_dataTask cancel];
    NSError *error = [NSError errorWithDomain:@"Connection timeout."
                                       code:0
                                   userInfo:nil];
    cb(nil, error);
    cb = nil;
}

- (void)setHermesProxy {
    NSURLSessionConfiguration *configuration = _session.configuration;
    [URLConnection setHermesProxyForConfiguration:configuration];
}

+ (void)setHermesProxy:(CFReadStreamRef)stream {
    // This method is kept for header compatibility but is no longer used internally
    // The actual proxy configuration is now handled by setHermesProxyForConfiguration:
}

// Internal helper method for NSURLSession proxy configuration
+ (void)setHermesProxyForConfiguration:(NSURLSessionConfiguration *)configuration {
    switch (PREF_KEY_INT(ENABLED_PROXY)) {
        case PROXY_HTTP: {
            NSString *host = PREF_KEY_VALUE(PROXY_HTTP_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_HTTP_PORT);
            if ([self validProxyHost:&host port:port]) {
                configuration.connectionProxyDictionary = @{
                    (__bridge NSString *)kCFProxyTypeHTTP: @YES,
                    (__bridge NSString *)kCFProxyHostNameKey: host,
                    (__bridge NSString *)kCFProxyPortNumberKey: @(port),
                    (__bridge NSString *)kCFProxyTypeHTTPS: @YES,
                    (__bridge NSString *)kCFProxyHostNameKey: host,
                    (__bridge NSString *)kCFProxyPortNumberKey: @(port)
                };
            }
            break;
        }
        case PROXY_SOCKS: {
            NSString *host = PREF_KEY_VALUE(PROXY_SOCKS_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_SOCKS_PORT);
            if ([self validProxyHost:&host port:port]) {
                configuration.connectionProxyDictionary = @{
                    (__bridge NSString *)kCFProxyTypeSOCKS: @YES,
                    (__bridge NSString *)kCFProxyHostNameKey: host,
                    (__bridge NSString *)kCFProxyPortNumberKey: @(port)
                };
            }
            break;
        }
        case PROXY_SYSTEM:
        default:
            configuration.connectionProxyDictionary = CFBridgingRelease(CFNetworkCopySystemProxySettings());
            break;
    }
}

+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port {
    static BOOL wasValid = YES;
    *host = [*host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL isValid = ((port > 0 && port <= 65535) && [NSHost hostWithName:*host].address != nil);
    if (isValid != wasValid) {
        [[NSNotificationCenter defaultCenter] postNotificationName:URLConnectionProxyValidityChangedNotification
                                                          object:nil
                                                        userInfo:@{@"isValid": @(isValid)}];
        wasValid = isValid;
    }
    return isValid;
}

- (void)dealloc {
    [timeout invalidate];
    [_dataTask cancel];
    [_session finishTasksAndInvalidate];
    if (stream != NULL) {
        CFRelease(stream);
    }
}

@end
