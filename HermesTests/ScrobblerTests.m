#import <XCTest/XCTest.h>

#import "Scrobbler.h"
#import "Pandora/Song.h"
#import "Controllers/PreferencesController.h"

@interface FakeScrobblerEngine : NSObject <ScrobblerEngine>
@property (nonatomic, copy) NSString *lastMethod;
@property (nonatomic, strong) NSDictionary *lastParameters;
@end

@implementation FakeScrobblerEngine
- (void)performMethod:(NSString *)method
        withCallback:(FMCallback)callback
      withParameters:(NSDictionary *)parameters
        useSignature:(BOOL)useSignature
          httpMethod:(NSString *)httpMethod {
  self.lastMethod = method;
  self.lastParameters = parameters;
}
@end

@interface StubScrobblerCredentialStore : NSObject <ScrobblerCredentialStore>
@property (nonatomic, copy) NSString *token;
@end

@implementation StubScrobblerCredentialStore
- (NSString *)fetchSessionToken { return self.token; }
- (BOOL)storeSessionToken:(NSString *)token {
  self.token = token;
  return YES;
}
@end

@interface ScrobblerTests : XCTestCase
@end

@implementation ScrobblerTests

- (Song *)sampleSong {
  Song *song = [[Song alloc] init];
  song.artist = @"Artist";
  song.title = @"Title";
  song.album = @"Album";
  return song;
}

- (void)setUp {
  [super setUp];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
}

- (void)testScrobbleSendsNowPlayingWhenEnabled {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setBool:YES forKey:PLEASE_SCROBBLE];
  [defaults setBool:NO forKey:ONLY_SCROBBLE_LIKED];

  FakeScrobblerEngine *engine = [[FakeScrobblerEngine alloc] init];
  StubScrobblerCredentialStore *store = [[StubScrobblerCredentialStore alloc] init];
  store.token = @"session";
  Scrobbler *scrobbler = [[Scrobbler alloc] initWithEngine:engine credentialStore:store];

  [scrobbler scrobble:[self sampleSong] state:NowPlaying];

  XCTAssertEqualObjects(engine.lastMethod, @"track.updateNowPlaying");
  XCTAssertEqualObjects(engine.lastParameters[@"track"], @"Title");
  XCTAssertEqualObjects(engine.lastParameters[@"artist"], @"Artist");
  XCTAssertEqualObjects(engine.lastParameters[@"album"], @"Album");
}

- (void)testScrobbleDoesNothingWhenDisabled {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setBool:NO forKey:PLEASE_SCROBBLE];

  FakeScrobblerEngine *engine = [[FakeScrobblerEngine alloc] init];
  StubScrobblerCredentialStore *store = [[StubScrobblerCredentialStore alloc] init];
  store.token = @"session";
  Scrobbler *scrobbler = [[Scrobbler alloc] initWithEngine:engine credentialStore:store];

  [scrobbler scrobble:[self sampleSong] state:NowPlaying];

  XCTAssertNil(engine.lastMethod);
}

- (void)testSetPreferenceRequestsSessionWhenMissing {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setBool:YES forKey:PLEASE_SCROBBLE];
  [defaults setBool:YES forKey:PLEASE_SCROBBLE_LIKES];

  FakeScrobblerEngine *engine = [[FakeScrobblerEngine alloc] init];
  StubScrobblerCredentialStore *store = [[StubScrobblerCredentialStore alloc] init];
  store.token = nil;
  Scrobbler *scrobbler = [[Scrobbler alloc] initWithEngine:engine credentialStore:store];

  [scrobbler setPreference:[self sampleSong] loved:YES];

  XCTAssertEqualObjects(engine.lastMethod, @"auth.getToken");
}

@end
