#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "ImageLoader.h"
#import "URLConnection.h"

@interface StubImageLoaderConnection : NSObject
@property(nonatomic, copy) URLConnectionCallback callback;
@property(nonatomic, copy) NSString *requestURL;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL cancelled;
- (instancetype)initWithRequest:(NSURLRequest *)request callback:(URLConnectionCallback)callback;
- (void)start;
- (void)cancel;
@end

static NSMutableArray<StubImageLoaderConnection *> *StubConnections;
static IMP OriginalURLConnectionFactoryIMP;

@implementation StubImageLoaderConnection

- (instancetype)initWithRequest:(NSURLRequest *)request callback:(URLConnectionCallback)callback {
  if ((self = [super init])) {
    _callback = [callback copy];
    _requestURL = request.URL.absoluteString;
  }
  return self;
}

- (void)start {
  self.started = YES;
}

- (void)cancel {
  self.cancelled = YES;
  self.callback = nil;
}

@end

static id StubConnectionFactory(id self, SEL _cmd, NSURLRequest *request, URLConnectionCallback callback) {
  StubConnections = StubConnections ?: [NSMutableArray array];
  StubImageLoaderConnection *connection = [[StubImageLoaderConnection alloc] initWithRequest:request callback:callback];
  [StubConnections addObject:connection];
  return connection;
}

@interface ImageLoaderTests : XCTestCase
@end

@implementation ImageLoaderTests

- (void)setUp {
  [super setUp];
  StubConnections = [NSMutableArray array];
  Class urlConnectionClass = [URLConnection class];
  Method factoryMethod = class_getClassMethod(urlConnectionClass, @selector(connectionForRequest:completionHandler:));
  OriginalURLConnectionFactoryIMP = method_getImplementation(factoryMethod);
  method_setImplementation(factoryMethod, (IMP)StubConnectionFactory);
}

- (void)tearDown {
  Class urlConnectionClass = [URLConnection class];
  Method factoryMethod = class_getClassMethod(urlConnectionClass, @selector(connectionForRequest:completionHandler:));
  if (OriginalURLConnectionFactoryIMP != NULL) {
    method_setImplementation(factoryMethod, OriginalURLConnectionFactoryIMP);
  }
  StubConnections = nil;
  [super tearDown];
}

- (void)testCancelStopsCurrentDownloadAndStartsNext {
  ImageLoader *loader = [[ImageLoader alloc] init];
  __block BOOL firstCallbackInvoked = NO;

  [loader loadImageURL:@"http://example.com/artA.png" callback:^(NSData *data) {
    firstCallbackInvoked = YES;
  }];
  [loader loadImageURL:@"http://example.com/artB.png" callback:^(__unused NSData *data) { }];

  XCTAssertEqual(StubConnections.count, (NSUInteger)1);
  StubImageLoaderConnection *firstConnection = StubConnections.firstObject;
  XCTAssertTrue(firstConnection.started);

  [loader cancel:@"http://example.com/artA.png"];

  XCTAssertTrue(firstConnection.cancelled);
  XCTAssertFalse(firstCallbackInvoked);
  XCTAssertEqual(StubConnections.count, (NSUInteger)2);
  StubImageLoaderConnection *secondConnection = StubConnections.lastObject;
  XCTAssertTrue(secondConnection.started);
  XCTAssertEqualObjects(secondConnection.requestURL, @"http://example.com/artB.png");
}

@end
