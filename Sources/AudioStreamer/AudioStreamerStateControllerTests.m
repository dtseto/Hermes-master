#import <XCTest/XCTest.h>

#import "AudioStreamerStateController.h"

@interface TestDistributedNotificationCenter : NSObject <AudioStreamerDistributedNotificationPosting>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *posts;
@end

@implementation TestDistributedNotificationCenter

- (instancetype)init {
  if (self = [super init]) {
    _posts = [NSMutableArray array];
  }
  return self;
}

- (void)postNotificationName:(NSNotificationName)name
                       object:(nullable NSString *)object
                     userInfo:(nullable NSDictionary *)userInfo
          deliverImmediately:(BOOL)deliverImmediately {
  [self.posts addObject:@{
    @"name": name ?: @"",
    @"object": object ?: [NSNull null],
    @"userInfo": userInfo ?: @{},
    @"deliverImmediately": @(deliverImmediately)
  }];
}

@end

@interface AudioStreamerStateControllerTests : XCTestCase
@end

@implementation AudioStreamerStateControllerTests

- (void)testTransitionUpdatesStateAndPostsNotifications {
  __block AudioStreamerState state = AS_INITIALIZED;
  NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
  TestDistributedNotificationCenter *distributed = [[TestDistributedNotificationCenter alloc] init];

  AudioStreamerStateController *controller = [[AudioStreamerStateController alloc]
    initWithOwner:nil
     statePointer:&state
  notificationCenter:center
distributedNotificationCenter:(NSDistributedNotificationCenter *)distributed
           targetQueue:dispatch_get_main_queue()];
  controller.dispatchSynchronouslyForTesting = YES;

  __block NSMutableArray<NSNotification *> *captured = [NSMutableArray array];
  id token = [center addObserverForName:ASStatusChangedNotification
                                 object:nil
                                  queue:nil
                             usingBlock:^(NSNotification * _Nonnull note) {
    [captured addObject:note];
  }];

  [controller transitionToState:AS_PLAYING];

  XCTAssertEqual(state, AS_PLAYING);
  XCTAssertEqual(captured.count, (NSUInteger)1);
  XCTAssertEqualObjects(captured.firstObject.name, ASStatusChangedNotification);
  XCTAssertEqual(distributed.posts.count, (NSUInteger)1);
  NSDictionary *post = distributed.posts.firstObject;
  XCTAssertEqualObjects(post[@"name"], ASDidChangeStateDistributedNotification);
  XCTAssertEqualObjects(post[@"userInfo"], (@{ @"state": @"playing" }));

  [center removeObserver:token];
}

- (void)testDuplicateTransitionDoesNotPost {
  __block AudioStreamerState state = AS_INITIALIZED;
  NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
  TestDistributedNotificationCenter *distributed = [[TestDistributedNotificationCenter alloc] init];
  AudioStreamerStateController *controller = [[AudioStreamerStateController alloc]
    initWithOwner:nil
     statePointer:&state
  notificationCenter:center
distributedNotificationCenter:(NSDistributedNotificationCenter *)distributed
           targetQueue:dispatch_get_main_queue()];
  controller.dispatchSynchronouslyForTesting = YES;

  [controller transitionToState:AS_PLAYING];
  [distributed.posts removeAllObjects];

  __block NSUInteger notificationCount = 0;
  id token = [center addObserverForName:ASStatusChangedNotification
                                 object:nil
                                  queue:nil
                             usingBlock:^(__unused NSNotification *note) {
    notificationCount += 1;
  }];

  [controller transitionToState:AS_PLAYING];

  XCTAssertEqual(notificationCount, (NSUInteger)0);
  XCTAssertEqual(distributed.posts.count, (NSUInteger)0);

  [center removeObserver:token];
}

- (void)testDistributedNotificationsCanBeDisabled {
  __block AudioStreamerState state = AS_INITIALIZED;
  NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
  TestDistributedNotificationCenter *distributed = [[TestDistributedNotificationCenter alloc] init];
  AudioStreamerStateController *controller = [[AudioStreamerStateController alloc]
    initWithOwner:nil
     statePointer:&state
  notificationCenter:center
distributedNotificationCenter:(NSDistributedNotificationCenter *)distributed
           targetQueue:dispatch_get_main_queue()];
  controller.dispatchSynchronouslyForTesting = YES;
  controller.postsDistributedNotifications = NO;

  [controller transitionToState:AS_PLAYING];
  XCTAssertEqual(distributed.posts.count, (NSUInteger)0);
}

- (void)testTransitionExecutesOnTargetQueue {
  AudioStreamerState stateStorage = AS_INITIALIZED;
  NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
  TestDistributedNotificationCenter *distributed = [[TestDistributedNotificationCenter alloc] init];
  dispatch_queue_t targetQueue = dispatch_queue_create("test.target.queue", DISPATCH_QUEUE_SERIAL);
  static char kQueueKey;
  int specificValue = 42;
  dispatch_queue_set_specific(targetQueue, &kQueueKey, &specificValue, NULL);

  AudioStreamerStateController *controller = [[AudioStreamerStateController alloc]
    initWithOwner:nil
     statePointer:&stateStorage
  notificationCenter:center
distributedNotificationCenter:distributed
           targetQueue:targetQueue];

  XCTestExpectation *expectation = [self expectationWithDescription:@"Notification dispatched on target queue"];

  __block AudioStreamerState observedState = AS_INITIALIZED;
  id token = [center addObserverForName:ASStatusChangedNotification
                                 object:nil
                                  queue:nil
                             usingBlock:^(__unused NSNotification *note) {
    XCTAssertNotEqual(dispatch_get_specific(&kQueueKey), NULL);
    observedState = [controller currentState];
    [expectation fulfill];
  }];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [controller transitionToState:AS_PLAYING];
  });

  [self waitForExpectationsWithTimeout:5.0 handler:nil];
  XCTAssertEqual(observedState, AS_PLAYING);
  XCTAssertEqual([controller currentState], AS_PLAYING);
  [center removeObserver:token];
}

- (void)testPerformBlockOnTargetQueueReturnsExpectedValue {
  AudioStreamerState stateStorage = AS_INITIALIZED;
  NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
  AudioStreamerStateController *controller = [[AudioStreamerStateController alloc]
    initWithOwner:nil
     statePointer:&stateStorage
  notificationCenter:center
distributedNotificationCenter:nil
           targetQueue:dispatch_get_main_queue()];
  controller.dispatchSynchronouslyForTesting = YES;

  __block BOOL executed = NO;
  BOOL returned = [controller performBlockOnTargetQueue:^{ executed = YES; }];
  XCTAssertTrue(returned);
  XCTAssertTrue(executed);

  controller.dispatchSynchronouslyForTesting = NO;
  executed = NO;
  returned = [controller performBlockOnTargetQueue:^{ executed = YES; }];
  XCTAssertTrue(returned);

  XCTestExpectation *expectation = [self expectationWithDescription:@"Async block executed"];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (executed) {
      [expectation fulfill];
    }
  });
  [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testConcurrentTransitionsCollapseToFinalState {
  AudioStreamerState stateStorage = AS_INITIALIZED;
  NSNotificationCenter *center = [[NSNotificationCenter alloc] init];
  AudioStreamerStateController *controller = [[AudioStreamerStateController alloc]
    initWithOwner:nil
     statePointer:&stateStorage
  notificationCenter:center
distributedNotificationCenter:nil
           targetQueue:dispatch_get_main_queue()];

  dispatch_group_t group = dispatch_group_create();
  NSArray<NSNumber *> *states = @[
    @(AS_WAITING_FOR_DATA),
    @(AS_WAITING_FOR_QUEUE_TO_START),
    @(AS_PLAYING),
    @(AS_PAUSED),
    @(AS_PLAYING),
    @(AS_STOPPED)
  ];

  XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"All transitions observed"];
  notificationExpectation.expectedFulfillmentCount = states.count;

  NSMutableArray<NSNumber *> *observedStates = [NSMutableArray array];

  id token = [center addObserverForName:ASStatusChangedNotification
                                 object:nil
                                  queue:nil
                             usingBlock:^(__unused NSNotification *note) {
    AudioStreamerState current = [controller currentState];
    [observedStates addObject:@(current)];
    [notificationExpectation fulfill];
  }];

  for (NSNumber *stateNumber in states) {
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [controller transitionToState:(AudioStreamerState)stateNumber.integerValue];
    });
  }

  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

  [self waitForExpectationsWithTimeout:2.0 handler:nil];

  // Pump the run loop briefly to let any queued transitions finish.
  [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

  XCTAssertEqual([controller currentState], AS_STOPPED);
  XCTAssertEqual(stateStorage, AS_STOPPED);
  XCTAssertEqual([[observedStates lastObject] integerValue], AS_STOPPED);

  [center removeObserver:token];
}

@end
