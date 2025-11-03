#import <XCTest/XCTest.h>

extern NSString * const URLConnectionProxyValidityChangedNotification;

@interface URLConnection : NSObject
+ (NSURLSessionConfiguration *)sessionConfiguration;
+ (void)setHermesProxy:(NSURLSessionConfiguration *)config;
+ (void)validateProxyHostAsync:(NSString *)host port:(NSInteger)port;
@end

static NSString * const kEnabledProxyKey = @"enabledProxy";
static NSString * const kHTTPHostKey = @"httpProxyHost";
static NSString * const kHTTPPortKey = @"httpProxyPort";
static NSInteger const kProxyHTTP = 1;

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
  [defaults setObject:@"example.com" forKey:kHTTPHostKey];
  [defaults setInteger:8888 forKey:kHTTPPortKey];

  NSURLSessionConfiguration *config = [URLConnection sessionConfiguration];
  [URLConnection setHermesProxy:config];

  NSDictionary *proxy = config.connectionProxyDictionary;
  XCTAssertEqualObjects(proxy[@"HTTPProxy"], @"example.com");
  XCTAssertEqualObjects(proxy[@"HTTPSProxy"], @"example.com");
  XCTAssertEqualObjects(proxy[@"HTTPPort"], @8888);
  XCTAssertEqualObjects(proxy[@"HTTPSPort"], @8888);
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

@end
