#import "AudioStreamerStateController.h"

extern NSString * const ASDidChangeStateDistributedNotification;

@interface AudioStreamerStateController ()
@property (nonatomic, weak, nullable) AudioStreamer *owner;
@property (nonatomic, assign) AudioStreamerState *statePointer;
@property (nonatomic, strong) NSNotificationCenter *notificationCenter;
@property (nonatomic, strong, nullable) id<AudioStreamerDistributedNotificationPosting> distributedCenter;
@property (nonatomic, strong) dispatch_queue_t targetQueue;
@end

@implementation AudioStreamerStateController

@synthesize postsDistributedNotifications = _postsDistributedNotifications;
@synthesize dispatchSynchronouslyForTesting = _dispatchSynchronouslyForTesting;

- (instancetype)initWithOwner:(AudioStreamer *)owner
                 statePointer:(AudioStreamerState *)statePointer
          notificationCenter:(NSNotificationCenter *)notificationCenter
 distributedNotificationCenter:(id<AudioStreamerDistributedNotificationPosting>)distributedCenter
                  targetQueue:(dispatch_queue_t)queue {
  NSParameterAssert(statePointer != NULL);

  self = [super init];
  if (self) {
    _owner = owner;
    _statePointer = statePointer;
    _notificationCenter = notificationCenter ?: [NSNotificationCenter defaultCenter];
    _distributedCenter = distributedCenter;
    _targetQueue = queue ?: dispatch_get_main_queue();
    _postsDistributedNotifications = YES;
    _dispatchSynchronouslyForTesting = NO;
  }
  return self;
}

- (AudioStreamerState)currentState {
  return (_statePointer != NULL) ? *_statePointer : AS_INITIALIZED;
}

- (BOOL)performBlockOnTargetQueue:(dispatch_block_t)block {
  if (block == nil) {
    return YES;
  }

  if (self.dispatchSynchronouslyForTesting || self.targetQueue == NULL) {
    block();
    return YES;
  }

  if (self.targetQueue == dispatch_get_main_queue()) {
    if ([NSThread isMainThread]) {
      block();
      return YES;
    }
    dispatch_async(self.targetQueue, block);
    return NO;
  }

  dispatch_async(self.targetQueue, block);
  return NO;
}

- (void)transitionToState:(AudioStreamerState)newState {
  __weak typeof(self) weakSelf = self;
  [self performBlockOnTargetQueue:^{
    typeof(self) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    AudioStreamerState *statePtr = strongSelf.statePointer;
    if (statePtr == NULL) {
      return;
    }

    AudioStreamerState current = *statePtr;
    if (current == newState) {
      return;
    }

    NSLog(@"State transition: %d -> %d", current, newState);
    *statePtr = newState;

    NSNotificationCenter *center = strongSelf.notificationCenter;
    [center postNotificationName:ASStatusChangedNotification object:strongSelf.owner];

    if (strongSelf.postsDistributedNotifications && strongSelf.distributedCenter != nil) {
      NSString *statusString = [strongSelf statusStringForState:newState];
      if (statusString != nil) {
        [strongSelf.distributedCenter postNotificationName:ASDidChangeStateDistributedNotification
                                                    object:@"hermes"
                                                  userInfo:@{@"state": statusString}
                                       deliverImmediately:YES];
      }
    }
  }];
}

#pragma mark - Helpers

- (nullable NSString *)statusStringForState:(AudioStreamerState)state {
  switch (state) {
    case AS_PLAYING:
      return @"playing";
    case AS_PAUSED:
      return @"paused";
    case AS_STOPPED:
      return @"stopped";
    default:
      return nil;
  }
}

@end
