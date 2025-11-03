#import <XCTest/XCTest.h>
#import <objc/runtime.h>

typedef void(^URLConnectionCallback)(NSData *, NSError *);
typedef void(^PandoraCallback)(NSDictionary *);

@interface URLConnection : NSObject
+ (id)connectionForRequest:(NSURLRequest *)request
        completionHandler:(URLConnectionCallback)cb;
@end

@interface PandoraRequest : NSObject
@property(nonatomic, copy) NSString *method;
@property(nonatomic, copy) NSString *partnerId;
@property(nonatomic, copy) NSString *userId;
@property(nonatomic, copy) NSString *authToken;
@property(nonatomic, strong) NSDictionary *request;
@property(nonatomic, copy) PandoraCallback callback;
@end

@interface PandoraRequest (Testing)
@property(nonatomic, assign) BOOL tls;
@property(nonatomic, assign) BOOL encrypted;
@end

@interface Pandora : NSObject
- (BOOL)sendRequest:(PandoraRequest *)request;
@end

extern NSString * const PandoraDidErrorNotification;

static NSData *StubResponseData = nil;
static NSError *StubResponseError = nil;

@interface HermesStubConnection : NSObject
@property(nonatomic, copy) URLConnectionCallback callback;
@end

@implementation HermesStubConnection
- (instancetype)initWithCallback:(URLConnectionCallback)callback {
  if ((self = [super init])) {
    _callback = [callback copy];
  }
  return self;
}
- (void)start {
  URLConnectionCallback cb = self.callback;
  NSData *data = StubResponseData;
  NSError *error = StubResponseError;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (cb) {
      cb(data, error);
    }
  });
}
@end

static id StubConnectionForRequest(id self, SEL _cmd, NSURLRequest *request, URLConnectionCallback cb) {
  return [[HermesStubConnection alloc] initWithCallback:cb];
}

@interface PandoraSendRequestTests : XCTestCase
@property(nonatomic, assign) IMP originalConnectionIMP;
@end

@implementation PandoraSendRequestTests

- (void)setUp {
  [super setUp];
  Class urlConnectionClass = [URLConnection class];
  Method method = class_getClassMethod(urlConnectionClass, @selector(connectionForRequest:completionHandler:));
  self.originalConnectionIMP = method_getImplementation(method);
  method_setImplementation(method, (IMP)StubConnectionForRequest);
}

- (void)tearDown {
  Class urlConnectionClass = [URLConnection class];
  Method method = class_getClassMethod(urlConnectionClass, @selector(connectionForRequest:completionHandler:));
  if (self.originalConnectionIMP != NULL) {
    method_setImplementation(method, self.originalConnectionIMP);
  }
  StubResponseData = nil;
  StubResponseError = nil;
  [super tearDown];
}

- (PandoraRequest *)basicRequestWithCallback:(PandoraCallback)callback {
  PandoraRequest *request = [[PandoraRequest alloc] init];
  request.method = @"test.method";
  request.partnerId = @"partner";
  request.userId = @"user";
  request.authToken = @"token";
  request.request = @{};
  request.callback = callback;
  return request;
}

- (void)testSendRequestInvokesCallbackOnSuccess {
  NSDictionary *payload = @{@"stat": @"ok", @"result": @{@"message": @"hello"}};
  StubResponseData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  StubResponseError = nil;

  Pandora *pandora = [[Pandora alloc] init];

  XCTestExpectation *expectation = [self expectationWithDescription:@"Callback invoked"];
  __block NSDictionary *result = nil;
  PandoraRequest *request = [self basicRequestWithCallback:^(NSDictionary *dict) {
    result = dict;
    [expectation fulfill];
  }];

  BOOL started = [pandora sendRequest:request];
  XCTAssertTrue(started);
  [self waitForExpectations:@[expectation] timeout:1.0];
  XCTAssertEqualObjects(result[@"stat"], @"ok");
}

- (void)testSendRequestPostsErrorNotificationOnFailure {
  NSDictionary *payload = @{@"stat": @"fail", @"message": @"bad things", @"code": @1234};
  StubResponseData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  StubResponseError = nil;

  Pandora *pandora = [[Pandora alloc] init];

  XCTestExpectation *expectation = [self expectationWithDescription:@"Error notification fired"];
  id token = [[NSNotificationCenter defaultCenter] addObserverForName:PandoraDidErrorNotification
                                                              object:pandora
                                                               queue:nil
                                                          usingBlock:^(NSNotification *note) {
    NSDictionary *info = note.userInfo;
    XCTAssertEqualObjects(info[@"error"], @"bad things");
    XCTAssertEqualObjects(info[@"pandoraCode"], @1234);
    XCTAssertEqualObjects(info[@"method"], @"test.method");
    XCTAssertNil(info[@"request"]);
    [expectation fulfill];
  }];

  PandoraRequest *request = [self basicRequestWithCallback:^(NSDictionary *dict) {
    XCTFail(@"Callback should not be invoked when request fails");
  }];

  BOOL started = [pandora sendRequest:request];
  XCTAssertTrue(started);

  [self waitForExpectations:@[expectation] timeout:1.0];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
}

@end
