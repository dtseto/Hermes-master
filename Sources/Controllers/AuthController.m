#import "AuthController.h"
#import "PlaybackController.h"
#import "StationsController.h"
#import "Notifications.h"

#define ROUGH_EMAIL_REGEX @"[^\\s@]+@[^\\s@]+\\.[^\\s@]+"

@implementation AuthController

- (id) init {
  self = [super init]; // Fix: Call super init
  if (self) {
    _notificationCenter = [NSNotificationCenter defaultCenter];

    [self.notificationCenter
      addObserver:self
      selector:@selector(authenticationSucceeded:)
      name:PandoraDidAuthenticateNotification
      object:nil];

  }
  return self;
}

- (void)awakeFromNib {
  [super awakeFromNib];

  [self.notificationCenter addObserver:self
                              selector:@selector(handleCredentialFieldDidChange:)
                                  name:NSControlTextDidChangeNotification
                                object:username];

  [self.notificationCenter addObserver:self
                              selector:@selector(handleCredentialFieldDidChange:)
                                  name:NSControlTextDidChangeNotification
                                object:password];

  [self updateLoginButtonState];
}

// Fix: Add dealloc to remove observers
- (void)dealloc {
  [self.notificationCenter removeObserver:self];
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
    [[self credentialStore] saveUsername:[username stringValue] password:[password stringValue]];
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

  [[self pandoraClient] authenticate:[username stringValue]
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
  [[self pandoraClient] logout];
}

- (void)handleCredentialFieldDidChange:(NSNotification *)obj {
  [self updateLoginButtonState];
}

// Fix: Replace deprecated validateMenuItem with validateUserInterfaceItem
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  HermesAppDelegate *delegate = HMSAppDelegate;

  if (![[delegate pandora] isAuthenticated]) {
    return NO;
  }

  return YES;
}

- (NSNotificationCenter *)notificationCenter {
  if (_notificationCenter == nil) {
    _notificationCenter = [NSNotificationCenter defaultCenter];
  }
  return _notificationCenter;
}

- (id<AuthPandoraClient>)pandoraClient {
  if (_pandoraClient == nil) {
    _pandoraClient = (id<AuthPandoraClient>)[HMSAppDelegate pandora];
  }
  return _pandoraClient;
}

- (id<AuthCredentialStore>)credentialStore {
  if (_credentialStore == nil) {
    _credentialStore = (id<AuthCredentialStore>)HMSAppDelegate;
  }
  return _credentialStore;
}

@end
