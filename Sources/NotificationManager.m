#import "NotificationManager.h"
#import "Song.h"  // Make sure to import your Song class header
#import "PreferencesController.h"


// Use existing preference keys
#define PLEASE_GROWL @"pleaseGrowl"
#define PLEASE_GROWL_NEW @"pleaseGrowlNew"
#define PLEASE_GROWL_PLAY @"pleaseGrowlPlay"
#define NOTIFICATION_TYPE @"notificationType"


@implementation NotificationManager

+ (instancetype)sharedManager {
    static NotificationManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        center.delegate = self;
    }
    return self;
}

- (void)notifySongPlaying:(Song *)song withImageData:(NSData *)imageData isNew:(BOOL)isNew {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Check if notifications are enabled
    if (![defaults boolForKey:PLEASE_GROWL]) {
        return;
    }
    
    // Check specific notification settings
    if (isNew && ![defaults boolForKey:PLEASE_GROWL_NEW]) {
        return;
    }
    
    if (!isNew && ![defaults boolForKey:PLEASE_GROWL_PLAY]) {
        return;
    }
    
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = [song title];
    notification.subtitle = [song artist];
    notification.informativeText = [song album];
    
    if (imageData) {
        notification.contentImage = [[NSImage alloc] initWithData:imageData];
    }
    
    // Only play sound for new songs, not resumed playback
    if (isNew) {
        notification.soundName = NSUserNotificationDefaultSoundName;
    }
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}
#pragma mark - NSUserNotificationCenterDelegate

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
        shouldPresentNotification:(NSUserNotification *)notification {
    // Always show notifications, even when app is active
    return YES;
}
@end
