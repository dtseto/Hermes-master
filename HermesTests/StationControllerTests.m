#import <XCTest/XCTest.h>

#import "StationController.h"
#import "Pandora/Station.h"
#import "Pandora/Pandora.h"

@interface FakeStationService : NSObject <StationService>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *log;
@end

@implementation FakeStationService

- (instancetype)init {
  if ((self = [super init])) {
    _log = [NSMutableArray array];
  }
  return self;
}

- (void)fetchStationInfo:(Station *)station {
  [self.log addObject:@{@"action": @"fetch", @"station": station ?: [NSNull null]}];
}

- (void)renameStation:(NSString *)stationToken to:(NSString *)name {
  [self.log addObject:@{@"action": @"rename", @"token": stationToken ?: @"", @"name": name ?: @""}];
}

- (void)search:(NSString *)query {
  [self.log addObject:@{@"action": @"search", @"query": query ?: @""}];
}

- (void)addSeed:(NSString *)seedIdentifier toStation:(Station *)station {
  [self.log addObject:@{@"action": @"addSeed", @"seed": seedIdentifier ?: @"", @"station": station ?: [NSNull null]}];
}

- (void)removeSeed:(NSString *)seedIdentifier {
  [self.log addObject:@{@"action": @"removeSeed", @"seed": seedIdentifier ?: @""}];
}

- (void)deleteFeedback:(NSString *)feedbackId {
  [self.log addObject:@{@"action": @"deleteFeedback", @"feedback": feedbackId ?: @""}];
}

@end

@interface TestOutlineView : NSOutlineView
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, strong) NSIndexSet *testSelectedIndexes;
@end

@implementation TestOutlineView
- (NSIndexSet *)selectedRowIndexes {
  return self.testSelectedIndexes ?: [NSIndexSet indexSet];
}
- (NSInteger)numberOfSelectedRows {
  return self.selectedRowIndexes.count;
}
- (id)itemAtRow:(NSInteger)row {
  return row < self.items.count ? self.items[row] : nil;
}
- (void)deselectAll:(id)sender {
  self.testSelectedIndexes = [NSIndexSet indexSet];
}
- (void)expandItem:(id)item {
  // no-op for tests
}
@end

@interface TestTableView : NSTableView
@property (nonatomic, strong) NSIndexSet *testSelectedIndexes;
@end

@implementation TestTableView
- (NSIndexSet *)selectedRowIndexes {
  return self.testSelectedIndexes ?: [NSIndexSet indexSet];
}
- (NSInteger)numberOfSelectedRows {
  return self.selectedRowIndexes.count;
}
- (void)deselectAll:(id)sender {
  self.testSelectedIndexes = [NSIndexSet indexSet];
}
- (NSTableRowView *)rowViewAtRow:(NSInteger)row makeIfNecessary:(BOOL)make {
  return [[NSTableRowView alloc] init];
}
@end

@interface StationControllerTests : XCTestCase
@end

@implementation StationControllerTests

- (StationController *)makeControllerWithService:(FakeStationService **)serviceOut {
  StationController *controller = [[StationController alloc] init];
  FakeStationService *service = [[FakeStationService alloc] init];
  controller.stationService = service;
  controller.notificationCenter = [[NSNotificationCenter alloc] init];
  [controller setValue:[[NSProgressIndicator alloc] init] forKey:@"progress"];
  [controller setValue:[[NSTextField alloc] init] forKey:@"stationName"];
  [controller setValue:[[NSTextField alloc] init] forKey:@"stationCreated"];
  [controller setValue:[[NSTextField alloc] init] forKey:@"stationGenres"];
  [controller setValue:[[NSImageView alloc] init] forKey:@"art"];
  [controller setValue:[[NSButton alloc] init] forKey:@"seedAdd"];
  [controller setValue:[[NSButton alloc] init] forKey:@"seedDel"];
  [controller setValue:[[NSButton alloc] init] forKey:@"deleteFeedback"];
  [controller setValue:[[NSTableView alloc] init] forKey:@"likes"];
  [controller setValue:[[NSTableView alloc] init] forKey:@"dislikes"];
  [controller setValue:[[NSTableView alloc] init] forKey:@"seedsCurrent"];
  [controller setValue:[[NSTableView alloc] init] forKey:@"seedsResults"];
  if (serviceOut) {
    *serviceOut = service;
  }
  return controller;
}

- (void)testRenameStationInvokesService {
  FakeStationService *service = nil;
  StationController *controller = [self makeControllerWithService:&service];
  Station *station = [[Station alloc] init];
  station.token = @"token-1";
  [controller setValue:station forKey:@"cur_station"];
  NSTextField *nameField = [controller valueForKey:@"stationName"];
  nameField.stringValue = @"New Name";

  [controller renameStation:nil];

  NSDictionary *entry = service.log.lastObject;
  XCTAssertEqualObjects(entry[@"action"], @"rename");
  XCTAssertEqualObjects(entry[@"token"], @"token-1");
  XCTAssertEqualObjects(entry[@"name"], @"New Name");
}

- (void)testAddSeedRequestsAllSelectedResults {
  FakeStationService *service = nil;
  StationController *controller = [self makeControllerWithService:&service];
  Station *station = [[Station alloc] init];
  [controller setValue:station forKey:@"cur_station"];

  TestOutlineView *results = [[TestOutlineView alloc] init];
  PandoraSearchResult *result1 = [[PandoraSearchResult alloc] init];
  result1.value = @"seed-a";
  PandoraSearchResult *result2 = [[PandoraSearchResult alloc] init];
  result2.value = @"seed-b";
  results.items = @[result1, result2];
  results.testSelectedIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)];
  [controller setValue:results forKey:@"seedsResults"];

  [controller addSeed:nil];

  NSArray *actions = service.log;
  XCTAssertEqual(actions.count, 2);
  XCTAssertEqualObjects(actions[0][@"seed"], @"seed-a");
  XCTAssertEqualObjects(actions[1][@"seed"], @"seed-b");
}

- (void)testDeleteSeedInvokesRemoveForSelection {
  FakeStationService *service = nil;
  StationController *controller = [self makeControllerWithService:&service];
  TestOutlineView *current = [[TestOutlineView alloc] init];
  current.items = @[ @{@"seedId": @"1"},
                     @{@"seedId": @"2"} ];
  current.testSelectedIndexes = [NSIndexSet indexSetWithIndex:1];
  [controller setValue:current forKey:@"seedsCurrent"];

  [controller deleteSeed:nil];

  NSDictionary *entry = service.log.lastObject;
  XCTAssertEqualObjects(entry[@"action"], @"removeSeed");
  XCTAssertEqualObjects(entry[@"seed"], @"2");
}

- (void)testDeleteFeedbackRemovesSelectedItems {
  FakeStationService *service = nil;
  StationController *controller = [self makeControllerWithService:&service];
  NSArray *likes = @[ @{@"feedbackId": @"like-1"} ];
  NSArray *dislikes = @[ @{@"feedbackId": @"dislike-1"} ];
  [controller setValue:likes forKey:@"alikes"];
  [controller setValue:dislikes forKey:@"adislikes"];

  TestTableView *likesTable = [[TestTableView alloc] init];
  likesTable.testSelectedIndexes = [NSIndexSet indexSetWithIndex:0];
  TestTableView *dislikesTable = [[TestTableView alloc] init];
  dislikesTable.testSelectedIndexes = [NSIndexSet indexSetWithIndex:0];
  [controller setValue:likesTable forKey:@"likes"];
  [controller setValue:dislikesTable forKey:@"dislikes"];

  [controller deleteFeedback:nil];

  XCTAssertEqual(service.log.count, 2);
  NSDictionary *expectedLike = @{@"action": @"deleteFeedback",
                                 @"feedback": @"like-1"};
  NSDictionary *expectedDislike = @{@"action": @"deleteFeedback",
                                    @"feedback": @"dislike-1"};
  XCTAssertTrue([service.log containsObject:expectedLike],
                @"Missing like feedback removal");
  XCTAssertTrue([service.log containsObject:expectedDislike],
                @"Missing dislike feedback removal");
}

@end
