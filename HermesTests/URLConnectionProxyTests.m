#import <XCTest/XCTest.h>

@interface URLConnection : NSObject
+ (NSURLSessionConfiguration *)sessionConfiguration;
+ (void)setHermesProxy:(NSURLSessionConfiguration *)config;
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

@end
