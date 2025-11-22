#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@class PandoraRequest;

NS_ASSUME_NONNULL_BEGIN

@protocol AuthPandoraClient <NSObject>
- (BOOL)authenticate:(NSString * _Nonnull)username
            password:(NSString * _Nonnull)password
             request:(PandoraRequest * _Nullable)request;
- (void)logout;
@end

@protocol AuthCredentialStore <NSObject>
- (void)saveUsername:(NSString * _Nonnull)username
            password:(NSString * _Nonnull)password;
@end

@interface AuthController : NSObject <NSUserInterfaceValidations> {
  IBOutlet NSView *view;

  // Fields of the authentication view
  IBOutlet NSButton *login;
  IBOutlet NSProgressIndicator *spinner;
  IBOutlet NSImageView *error;
  IBOutlet NSTextField *username;
  IBOutlet NSSecureTextField *password;
  IBOutlet NSTextField *errorText;
}

@property (nonatomic, strong, nullable) id<AuthPandoraClient> pandoraClient;
@property (nonatomic, strong, nullable) id<AuthCredentialStore> credentialStore;
@property (nonatomic, strong, nullable) NSNotificationCenter *notificationCenter;

- (IBAction) authenticate: (id)sender;
- (IBAction) logout: (id) sender;
- (void) authenticationFailed:(NSNotification * _Nullable) notification
                        error:(NSString*)err;
- (void) authenticationSucceeded:(NSNotification * _Nullable)notification;
- (void) show;
- (void) updateLoginButtonState;

@end

NS_ASSUME_NONNULL_END
