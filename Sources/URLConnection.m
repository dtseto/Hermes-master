#import "PreferencesController.h"
#import "URLConnection.h"

NSString * const URLConnectionProxyValidityChangedNotification = @"URLConnectionProxyValidityChangedNotification";
static const NSTimeInterval kURLConnectionTimeoutSeconds = 15.0;

static NSHashTable *URLConnectionActiveSessions;
static dispatch_queue_t URLConnectionActiveSessionsQueue;

static void URLConnectionEnsureSessionStorage(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        URLConnectionActiveSessionsQueue = dispatch_queue_create("com.hermes.URLConnection.sessions", DISPATCH_QUEUE_SERIAL);
        URLConnectionActiveSessions = [NSHashTable weakObjectsHashTable];
    });
}

static void URLConnectionRegisterSession(id session) {
    if (!session) {
        return;
    }
    URLConnectionEnsureSessionStorage();
    dispatch_sync(URLConnectionActiveSessionsQueue, ^{
        [URLConnectionActiveSessions addObject:session];
    });
}

static void URLConnectionUnregisterSession(id session) {
    if (!session) {
        return;
    }
    URLConnectionEnsureSessionStorage();
    dispatch_sync(URLConnectionActiveSessionsQueue, ^{
        [URLConnectionActiveSessions removeObject:session];
    });
}

static NSArray *URLConnectionCopyTrackedSessions(void) {
    URLConnectionEnsureSessionStorage();
    __block NSArray *sessions = nil;
    dispatch_sync(URLConnectionActiveSessionsQueue, ^{
        sessions = [URLConnectionActiveSessions allObjects];
        [URLConnectionActiveSessions removeAllObjects];
    });
    return sessions;
}

static void PostProxyValidity(BOOL isValid) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:URLConnectionProxyValidityChangedNotification
                          object:nil
                        userInfo:@{ @"isValid": @(isValid) }];
    });
}

@implementation URLConnection

- (void)dealloc {
  [self->dataTask cancel];
  [self->timeoutTimer invalidate];
  self->timeoutTimer = nil;
  if (self->session) {
    [self->session invalidateAndCancel];
    URLConnectionUnregisterSession(self->session);
    self->session = nil;
  }
}

+ (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = kURLConnectionTimeoutSeconds;
    config.timeoutIntervalForResource = 45.0;
    return config;
}

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)config
                                   delegate:(id<NSURLSessionDelegate>)delegate {
    if (delegate) {
        return [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
    }
    return [NSURLSession sessionWithConfiguration:config];
}

- (NSURLSessionDataTask *)dataTaskForSession:(NSURLSession *)sessionInstance
                                     request:(NSURLRequest *)request {
    __weak URLConnection *weakSelf = self;
    return [sessionInstance dataTaskWithRequest:request
                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong URLConnection *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf->started = NO;
            [strongSelf invalidateTimeout];
            URLConnectionCallback callback = strongSelf->cb;
            strongSelf->cb = nil;
            if (callback) {
                if (error) {
                    callback(nil, error);
                } else {
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    if ([httpResponse isKindOfClass:[NSHTTPURLResponse class]] &&
                        httpResponse.statusCode >= 400) {
                        NSDictionary *userInfo = @{
                            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP Error: %ld", (long)httpResponse.statusCode]
                        };
                        NSError *httpError = [NSError errorWithDomain:@"HTTPError"
                                                                 code:httpResponse.statusCode
                                                             userInfo:userInfo];
                        callback(nil, httpError);
                    } else {
                        if (data != nil) {
                            [strongSelf->bytes appendData:data];
                        }
                        callback(strongSelf->bytes, nil);
                    }
                }
            }
            if (strongSelf->session) {
                URLConnectionUnregisterSession(strongSelf->session);
                strongSelf->session = nil;
            }
        });
    }];
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
    c->session = [self sessionWithConfiguration:config delegate:nil];
    URLConnectionRegisterSession(c->session);
    c->dataTask = [c dataTaskForSession:c->session request:request];
    
    return c;
}

- (void)start {
    started = YES;
    [self beginTimeout];
    [dataTask resume];
}

- (void)cancel {
    [self invalidateTimeout];
    started = NO;
    cb = nil;
    [dataTask cancel];
    dataTask = nil;
    if (session) {
        URLConnectionUnregisterSession(session);
        if ([session respondsToSelector:@selector(invalidateAndCancel)]) {
            [session invalidateAndCancel];
        }
        session = nil;
    }
}

- (void)setHermesProxy {

  if (!dataTask) {
      // If dataTask doesn't exist yet, just return - we'll handle proxy settings elsewhere
      return;
  }

    // Get current request from existing data task
    NSURLRequest *currentRequest = dataTask.currentRequest;
    [dataTask cancel]; // Cancel existing task
    dataTask = nil;
    if (session) {
        URLConnectionUnregisterSession(session);
        if ([session respondsToSelector:@selector(invalidateAndCancel)]) {
            [session invalidateAndCancel];
        }
        session = nil;
    }
    
    // Create new configuration and session
    NSURLSessionConfiguration *config = [[self class] sessionConfiguration];
    [[self class] setHermesProxy:config];
    session = [[self class] sessionWithConfiguration:config delegate:nil];
    URLConnectionRegisterSession(session);
    
    // Create new data task with the same request
    dataTask = [self dataTaskForSession:session request:currentRequest];
    
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
    NSString *trimmed = nil;
    if (host || *host) {
        trimmed = [*host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
    if (trimmed.length == 0) {
        NSLog(@"Invalid proxy host: null or empty");
        return NO;
    }
    if (port <= 0 || port > 65535) {
        NSLog(@"Invalid proxy port: %ld", (long)port);
        return NO;
    }
    *host = trimmed;
    NSHost *proxyHost = [NSHost hostWithName:*host];
    BOOL isValid = (proxyHost.address != nil);
    if (!isValid) {
        NSLog(@"Cannot resolve proxy host: %@", *host);
    } else {
        NSLog(@"Proxy host resolved to: %@", proxyHost.address);
    }
    return isValid;
}

+ (void)validateProxyHostAsync:(NSString *)host port:(NSInteger)port {
    NSString *trimmedHost = [host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmedHost.length == 0 || port <= 0 || port > 65535) {
        NSLog(@"Invalid proxy settings provided for async validation");
        PostProxyValidity(NO);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSHost *proxyHost = [NSHost hostWithName:trimmedHost];
        BOOL isValid = (proxyHost.address != nil);
        if (!isValid) {
            NSLog(@"Cannot resolve proxy host: %@", trimmedHost);
        } else {
            NSLog(@"Proxy host resolved to: %@", proxyHost.address);
        }
        PostProxyValidity(isValid);
    });
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

+ (void)resetCachedProxySessions {
    NSArray *sessions = URLConnectionCopyTrackedSessions();
    for (id session in sessions) {
        if ([session respondsToSelector:@selector(invalidateAndCancel)]) {
            [session invalidateAndCancel];
        }
    }
}

@end
