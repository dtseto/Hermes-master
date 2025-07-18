#import <Cocoa/Cocoa.h>  // For NSImage
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

@class Song;

@interface NotificationManager : NSObject <UNUserNotificationCenterDelegate>

+ (instancetype)sharedManager;
- (void)notifySongPlaying:(Song *)song withImageData:(NSData *)imageData isNew:(BOOL)isNew;
- (void)requestNotificationPermissions;

@end
