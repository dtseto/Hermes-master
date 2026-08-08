#import <XCTest/XCTest.h>
#import <MediaPlayer/MediaPlayer.h>

#import "ApolloGeneAppDelegate.h"
#import "PreferencesController.h"

@interface HermesAppDelegate (NowPlayingTests)
+ (MPMediaItemArtwork *)mediaItemArtworkForImage:(NSImage *)image;
@end

@interface AppLifecycleTests : XCTestCase
@end

@implementation AppLifecycleTests

- (void)tearDown {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:STATUS_BAR_ICON];
  [super tearDown];
}

- (void)testClosingLastWindowKeepsHermesRunningWithStatusItemVisible {
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STATUS_BAR_ICON];
  HermesAppDelegate *delegate = [[HermesAppDelegate alloc] init];

  XCTAssertFalse([delegate applicationShouldTerminateAfterLastWindowClosed:NSApp]);
}

- (void)testClosingLastWindowQuitsHermesWithoutStatusItem {
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:STATUS_BAR_ICON];
  HermesAppDelegate *delegate = [[HermesAppDelegate alloc] init];

  XCTAssertTrue([delegate applicationShouldTerminateAfterLastWindowClosed:NSApp]);
}

- (void)testCurrentViewTracksWindowContentSize {
  HermesAppDelegate *delegate = [[HermesAppDelegate alloc] init];
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 320, 240)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  delegate.window = window;

  NSView *contentScreen = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
  [delegate setCurrentView:contentScreen];

  XCTAssertEqual(contentScreen.autoresizingMask,
                 NSViewWidthSizable | NSViewHeightSizable);
  XCTAssertTrue(NSEqualRects(contentScreen.frame, window.contentView.bounds));

  [window setContentSize:NSMakeSize(640, 480)];

  XCTAssertTrue(NSEqualRects(contentScreen.frame, window.contentView.bounds));
}

- (void)testNowPlayingArtworkProvidesTheRequestedImageSize {
  NSImage *sourceImage = [[NSImage alloc] initWithSize:NSMakeSize(600, 600)];
  MPMediaItemArtwork *artwork = [HermesAppDelegate mediaItemArtworkForImage:sourceImage];

  XCTAssertNotNil(artwork);
  XCTAssertTrue(CGSizeEqualToSize(artwork.bounds.size, CGSizeMake(600, 600)));

  NSImage *requestedImage = [artwork imageWithSize:CGSizeMake(128, 128)];
  XCTAssertNotNil(requestedImage);
  XCTAssertTrue(NSEqualSizes(requestedImage.size, NSMakeSize(128, 128)));
}

@end
