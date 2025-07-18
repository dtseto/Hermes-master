#import "NotificationManager.h"
#import "Song.h"
#import "PreferencesController.h"
#import <UserNotifications/UserNotifications.h>

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
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
        
        // Request notification permissions
        [self requestNotificationPermissions];
    }
    return self;
}

- (void)requestNotificationPermissions {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    
    [center requestAuthorizationWithOptions:options
                           completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Notification permission error: %@", error);
        }
        if (!granted) {
            NSLog(@"Notification permission denied");
        }
    }];
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
    
    // Create notification content
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [song title];
    content.subtitle = [song artist];
    content.body = [song album];
    
    // Add image attachment if available
    if (imageData) {
        NSError *error;
        NSString *tempDir = NSTemporaryDirectory();
        NSString *imagePath = [tempDir stringByAppendingPathComponent:@"notification_image.jpg"];
        
        if ([imageData writeToFile:imagePath atomically:YES]) {
            UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"songImage"
                                                                                                  URL:[NSURL fileURLWithPath:imagePath]
                                                                                              options:nil
                                                                                                error:&error];
            if (attachment && !error) {
                content.attachments = @[attachment];
            }
        }
    }
    
    // Only play sound for new songs, not resumed playback
    if (isNew) {
        content.sound = [UNNotificationSound defaultSound];
    }
    
    // Create notification request
    NSString *identifier = [NSString stringWithFormat:@"song_notification_%@", [[NSUUID UUID] UUIDString]];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:nil]; // nil trigger means deliver immediately
    
    // Schedule the notification
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Error delivering notification: %@", error);
        }
    }];
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // Show notifications even when app is in foreground
  UNNotificationPresentationOptions options = UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner |
                                               UNNotificationPresentationOptionSound;
    
    // On macOS 11+ you can also use UNNotificationPresentationOptionBanner
    if (@available(macOS 11.0, *)) {
        options = UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound;
    }
    
    completionHandler(options);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    // Handle notification tap/interaction if needed
    NSLog(@"User interacted with notification: %@", response.notification.request.identifier);
    completionHandler();
}

@end
