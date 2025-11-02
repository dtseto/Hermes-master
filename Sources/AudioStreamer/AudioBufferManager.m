#import "AudioBufferManager.h"
#import <string.h>

typedef struct queued_packet {
    AudioStreamPacketDescription desc;
    struct queued_packet *next;
    char data[];
} queued_packet_t;

@interface AudioBufferManager ()
@property (nonatomic, weak) id<AudioBufferManagerDelegate> delegate;
@property (nonatomic) UInt32 bufferCount;
@property (nonatomic) UInt32 packetBufferSize;
@property (nonatomic) UInt32 maxPacketDescs;
@property (nonatomic) BOOL bufferInfinite;
@property (nonatomic) AudioStreamPacketDescription *packetDescs;
@property (nonatomic) BOOL *inuse;
@property (nonatomic) queued_packet_t *queuedHead;
@property (nonatomic) queued_packet_t *queuedTail;
@property (nonatomic) UInt32 fillBufferIndex;
@property (nonatomic) UInt32 packetsFilled;
@property (nonatomic) UInt32 bytesFilled;
@property (nonatomic) UInt32 buffersUsed;
@property (nonatomic, getter=isWaitingOnBuffer) BOOL waitingOnBuffer;
@property (nonatomic) BOOL didSuspendDataTask;
@property (nonatomic) BOOL streamAborted;
@end

@implementation AudioBufferManager

- (instancetype)initWithBufferCount:(UInt32)bufferCount
                   packetBufferSize:(UInt32)packetBufferSize
                    maxPacketDescs:(UInt32)maxPacketDescs
                     bufferInfinite:(BOOL)bufferInfinite
                           delegate:(id<AudioBufferManagerDelegate>)delegate {
    self = [super init];
    if (!self) {
        return nil;
    }

    _bufferCount = bufferCount;
    _packetBufferSize = packetBufferSize;
    _maxPacketDescs = maxPacketDescs;
    _bufferInfinite = bufferInfinite;
    _delegate = delegate;

    _packetDescs = calloc(maxPacketDescs, sizeof(AudioStreamPacketDescription));
    if (!_packetDescs) {
        return nil;
    }

    _inuse = calloc(bufferCount, sizeof(BOOL));
    if (!_inuse) {
        free(_packetDescs);
        _packetDescs = NULL;
        return nil;
    }

    [self reset];
    return self;
}

- (void)dealloc {
    [self freeQueuedPackets];
    free(_packetDescs);
    free(_inuse);
}

- (AudioStreamPacketDescription *)packetDescriptions {
    return _packetDescs;
}

- (void)reset {
    _packetsFilled = 0;
    _bytesFilled = 0;
    _fillBufferIndex = 0;
    _buffersUsed = 0;
    _waitingOnBuffer = NO;
    _didSuspendDataTask = NO;
    _streamAborted = NO;
    if (_inuse) {
        memset(_inuse, 0, sizeof(BOOL) * _bufferCount);
    }
    [self freeQueuedPackets];
}

- (void)freeQueuedPackets {
    queued_packet_t *cur = _queuedHead;
    while (cur) {
        queued_packet_t *next = cur->next;
        free(cur);
        cur = next;
    }
    _queuedHead = NULL;
    _queuedTail = NULL;
}

- (void)updatePacketBufferSize:(UInt32)packetBufferSize {
    _packetBufferSize = packetBufferSize;
}

- (void)updateBufferInfinite:(BOOL)bufferInfinite {
    _bufferInfinite = bufferInfinite;
    if (bufferInfinite && _didSuspendDataTask) {
        _didSuspendDataTask = NO;
    }
}

- (AudioBufferManagerEnqueueResult)handlePacketData:(const void *)data
                                        description:(AudioStreamPacketDescription)desc {
    if (_streamAborted) {
        return AudioBufferManagerEnqueueResultFailed;
    }

    UInt32 packetSize = desc.mDataByteSize;
    if (packetSize == 0) {
        return AudioBufferManagerEnqueueResultCommitted;
    }

    if (packetSize > _packetBufferSize) {
        return AudioBufferManagerEnqueueResultFailed;
    }

    if (_packetBufferSize - _bytesFilled < packetSize) {
        AudioBufferManagerEnqueueResult flushResult = [self flushCurrentBuffer];
        if (flushResult != AudioBufferManagerEnqueueResultCommitted) {
            return flushResult;
        }
        NSAssert(_bytesFilled == 0, @"bytesFilled should be zero after flushing buffer.");
        NSAssert(_packetBufferSize >= packetSize, @"Buffer size must be large enough for packet.");
    }

    AudioStreamPacketDescription packetDesc = desc;
    packetDesc.mStartOffset = _bytesFilled;

    if (_delegate) {
        [_delegate audioBufferManager:self
                       copyPacketData:data
                           packetSize:packetSize
                        toBufferIndex:_fillBufferIndex
                               offset:_bytesFilled];
    }

    _packetDescs[_packetsFilled] = packetDesc;
    _bytesFilled += packetSize;
    _packetsFilled++;

    if (_packetsFilled >= _maxPacketDescs) {
        return [self flushCurrentBuffer];
    }

    return AudioBufferManagerEnqueueResultCommitted;
}

- (AudioBufferManagerEnqueueResult)flushCurrentBuffer {
    if (_streamAborted) {
        _bytesFilled = 0;
        _packetsFilled = 0;
        return AudioBufferManagerEnqueueResultFailed;
    }

    if (_packetsFilled == 0) {
        return AudioBufferManagerEnqueueResultCommitted;
    }

    NSAssert(_fillBufferIndex < _bufferCount, @"fillBufferIndex is out of range.");
    if (_inuse[_fillBufferIndex]) {
        _waitingOnBuffer = YES;
        if (!_bufferInfinite && !_didSuspendDataTask && _delegate) {
            [_delegate audioBufferManagerSuspendData:self];
            _didSuspendDataTask = YES;
        }
        return AudioBufferManagerEnqueueResultBlocked;
    }

    _inuse[_fillBufferIndex] = YES;
    _buffersUsed++;

    OSStatus enqueueError = noErr;
    if (_delegate) {
        enqueueError = [_delegate audioBufferManager:self
                            enqueueBufferAtIndex:_fillBufferIndex
                                     bytesFilled:_bytesFilled
                                   packetsFilled:_packetsFilled
                              packetDescriptions:_packetDescs];
    }

    if (enqueueError != noErr) {
        _inuse[_fillBufferIndex] = NO;
        if (_buffersUsed > 0) {
            _buffersUsed--;
        }
        return AudioBufferManagerEnqueueResultFailed;
    }

    if (_delegate && [_delegate audioBufferManagerShouldStartQueue:self]) {
        [_delegate audioBufferManagerStartQueue:self];
    }

    _fillBufferIndex++;
    if (_fillBufferIndex >= _bufferCount) {
        _fillBufferIndex = 0;
    }
    _bytesFilled = 0;
    _packetsFilled = 0;

    if (_inuse[_fillBufferIndex]) {
        _waitingOnBuffer = YES;
        if (!_bufferInfinite && !_didSuspendDataTask && _delegate) {
            [_delegate audioBufferManagerSuspendData:self];
            _didSuspendDataTask = YES;
        }
        return AudioBufferManagerEnqueueResultBlocked;
    }

    return AudioBufferManagerEnqueueResultCommitted;
}

- (void)cachePacketData:(const void *)data
              packetSize:(UInt32)packetSize
             description:(AudioStreamPacketDescription)desc {
    queued_packet_t *packet = malloc(sizeof(queued_packet_t) + packetSize);
    if (!packet) {
        return;
    }

    packet->next = NULL;
    packet->desc = desc;
    packet->desc.mStartOffset = 0;
    if (packetSize > 0) {
        memcpy(packet->data, data, packetSize);
    }

    if (_queuedHead == NULL) {
        _queuedHead = _queuedTail = packet;
    } else {
        _queuedTail->next = packet;
        _queuedTail = packet;
    }
}

- (BOOL)hasQueuedPackets {
    return _queuedHead != NULL;
}

- (void)clearQueuedPackets {
    [self freeQueuedPackets];
    _waitingOnBuffer = NO;
    if (_didSuspendDataTask) {
        _didSuspendDataTask = NO;
    }
}

- (void)abortPendingData {
    _streamAborted = YES;
    _bytesFilled = 0;
    _packetsFilled = 0;
    _waitingOnBuffer = NO;
    if (_didSuspendDataTask && _delegate) {
        [_delegate audioBufferManagerResumeData:self];
    }
    _didSuspendDataTask = NO;
    [self freeQueuedPackets];
}

- (void)processQueuedPackets {
    if (_streamAborted) {
        [self freeQueuedPackets];
        return;
    }

    queued_packet_t *current = _queuedHead;
    while (current && !_waitingOnBuffer) {
        AudioBufferManagerEnqueueResult result =
            [self handlePacketData:current->data description:current->desc];
        if (result == AudioBufferManagerEnqueueResultFailed) {
            break;
        }
        if (result == AudioBufferManagerEnqueueResultBlocked) {
            break;
        }

        queued_packet_t *next = current->next;
        free(current);
        current = next;
    }

    _queuedHead = current;
    if (_queuedHead == NULL) {
        _queuedTail = NULL;
        if (_delegate && !_bufferInfinite && _didSuspendDataTask) {
            [_delegate audioBufferManagerResumeData:self];
            _didSuspendDataTask = NO;
        }
    }
}

- (BOOL)bufferCompletedAtIndex:(UInt32)index {
    NSAssert(index < _bufferCount, @"Buffer index out of range.");
    NSAssert(_inuse[index], @"Completed buffer was not marked as in use.");

    _inuse[index] = NO;
    if (_buffersUsed > 0) {
        _buffersUsed--;
    }

    BOOL wasWaiting = _waitingOnBuffer;
    if (wasWaiting) {
        _waitingOnBuffer = NO;
    }

    if (_streamAborted) {
        return NO;
    }

    return wasWaiting;
}

@end
