#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>  // For NSImage

@class Song;

@interface NotificationManager : NSObject <NSUserNotificationCenterDelegate>

+ (instancetype)sharedManager;
- (void)notifySongPlaying:(Song *)song withImageData:(NSData *)imageData isNew:(BOOL)isNew;

@end
