#import <Foundation/Foundation.h>

#import "AudioStreamer.h"

NS_ASSUME_NONNULL_BEGIN

@protocol AudioStreamerDistributedNotificationPosting <NSObject>
- (void)postNotificationName:(NSNotificationName)name
                       object:(nullable NSString *)object
                     userInfo:(nullable NSDictionary *)userInfo
          deliverImmediately:(BOOL)deliverImmediately;
@end

@interface NSDistributedNotificationCenter (AudioStreamerDistributedNotificationPosting) <AudioStreamerDistributedNotificationPosting>
@end

@protocol AudioStreamerStateControllerProtocol <NSObject>

@property (nonatomic, assign) BOOL postsDistributedNotifications;
@property (nonatomic, assign) BOOL dispatchSynchronouslyForTesting;

- (AudioStreamerState)currentState;

- (instancetype)initWithOwner:(nullable AudioStreamer *)owner
                 statePointer:(AudioStreamerState *)statePointer
          notificationCenter:(NSNotificationCenter *)notificationCenter
 distributedNotificationCenter:(nullable id<AudioStreamerDistributedNotificationPosting>)distributedCenter
                  targetQueue:(dispatch_queue_t)queue;

- (instancetype)init NS_UNAVAILABLE;

- (void)transitionToState:(AudioStreamerState)newState;

- (BOOL)performBlockOnTargetQueue:(dispatch_block_t)block;

@end

@interface AudioStreamerStateController : NSObject <AudioStreamerStateControllerProtocol>
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithOwner:(nullable AudioStreamer *)owner
                 statePointer:(AudioStreamerState *)statePointer
          notificationCenter:(NSNotificationCenter *)notificationCenter
 distributedNotificationCenter:(nullable id<AudioStreamerDistributedNotificationPosting>)distributedCenter
                  targetQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
