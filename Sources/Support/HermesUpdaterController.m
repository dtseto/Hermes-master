#import "HermesUpdaterController.h"
#import <objc/message.h>

#if __has_include(<Sparkle/Sparkle.h>)
#import <Sparkle/Sparkle.h>
#else
@interface SUUpdater : NSObject
+ (instancetype)sharedUpdater;
- (void)setAutomaticallyChecksForUpdates:(BOOL)flag;
- (void)setAutomaticallyDownloadsUpdates:(BOOL)flag;
- (void)setUpdateCheckInterval:(NSTimeInterval)interval;
- (void)checkForUpdates:(id)sender;
@end
#endif

static NSString * const kHermesUpdaterEnabledDefaultsKey = @"hermes.updater.enabled";

@interface HermesUpdaterController ()
@property (nonatomic, strong, nullable) id sparkleUpdater;
@end

@implementation HermesUpdaterController

+ (instancetype)sharedController {
  static HermesUpdaterController *sharedController = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedController = [[self alloc] init];
  });
  return sharedController;
}

- (instancetype)init {
  if ((self = [super init])) {
    _updatesEnabled = NO;
    [self registerDefaultPreferences];
    [self resolveSparkleUpdater];
  }
  return self;
}

- (void)registerDefaultPreferences {
  [[NSUserDefaults standardUserDefaults] registerDefaults:@{
    kHermesUpdaterEnabledDefaultsKey: @NO,
  }];
}

- (void)resolveSparkleUpdater {
  Class updaterClass = NSClassFromString(@"SUUpdater");
  if (updaterClass && [updaterClass respondsToSelector:@selector(sharedUpdater)]) {
    self.sparkleUpdater = ((id (*)(id, SEL))objc_msgSend)(updaterClass, @selector(sharedUpdater));
    [self configureSparkleDefaults];
  } else {
    self.sparkleUpdater = nil;
    NSLog(@"Hermes: Sparkle framework not bundled; auto-updates remain disabled.");
  }
}

- (void)configureSparkleDefaults {
  if (!self.sparkleUpdater) { return; }
  if ([self.sparkleUpdater respondsToSelector:@selector(setAutomaticallyChecksForUpdates:)]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self.sparkleUpdater, @selector(setAutomaticallyChecksForUpdates:), NO);
  }
  if ([self.sparkleUpdater respondsToSelector:@selector(setAutomaticallyDownloadsUpdates:)]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self.sparkleUpdater, @selector(setAutomaticallyDownloadsUpdates:), NO);
  }
  if ([self.sparkleUpdater respondsToSelector:@selector(setUpdateCheckInterval:)]) {
    NSTimeInterval week = 7 * 24 * 60 * 60;
    ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(self.sparkleUpdater, @selector(setUpdateCheckInterval:), week);
  }
}

- (void)configureFromDefaults {
  BOOL persisted = [[NSUserDefaults standardUserDefaults] boolForKey:kHermesUpdaterEnabledDefaultsKey];
  self.updatesEnabled = persisted;
}

- (void)persistUpdatesEnabled:(BOOL)enabled {
  self.updatesEnabled = enabled;
}

- (void)setUpdatesEnabled:(BOOL)updatesEnabled {
  _updatesEnabled = updatesEnabled;
  [[NSUserDefaults standardUserDefaults] setBool:updatesEnabled forKey:kHermesUpdaterEnabledDefaultsKey];
  if (!self.sparkleUpdater) { return; }
  if ([self.sparkleUpdater respondsToSelector:@selector(setAutomaticallyChecksForUpdates:)]) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self.sparkleUpdater, @selector(setAutomaticallyChecksForUpdates:), updatesEnabled);
  }
}

- (IBAction)checkForUpdates:(id)sender {
  if (!self.sparkleUpdater) {
    NSLog(@"Hermes: Sparkle updater unavailable. Ship the framework to enable updates.");
    return;
  }
  if (!self.isUpdatesEnabled) {
    NSLog(@"Hermes: Updates are disabled. Toggle HermesUpdaterController.updatesEnabled to opt in.");
    return;
  }
  if ([self.sparkleUpdater respondsToSelector:@selector(checkForUpdates:)]) {
    ((void (*)(id, SEL, id))objc_msgSend)(self.sparkleUpdater, @selector(checkForUpdates:), sender);
  }
}

@end
