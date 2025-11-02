#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AudioBufferManagerEnqueueResult) {
    AudioBufferManagerEnqueueResultFailed = -1,
    AudioBufferManagerEnqueueResultBlocked = 0,
    AudioBufferManagerEnqueueResultCommitted = 1
};

@class AudioBufferManager;

@protocol AudioBufferManagerDelegate <NSObject>
- (OSStatus)audioBufferManager:(AudioBufferManager *)manager
        enqueueBufferAtIndex:(UInt32)bufferIndex
                 bytesFilled:(UInt32)bytesFilled
               packetsFilled:(UInt32)packetsFilled
          packetDescriptions:(AudioStreamPacketDescription *)packetDescs;
- (void)audioBufferManager:(AudioBufferManager *)manager
             copyPacketData:(const void *)packetData
                 packetSize:(UInt32)packetSize
              toBufferIndex:(UInt32)bufferIndex
                     offset:(UInt32)offset;
- (void)audioBufferManagerSuspendData:(AudioBufferManager *)manager;
- (void)audioBufferManagerResumeData:(AudioBufferManager *)manager;
- (BOOL)audioBufferManagerShouldStartQueue:(AudioBufferManager *)manager;
- (void)audioBufferManagerStartQueue:(AudioBufferManager *)manager;
@end

@interface AudioBufferManager : NSObject

- (instancetype)initWithBufferCount:(UInt32)bufferCount
                   packetBufferSize:(UInt32)packetBufferSize
                    maxPacketDescs:(UInt32)maxPacketDescs
                     bufferInfinite:(BOOL)bufferInfinite
                           delegate:(id<AudioBufferManagerDelegate>)delegate NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) UInt32 packetsFilled;
@property (nonatomic, readonly) UInt32 bytesFilled;
@property (nonatomic, readonly) UInt32 buffersUsed;
@property (nonatomic, readonly) UInt32 fillBufferIndex;
@property (nonatomic, readonly, getter=isWaitingOnBuffer) BOOL waitingOnBuffer;
@property (nonatomic, readonly) AudioStreamPacketDescription *packetDescriptions;

- (void)reset;
- (void)updatePacketBufferSize:(UInt32)packetBufferSize;
- (void)updateBufferInfinite:(BOOL)bufferInfinite;
- (AudioBufferManagerEnqueueResult)handlePacketData:(const void *)data
                                        description:(AudioStreamPacketDescription)desc;
- (AudioBufferManagerEnqueueResult)flushCurrentBuffer;
- (void)cachePacketData:(const void *)data
              packetSize:(UInt32)packetSize
             description:(AudioStreamPacketDescription)desc;
- (BOOL)hasQueuedPackets;
- (void)processQueuedPackets;
- (void)clearQueuedPackets;
- (void)abortPendingData;
- (BOOL)bufferCompletedAtIndex:(UInt32)index;

@end

NS_ASSUME_NONNULL_END
