
#import "Pandora/Station.h"
#import "PreferencesController.h"
#import "StationsController.h"
#import "Notifications.h"

static NSString *HMSStationDecodeString(NSCoder *decoder, NSString *key) {
  id value = [decoder decodeObjectOfClass:[NSString class] forKey:key];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

@implementation Station

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (id) init {
  if (!(self = [super init])) return nil;

  songs = [NSMutableArray arrayWithCapacity:10];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(fetchMoreSongs:)
             name:ASRunningOutOfSongs
           object:self];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(fetchMoreSongs:)
             name:ASNoSongsLeft
           object:self];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(configureNewStream:)
             name:ASCreatedNewStream
           object:self];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(newSongPlaying:)
             name:ASNewSongPlaying
           object:self];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(attemptingNewSong:)
             name:ASAttemptingNewSong
           object:self];

  return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
  if ((self = [self init])) {
    NSString *decodedStationId = HMSStationDecodeString(aDecoder, @"stationId");
    if (decodedStationId != nil) {
      [self setStationId:decodedStationId];
    }

    NSString *decodedName = HMSStationDecodeString(aDecoder, @"name");
    if (decodedName != nil) {
      [self setName:decodedName];
    }

    if ([aDecoder containsValueForKey:@"volume"]) {
      [self setVolume:[aDecoder decodeDoubleForKey:@"volume"]];
    }

    if ([aDecoder containsValueForKey:@"created"]) {
      long long decodedCreated = [aDecoder decodeInt64ForKey:@"created"];
      if (decodedCreated >= 0) {
        [self setCreated:(unsigned long long)decodedCreated];
      }
    }

    NSString *decodedToken = HMSStationDecodeString(aDecoder, @"token");
    if (decodedToken != nil) {
      [self setToken:decodedToken];
    }

    [self setShared:[aDecoder decodeBoolForKey:@"shared"]];
    [self setAllowAddMusic:[aDecoder decodeBoolForKey:@"allowAddMusic"]];
    [self setAllowRename:[aDecoder decodeBoolForKey:@"allowRename"]];
    [self setIsQuickMix:[aDecoder decodeBoolForKey:@"isQuickMix"]];

    if ([aDecoder containsValueForKey:@"lastKnownSeekTime"]) {
      lastKnownSeekTime = [aDecoder decodeDoubleForKey:@"lastKnownSeekTime"];
    }

    Song *decodedPlayingSong = [aDecoder decodeObjectOfClass:[Song class] forKey:@"playing"];
    if ([decodedPlayingSong isKindOfClass:[Song class]]) {
      [self setPlayingSong:decodedPlayingSong];
      [songs addObject:decodedPlayingSong];
    } else {
      [self setPlayingSong:nil];
    }
    Song *currentPlayingSong = self.playingSong;

    NSSet *songClasses = [NSSet setWithObjects:[NSArray class], [Song class], nil];
    NSArray<Song *> *decodedSongs = [aDecoder decodeObjectOfClasses:songClasses forKey:@"songs"];
    for (Song *song in decodedSongs) {
      if (![song isKindOfClass:[Song class]]) {
        continue;
      }
      if (song == currentPlayingSong) {
        continue;
      }
      [songs addObject:song];
    }

    NSURL *decodedPlayingURL = [aDecoder decodeObjectOfClass:[NSURL class] forKey:@"playingURL"];
    if ([decodedPlayingURL isKindOfClass:[NSURL class]]) {
      [urls addObject:decodedPlayingURL];
    }
    NSURL *currentPlayingURL = decodedPlayingURL;

    NSSet *urlClasses = [NSSet setWithObjects:[NSArray class], [NSURL class], nil];
    NSArray<NSURL *> *decodedURLs = [aDecoder decodeObjectOfClasses:urlClasses forKey:@"urls"];
    for (NSURL *url in decodedURLs) {
      if (![url isKindOfClass:[NSURL class]]) {
        continue;
      }
      if (currentPlayingURL != nil && [url isEqual:currentPlayingURL]) {
        continue;
      }
      [urls addObject:url];
    }

    if ([songs count] != [urls count]) {
      [songs removeAllObjects];
      [urls removeAllObjects];
      [self setPlayingSong:nil];
    }

    [Station addStation:self];
  }
  return self;
}

- (void) encodeWithCoder:(NSCoder *)aCoder {
  if (_stationId != nil) {
    [aCoder encodeObject:_stationId forKey:@"stationId"];
  }
  if (_name != nil) {
    [aCoder encodeObject:_name forKey:@"name"];
  }
  if (_playingSong != nil) {
    [aCoder encodeObject:_playingSong forKey:@"playing"];
  }

  double seek = -1.0;
  if (_playingSong != nil && stream != nil) {
    [stream progress:&seek];
  }
  [aCoder encodeDouble:seek forKey:@"lastKnownSeekTime"];
  [aCoder encodeDouble:volume forKey:@"volume"];
  [aCoder encodeInt64:(int64_t)_created forKey:@"created"];

  if (songs != nil) {
    [aCoder encodeObject:[songs copy] forKey:@"songs"];
  }
  if (urls != nil) {
    [aCoder encodeObject:[urls copy] forKey:@"urls"];
  }

  NSURL *currentPlayingURL = [self playing];
  if (currentPlayingURL != nil) {
    [aCoder encodeObject:currentPlayingURL forKey:@"playingURL"];
  }

  if (_token != nil) {
    [aCoder encodeObject:_token forKey:@"token"];
  }

  [aCoder encodeBool:_shared forKey:@"shared"];
  [aCoder encodeBool:_allowAddMusic forKey:@"allowAddMusic"];
  [aCoder encodeBool:_allowRename forKey:@"allowRename"];
  [aCoder encodeBool:_isQuickMix forKey:@"isQuickMix"];
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:nil];
}

- (BOOL) isEqual:(id)object {
  return [_stationId isEqual:[object stationId]];
}

- (void) attemptingNewSong:(NSNotification*) notification {
    _playingSong = songs[0];
    [songs removeObjectAtIndex:0];
}

- (void) fetchMoreSongs:(NSNotification*) notification {
  shouldPlaySongOnFetch = YES;
  [radio fetchPlaylistForStation:self];
}

- (void) setRadio:(Pandora *)pandora {
  @synchronized(radio) {
    if (radio != nil) {
      [[NSNotificationCenter defaultCenter] removeObserver:self
                                                      name:nil
                                                    object:radio];
    }
    radio = pandora;

    NSString *n = [NSString stringWithFormat:@"hermes.fragment-fetched.%@", _token];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(songsLoaded:)
                                                 name:n
                                               object:nil];
  }
}

- (void) songsLoaded: (NSNotification*)not {
  NSArray *more = [not userInfo][@"songs"];
  NSMutableArray *qualities = [[NSMutableArray alloc] init];
  if (more == nil) return;

  for (Song *s in more) {
    NSURL *url = nil;
    switch (PREF_KEY_INT(DESIRED_QUALITY)) {
      case QUALITY_HIGH:
        [qualities addObject:@"high"];
        url = [NSURL URLWithString:[s highUrl]];
        break;
      case QUALITY_LOW:
        [qualities addObject:@"low"];
        url = [NSURL URLWithString:[s lowUrl]];
        break;

      case QUALITY_MED:
      default:
        [qualities addObject:@"med"];
        url = [NSURL URLWithString:[s medUrl]];
        break;
    }
    [urls addObject:url];
    [songs addObject:s];
  }
  if (shouldPlaySongOnFetch) {
    [self play];
  }
  shouldPlaySongOnFetch = NO;
  NSLogd(@"Received %@ from %@ with qualities: %@", not.name, not.object, [qualities componentsJoinedByString:@" "]);
}

- (void) configureNewStream:(NSNotification*) notification {
  assert(stream == [notification userInfo][@"stream"]);
  [stream setBufferInfinite:TRUE];
  [stream setTimeoutInterval:15];

  if (PREF_KEY_BOOL(PROXY_AUDIO)) {
    switch ([PREF_KEY_VALUE(ENABLED_PROXY) intValue]) {
      case PROXY_HTTP:
        [stream setHTTPProxy:PREF_KEY_VALUE(PROXY_HTTP_HOST)
                        port:[PREF_KEY_VALUE(PROXY_HTTP_PORT) intValue]];
        break;
      case PROXY_SOCKS:
        [stream setSOCKSProxy:PREF_KEY_VALUE(PROXY_SOCKS_HOST)
                         port:[PREF_KEY_VALUE(PROXY_SOCKS_PORT) intValue]];
        break;
      default:
        break;
    }
  }
}

- (void) newSongPlaying:(NSNotification*) notification {
  assert([songs count] == [urls count]);
  [[NSNotificationCenter defaultCenter]
        postNotificationName:StationDidPlaySongNotification
                      object:self
                    userInfo:nil];
}

- (NSString*) streamNetworkError {
  if ([stream errorCode] == AS_NETWORK_CONNECTION_FAILED) {
    return [[stream networkError] localizedDescription];
  }
  return [AudioStreamer stringForErrorCode:[stream errorCode]];
}

- (NSScriptObjectSpecifier *) objectSpecifier {
  HermesAppDelegate *delegate = HMSAppDelegate;
  StationsController *stationsc = [delegate stations];
  int index = [stationsc stationIndex:self];

  NSScriptClassDescription *containerClassDesc =
      [NSScriptClassDescription classDescriptionForClass:[NSApp class]];

  return [[NSIndexSpecifier alloc]
           initWithContainerClassDescription:containerClassDesc
           containerSpecifier:nil key:@"stations" index:index];
}

- (void) clearSongList {
  [songs removeAllObjects];
  [super clearSongList];
}

static NSMutableDictionary *stations = nil;

+ (Station*) stationForToken:(NSString*)stationId{
  if (stations == nil)
    return nil;
  return stations[stationId];
}

+ (void) addStation:(Station*) s {
  if (stations == nil) {
    stations = [NSMutableDictionary dictionary];
  }
  stations[[s stationId]] = s;
}

+ (void) removeStation:(Station*) s {
  if (stations == nil)
    return;
  [stations removeObjectForKey:[s stationId]];
}

@end
