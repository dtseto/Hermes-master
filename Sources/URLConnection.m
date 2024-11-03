#import "PreferencesController.h"
#import "URLConnection.h"

NSString * const URLConnectionProxyValidityChangedNotification = @"URLConnectionProxyValidityChangedNotification";

<<<<<<< Updated upstream
@implementation URLConnection

static void URLConnectionStreamCallback(CFReadStreamRef aStream,
                                        CFStreamEventType eventType,
                                        void* _conn) {
  UInt8 buf[1024];
  CFIndex len;
  URLConnection* conn = (__bridge URLConnection*) _conn;
  conn->events++;

  switch (eventType) {
    case kCFStreamEventHasBytesAvailable:
      while ((len = CFReadStreamRead(aStream, buf, sizeof(buf))) > 0) {
        [conn->bytes appendBytes:buf length:len];
      }
      return;
    case kCFStreamEventErrorOccurred:
      conn->cb(nil, (__bridge_transfer NSError*) CFReadStreamCopyError(aStream));
      break;
    case kCFStreamEventEndEncountered: {
      conn->cb(conn->bytes, nil);
      break;
    }
    default:
      assert(0);
  }

  conn->cb = nil;
  [conn->timeout invalidate];
  conn->timeout = nil;
  CFReadStreamClose(conn->stream);
  CFRelease(conn->stream);
  conn->stream = nil;
=======
@interface URLConnection () {
    NSURLSessionDataTask *_dataTask;
    NSURLSession *_session;
}
@end

@implementation URLConnection

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb {
    URLConnection *connection = [[URLConnection alloc] init];
    
    // Initialize instance variables exactly as defined in header
    connection->stream = NULL;
    connection->cb = [cb copy];
    connection->bytes = [NSMutableData dataWithCapacity:100];
    connection->timeout = nil;
    connection->events = 0;
    
    // Create session configuration
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    // Create session
    connection->_session = [NSURLSession sessionWithConfiguration:configuration
                                                      delegate:nil
                                                 delegateQueue:[NSOperationQueue mainQueue]];
    
    // Apply proxy settings before creating data task
    [connection setHermesProxy];
    
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
>>>>>>> Stashed changes
}

- (void) dealloc {
  [timeout invalidate];
  if (stream != nil) {
    CFReadStreamClose(stream);
    CFRelease(stream);
  }
}

/**
 * @brief Creates a new instance for the specified request
 *
 * @param request the request to be sent
 * @param cb the callback to invoke when the request is done. If an error
 *        happened, then the data will be nil, and the error will be valid.
 *        Otherwise the data will be valid and the error will be nil.
 */
+ (URLConnection*) connectionForRequest:(NSURLRequest*)request
                      completionHandler:(void(^)(NSData*, NSError*)) cb {

  URLConnection *c = [[URLConnection alloc] init];

  /* Create the HTTP message to send */
  CFHTTPMessageRef message =
      CFHTTPMessageCreateRequest(NULL,
                                 (__bridge CFStringRef)[request HTTPMethod],
                                 (__bridge CFURLRef)   [request URL],
                                 kCFHTTPVersion1_1);

  /* Copy headers over */
  NSDictionary *headers = [request allHTTPHeaderFields];
  for (NSString *header in headers) {
    CFHTTPMessageSetHeaderFieldValue(message,
                         (__bridge CFStringRef) header,
                         (__bridge CFStringRef) headers[header]);
  }

  /* Also the http body */
  if ([request HTTPBody] != nil) {
    CFHTTPMessageSetBody(message, (__bridge CFDataRef) [request HTTPBody]);
  }
  c->stream = CFReadStreamCreateForHTTPRequest(NULL, message);
  CFRelease(message);

  /* Handle SSL connections */
  NSString *urlstring = [[request URL] absoluteString];
  if ([urlstring rangeOfString:@"https"].location == 0) {
    NSDictionary *settings =
    @{(id)kCFStreamSSLLevel: (NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL,
     (id)kCFStreamSSLValidatesCertificateChain: @NO,
     (id)kCFStreamSSLPeerName: [NSNull null]};

    CFReadStreamSetProperty(c->stream, kCFStreamPropertySSLSettings,
                            (__bridge CFDictionaryRef) settings);
  }

  c->cb = [cb copy];
  c->bytes = [NSMutableData dataWithCapacity:100];
  [c setHermesProxy];
  return c;
}

/**
 * @brief Start sending this request to the server
 */
- (void) start {
  CFReadStreamOpen(stream);
  CFStreamStatus streamStatus = CFReadStreamGetStatus(stream);
  if (streamStatus == kCFStreamStatusError) {
    cb(nil, (NSError *)CFBridgingRelease(CFReadStreamCopyError(stream)));
    return;
  }
  if (streamStatus != kCFStreamStatusOpen)
    NSLog(@"Expected read stream to be open, but it was not (%ld)", (long)streamStatus);

  CFStreamClientContext context = {0, (__bridge_retained void*) self, NULL,
                                   NULL, NULL};
  CFReadStreamSetClient(stream,
                        kCFStreamEventHasBytesAvailable |
                          kCFStreamEventErrorOccurred |
                          kCFStreamEventEndEncountered,
                        URLConnectionStreamCallback,
                        &context);
  CFReadStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(),
                                  kCFRunLoopCommonModes);
  timeout = [NSTimer scheduledTimerWithTimeInterval:10
                                             target:self
                                           selector:@selector(checkTimeout)
                                           userInfo:nil
                                            repeats:YES];
}

- (void) checkTimeout {
  if (events > 0 || cb == nil || stream == NULL) {
    events = 0;
    return;
  }

  CFReadStreamClose(stream);
  CFRelease(stream);
  // FIXME: Most definitely a cause of "Internal Pandora Error".
  NSError *error = [NSError errorWithDomain:@"Connection timeout."
                                       code:0
                                   userInfo:nil];
  cb(nil, error);
  cb = nil;
}

<<<<<<< Updated upstream
- (void) setHermesProxy {
  [URLConnection setHermesProxy:stream];
}

/**
 * @brief Helper for setting whatever proxy is specified in the Hermes
 *        preferences
 */
+ (void) setHermesProxy:(CFReadStreamRef) stream {
  switch (PREF_KEY_INT(ENABLED_PROXY)) {
    case PROXY_HTTP:
      [self setHTTPProxy:stream
                    host:PREF_KEY_VALUE(PROXY_HTTP_HOST)
                    port:PREF_KEY_INT(PROXY_HTTP_PORT)];
      break;

    case PROXY_SOCKS:
      [self setSOCKSProxy:stream
                     host:PREF_KEY_VALUE(PROXY_SOCKS_HOST)
                     port:PREF_KEY_INT(PROXY_SOCKS_PORT)];
      break;

    case PROXY_SYSTEM:
    default:
      [self setSystemProxy:stream];
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
=======
- (void)setHermesProxy {
    if (!_session) {
        NSLog(@"Error: No session available for proxy configuration");
        return;
    }
    
    NSURLSessionConfiguration *configuration = _session.configuration;
    NSMutableDictionary *proxyDict = [NSMutableDictionary new];
    
    switch (PREF_KEY_INT(ENABLED_PROXY)) {
        case PROXY_HTTP: {
            NSString *host = PREF_KEY_VALUE(PROXY_HTTP_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_HTTP_PORT);
            if ([URLConnection validProxyHost:&host port:port]) {
                // HTTP Proxy settings
                [proxyDict addEntriesFromDictionary:@{
                    (NSString *)kCFProxyTypeKey: (NSString *)kCFProxyTypeHTTP,
                    (NSString *)kCFProxyHostNameKey: host,
                    (NSString *)kCFProxyPortNumberKey: @(port),
                    (NSString *)kCFStreamPropertyHTTPSProxyHost: host,
                    (NSString *)kCFStreamPropertyHTTPSProxyPort: @(port)
                }];
                NSLog(@"HTTP proxy configured: %@:%ld", host, (long)port);
            } else {
                NSLog(@"Invalid HTTP proxy configuration: %@:%ld", host, (long)port);
            }
            break;
        }
        
        case PROXY_SOCKS: {
            NSString *host = PREF_KEY_VALUE(PROXY_SOCKS_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_SOCKS_PORT);
            if ([URLConnection validProxyHost:&host port:port]) {
                // SOCKS Proxy settings
                [proxyDict addEntriesFromDictionary:@{
                    (NSString *)kCFProxyTypeKey: (NSString *)kCFProxyTypeSOCKS,
                    (NSString *)kCFProxyHostNameKey: host,
                    (NSString *)kCFProxyPortNumberKey: @(port),
                    (NSString *)kCFStreamPropertySOCKSProxyHost: host,
                    (NSString *)kCFStreamPropertySOCKSProxyPort: @(port)
                }];
                NSLog(@"SOCKS proxy configured: %@:%ld", host, (long)port);
            } else {
                NSLog(@"Invalid SOCKS proxy configuration: %@:%ld", host, (long)port);
            }
            break;
        }
        
        case PROXY_SYSTEM:
        default: {
            CFDictionaryRef systemProxySettings = CFNetworkCopySystemProxySettings();
            if (systemProxySettings) {
                proxyDict = [(__bridge NSDictionary *)systemProxySettings mutableCopy];
                CFRelease(systemProxySettings);
                NSLog(@"System proxy settings applied");
            } else {
                NSLog(@"Failed to get system proxy settings");
            }
            break;
        }
    }
    
    if (proxyDict.count > 0) {
        // Configure session with proxy settings
        configuration.connectionProxyDictionary = proxyDict;
        
        // Enable necessary session features
        configuration.HTTPShouldUsePipelining = YES;
        configuration.HTTPShouldSetCookies = YES;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        // Recreate session with new configuration
        NSURLSession *newSession = [NSURLSession sessionWithConfiguration:configuration
                                                               delegate:nil
                                                          delegateQueue:[NSOperationQueue mainQueue]];
        
        // Clean up old session and assign new one
        [_session finishTasksAndInvalidate];
        _session = newSession;
        
        NSLog(@"Proxy configuration applied to session");
    } else {
        NSLog(@"No proxy configuration applied");
    }
}

+ (void)setHermesProxy:(CFReadStreamRef)stream {
    if (!stream) return;
    
    CFDictionaryRef proxyDict = NULL;
    
    switch (PREF_KEY_INT(ENABLED_PROXY)) {
        case PROXY_HTTP: {
            NSString *host = PREF_KEY_VALUE(PROXY_HTTP_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_HTTP_PORT);
            if ([self validProxyHost:&host port:port]) {
                const CFStringRef keys[] = {
                    kCFProxyTypeKey,
                    kCFProxyHostNameKey,
                    kCFProxyPortNumberKey
                };
                const void *values[] = {
                    kCFProxyTypeHTTP,
                    (__bridge CFStringRef)host,
                    (__bridge CFNumberRef)@(port)
                };
                proxyDict = CFDictionaryCreate(NULL, (const void **)&keys,
                                             (const void **)&values, 3,
                                             &kCFTypeDictionaryKeyCallBacks,
                                             &kCFTypeDictionaryValueCallBacks);
            }
            break;
        }
        
        case PROXY_SOCKS: {
            NSString *host = PREF_KEY_VALUE(PROXY_SOCKS_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_SOCKS_PORT);
            if ([self validProxyHost:&host port:port]) {
                const CFStringRef keys[] = {
                    kCFProxyTypeKey,
                    kCFProxyHostNameKey,
                    kCFProxyPortNumberKey
                };
                const void *values[] = {
                    kCFProxyTypeSOCKS,
                    (__bridge CFStringRef)host,
                    (__bridge CFNumberRef)@(port)
                };
                proxyDict = CFDictionaryCreate(NULL, (const void **)&keys,
                                             (const void **)&values, 3,
                                             &kCFTypeDictionaryKeyCallBacks,
                                             &kCFTypeDictionaryValueCallBacks);
            }
            break;
        }
        
        case PROXY_SYSTEM:
        default:
            proxyDict = CFNetworkCopySystemProxySettings();
            break;
    }
    
    if (proxyDict) {
        CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxyDict);
        CFRelease(proxyDict);
    }
}

+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port {
    static BOOL wasValid = YES;
    
    if (!host || !*host) return NO;
    
    *host = [*host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL isValid = ((port > 0 && port <= 65535) &&
                   [NSHost hostWithName:*host].address != nil);
    
    if (isValid != wasValid) {
        [[NSNotificationCenter defaultCenter] postNotificationName:URLConnectionProxyValidityChangedNotification
                                                          object:nil
                                                        userInfo:@{@"isValid": @(isValid)}];
        wasValid = isValid;
    }
    
    return isValid;
>>>>>>> Stashed changes
}

+ (BOOL) setHTTPProxy:(CFReadStreamRef)stream
                 host:(NSString*)host
                 port:(NSInteger)port {
  if (![self validProxyHost:&host port:port]) return NO;
  CFDictionaryRef proxySettings = (__bridge CFDictionaryRef)
          [NSDictionary dictionaryWithObjectsAndKeys:
                  host, kCFStreamPropertyHTTPProxyHost,
                  @(port), kCFStreamPropertyHTTPProxyPort,
                  host, kCFStreamPropertyHTTPSProxyHost,
                  @(port), kCFStreamPropertyHTTPSProxyPort,
                  nil];
  CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxySettings);
  return YES;
}

+ (BOOL) setSOCKSProxy:(CFReadStreamRef)stream
                 host:(NSString*)host
                 port:(NSInteger)port {
  if (![self validProxyHost:&host port:port]) return NO;
  CFDictionaryRef proxySettings = (__bridge CFDictionaryRef)
          [NSDictionary dictionaryWithObjectsAndKeys:
                  host, kCFStreamPropertySOCKSProxyHost,
                  @(port), kCFStreamPropertySOCKSProxyPort,
                  nil];
  CFReadStreamSetProperty(stream, kCFStreamPropertySOCKSProxy, proxySettings);
  return YES;
}

+ (void) setSystemProxy:(CFReadStreamRef)stream {
  CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
  CFReadStreamSetProperty(stream, kCFStreamPropertyHTTPProxy, proxySettings);
  CFRelease(proxySettings);
}

@end
