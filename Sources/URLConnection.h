typedef void(^URLConnectionCallback)(NSData*, NSError*);

extern NSString * const URLConnectionProxyValidityChangedNotification;

@interface URLConnection : NSObject {
    NSURLSessionDataTask *dataTask;
    URLConnectionCallback cb;
    NSMutableData *bytes;
    NSTimer *timeout;
    int events;
}

+ (URLConnection*)connectionForRequest:(NSURLRequest*)request
                    completionHandler:(URLConnectionCallback)cb;
+ (void)setHermesProxy:(NSURLSessionConfiguration*)config;
+ (BOOL)validProxyHost:(NSString **)host port:(NSInteger)port;

- (void)start;
- (void)setHermesProxy;

@end
