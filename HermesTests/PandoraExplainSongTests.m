#import <XCTest/XCTest.h>

typedef void(^PandoraCallback)(NSDictionary *);

@interface Song : NSObject
@property(nonatomic, copy) NSString *token;
@end

@interface PandoraRequest : NSObject
@property(nonatomic, copy) PandoraCallback callback;
@end

@interface Pandora : NSObject
- (BOOL)sendRequest:(PandoraRequest *)request;
- (void)explainSong:(Song *)song;
@end

extern NSString * const PandoraDidExplainSongNotification;

@interface TestExplainPandora : Pandora
@property(nonatomic, strong) PandoraRequest *capturedRequest;
@end

@implementation TestExplainPandora
- (BOOL)sendRequest:(PandoraRequest *)request {
  self.capturedRequest = request;
  return YES;
}
@end

@interface PandoraExplainSongTests : XCTestCase
@end

@implementation PandoraExplainSongTests

- (Song *)songWithToken:(NSString *)token {
  Song *song = [[Song alloc] init];
  song.token = token;
  return song;
}

- (NSDictionary *)responseWithTraits:(NSArray<NSString *> *)traits {
  NSMutableArray *explanations = [NSMutableArray array];
  for (NSString *name in traits) {
    [explanations addObject:@{ @"focusTraitName": name }];
  }
  return @{ @"result": @{ @"explanations": explanations } };
}

- (void)testExplainSongPostsFormattedNotification {
  TestExplainPandora *pandora = [[TestExplainPandora alloc] init];
  Song *song = [self songWithToken:@"token-123"];

  XCTestExpectation *expectation = [self expectationWithDescription:@"Explanation notification"];
  __block NSString *receivedExplanation = nil;
  id observer = [[NSNotificationCenter defaultCenter] addObserverForName:PandoraDidExplainSongNotification
                                                                  object:song
                                                                   queue:nil
                                                              usingBlock:^(NSNotification * _Nonnull note) {
    receivedExplanation = note.userInfo[@"explanation"];
    [expectation fulfill];
  }];

  [pandora explainSong:song];
  XCTAssertNotNil(pandora.capturedRequest);

  pandora.capturedRequest.callback([self responseWithTraits:@[@"acoustic vibe", @"folk roots", @"lyrical depth"]]);

  [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  [self waitForExpectationsWithTimeout:1.0 handler:nil];

  XCTAssertEqualObjects(receivedExplanation, @"Chosen for: acoustic vibe, folk roots, and lyrical depth.");
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testExplainSongFallsBackWhenNoTraits {
  TestExplainPandora *pandora = [[TestExplainPandora alloc] init];
  Song *song = [self songWithToken:@"token-456"];
  XCTestExpectation *expectation = [self expectationWithDescription:@"Fallback explanation"];
  __block NSString *receivedExplanation = nil;
  id observer = [[NSNotificationCenter defaultCenter] addObserverForName:PandoraDidExplainSongNotification
                                                                  object:song
                                                                   queue:nil
                                                              usingBlock:^(NSNotification * _Nonnull note) {
    receivedExplanation = note.userInfo[@"explanation"];
    [expectation fulfill];
  }];

  [pandora explainSong:song];
  XCTAssertNotNil(pandora.capturedRequest);

  pandora.capturedRequest.callback(@{ @"result": @{ @"explanations": @[] } });

  [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  [self waitForExpectationsWithTimeout:1.0 handler:nil];

  XCTAssertEqualObjects(receivedExplanation, @"No explanation available for this song");
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end
