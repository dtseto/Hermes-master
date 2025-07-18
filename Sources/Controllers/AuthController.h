#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

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

- (IBAction) authenticate: (id)sender;
- (IBAction) logout: (id) sender;
- (void) authenticationFailed:(NSNotification*) notification
                        error:(NSString*)err;
- (void) show;
- (void) updateLoginButtonState;

@end
