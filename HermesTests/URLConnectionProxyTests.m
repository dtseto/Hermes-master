#import <XCTest/XCTest.h>

extern NSString * const URLConnectionProxyValidityChangedNotification;

@protocol NSURLSessionDelegate;

@interface URLConnection : NSObject
+ (instancetype)connectionForRequest:(NSURLRequest *)request
                 completionHandler:(void (^)(NSData *, NSError *))cb;
+ (NSURLSessionConfiguration *)sessionConfiguration;
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)config
                                   delegate:(id<NSURLSessionDelegate>)delegate;
+ (void)setHermesProxy:(NSURLSessionConfiguration *)config;
+ (void)validateProxyHostAsync:(NSString *)host port:(NSInteger)port;
+ (void)resetCachedProxySessions;
- (void)cancel;
@end

static NSString * const kEnabledProxyKey = @"enabledProxy";
static NSString * const kHTTPHostKey = @"httpProxyHost";
static NSString * const kHTTPPortKey = @"httpProxyPort";
static NSInteger const kProxyHTTP = 1;

@interface MockURLSessionDataTask : NSObject
@property(nonatomic, copy) void (^completionHandler)(NSData *, NSURLResponse *, NSError *);
@property(nonatomic, strong) NSURLRequest *request;
@property(nonatomic, assign) BOOL cancelled;
- (instancetype)initWithRequest:(NSURLRequest *)request
               completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (void)resume;
- (void)cancel;
- (NSURLRequest *)currentRequest;
@end

@implementation MockURLSessionDataTask
- (instancetype)initWithRequest:(NSURLRequest *)request
               completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
  if ((self = [super init])) {
    _request = request;
    _completionHandler = [completionHandler copy];
    _cancelled = NO;
  }
  return self;
}
- (void)resume {
  // No-op for tests
}
- (void)cancel {
  self.cancelled = YES;
}
- (NSURLRequest *)currentRequest {
  return self.request;
}
@end

@interface MockProxySession : NSObject
@property(nonatomic, assign) BOOL invalidated;
@property(nonatomic, strong) MockURLSessionDataTask *dataTask;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
- (void)invalidateAndCancel;
@end

@implementation MockProxySession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                           completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
  self.dataTask = [[MockURLSessionDataTask alloc] initWithRequest:request completionHandler:completionHandler];
  return (NSURLSessionDataTask *)self.dataTask;
}
- (void)invalidateAndCancel {
  self.invalidated = YES;
}
@end

static MockProxySession *gCurrentMockProxySession = nil;

@interface TestProxyURLConnection : URLConnection
@end

@implementation TestProxyURLConnection
+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)config
                                   delegate:(id<NSURLSessionDelegate>)delegate {
  return (NSURLSession *)gCurrentMockProxySession;
}
@end

@interface URLConnectionProxyTests : XCTestCase
@end

@implementation URLConnectionProxyTests

- (void)setUp {
  [super setUp];
}

- (void)tearDown {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:kEnabledProxyKey];
  [defaults removeObjectForKey:kHTTPHostKey];
  [defaults removeObjectForKey:kHTTPPortKey];
  [super tearDown];
}

- (void)testSetHermesProxyAppliesHTTPSettings {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:kProxyHTTP forKey:kEnabledProxyKey];
  [defaults setObject:@" example.com " forKey:kHTTPHostKey];
  [defaults setInteger:8888 forKey:kHTTPPortKey];

  NSURLSessionConfiguration *config = [URLConnection sessionConfiguration];
  [URLConnection setHermesProxy:config];

  NSDictionary *proxy = config.connectionProxyDictionary;
  XCTAssertEqualObjects(proxy[@"HTTPProxy"], @"example.com");
  XCTAssertEqualObjects(proxy[@"HTTPSProxy"], @"example.com");
  XCTAssertEqualObjects(proxy[@"HTTPPort"], @8888);
  XCTAssertEqualObjects(proxy[@"HTTPSPort"], @8888);
}

- (void)testSetHermesProxyRejectsEmptyHost {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:kProxyHTTP forKey:kEnabledProxyKey];
  [defaults setObject:@"   " forKey:kHTTPHostKey];
  [defaults setInteger:1234 forKey:kHTTPPortKey];

  NSURLSessionConfiguration *config = [URLConnection sessionConfiguration];
  [URLConnection setHermesProxy:config];

  XCTAssertNil(config.connectionProxyDictionary[@"HTTPProxy"]);
  XCTAssertNil(config.connectionProxyDictionary[@"HTTPSProxy"]);
}

- (void)testValidateProxyHostAsyncImmediateInvalid {
  XCTestExpectation *expectation = [self expectationWithDescription:@"Invalid host notification"];
  id token = [[NSNotificationCenter defaultCenter] addObserverForName:URLConnectionProxyValidityChangedNotification
                                                                object:nil
                                                                 queue:nil
                                                            usingBlock:^(NSNotification * _Nonnull note) {
    XCTAssertFalse([note.userInfo[@"isValid"] boolValue]);
    [expectation fulfill];
  }];

  [URLConnection validateProxyHostAsync:@"" port:80];

  [self waitForExpectations:@[expectation] timeout:0.2];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
}

- (void)testValidateProxyHostAsyncValidHost {
  XCTestExpectation *expectation = [self expectationWithDescription:@"Valid host notification"];
  id token = [[NSNotificationCenter defaultCenter] addObserverForName:URLConnectionProxyValidityChangedNotification
                                                                object:nil
                                                                 queue:nil
                                                            usingBlock:^(NSNotification * _Nonnull note) {
    if ([note.userInfo[@"isValid"] boolValue]) {
      [expectation fulfill];
    }
  }];

  [URLConnection validateProxyHostAsync:@"localhost" port:80];

  [self waitForExpectations:@[expectation] timeout:5.0];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
}

- (void)testResetCachedProxySessionsInvalidatesTrackedSessions {
  MockProxySession *mockSession = [[MockProxySession alloc] init];
  gCurrentMockProxySession = mockSession;

  NSURL *url = [NSURL URLWithString:@"https://example.com/reset-proxy"];
  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  URLConnection *connection = [TestProxyURLConnection connectionForRequest:request
                                                         completionHandler:^(NSData *data, NSError *error) {}];
  XCTAssertNotNil(connection);
  XCTAssertFalse(mockSession.invalidated);

  [URLConnection resetCachedProxySessions];
  XCTAssertTrue(mockSession.invalidated);

  [connection cancel];
  gCurrentMockProxySession = nil;
}

@end
