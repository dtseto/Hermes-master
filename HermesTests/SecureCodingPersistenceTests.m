#import <XCTest/XCTest.h>

#import "HistoryController.h"
#import "Song.h"
#import "Station.h"

@interface HistoryController (Testing)
- (NSArray<Song *> *)decodeSavedSongsFromData:(NSData *)data path:(NSString *)path;
@end

@interface SecureCodingPersistenceTests : XCTestCase
@end

@implementation SecureCodingPersistenceTests

- (Song *)sampleSongWithToken:(NSString *)token playDateOffset:(NSTimeInterval)offset {
  Song *song = [[Song alloc] init];
  song.artist = [NSString stringWithFormat:@"Artist-%@", token];
  song.title = [NSString stringWithFormat:@"Title-%@", token];
  song.album = @"Album";
  song.stationId = @"station-001";
  song.token = token;
  song.nrating = @1;
  song.albumUrl = @"https://example.com/album";
  song.artistUrl = @"https://example.com/artist";
  song.titleUrl = @"https://example.com/title";
  song.highUrl = @"https://example.com/high";
  song.medUrl = @"https://example.com/med";
  song.lowUrl = @"https://example.com/low";
  song.playDate = [NSDate dateWithTimeIntervalSince1970:offset];
  return song;
}

- (void)testHistoryControllerSecureArchiveRoundTrip {
  HistoryController *controller = [[HistoryController alloc] init];
  Song *song = [self sampleSongWithToken:@"secure" playDateOffset:100];
  NSArray<Song *> *originalSongs = @[song];

  NSError *archiveError = nil;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:originalSongs
                                      requiringSecureCoding:YES
                                                      error:&archiveError];
  XCTAssertNotNil(data);
  XCTAssertNil(archiveError);

  NSArray<Song *> *decoded = [controller decodeSavedSongsFromData:data path:@"/dev/null"];
  XCTAssertNotNil(decoded);
  XCTAssertEqual(decoded.count, originalSongs.count);
  XCTAssertTrue([decoded.firstObject isEqual:originalSongs.firstObject]);
}

- (void)testHistoryControllerMigratesLegacyArchive {
  HistoryController *controller = [[HistoryController alloc] init];
  Song *song = [self sampleSongWithToken:@"legacy" playDateOffset:200];
  NSArray<Song *> *originalSongs = @[song];

  NSDictionary *legacyRoot = @{@"songs": originalSongs};
  NSError *archiveError = nil;
  NSData *legacyData = [NSKeyedArchiver archivedDataWithRootObject:legacyRoot
                                              requiringSecureCoding:NO
                                                              error:&archiveError];
  XCTAssertNotNil(legacyData);
  XCTAssertNil(archiveError);

  NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"history-%@.archive", NSUUID.UUID.UUIDString]];
  XCTAssertTrue([legacyData writeToFile:tempPath atomically:YES]);

  NSArray<Song *> *migrated = [controller decodeSavedSongsFromData:legacyData path:tempPath];
  XCTAssertNotNil(migrated);
  XCTAssertEqual(migrated.count, originalSongs.count);
  XCTAssertTrue([migrated.firstObject isEqual:originalSongs.firstObject]);

  NSData *rewrittenData = [NSData dataWithContentsOfFile:tempPath];
  XCTAssertNotNil(rewrittenData);

  NSError *rewriteError = nil;
  NSArray<Song *> *rewrittenSongs = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[Song class]
                                                                              fromData:rewrittenData
                                                                                 error:&rewriteError];
  XCTAssertNotNil(rewrittenSongs);
  XCTAssertNil(rewriteError);
  XCTAssertEqual(rewrittenSongs.count, originalSongs.count);
  XCTAssertTrue([rewrittenSongs.firstObject isEqual:originalSongs.firstObject]);

  [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
}

- (void)testStationSecureCodingRoundTrip {
  Station *station = [[Station alloc] init];
  station.stationId = @"station-123";
  station.name = @"Sample Station";
  station.token = @"token-123";
  station.shared = YES;
  station.allowAddMusic = NO;
  station.allowRename = YES;
  station.isQuickMix = YES;
  station.created = 987654321ull;
  [station setVolume:42.0];

  Song *playingSong = [self sampleSongWithToken:@"playing" playDateOffset:300];
  Song *queuedSong = [self sampleSongWithToken:@"queued" playDateOffset:400];

  NSMutableArray *songsQueue = [station valueForKey:@"songs"];
  XCTAssertNotNil(songsQueue);
  [songsQueue addObject:playingSong];
  [songsQueue addObject:queuedSong];

  NSURL *playingURL = [NSURL URLWithString:@"https://example.com/stream/high"];
  NSURL *queuedURL = [NSURL URLWithString:@"https://example.com/stream/next"];
  NSMutableArray *urlQueue = [station valueForKey:@"urls"];
  XCTAssertNotNil(urlQueue);
  [urlQueue addObject:playingURL];
  [urlQueue addObject:queuedURL];
  station.playingSong = playingSong;
  station.playing = playingURL;

  NSError *archiveError = nil;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:station
                                      requiringSecureCoding:YES
                                                      error:&archiveError];
  XCTAssertNotNil(data);
  XCTAssertNil(archiveError);

  NSError *unarchiveError = nil;
  Station *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[Station class]
                                                       fromData:data
                                                          error:&unarchiveError];
  XCTAssertNotNil(decoded);
  XCTAssertNil(unarchiveError);

  XCTAssertEqualObjects(decoded.stationId, station.stationId);
  XCTAssertEqualObjects(decoded.name, station.name);
  XCTAssertEqualObjects(decoded.token, station.token);
  XCTAssertEqual(decoded.shared, station.shared);
  XCTAssertEqual(decoded.allowAddMusic, station.allowAddMusic);
  XCTAssertEqual(decoded.allowRename, station.allowRename);
  XCTAssertEqual(decoded.isQuickMix, station.isQuickMix);
  XCTAssertEqual(decoded.created, station.created);
  NSArray *decodedSongs = [decoded valueForKey:@"songs"];
  NSArray *originalSongs = [station valueForKey:@"songs"];
  XCTAssertEqual(decodedSongs.count, originalSongs.count);
  XCTAssertEqual(decoded.playingSong.nrating, station.playingSong.nrating);
  XCTAssertEqualObjects(decoded.playingSong.token, station.playingSong.token);
  XCTAssertEqualObjects(decoded.playing, station.playing);
  NSArray *decodedURLs = [decoded valueForKey:@"urls"];
  XCTAssertEqual(decodedSongs.count, decodedURLs.count);

  [Station removeStation:decoded];
}

@end
