/**
 * @file Scrobbler.h
 *
 * @brief Interface for talking to last.fm's api and updating what's currently
 *        being listened to and such.
 */

#import "FMEngine/FMEngine.h"
#import "Pandora/Song.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum {
  NewSong,
  NowPlaying,
  FinalStatus
} ScrobbleState;

#define SCROBBLER [HMSAppDelegate scrobbler]

@protocol ScrobblerEngine <NSObject>
- (void)performMethod:(NSString * _Nonnull)method
        withCallback:(FMCallback _Nonnull)callback
      withParameters:(NSDictionary * _Nonnull)parameters
        useSignature:(BOOL)useSignature
          httpMethod:(NSString * _Nonnull)httpMethod;
@end

@protocol ScrobblerCredentialStore <NSObject>
- (nullable NSString *)fetchSessionToken;
- (BOOL)storeSessionToken:(nullable NSString *)token;
@end

@interface Scrobbler : NSObject {
  NSString *requestToken;
  BOOL inAuthorization;
}

- (instancetype)initWithEngine:(id<ScrobblerEngine> _Nonnull)engine
             credentialStore:(id<ScrobblerCredentialStore> _Nonnull)credentialStore NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

- (void) setPreference: (Song * _Nonnull)song loved:(BOOL)loved;
- (void) scrobble: (Song * _Nonnull) song state: (ScrobbleState) status;

@end

NS_ASSUME_NONNULL_END
