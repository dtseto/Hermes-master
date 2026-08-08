#import <XCTest/XCTest.h>

@interface MenuNibIntegrityTests : XCTestCase

@end

@implementation MenuNibIntegrityTests

- (NSXMLDocument *)mainMenuDocumentWithError:(NSError **)error {
  NSString *testFilePath = [NSString stringWithUTF8String:__FILE__];
  NSURL *projectRootURL = [[NSURL fileURLWithPath:testFilePath] URLByDeletingLastPathComponent].URLByDeletingLastPathComponent;
  NSURL *mainMenuURL = [projectRootURL URLByAppendingPathComponent:@"Resources/Base.lproj/MainMenu.xib"];
  NSData *data = [NSData dataWithContentsOfURL:mainMenuURL options:0 error:error];
  if (data == nil) {
    return nil;
  }
  return [[NSXMLDocument alloc] initWithData:data options:0 error:error];
}

- (NSString *)destinationForFileOwnerOutlet:(NSString *)property document:(NSXMLDocument *)document {
  NSString *xpath = [NSString stringWithFormat:@"//customObject[@id='-2']/connections/outlet[@property='%@']/@destination", property];
  NSError *error = nil;
  NSArray<NSXMLNode *> *nodes = [document nodesForXPath:xpath error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(nodes.count, 1, @"Expected exactly one %@ outlet on NSApplication File's Owner", property);
  return nodes.firstObject.stringValue;
}

- (void)testMainMenuNibConnectsApplicationMenuOutlets {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  XCTAssertEqualObjects([self destinationForFileOwnerOutlet:@"mainMenu" document:document], @"29");
  XCTAssertEqualObjects([self destinationForFileOwnerOutlet:@"servicesMenu" document:document], @"130");
  XCTAssertEqualObjects([self destinationForFileOwnerOutlet:@"windowsMenu" document:document], @"24");
}

- (void)testMainMenuNibKeepsTopLevelMenuItems {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  NSArray<NSXMLNode *> *topLevelItems = [document nodesForXPath:@"//menu[@id='29']/items/menuItem" error:&error];
  XCTAssertNil(error);

  NSArray<NSString *> *expectedTitles = @[@"ApolloGene", @"File", @"Edit", @"View", @"Pandora", @"Window", @"Help"];
  NSMutableArray<NSString *> *actualTitles = [[NSMutableArray alloc] initWithCapacity:topLevelItems.count];
  for (NSXMLNode *item in topLevelItems) {
    NSString *title = [[(NSXMLElement *)item attributeForName:@"title"] stringValue];
    if (title != nil) {
      [actualTitles addObject:title];
    }
  }

  for (NSString *title in expectedTitles) {
    XCTAssertTrue([actualTitles containsObject:title], @"MainMenu.xib is missing top-level menu item %@", title);
  }
}

- (void)testMainMenuNibDoesNotForceAquaAppearance {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  NSArray<NSXMLNode *> *forcedAquaElements =
      [document nodesForXPath:@"//*[@appearanceType='aqua']" error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(forcedAquaElements.count, 0,
                 @"MainMenu.xib should inherit the system appearance");
}

- (void)testPlaybackSidebarsCollapseWithoutImposingRequiredMinimums {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  NSArray<NSXMLNode *> *visibleSidebars =
      [document nodesForXPath:@"//scrollView[@id='3m8-kZ-bMO' and not(@hidden='YES')] | //stackView[@id='wAm-n0-TIB' and not(@hidden='YES')]"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(visibleSidebars.count, 2,
                 @"The station and history sidebars must remain available in the playback layout");

  NSArray<NSXMLNode *> *historyWidth =
      [document nodesForXPath:@"//collectionView[@id='7eQ-hl-E1A']/constraints/constraint[@firstAttribute='width' and @constant='198' and @priority='250']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(historyWidth.count, 1,
                 @"History should keep its designed width when space exists without becoming a resize floor");

  NSArray<NSXMLNode *> *historyHeight =
      [document nodesForXPath:@"//collectionView[@id='7eQ-hl-E1A']/constraints/constraint[@firstAttribute='height' and @constant='180' and @priority='250']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(historyHeight.count, 1,
                 @"Playback history must not impose a vertical resize floor");

  NSArray<NSXMLNode *> *stationWidth =
      [document nodesForXPath:@"//scrollView[@id='3m8-kZ-bMO']/constraints/constraint[@firstAttribute='width' and @constant='198' and @priority='250']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(stationWidth.count, 1,
                 @"The station list width must remain a preference, not a resize floor");

  NSArray<NSXMLNode *> *obsoleteLayoutNeutralClasses =
      [document nodesForXPath:@"//*[@customClass='LayoutNeutralScrollView' or @customClass='LayoutNeutralStackView']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(obsoleteLayoutNeutralClasses.count, 0,
                 @"Sidebar sizing belongs to PlaybackSplitView, not intrinsic-size workarounds");

  NSArray<NSXMLNode *> *obsoleteSidebarConstraintOutlets =
      [document nodesForXPath:@"//outlet[@property='stationsPanelWidthConstraint' or @property='stationsPanelSpacingConstraint']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(obsoleteSidebarConstraintOutlets.count, 0,
                 @"PlaybackController must not toggle sidebars by mutating legacy row constraints");

  NSArray<NSXMLNode *> *compressibleHistoryContent =
      [document nodesForXPath:@"//collectionView[@id='7eQ-hl-E1A' and @horizontalHuggingPriority='1' and @horizontalCompressionResistancePriority='1']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(compressibleHistoryContent.count, 1,
                 @"History content must yield when its sidebar is narrower than its preferred width");

  NSArray<NSXMLNode *> *fixedArtworkDimensions =
      [document nodesForXPath:@"//button[@id='2436']/constraints/constraint[(@firstAttribute='width' or @firstAttribute='height') and @constant]"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(fixedArtworkDimensions.count, 0,
                 @"Artwork must derive its size from available layout space");

  NSArray<NSXMLNode *> *responsiveArtworkContainer =
      [document nodesForXPath:@"//customView[@id='Cdx-yI-Art' and @customClass='ArtworkContainerView']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(responsiveArtworkContainer.count, 1,
                 @"Artwork must be sized by a container that cannot constrain the window");

  NSArray<NSXMLNode *> *artworkLayoutConstraints =
      [document nodesForXPath:@"//customView[@id='Cdx-yI-Art']//constraint[@firstItem='2436' or @secondItem='2436']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(artworkLayoutConstraints.count, 0,
                 @"Artwork must not create a height-to-width constraint path through the window");

  NSArray<NSXMLNode *> *manuallySizedArtwork =
      [document nodesForXPath:@"//button[@id='2436' and @translatesAutoresizingMaskIntoConstraints='NO']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(manuallySizedArtwork.count, 1,
                 @"Artwork must not generate fixed autoresizing-mask constraints");

  NSArray<NSXMLNode *> *responsiveArtworkControl =
      [document nodesForXPath:@"//button[@id='2436' and @customClass='ArtworkButton']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(responsiveArtworkControl.count, 1,
                 @"Downloaded bitmap dimensions must not become layout dimensions");

  NSArray<NSXMLNode *> *requiredArtworkIntrinsicSize =
      [document nodesForXPath:@"//button[@id='2436'][@horizontalHuggingPriority='1000' or @verticalHuggingPriority='1000' or @horizontalCompressionResistancePriority='1000' or @verticalCompressionResistancePriority='1000']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(requiredArtworkIntrinsicSize.count, 0,
                 @"Album image intrinsic size must not compete with the artwork dimensions");

  NSArray<NSXMLNode *> *flexibleSpacer =
      [document nodesForXPath:@"//customView[@id='Cdx-yI-Cfs' and @hidden='YES']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(flexibleSpacer.count, 1,
                 @"Unused vertical space must be offered to artwork instead of a spacer");

  NSArray<NSXMLNode *> *songWidthMinimum =
      [document nodesForXPath:@"//stackView[@id='2tX-eR-9Av']/constraints/constraint[@firstAttribute='width' and @relation='greaterThanOrEqual']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(songWidthMinimum.count, 0,
                 @"The compact player must not impose a fixed song-content width");

  NSArray<NSXMLNode *> *fixedControlWidths =
      [document nodesForXPath:@"//stackView[@id='2tX-eR-9Av']/*/slider/constraints/constraint[@firstAttribute='width' and @constant]"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(fixedControlWidths.count, 0,
                 @"Playback and volume controls must resize with the song column");

  NSArray<NSXMLNode *> *fluidControlWidths =
      [document nodesForXPath:@"//stackView[@id='2tX-eR-9Av']/constraints/constraint[(@firstItem='7eu-hy-jM9' or @firstItem='1158') and @firstAttribute='width' and @secondItem='Cdx-yI-Art' and @secondAttribute='width']"
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(fluidControlWidths.count, 2,
                 @"Playback and volume controls should track the responsive content width");

}

@end
