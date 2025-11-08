//
//  ASPlaylist+Testing.h
//  Hermes
//
//  Lightweight hooks so tests can inspect playlist state without KVC.
//

#import "ASPlaylist.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

 @interface ASPlaylist (Testing)

@property (nonatomic, readonly) AudioStreamer *testing_currentStream;
@property (nonatomic, readonly) NSURL *testing_currentURL;

@end

#endif

NS_ASSUME_NONNULL_END
