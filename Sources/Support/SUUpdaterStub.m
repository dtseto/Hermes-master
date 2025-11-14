#import <Foundation/Foundation.h>

/**
 A minimal placeholder for Sparkle's SUUpdater so that legacy nib
 connections keep working even when Sparkle.framework is not bundled.
 */
@interface SUUpdater : NSObject
@property (nonatomic, assign) BOOL automaticallyChecksForUpdates;
@property (nonatomic, assign) BOOL automaticallyDownloadsUpdates;
@property (nonatomic, assign) NSInteger updateCheckInterval;
+ (instancetype)sharedUpdater;
- (IBAction)checkForUpdates:(id)sender;
@end

@implementation SUUpdater

+ (instancetype)sharedUpdater {
  static SUUpdater *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  if ((self = [super init])) {
    _automaticallyChecksForUpdates = NO;
    _automaticallyDownloadsUpdates = NO;
    _updateCheckInterval = 0;
  }
  return self;
}

- (IBAction)checkForUpdates:(__unused id)sender {
  NSLog(@"Sparkle updater stub invoked. Updates are disabled in this build.");
}

@end
