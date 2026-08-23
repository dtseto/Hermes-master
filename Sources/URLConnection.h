typedef void(^URLConnectionCallback)(NSData*, NSError*);

typedef NS_ENUM(NSInteger, HMSProxyTrafficKind) {
    HMSProxyTrafficKindControl,
    HMSProxyTrafficKindAudio
};

extern NSString * const URLConnectionProxyValidityChangedNotification;

@interface URLConnection : NSObject <NSURLSessionTaskDelegate> {
    NSURLSession *session;
    NSURLSessionDataTask *dataTask;
    URLConnectionCallback cb;
    NSMutableData *bytes;
    BOOL started;
    NSTimer *timeoutTimer;
    NSError *configurationError;
}

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb;
+ (NSURLSessionConfiguration *)sessionConfiguration;
+ (void)setHermesProxy:(NSURLSessionConfiguration*)config;
+ (BOOL)applyHermesProxyToConfiguration:(NSURLSessionConfiguration *)config
                            trafficKind:(HMSProxyTrafficKind)trafficKind;
+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port;
+ (void)validateProxyHostAsync:(NSString *)host port:(NSInteger)port;
+ (void)resetCachedProxySessions;
+ (void)handleProxyAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
                          completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition,
                                                      NSURLCredential *credential))completionHandler;

- (void)start;
- (void)cancel;
- (void)setHermesProxy;

@end
