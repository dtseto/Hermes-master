#import "PreferencesController.h"
#import "URLConnection.h"
#include <netdb.h>

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
    if (![self applyHermesProxyToConfiguration:config trafficKind:HMSProxyTrafficKindControl]) {
        c->configurationError = [NSError errorWithDomain:NSURLErrorDomain
                                                    code:NSURLErrorBadURL
                                                userInfo:@{ NSLocalizedDescriptionKey:
                                                              NSLocalizedString(@"Invalid proxy configuration.",
                                                                                @"Invalid proxy settings error") }];
        return c;
    }
    c->session = [self sessionWithConfiguration:config delegate:c];
    URLConnectionRegisterSession(c->session);
    c->dataTask = [c dataTaskForSession:c->session request:request];
    
    return c;
}

- (void)start {
    if (configurationError != nil) {
        URLConnectionCallback callback = cb;
        cb = nil;
        if (callback) {
            callback(nil, configurationError);
        }
        return;
    }
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

- (void)URLSession:(NSURLSession *)sessionInstance
              task:(NSURLSessionTask *)task
didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
  NSURLSessionTaskTransactionMetrics *transaction = metrics.transactionMetrics.lastObject;
  NSInteger status = [(NSHTTPURLResponse *)task.response statusCode];
  NSLog(@"Proxy diagnostic: traffic=control proxyUsed=%@ status=%ld redirects=%lu durationMs=%.0f",
        transaction.isProxyConnection ? @"yes" : @"no",
        (long)status,
        (unsigned long)metrics.redirectCount,
        metrics.taskInterval.duration * 1000.0);
}

- (void)URLSession:(NSURLSession *)sessionInstance
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                             NSURLCredential *credential))completionHandler {
  [[self class] handleProxyAuthenticationChallenge:challenge completionHandler:completionHandler];
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
    [self applyHermesProxyToConfiguration:config trafficKind:HMSProxyTrafficKindControl];
}

+ (BOOL)applyHermesProxyToConfiguration:(NSURLSessionConfiguration *)config
                            trafficKind:(HMSProxyTrafficKind)trafficKind {
    if (!config) {
        return NO;
    }

    NSInteger proxyType = PREF_KEY_INT(ENABLED_PROXY);
    if (trafficKind == HMSProxyTrafficKindAudio && !PREF_KEY_BOOL(PROXY_AUDIO)) {
        // A control-only proxy mirrors pianobar's behavior while retaining the
        // normal macOS network policy for audio when manual audio proxying is off.
        return YES;
    }

    switch (proxyType) {
        case PROXY_HTTP: {
            NSString *host = PREF_KEY_VALUE(PROXY_HTTP_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_HTTP_PORT);
            return [self setHTTPProxy:config host:host port:port];
        }
        case PROXY_SOCKS: {
            NSString *host = PREF_KEY_VALUE(PROXY_SOCKS_HOST);
            NSInteger port = PREF_KEY_INT(PROXY_SOCKS_PORT);
            if (![self validProxyHost:&host port:port]) {
                return NO;
            }
            config.connectionProxyDictionary = @{
                (NSString *)kCFNetworkProxiesSOCKSEnable: @YES,
                (NSString *)kCFNetworkProxiesSOCKSProxy: host,
                (NSString *)kCFNetworkProxiesSOCKSPort: @(port)
            };
            return YES;
        }
        case PROXY_SYSTEM:
            [self setSystemProxy:config];
            return YES;
        default:
            NSLog(@"Proxy diagnostic: traffic=%@ result=invalid-type code=%ld",
                  trafficKind == HMSProxyTrafficKindControl ? @"control" : @"audio",
                  (long)proxyType);
            return NO;
    }
}

+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port {
    NSString *trimmed = nil;
    if (host && *host) {
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
    return YES;
}

+ (void)validateProxyHostAsync:(NSString *)host port:(NSInteger)port {
    NSString *trimmedHost = [host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmedHost.length == 0 || port <= 0 || port > 65535) {
        NSLog(@"Invalid proxy settings provided for async validation");
        PostProxyValidity(NO);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        char service[6];
        snprintf(service, sizeof(service), "%ld", (long)port);

        struct addrinfo *result = NULL;
        int lookupResult = getaddrinfo(trimmedHost.UTF8String, service, &hints, &result);
        BOOL isValid = (lookupResult == 0);
        if (result != NULL) {
            freeaddrinfo(result);
        }
        NSLog(@"Proxy diagnostic: stage=dns result=%@ code=%d",
              isValid ? @"resolved" : @"failed", lookupResult);
        PostProxyValidity(isValid);
    });
}

+ (BOOL)setHTTPProxy:(NSURLSessionConfiguration*)config host:(NSString*)host port:(NSInteger)port {
    if (!config || ![self validProxyHost:&host port:port]) {
        return NO;
    }
    
    NSLog(@"Proxy diagnostic: type=http result=configured");
    
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

+ (void)handleProxyAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                          completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                                      NSURLCredential *credential))completionHandler {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (!space.isProxy) {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }

    NSURLCredential *proposed = challenge.proposedCredential;
    if (challenge.previousFailureCount == 0 && proposed.user.length > 0) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, proposed);
        return;
    }

    NSLog(@"Proxy diagnostic: stage=authentication result=%@ method=%@ failures=%ld",
          challenge.previousFailureCount == 0 ? @"required" : @"rejected",
          space.authenticationMethod ?: @"unknown",
          (long)challenge.previousFailureCount);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = challenge.previousFailureCount == 0
          ? NSLocalizedString(@"Proxy Login Required", @"Proxy authentication prompt title")
          : NSLocalizedString(@"Proxy Login Was Rejected", @"Rejected proxy credentials prompt title");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(
          @"Enter credentials for the configured proxy at %@:%ld.", @"Proxy authentication prompt detail"),
          space.host ?: NSLocalizedString(@"proxy", @"Unknown proxy host fallback"), (long)space.port];
        [alert addButtonWithTitle:NSLocalizedString(@"Connect", @"Connect to proxy button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel proxy login button")];

        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 78)];
        NSTextField *username = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 50, 320, 24)];
        username.placeholderString = NSLocalizedString(@"Proxy username", @"Proxy username placeholder");
        username.stringValue = proposed.user ?: @"";
        NSSecureTextField *password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 24, 320, 24)];
        password.placeholderString = NSLocalizedString(@"Proxy password", @"Proxy password placeholder");
        NSButton *remember = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 20)];
        remember.buttonType = NSButtonTypeSwitch;
        remember.title = NSLocalizedString(@"Remember in Keychain", @"Remember proxy password checkbox");
        [accessory addSubview:username];
        [accessory addSubview:password];
        [accessory addSubview:remember];
        alert.accessoryView = accessory;

        if ([alert runModal] != NSAlertFirstButtonReturn ||
            username.stringValue.length == 0 || password.stringValue.length == 0) {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
            return;
        }

        NSURLCredentialPersistence persistence = remember.state == NSControlStateValueOn
          ? NSURLCredentialPersistencePermanent
          : NSURLCredentialPersistenceForSession;
        NSURLCredential *credential = [NSURLCredential credentialWithUser:username.stringValue
                                                                  password:password.stringValue
                                                               persistence:persistence];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    });
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
