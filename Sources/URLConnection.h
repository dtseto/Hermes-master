typedef void(^URLConnectionCallback)(NSData*, NSError*);

extern NSString * const URLConnectionProxyValidityChangedNotification;

@interface URLConnection : NSObject {
    NSURLSession *session;
    NSURLSessionDataTask *dataTask;
    URLConnectionCallback cb;
    NSMutableData *bytes;
    BOOL started;
    NSTimer *timeoutTimer;
}

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb;
+ (NSURLSessionConfiguration *)sessionConfiguration;
+ (void)setHermesProxy:(NSURLSessionConfiguration*)config;
+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port;
+ (void)validateProxyHostAsync:(NSString *)host port:(NSInteger)port;
+ (void)resetCachedProxySessions;

- (void)start;
- (void)cancel;
- (void)setHermesProxy;

@end
