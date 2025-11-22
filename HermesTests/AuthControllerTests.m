#import <XCTest/XCTest.h>

#import "AuthController.h"

@interface FakePandoraClient : NSObject <AuthPandoraClient>
@property (nonatomic, copy) NSString *lastUsername;
@property (nonatomic, copy) NSString *lastPassword;
@property (nonatomic, assign) NSInteger authenticateCount;
@property (nonatomic, assign) NSInteger logoutCount;
@end

@implementation FakePandoraClient
- (BOOL)authenticate:(NSString *)username password:(NSString *)password request:(PandoraRequest *)request {
  self.lastUsername = username;
  self.lastPassword = password;
  self.authenticateCount += 1;
  return YES;
}
- (void)logout {
  self.logoutCount += 1;
}
@end

@interface FakeCredentialStore : NSObject <AuthCredentialStore>
@property (nonatomic, copy) NSString *savedUsername;
@property (nonatomic, copy) NSString *savedPassword;
@end

@implementation FakeCredentialStore
- (void)saveUsername:(NSString *)username password:(NSString *)password {
  self.savedUsername = username;
  self.savedPassword = password;
}
@end

@interface TestAuthController : AuthController
@property (nonatomic, assign) BOOL didShowView;
@end

@implementation TestAuthController
- (void)show {
  self.didShowView = YES;
}
@end

@interface AuthControllerTests : XCTestCase
@end

@implementation AuthControllerTests

- (TestAuthController *)makeControllerWithClient:(FakePandoraClient **)clientOut store:(FakeCredentialStore **)storeOut {
  TestAuthController *controller = [[TestAuthController alloc] init];
  FakePandoraClient *client = [[FakePandoraClient alloc] init];
  FakeCredentialStore *store = [[FakeCredentialStore alloc] init];
  controller.pandoraClient = client;
  controller.credentialStore = store;
  controller.notificationCenter = [[NSNotificationCenter alloc] init];

  NSButton *login = [[NSButton alloc] init];
  login.enabled = YES;
  NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
  spinner.hidden = YES;
  NSImageView *errorIcon = [[NSImageView alloc] init];
  errorIcon.hidden = YES;
  NSTextField *errorText = [[NSTextField alloc] init];
  errorText.hidden = YES;
  NSTextField *username = [[NSTextField alloc] init];
  NSSecureTextField *password = [[NSSecureTextField alloc] init];

  [controller setValue:login forKey:@"login"];
  [controller setValue:spinner forKey:@"spinner"];
  [controller setValue:errorIcon forKey:@"error"];
  [controller setValue:errorText forKey:@"errorText"];
  [controller setValue:username forKey:@"username"];
  [controller setValue:password forKey:@"password"];

  if (clientOut) {
    *clientOut = client;
  }
  if (storeOut) {
    *storeOut = store;
  }
  return controller;
}

- (void)testLoginButtonEnablesAfterTypingValidCredentials {
  TestAuthController *controller = [self makeControllerWithClient:NULL store:NULL];
  [controller awakeFromNib];

  NSButton *login = [controller valueForKey:@"login"];
  login.enabled = NO;

  NSTextField *username = [controller valueForKey:@"username"];
  NSSecureTextField *password = [controller valueForKey:@"password"];

  [username setStringValue:@"user@example.com"];
  [[controller notificationCenter] postNotificationName:NSControlTextDidChangeNotification object:username];
  XCTAssertFalse(login.isEnabled);

  [password setStringValue:@"hunter2"];
  [[controller notificationCenter] postNotificationName:NSControlTextDidChangeNotification object:password];
  XCTAssertTrue(login.isEnabled);
}

- (void)testAuthenticateInvokesPandoraClient {
  FakePandoraClient *client = nil;
  TestAuthController *controller = [self makeControllerWithClient:&client store:NULL];
  [[controller valueForKey:@"username"] setStringValue:@"user@example.com"];
  [[controller valueForKey:@"password"] setStringValue:@"secret"];

  [controller authenticate:controller];

  XCTAssertEqual(client.authenticateCount, 1);
  XCTAssertEqualObjects(client.lastUsername, @"user@example.com");
  XCTAssertEqualObjects(client.lastPassword, @"secret");
  NSButton *login = [controller valueForKey:@"login"];
  XCTAssertFalse(login.isEnabled);
}

- (void)testAuthenticationFailedDisplaysError {
  TestAuthController *controller = [self makeControllerWithClient:NULL store:NULL];
  NSTextField *usernameField = [controller valueForKey:@"username"];
  [usernameField setStringValue:@""];

  [controller authenticationFailed:nil error:@"Invalid login"];

  NSTextField *errorText = [controller valueForKey:@"errorText"];
  XCTAssertEqualObjects(errorText.stringValue, @"Invalid login");
  XCTAssertFalse(errorText.isHidden);
  XCTAssertTrue(controller.didShowView);
}

- (void)testAuthenticationSucceededSavesCredentials {
  FakePandoraClient *client = nil;
  FakeCredentialStore *store = nil;
  TestAuthController *controller = [self makeControllerWithClient:&client store:&store];
  [[controller valueForKey:@"username"] setStringValue:@"user@example.com"];
  [[controller valueForKey:@"password"] setStringValue:@"pw"];

  [controller authenticationSucceeded:nil];

  XCTAssertEqualObjects(store.savedUsername, @"user@example.com");
  XCTAssertEqualObjects(store.savedPassword, @"pw");
}

- (void)testLogoutInvokesClient {
  FakePandoraClient *client = nil;
  TestAuthController *controller = [self makeControllerWithClient:&client store:NULL];

  [controller logout:controller];

  XCTAssertEqual(client.logoutCount, 1);
}

@end
