
#import "Station.h"

static NSSet *HMSSongStringClasses(void) {
  static NSSet *classes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    classes = [NSSet setWithObjects:[NSString class], [NSNull class], nil];
  });
  return classes;
}

static NSString *HMSSecureDecodeSongString(NSCoder *coder, NSString *key) {
  id value = [coder decodeObjectOfClasses:HMSSongStringClasses() forKey:key];
  return value == [NSNull null] ? nil : value;
}

@implementation Song

@synthesize artist, title, album, highUrl, stationId, nrating,
  albumUrl, artistUrl, titleUrl, art, token, medUrl, lowUrl, playDate;

+ (BOOL)supportsSecureCoding {
  return YES;
}

#pragma mark - NSObject

- (BOOL) isEqual:(id)object {
  return [token isEqual:[object token]];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p %@ - %@>", NSStringFromClass(self.class), self, self.artist, self.title];
}

#pragma mark - NSCoding

- (id) initWithCoder: (NSCoder *)coder {
  if ((self = [super init])) {
    [self setArtist:HMSSecureDecodeSongString(coder, @"artist")];
    [self setTitle:HMSSecureDecodeSongString(coder, @"title")];
    [self setAlbum:HMSSecureDecodeSongString(coder, @"album")];
    [self setArt:HMSSecureDecodeSongString(coder, @"art")];
    [self setHighUrl:HMSSecureDecodeSongString(coder, @"highUrl")];
    [self setMedUrl:HMSSecureDecodeSongString(coder, @"medUrl")];
    [self setLowUrl:HMSSecureDecodeSongString(coder, @"lowUrl")];
    [self setStationId:HMSSecureDecodeSongString(coder, @"stationId")];
    [self setAlbumUrl:HMSSecureDecodeSongString(coder, @"albumUrl")];
    [self setArtistUrl:HMSSecureDecodeSongString(coder, @"artistUrl")];
    [self setTitleUrl:HMSSecureDecodeSongString(coder, @"titleUrl")];
    [self setToken:HMSSecureDecodeSongString(coder, @"token")];

    NSNumber *rating = [coder decodeObjectOfClass:[NSNumber class] forKey:@"nrating"];
    [self setNrating:rating];

    NSDate *decodedDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"playDate"];
    [self setPlayDate:decodedDate];
  }
  return self;
}

- (void) encodeWithCoder: (NSCoder *)coder {
  NSDictionary *info = [self toDictionary];
  for(id key in info) {
    [coder encodeObject:info[key] forKey:key];
  }
}

#pragma mark - NSDistributedNotification user info

- (NSDictionary*) toDictionary {
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  [info setValue:artist forKey:@"artist"];
  [info setValue:title forKey:@"title"];
  [info setValue:album forKey:@"album"];
  [info setValue:art forKey:@"art"];
  [info setValue:lowUrl forKey:@"lowUrl"];
  [info setValue:medUrl forKey:@"medUrl"];
  [info setValue:highUrl forKey:@"highUrl"];
  [info setValue:stationId forKey:@"stationId"];
  [info setValue:nrating forKey:@"nrating"];
  [info setValue:albumUrl forKey:@"albumUrl"];
  [info setValue:artistUrl forKey:@"artistUrl"];
  [info setValue:titleUrl forKey:@"titleUrl"];
  [info setValue:token forKey:@"token"];
  [info setValue:playDate forKey:@"playDate"];
  return info;
}

#pragma mark - Object Specifier

- (NSScriptObjectSpecifier *) objectSpecifier {
  NSScriptClassDescription *appDesc =
  [NSScriptClassDescription classDescriptionForClass:[NSApp class]];

  // currently, the only way to get a reference to a song
  // - if the playback history gets exposed, then publish it differently
  return [[NSPropertySpecifier alloc]
          initWithContainerClassDescription:appDesc containerSpecifier:nil key:@"currentSong"];
}

#pragma mark - Reference to station

- (Station*) station {
  return [Station stationForToken:[self stationId]];
}

#pragma mark - Formatted play date

- (NSString *)playDateString {
  if (self.playDate == nil)
    return nil;

  static NSDateFormatter *songDateFormatter = nil;
  if (songDateFormatter == nil) {
    songDateFormatter = [[NSDateFormatter alloc] init];
    songDateFormatter.dateStyle = NSDateFormatterShortStyle;
    songDateFormatter.timeStyle = NSDateFormatterShortStyle;
    songDateFormatter.doesRelativeDateFormatting = YES;
  }

  return [songDateFormatter stringFromDate:playDate];
}

@end
