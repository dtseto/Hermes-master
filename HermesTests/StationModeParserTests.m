#import <XCTest/XCTest.h>
#import "../Sources/Pandora/StationModeParser.h"

@interface StationModeParserTests : XCTestCase
@end

@implementation StationModeParserTests

- (void)testParsesValidModesAndMarksCurrent {
  NSDictionary *result = @{ @"availableModes": @[ @{ @"modeId": @0, @"modeName": @"My Station" },
                                                    @{ @"modeId": @42, @"modeName": @"Crowd Faves" } ],
                            @"currentModeId": @42 };

  NSString *currentIdentifier = nil;
  NSArray<HMSStationMode *> *modes = [StationModeParser modesFromResultDictionary:result
                                                          currentModeIdentifier:&currentIdentifier];

  XCTAssertEqual(modes.count, 2U);
  XCTAssertEqualObjects(currentIdentifier, @"42");
  XCTAssertFalse(modes[0].isCurrent);
  XCTAssertTrue(modes[1].isCurrent);
  XCTAssertEqualObjects(modes[1].name, @"Crowd Faves");
}

- (void)testFiltersInvalidModeEntries {
  NSDictionary *result = @{ @"availableModes": @[ @{ @"modeName": @"Missing Id" },
                                                    @{ @"modeId": @3 } ],
                            @"currentModeId": @3 };

  NSString *currentIdentifier = nil;
  NSArray<HMSStationMode *> *modes = [StationModeParser modesFromResultDictionary:result
                                                          currentModeIdentifier:&currentIdentifier];

  XCTAssertEqual(modes.count, 0U);
  XCTAssertEqualObjects(currentIdentifier, @"3");
}

@end
