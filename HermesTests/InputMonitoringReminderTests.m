#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>

#import "PreferencesController.h"

#import <objc/message.h>

@interface ReminderPlaybackProxy : NSObject
@property (nonatomic, strong) id mediaKeyTap;
@property (nonatomic, assign) BOOL hasAccess;
@end

@implementation ReminderPlaybackProxy

- (BOOL)hasInputMonitoringAccess {
  return self.hasAccess;
}

@end

@interface InputMonitoringReminderTests : XCTestCase
@end

@implementation InputMonitoringReminderTests

- (void)setUp {
  [super setUp];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:PLEASE_BIND_MEDIA];
}

- (void)tearDown {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:PLEASE_BIND_MEDIA];
  [super tearDown];
}

- (void)testPlaybackControllerRequestsReminderWhenNeeded {
  Class playbackClass = NSClassFromString(@"PlaybackController");
  XCTAssertNotNil(playbackClass);

  id controller = [[playbackClass alloc] init];
  XCTAssertNotNil(controller);

  id dummyTap = [[NSObject alloc] init];
  [controller setValue:dummyTap forKey:@"mediaKeyTap"];
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PLEASE_BIND_MEDIA];

  __block BOOL reminderShown = NO;

  SEL presentSelector = NSSelectorFromString(@"presentInputMonitoringInstructions");
  Method presentMethod = class_getInstanceMethod(playbackClass, presentSelector);
  IMP originalPresentIMP = method_getImplementation(presentMethod);
  IMP replacementPresentIMP = imp_implementationWithBlock(^(__kindof id _self){
    reminderShown = YES;
  });
  method_setImplementation(presentMethod, replacementPresentIMP);

  SEL hasAccessSelector = NSSelectorFromString(@"hasInputMonitoringAccess");
  Method hasAccessMethod = class_getInstanceMethod(playbackClass, hasAccessSelector);
  IMP originalHasAccessIMP = method_getImplementation(hasAccessMethod);
  IMP replacementHasAccessIMP = imp_implementationWithBlock(^BOOL(__kindof id _self){
    return NO;
  });
  method_setImplementation(hasAccessMethod, replacementHasAccessIMP);

  SEL requestSelector = NSSelectorFromString(@"requestInputMonitoringReminderIfNeeded");
  if ([controller respondsToSelector:requestSelector]) {
    ((void (*)(id, SEL))objc_msgSend)(controller, requestSelector);
  }

  XCTAssertTrue(reminderShown);

  method_setImplementation(presentMethod, originalPresentIMP);
  method_setImplementation(hasAccessMethod, originalHasAccessIMP);
  imp_removeBlock(replacementPresentIMP);
  imp_removeBlock(replacementHasAccessIMP);
}

- (void)testStatusMenuReminderVisibilityTracksInputMonitoringAccess {
  Class delegateClass = NSClassFromString(@"HermesAppDelegate");
  XCTAssertNotNil(delegateClass);
  id delegate = [[delegateClass alloc] init];
  XCTAssertNotNil(delegate);

  ReminderPlaybackProxy *proxy = [[ReminderPlaybackProxy alloc] init];
  proxy.mediaKeyTap = [[NSObject alloc] init];
  proxy.hasAccess = NO;
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PLEASE_BIND_MEDIA];

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Status"];
  [delegate setValue:menu forKey:@"statusBarMenu"];
  [delegate setValue:proxy forKey:@"playback"];

  SEL refreshSelector = NSSelectorFromString(@"refreshInputMonitoringReminder");
  if ([delegate respondsToSelector:refreshSelector]) {
    ((void (*)(id, SEL))objc_msgSend)(delegate, refreshSelector);
  }

  NSMenuItem *reminderItem = [delegate valueForKey:@"inputMonitoringMenuItem"];
  XCTAssertNotNil(reminderItem);
  XCTAssertFalse(reminderItem.hidden);

  proxy.hasAccess = YES;
  if ([delegate respondsToSelector:refreshSelector]) {
    ((void (*)(id, SEL))objc_msgSend)(delegate, refreshSelector);
  }

  XCTAssertTrue(reminderItem.hidden);
}

@end
