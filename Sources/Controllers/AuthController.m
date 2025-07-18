#import "AuthController.h"
#import "PlaybackController.h"
#import "StationsController.h"
#import "Notifications.h"

#define ROUGH_EMAIL_REGEX @"[^\\s@]+@[^\\s@]+\\.[^\\s@]+"

@implementation AuthController

- (id) init {
  self = [super init]; // Fix: Call super init
  if (self) {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    [notificationCenter
      addObserver:self
      selector:@selector(authenticationSucceeded:)
      name:PandoraDidAuthenticateNotification
      object:nil];

    [notificationCenter
     addObserver:self
     selector:@selector(controlTextDidChange:)
     name:NSControlTextDidChangeNotification
     object:username];

    [notificationCenter
     addObserver:self
     selector:@selector(controlTextDidChange:)
     name:NSControlTextDidChangeNotification
     object:password];
  }
  return self;
}

// Fix: Add dealloc to remove observers
- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Fix: Extract login validation logic to separate method
- (void)updateLoginButtonState {
  NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", ROUGH_EMAIL_REGEX];
  
  [login setEnabled:
   [spinner isHidden] &&
   [emailTest evaluateWithObject:[username stringValue]] &&
   ![[password stringValue] isEqualToString:@""]];
}

- (void)authenticationFailed:(NSNotification*)notification error:(NSString*)err {
  [spinner setHidden:YES];
  [spinner stopAnimation:nil];
  [self show];
  [error setHidden:NO];
  [errorText setHidden:NO];
  [errorText setStringValue:err];
  
  if ([username stringValue] == nil || [[username stringValue] isEqual:@""]) {
    [username becomeFirstResponder];
  } else {
    [password becomeFirstResponder];
  }
  
  // Fix: Use extracted method instead of manually calling controlTextDidChange
  [self updateLoginButtonState];
}

- (void) authenticationSucceeded: (NSNotification*) notification {
  [spinner setHidden:YES];
  [spinner stopAnimation:nil];

  HermesAppDelegate *delegate = HMSAppDelegate;
  if (![[username stringValue] isEqualToString:@""]) {
    [delegate saveUsername:[username stringValue] password:[password stringValue]];
  }

  [[delegate stations] show];
  [PlaybackController setPlayOnStart:YES];
}

/* Login button in sheet hit, should authenticate */
- (IBAction) authenticate: (id) sender {
  [error setHidden: YES];
  [errorText setHidden: YES];
  [spinner setHidden:NO];
  [spinner startAnimation: sender];

  [[HMSAppDelegate pandora] authenticate:[username stringValue]
                                  password:[password stringValue]
                                   request:nil];
  [login setEnabled:NO];
}

/* Show the authentication view */
- (void) show {
  [HMSAppDelegate setCurrentView:view];
  [username becomeFirstResponder];
  
  // Fix: Use extracted method instead of manually calling controlTextDidChange
  [self updateLoginButtonState];
}

/* Log out the current session */
- (IBAction) logout: (id) sender {
  [password setStringValue:@""];
  HermesAppDelegate *delegate = HMSAppDelegate;
  [[delegate pandora] logout];
}

//- (void)controlTextDidChange:(NSNotification *)obj {
//  [self updateLoginButtonState];
//}

// Fix: Replace deprecated validateMenuItem with validateUserInterfaceItem
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  HermesAppDelegate *delegate = HMSAppDelegate;

  if (![[delegate pandora] isAuthenticated]) {
    return NO;
  }

  return YES;
}

@end
