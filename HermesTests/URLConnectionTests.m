#import <XCTest/XCTest.h>

#import "URLConnection.h"

@interface SlowURLProtocol : NSURLProtocol
@property (atomic, assign) BOOL cancelled;
@end

@implementation SlowURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
  return [[request.URL scheme] isEqualToString:@"hermes-test"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
  return request;
}

- (void)startLoading {
  self.cancelled = NO;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(11 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    if (self.cancelled) {
      return;
    }
    NSData *data = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
    NSURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                         statusCode:200
                                                        HTTPVersion:@"HTTP/1.1"
                                                       headerFields:@{@"Content-Type": @"text/plain"}];
    id<NSURLProtocolClient> client = self.client;
    if (client == nil) {
      return;
    }
    [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [client URLProtocol:self didLoadData:data];
    [client URLProtocolDidFinishLoading:self];
  });
}

- (void)stopLoading {
  self.cancelled = YES;
}

@end

@interface TestURLConnection : URLConnection
@end

@implementation TestURLConnection

+ (NSURLSessionConfiguration *)sessionConfiguration {
  NSURLSessionConfiguration *config = [super sessionConfiguration];
  NSArray<Class> *existingProtocols = config.protocolClasses ?: @[];
  NSMutableArray<Class> *protocols = [existingProtocols mutableCopy];
  [protocols insertObject:[SlowURLProtocol class] atIndex:0];
  config.protocolClasses = protocols;
  return config;
}

@end

@interface URLConnectionTests : XCTestCase
@end

@implementation URLConnectionTests

- (void)testSlowResponseDoesNotTimeoutEarly {
  XCTestExpectation *expectation = [self expectationWithDescription:@"Slow response received"];
  NSURL *url = [NSURL URLWithString:@"hermes-test://slow-response"];
  NSURLRequest *request = [NSURLRequest requestWithURL:url];

  URLConnection *connection = [TestURLConnection connectionForRequest:request
                                                   completionHandler:^(NSData *data, NSError *error) {
    XCTAssertNil(error);
    NSString *body = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(body, @"ok");
    [expectation fulfill];
  }];

  [connection start];
  [self waitForExpectations:@[expectation] timeout:15.0];
}

@end
