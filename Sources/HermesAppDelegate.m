/**
 * @file HermesAppDelegate.m
 * @brief Implementation of the AppDelegate for Hermes
 *
 * Contains startup routines, and other interfaces with the OS
 */

#import <SPMediaKeyTap/SPMediaKeyTap.h>
#import <MediaPlayer/MediaPlayer.h>

#import "HermesAppDelegate.h"
// Add this to the top with other imports:
#import <AudioToolbox/AudioToolbox.h>

#import "AuthController.h"
#import "HistoryController.h"
#import "Integration/Keychain.h"
#import "PlaybackController.h"
#import "PreferencesController.h"
#import "StationController.h"
#import "StationsController.h"
#import "Notifications.h"

// strftime_l()
#include <xlocale.h>

#define HERMES_LOG_DIRECTORY_PATH @"~/Library/Logs/Hermes/"
#define DEBUG_MODE_TITLE_PREFIX @"🐞 "
#define STATUS_BAR_MAX_WIDTH 200

@interface HermesAppDelegate ()

@property (readonly) NSString *hermesLogFile;
@property (readonly, nonatomic) FILE *hermesLogFileHandle;
@property (strong, nonatomic) NSMenuItem *inputMonitoringMenuItem;
@property (strong, nonatomic) NSMenuItem *inputMonitoringSeparator;

@end

@implementation HermesAppDelegate

@synthesize stations, auth, playback, pandora, window, history, station,
             scrobbler, networkManager, preferences;

- (id) init {
  if ((self = [super init])) {
    pandora = [[Pandora alloc] init];
    _debugMode = NO;
  }
  return self;
}

- (void)dealloc {
  if (self.hermesLogFileHandle) {
    fclose(self.hermesLogFileHandle);
  }
}

// dummy callback functions before initializeModernAudioSystem:
static void DummyPropertyListenerProc(void *inClientData,
                                     AudioFileStreamID inAudioFileStream,
                                     AudioFileStreamPropertyID inPropertyID,
                                     UInt32 *ioFlags) {
    // Empty dummy callback
}

static void DummyPacketsProc(void *inClientData,
                           UInt32 inNumberBytes,
                           UInt32 inNumberPackets,
                           const void *inInputData,
                           AudioStreamPacketDescription *inPacketDescriptions) {
    // Empty dummy callback
}

#pragma mark - Audio System Initialization
- (void)initializeModernAudioSystem {
    @autoreleasepool {
        NSLog(@"Initializing modern audio system at app startup...");
        
        // Simplified macOS audio setup without CoreAudio framework dependencies
        AudioComponentDescription descriptions[] = {
            {
                .componentType = kAudioUnitType_Output,
                .componentSubType = kAudioUnitSubType_DefaultOutput,
                .componentManufacturer = kAudioUnitManufacturer_Apple
            },
            {
                .componentType = kAudioUnitType_Output,
                .componentSubType = kAudioUnitSubType_HALOutput,
                .componentManufacturer = kAudioUnitManufacturer_Apple
            },
            {
                .componentType = kAudioUnitType_FormatConverter,
                .componentSubType = kAudioUnitSubType_AUConverter,
                .componentManufacturer = kAudioUnitManufacturer_Apple
            }
        };
        
        int componentCount = sizeof(descriptions) / sizeof(descriptions[0]);
        for (int i = 0; i < componentCount; i++) {
            @autoreleasepool {
                AudioComponent component = AudioComponentFindNext(NULL, &descriptions[i]);
                if (component) {
                    NSLog(@"Modern audio component %d initialized successfully", i);
                } else {
                    NSLog(@"Failed to find audio component %d", i);
                }
            }
        }
        
        // Pre-load AAC decoder - use dispatch to avoid blocking main thread
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                AudioFileStreamID testStream;
                OSStatus err = AudioFileStreamOpen(NULL, DummyPropertyListenerProc, DummyPacketsProc,
                                                  kAudioFileAAC_ADTSType, &testStream);
                if (err == 0) {
                    NSLog(@"AAC decoder pre-loaded successfully");
                    AudioFileStreamClose(testStream);
                } else {
                    NSLog(@"AAC decoder pre-load failed: %d", (int)err);
                }
            }
        });
        
        NSLog(@"Modern audio system initialization complete");
    }
}

#pragma mark - NSApplicationDelegate

- (BOOL) applicationShouldHandleReopen:(NSApplication *)theApplication
                    hasVisibleWindows:(BOOL)flag {
  if (!flag) {
    [window makeKeyAndOrderFront:nil];
  }

  return YES;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
  NSMenu *menu = [[NSMenu alloc] init];
  NSMenuItem *menuItem;
  Song *song = [[playback playing] playingSong];
  if (song != nil) {
    [menu addItemWithTitle:nowPlaying.title action:nil keyEquivalent:@""];
    [menu addItemWithTitle:[@"   " stringByAppendingString:song.title] action:nil keyEquivalent:@""];
    [menu addItemWithTitle:[@"   " stringByAppendingString:song.artist] action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
  }
  NSString *title;
  if ([[playback playing] isPaused] || song == nil) {
    title = @"Play";
  } else {
    title = @"Pause";
  }
  menuItem = [menu addItemWithTitle:title
                             action:@selector(playpause:)
                      keyEquivalent:@""];
  [menuItem setTarget:playback];
  menuItem = [menu addItemWithTitle:@"Like"
                             action:@selector(like:)
                      keyEquivalent:@""];
  [menuItem setTarget:playback];
  if ([[song nrating] intValue] == 1) {
    menuItem.state = NSControlStateValueOn;
  }
  menuItem = [menu addItemWithTitle:@"Dislike"
                             action:@selector(dislike:)
                      keyEquivalent:@""];
  [menuItem setTarget:playback];
  menuItem = [menu addItemWithTitle:@"Skip to Next Song"
                             action:@selector(next:)
                      keyEquivalent:@""];
  [menuItem setTarget:playback];
  menuItem = [menu addItemWithTitle:@"Tired of Song"
                             action:@selector(tired:)
                      keyEquivalent:@""];
  [menuItem setTarget:playback];
  return menu;
}

#pragma mark -

- (void) closeNewStationSheet {
  [window endSheet:newStationSheet];
}

- (void) showNewStationSheet {
  [window beginSheet:newStationSheet completionHandler:nil];
}

- (void) showLoader {
  [self setCurrentView:loadingView];
  [loadingIcon startAnimation:nil];
}

- (void) setCurrentView:(NSView *)view {
  NSView *superview = [window contentView];

  if ([[superview subviews] count] > 0) {
    NSView *prev_view = [superview subviews][0];
    if (prev_view == view) {
      return;
    }
    [superview replaceSubview:prev_view with:view];
    // FIXME: This otherwise looks nicer but it causes the toolbar to flash.
    // [[superview animator] replaceSubview:prev_view with:view];
  } else {
    [superview addSubview:view];
  }

  NSRect frame = [view frame];
  NSRect superFrame = [superview frame];
  frame.size.width = superFrame.size.width;
  frame.size.height = superFrame.size.height;
  [view setFrame:frame];

  [self updateWindowTitle];
}

- (void) migrateDefaults:(NSUserDefaults*) defaults {
  NSDictionary *map = @{
    @"hermes.please-bind-media":        PLEASE_BIND_MEDIA,
    @"hermes.please-scrobble":          PLEASE_SCROBBLE,
    @"hermes.please-scrobble-likes":    PLEASE_SCROBBLE_LIKES,
    @"hermes.only-scrobble-likes":      ONLY_SCROBBLE_LIKED,
    @"hermes.please-growl":             PLEASE_GROWL,
    @"hermes.please-growl-new":         PLEASE_GROWL_NEW,
    @"hermes.please-growl-play":        PLEASE_GROWL_PLAY,
    @"hermes.please-close-drawer":      PLEASE_CLOSE_DRAWER,
    @"hermes.drawer-width":             DRAWER_WIDTH,
    @"hermes.audio-quality":            DESIRED_QUALITY,
    @"hermes.last-pref-pane":           LAST_PREF_PANE
  };

  NSDictionary *d = [defaults dictionaryRepresentation];

  for (NSString *key in d) {
    NSString *newKey = map[key];
    if (newKey == nil) continue;
    [defaults setObject:[defaults objectForKey:key]
                 forKey:map[key]];
    [defaults removeObjectForKey:key];
  }

  NSString *s = [defaults objectForKey:@"hermes.audio-quality"];
  if (s == nil) return;
  if ([s isEqualToString:@"high"]) {
    [defaults setInteger:QUALITY_HIGH forKey:DESIRED_QUALITY];
  } else if ([s isEqualToString:@"med"]) {
    [defaults setInteger:QUALITY_MED forKey:DESIRED_QUALITY];
  } else if ([s isEqualToString:@"low"]) {
    [defaults setInteger:QUALITY_LOW forKey:DESIRED_QUALITY];
  }
}

#pragma mark - NSApplication notifications

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
  
  // Initialize modern audio system BEFORE anything else:
  [self initializeModernAudioSystem];

  // Must do this before the app is activated, or the menu bar doesn't draw.
  // <http://stackoverflow.com/questions/7596643/>
  [self updateStatusItemVisibility:nil];
  [self refreshInputMonitoringReminder];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  // Enable window restoration
  [self.window setRestorationClass:[HermesAppDelegate class]];
  
  // Set a unique identifier for the window
  [self.window setIdentifier:@"MainWindow"];
  
  // Enable restoration for the window
  [self.window setRestorable:YES];
  
  NSUInteger flags = ([NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask);
  BOOL isOptionPressed = (flags == NSEventModifierFlagOption);
  
  if (isOptionPressed && [self configureLogFile]) {
    _debugMode = YES;
    HMSLog("Starting in debug mode. Log file: %@", self.hermesLogFile);
    [self updateWindowTitle];
  }
  
  window.restorable = YES;
  window.restorationClass = [self class];

  [NSApp activateIgnoringOtherApps:YES];

  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

  [notificationCenter addObserver:self selector:@selector(handlePandoraError:)
                             name:PandoraDidErrorNotification object:nil];

  [notificationCenter addObserver:self selector:@selector(handleStreamError:)
                             name:ASStreamError object:nil];

  [notificationCenter addObserver:self selector:@selector(handlePandoraLoggedOut:)
                             name:PandoraDidLogOutNotification object:nil];

  [notificationCenter addObserver:self selector:@selector(songPlayed:)
                             name:StationDidPlaySongNotification object:nil];

  [notificationCenter addObserver:self selector:@selector(playbackStateChanged:)
                             name:ASStatusChangedNotification object:nil];

  // See http://developer.apple.com/mac/library/qa/qa2004/qa1340.html
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
      selector: @selector(receiveSleepNote:)
      name: NSWorkspaceWillSleepNotification object: NULL];

  NSString *savedUsername = [self getSavedUsername];
  NSString *savedPassword = [self getSavedPassword];
  if (savedPassword == nil || [savedPassword isEqualToString:@""] ||
      savedUsername == nil || [savedUsername isEqualToString:@""]) {
    [auth show];
  } else {
    [self showLoader];
    [pandora authenticate:[self getSavedUsername]
                 password:[self getSavedPassword]
                  request:nil];
  }

  NSDictionary *app_defaults = @{
    PLEASE_SCROBBLE:            @"0",
    ONLY_SCROBBLE_LIKED:        @"0",
    PLEASE_GROWL:               @"1",
    PLEASE_GROWL_PLAY:          @"0",
    PLEASE_GROWL_NEW:           @"1",
    PLEASE_BIND_MEDIA:          @"1",
    INPUT_MONITORING_REMINDER_ENABLED: @"1",
    PLEASE_CLOSE_DRAWER:        @"0",
    ENABLED_PROXY:              @PROXY_SYSTEM,
    PROXY_AUDIO:                @"0",
    DESIRED_QUALITY:            @QUALITY_MED,
    OPEN_DRAWER:                @DRAWER_STATIONS,
    HIST_DRAWER_WIDTH:          @150,
    DRAWER_WIDTH:               @130,
    GROWL_TYPE:                 @GROWL_TYPE_OSX,
    kMediaKeyUsingBundleIdentifiersDefaultsKey:
        [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers]
  };

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults registerDefaults:app_defaults];
  [self migrateDefaults:defaults];
  [playback prepareFirst];

  [self addDeleteStationMenuItemIfNeeded];

  [self updateAlwaysOnTop:nil];
  [self refreshInputMonitoringReminder];
}

/**
 * Ensure the Pandora menu exposes a "Delete Station…" option alongside Add/Edit.
 * Inserted at runtime so we avoid nib edits and duplicate entries.
 */
- (void)addDeleteStationMenuItemIfNeeded {
  NSMenu *mainMenu = [NSApp mainMenu];
  if (!mainMenu) return;

  NSMenuItem *pandoraMenuItem = [mainMenu itemWithTitle:@"Pandora"];
  if (!pandoraMenuItem) return;

  NSMenu *pandoraMenu = pandoraMenuItem.submenu;
  if (!pandoraMenu) return;

  if ([pandoraMenu itemWithTitle:@"Delete Station…"] != nil) return;

  NSInteger editIndex = [pandoraMenu indexOfItemWithTarget:self.stations
                                                andAction:@selector(editSelected:)];

  NSMenuItem *deleteItem =
      [[NSMenuItem alloc] initWithTitle:@"Delete Station…"
                                 action:@selector(deleteSelected:)
                          keyEquivalent:@""];
  deleteItem.target = self.stations;

  if (editIndex != -1 && editIndex + 1 <= pandoraMenu.numberOfItems) {
    [pandoraMenu insertItem:deleteItem atIndex:editIndex + 1];
  } else {
    [pandoraMenu addItem:deleteItem];
  }
}

// Required for macOS 10.15+ (Catalina and later)
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)applicationWillResignActive:(NSNotification *)aNotification {
  [playback saveState];
  [history saveSongs];
}

// Save additional window state when needed
- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Get the window's frame
    NSRect frame = [self.window frame];
    
    // Save it to user defaults or other persistent storage if needed
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(frame)
                                            forKey:@"MainWindowFrame"];
    
    // Ensure proper cleanup
    [playback saveState];
    [playback stop];
    [history saveSongs];
}

// Optional: Handle window closing
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;  // App will quit when last window is closed
}

#pragma mark - NSWindow notification

- (void)windowDidBecomeKey:(NSNotification *)notification {

}

#pragma mark - NSWindowRestoration

// Window restoration handler
+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                            state:(NSCoder *)state
                completionHandler:(void (^)(NSWindow *, NSError *))completionHandler {
    // Check if it's our main window
    if ([identifier isEqualToString:@"MainWindow"]) {
        // Get the main window from the app delegate
        NSWindow *window = [(HermesAppDelegate *)[NSApp delegate] window];
        
        // Restore window frame if saved
        if ([state containsValueForKey:@"windowFrame"]) {
            NSRect savedFrame = [state decodeRectForKey:@"windowFrame"];
            [window setFrame:savedFrame display:NO];
        }
        
        completionHandler(window, nil);
    } else {
        // Unknown window identifier
        completionHandler(nil, nil);
    }
}

#pragma mark -

- (NSString*) getSavedUsername {
  return [[NSUserDefaults standardUserDefaults] stringForKey:USERNAME_KEY];
}

- (NSString*) getSavedPassword {
  return KeychainGetPassword([self getSavedUsername]);
}

- (void) saveUsername: (NSString*) username password: (NSString*) password {
  [[NSUserDefaults standardUserDefaults] setObject:username forKey:USERNAME_KEY];
  KeychainSetItem(username, password);
}

- (void) retry:(id)sender {
  [autoRetry invalidate];
  autoRetry = nil;
  if (lastRequest != nil) {
    [pandora sendRequest:lastRequest];
    lastRequest = nil;
    if ([playback playing] && ([[playback playing] isPlaying] ||
                               [[playback playing] isPaused])) {
      [playback show];
    } else {
      [self showLoader];
    }
  } else if (lastStationErr != nil) {
    [lastStationErr retry];
    [playback show];
    lastStationErr = nil;
  }
}

- (void) tryRetry {
  if (lastRequest != nil || lastStationErr != nil) {
    [self retry:nil];
  }
}

- (NSString*) stateDirectory:(NSString *)file {
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *folder = @"~/Library/Application Support/Hermes/";
  folder = [folder stringByExpandingTildeInPath];
  BOOL hasFolder = YES;

  if ([fileManager fileExistsAtPath: folder] == NO) {
    hasFolder = [fileManager createDirectoryAtPath:folder
                       withIntermediateDirectories:YES
                                        attributes:nil
                                             error:NULL];
  }

  if (!hasFolder) {
    return nil;
  }

  return [folder stringByAppendingPathComponent: file];
}

#pragma mark - Actions

- (IBAction) updateAlwaysOnTop:(id)sender {
  if (PREF_KEY_BOOL(ALWAYS_ON_TOP)) {
    [[self window] setLevel:NSFloatingWindowLevel];
  } else {
    [[self window] setLevel:NSNormalWindowLevel];
  }
}

- (IBAction) activate:(id)sender {
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:sender];
}

- (IBAction)showMainWindow:(id)sender {
  [self activate:nil];
}

- (IBAction)changelog:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/HermesApp/Hermes/blob/master/CHANGELOG.md"]];
}

- (IBAction) hermesOnGitHub:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/dtseto/Hermes-master"]];
}

- (IBAction) reportAnIssue:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/dtseto/Hermes-master/issues"]];
}

- (IBAction)hermesHomepage:(id)sender {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://hermesapp.org/"]];
}

#pragma mark - Drawer management

- (IBAction)toggleDrawerContent:(id)sender {
  NSLog(@"toggleDrawerContent: ignored (drawer UI deprecated on macOS 11+).");
}

- (IBAction)toggleDrawerVisible:(id)sender {
  NSLog(@"toggleDrawerVisible: ignored (drawer UI deprecated on macOS 11+).");
}

- (IBAction)showStationsDrawer:(id)sender {
  NSLog(@"showStationsDrawer: redirecting to stations list (drawer UI deprecated).");
  [self activate:nil];
  if ([stations respondsToSelector:@selector(focus)]) {
    [stations focus];
  }
}

- (IBAction)showHistoryDrawer:(id)sender {
  NSLog(@"showHistoryDrawer: redirecting to history list (drawer UI deprecated).");
  [self activate:nil];
  [[self history] updateUI];
}

/*
- (void) historyShow {
  [history showDrawer];
  [drawerToggle setImage:[NSImage imageNamed:@"radio"]];
  [drawerToggle setToolTip: @"Show station list"];
  drawerToggle.paletteLabel = drawerToggle.label = @"Stations";
}

- (void) stationsShow {
  [stations showDrawer];
  [drawerToggle setImage:[NSImage imageNamed:@"history"]];
  [drawerToggle setToolTip: @"Show song history"];
  drawerToggle.paletteLabel = drawerToggle.label = @"History";
}

- (IBAction) showHistoryDrawer:(id)sender {
  if ([PREF_KEY_VALUE(OPEN_DRAWER) intValue] == DRAWER_HISTORY) {
    [history focus];
    return;
  }
  [self historyShow];
  [stations hideDrawer];
  PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_HISTORY);
}

- (IBAction) showStationsDrawer:(id)sender {
  if ([PREF_KEY_VALUE(OPEN_DRAWER) intValue] == DRAWER_STATIONS) {
    [stations focus];
    return;
  }
  [history hideDrawer];
  [self stationsShow];
  PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_STATIONS);
}

- (void) handleDrawer {
  switch ([PREF_KEY_VALUE(OPEN_DRAWER) intValue]) {
    case DRAWER_NONE_HIST:
    case DRAWER_NONE_STA:
      break;
    case DRAWER_HISTORY:
      [self historyShow];
      break;
    case DRAWER_STATIONS:
      [self stationsShow];
      break;
  }
}

- (IBAction) toggleDrawerContent:(id)sender {
  switch ([PREF_KEY_VALUE(OPEN_DRAWER) intValue]) {
    case DRAWER_NONE_HIST:
      [self historyShow];
      PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_HISTORY);
      break;
    case DRAWER_NONE_STA:
      [self stationsShow];
      PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_STATIONS);
      break;
    case DRAWER_HISTORY:
      [self stationsShow];
      [history hideDrawer];
      PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_STATIONS);
      break;
    case DRAWER_STATIONS:
      [stations hideDrawer];
      [self historyShow];
      PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_HISTORY);
      break;
  }
}

- (IBAction) toggleDrawerVisible:(id)sender {
  switch ([PREF_KEY_VALUE(OPEN_DRAWER) intValue]) {
    case DRAWER_NONE_HIST:
      [self historyShow];
      PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_HISTORY);
      break;
    case DRAWER_NONE_STA:
      [self stationsShow];
      PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_STATIONS);
      break;
    case DRAWER_HISTORY:
      [history hideDrawer];
      break;
    case DRAWER_STATIONS:
      [stations hideDrawer];
      break;
  }
}

*/

#pragma mark - Input Monitoring Reminder

- (BOOL)shouldShowInputMonitoringReminder {
  if (@available(macOS 10.15, *)) {
    PlaybackController *playbackController = self.playback;
    if (playbackController == nil) {
      return NO;
    }
    if (playbackController.mediaKeyTap == nil) {
      return NO;
    }
    if (!PREF_KEY_BOOL(PLEASE_BIND_MEDIA)) {
      return NO;
    }
    if (!PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED)) {
      return NO;
    }
    return ![playbackController hasInputMonitoringAccess];
  }
  return NO;
}

- (void)ensureInputMonitoringMenuItem {
  if (statusBarMenu == nil || self.inputMonitoringMenuItem != nil) {
    return;
  }

  NSMenuItem *separator = [NSMenuItem separatorItem];
  self.inputMonitoringSeparator = separator;
  [statusBarMenu addItem:separator];

  NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"Enable Media Keys (Input Monitoring)…"
                                                    action:@selector(showInputMonitoringReminderFromStatusItem:)
                                             keyEquivalent:@""];
  menuItem.target = self;
  menuItem.hidden = YES;
  self.inputMonitoringMenuItem = menuItem;
  [statusBarMenu addItem:menuItem];
}

- (void)refreshInputMonitoringReminder {
  if (statusBarMenu == nil) {
    return;
  }
  [self ensureInputMonitoringMenuItem];
  BOOL shouldShow = [self shouldShowInputMonitoringReminder];
  self.inputMonitoringMenuItem.hidden = !shouldShow;
  self.inputMonitoringMenuItem.target = self;
  self.inputMonitoringMenuItem.action = @selector(showInputMonitoringReminderFromStatusItem:);
  if (self.inputMonitoringSeparator != nil) {
    self.inputMonitoringSeparator.hidden = !shouldShow;
  }
}

- (void)showInputMonitoringReminderFromStatusItem:(id)sender {
  [[self playback] presentInputMonitoringInstructionsAllowingRepeat];
}

#pragma mark - Status item display

- (IBAction) updateStatusItemVisibility:(id)sender {
  /* Transform the application appropriately */
  ProcessSerialNumber psn = { 0, kCurrentProcess };
  if (!PREF_KEY_BOOL(STATUS_BAR_ICON)) {
    window.collectionBehavior = NSWindowCollectionBehaviorDefault;
    [window setCanHide:YES];
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
    statusItem = nil;

    if (sender != nil) {
      /* If we're not executing at process launch, then the menu bar will be shown
         but be unusable until we switch to another application and back to Hermes */
      
      // Fix: Use modern NSWorkspace API instead of deprecated method
      NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
      NSURL *dockURL = [workspace URLForApplicationWithBundleIdentifier:@"com.apple.dock"];
      
      if (dockURL) {
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        [workspace openApplicationAtURL:dockURL
                          configuration:configuration
                      completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
          if (error) {
            NSLog(@"Failed to launch Dock: %@", error);
          }
        }];
      } else {
        NSLog(@"Could not find Dock application");
      }
      
      [NSApp activateIgnoringOtherApps:YES];
    }
    [self updateDockIcon:sender];
    return;
  }

  window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorTransient;

  if (sender != nil) {
    /* If we're not executing at process launch, then the menu bar will remain visible
       but unusable; hide/show Hermes to fix it, but stop the window from hiding with it */
    [window setCanHide:NO];

    /* Causes underlying window to activate briefly, but no other solution I could find */
    [NSApp hide:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
      TransformProcessType(&psn, kProcessTransformToUIElementApplication);
      dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
        [[NSApp mainWindow] makeKeyAndOrderFront:nil]; // restores mouse cursor
      });
    });
  }

  statusItem = [[NSStatusBar systemStatusBar]
                    statusItemWithLength:NSVariableStatusItemLength];
  statusItem.menu = statusBarMenu;
  [self refreshInputMonitoringReminder];
  [statusItem.button addConstraint:
   [NSLayoutConstraint constraintWithItem:statusItem.button
                                attribute:NSLayoutAttributeWidth
                                relatedBy:NSLayoutRelationLessThanOrEqual
                                   toItem:nil
                                attribute:NSLayoutAttributeNotAnAttribute
                               multiplier:0
                                 constant:STATUS_BAR_MAX_WIDTH]];

  [self updateStatusItem:sender];
}
- (NSImage *) buildPlayPauseAlbumArtImage:(NSSize)size {
    
  NSImage *icon;

  // Build base image
  NSData *data = [playback lastImg];
  icon = (data) ? [[NSImage alloc] initWithData:data] :
                  [NSImage imageNamed:@"missing-album"];
  [icon setSize:size];
  
  // draw the overlay image (if there is album art)
  if (data && PREF_KEY_BOOL(ALBUM_ART_PLAY_PAUSE)) {
    NSImage *overlay = [NSImage imageNamed:(playback.playing.isPlaying) ?
                        @"play" : @"pause"];
    
    int playPauseSize = size.width * 2 / 3;
    int playPauseOffset = (size.width - playPauseSize)/ 2;
    
    NSSize overlaySize = {.width = playPauseSize, .height = playPauseSize};
    [overlay setSize:overlaySize];
    
    [icon lockFocus];
    CGContextSetShadowWithColor([NSGraphicsContext currentContext].CGContext,
                                CGSizeMake(0, 0), 120, [NSColor whiteColor].CGColor);
    [overlay drawInRect:NSMakeRect(playPauseOffset, playPauseOffset,
                                   [overlay size].width, [overlay size].height)
               fromRect:NSZeroRect
              operation:NSCompositingOperationSourceOver
               fraction:1.0];
    [icon unlockFocus];
  }
  
  return icon;
}

- (IBAction) updateDockIcon:(id)sender {
  if (PREF_KEY_BOOL(DOCK_ICON_ALBUM_ART)) {
    NSSize size = {.width = 1024, .height = 1024};
    [NSApp setApplicationIconImage:[self buildPlayPauseAlbumArtImage:size]];
  } else {
    [NSApp setApplicationIconImage:nil];
  }
}

- (IBAction) updateStatusItem:(id)sender {
  
  if (!PREF_KEY_BOOL(STATUS_BAR_ICON)) {
    [self updateDockIcon:sender];
    return;
  }
  
  NSImage *icon;
  NSSize size = {.width = 18, .height = 18};

  if (PREF_KEY_BOOL(STATUS_BAR_ICON_BW)) {
    
    icon = [NSImage imageNamed:(playback.playing.isPlaying) ?
            @"Pandora-Menu-Dark-Play" : @"Pandora-Menu-Dark-Pause"];
    [icon setTemplate:YES];
    
  } else if (PREF_KEY_BOOL(STATUS_BAR_ICON_ALBUM)) {
    
    icon = [self buildPlayPauseAlbumArtImage:size];
    
  } else {
    // Use color application image
    icon = [NSImage imageNamed:@"pandora"];
  }

  // Set image size, then set status bar icon
  [icon setSize:size];
  NSStatusBarButton *button = statusItem.button;
  button.image = icon;
  
  // Optionally show song title in status bar
  NSString *title = nil;
  if (PREF_KEY_BOOL(STATUS_BAR_SHOW_SONG))
    title = playback.playing.playingSong.title;

  if (title) {
    button.imagePosition = NSImageLeft;
    button.lineBreakMode = NSLineBreakByTruncatingTail;
    button.title = title;
    
    if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_11) {
      // baseline is now correct with NSStatusItem changes in 10.12

      NSMutableAttributedString *attributedTitle = [button.attributedTitle mutableCopy];
      NSRange titleRange = NSMakeRange(0, attributedTitle.length);
      
      [attributedTitle addAttributes:@{NSBaselineOffsetAttributeName: @1} range:titleRange];
      button.attributedTitle = attributedTitle;
    }
    
    statusItem.length = NSVariableStatusItemLength;
  } else {
    button.title = @"";
    button.imagePosition = NSImageOnly;
    statusItem.length = NSSquareStatusItemLength;
  }
}

#pragma mark - Internal notifications

- (void) songPlayed:(NSNotification*) not {
  Station *s = [not object];
  Song *playing = [s playingSong];
  if (playing != nil) {
    nowPlaying.title = [@"Now Playing: " stringByAppendingString:s.name];
    currentSong.title = playing.title;
    currentArtist.title = playing.artist;
    currentArtist.hidden = NO;
    statusItem.button.toolTip = [NSString stringWithFormat:@"Song: %@\nArtist: %@\nAlbum: %@\nStation: %@", playing.title, playing.artist, playing.album, s.name];
  } else {
    nowPlaying.title = @"Now Playing";
    currentSong.title = @"(none)";
    currentArtist.hidden = YES;
    statusItem.button.toolTip = nil;
  }
}

- (void)playbackStateChanged:(NSNotification*) not {
  AudioStreamer *stream = [not object];
  BOOL streamIsPlaying = [stream isPlaying];
  if (streamIsPlaying) {
    [playbackState setTitle:@"Pause"];
  } else {
    [playbackState setTitle:@"Play"];
  }
  [self updateWindowTitle];
  [self updateStatusItem:nil];

  if ([MPNowPlayingInfoCenter class]) {
    MPNowPlayingInfoCenter *nowPlayingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
    if (streamIsPlaying) {
      Station *playing = [playback playing];
      Song *song = [playing playingSong];
      double progress = 0, duration = 0;
      [playing progress:&progress];
      [playing duration:&duration];
      nowPlayingInfoCenter.playbackState = MPNowPlayingPlaybackStatePlaying;
      nowPlayingInfoCenter.nowPlayingInfo = @{
        MPNowPlayingInfoPropertyMediaType: @(MPNowPlayingInfoMediaTypeAudio),
        MPMediaItemPropertyArtist: song.artist,
        MPMediaItemPropertyAlbumTitle: song.album,
        MPMediaItemPropertyTitle: song.title,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @(progress),
        MPNowPlayingInfoPropertyPlaybackRate: @(1.),
        @"playbackDuration": @(duration) // XXX MPMediaItemPropertyPlaybackDuration not exposed in 10.12 SDK
      };
    } else if ([stream isPaused])
      nowPlayingInfoCenter.playbackState = MPNowPlayingPlaybackStatePaused;
    else if ([stream isDone])
      nowPlayingInfoCenter.playbackState = MPNowPlayingPlaybackStateStopped;
    else
      nowPlayingInfoCenter.playbackState = MPNowPlayingPlaybackStateUnknown;
  }
}

- (void) receiveSleepNote: (NSNotification*) note {
  [[playback playing] pause];
}

- (void) handleStreamError: (NSNotification*) notification {
  lastStationErr = [notification object];
  [self setCurrentView:errorView];
  NSString *err = [lastStationErr streamNetworkError];
  [errorLabel setStringValue:err];
  [window orderFront:nil];
}

- (void) handlePandoraError: (NSNotification*) notification {
  
  // Log thread information
  NSLog(@"[DEBUG] handlePandoraError called on thread: %@, isMainThread: %d",
         [NSThread currentThread], [NSThread isMainThread]);
  

  // Ensure we're on the main thread for UI operations
  if (![NSThread isMainThread]) {
    NSLog(@"[DEBUG] Dispatching handlePandoraError to main thread");
    dispatch_async(dispatch_get_main_queue(), ^{
      [self handlePandoraError:notification];
    });
    return;
  }

  
  NSDictionary *info = [notification userInfo];
  NSString *err      = info[@"error"];
  NSNumber *nscode   = info[@"code"];
  NSLogd(@"error received %@", info);
  NSLog(@"[DEBUG] Pandora error code: %@, error message: %@", nscode, err);
  /* If this is a generic error (like a network error) it's possible to retry.
   Otherewise if it's a Pandora error (with a code listed) there's likely
   nothing we can do about it */
  [errorButton setHidden:FALSE];
  lastRequest = nil;
  int code = [nscode intValue];
  NSString *other = [Pandora stringForErrorCode:code];
  if (other != nil) {
    NSLog(@"[DEBUG] Using mapped error string: %@ for code: %d", other, code);
    err = other;
  }

  if (nscode != nil) {
    NSLog(@"[DEBUG] Handling specific error code: %d", code);
    [errorButton setHidden:TRUE];

    switch (code) {
      case INVALID_SYNC_TIME:
      case INVALID_AUTH_TOKEN: {
        NSLog(@"[DEBUG] Auth token or sync time invalid, attempting reauth");
        NSString *user = [self getSavedUsername];
        NSString *pass = [self getSavedPassword];
        if (user == nil || pass == nil) {
          NSLog(@"[DEBUG] No saved credentials, showing auth failure");
          [[playback playing] pause];
          [auth authenticationFailed:notification error:err];
        } else {
          // Create a local copy of the request
          PandoraRequest *originalRequest = [info[@"request"] copy];
          NSLog(@"[DEBUG] Have credentials, reauthing with request: %@", originalRequest);
          
          // Do logout and re-auth with proper sequencing
          dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[DEBUG] Performing logout and reauth");
            [self->pandora logoutNoNotify];
            [self->pandora authenticate:user
                              password:pass
                               request:originalRequest];
          });
        }
        return;
      }


        /* Oddly enough, the same error code is given our for invalid login
         information as is for invalid partner login information... */
      case INVALID_PARTNER_LOGIN:
      case INVALID_USERNAME:
      case INVALID_PASSWORD:
        NSLog(@"[DEBUG] Invalid credentials, showing auth failure");

        [[playback playing] pause];
        [auth authenticationFailed:notification error:err];
        return;

      case NO_SEEDS_LEFT:
        NSLog(@"[DEBUG] No seeds left error, handling in station controller");

        [station seedFailedDeletion:notification];
        return;

      default:
        NSLog(@"[DEBUG] Unhandled specific error code: %d", code);
        break;
    }
  }
  NSLog(@"[DEBUG] General error handling, showing error view");
  lastRequest = [notification userInfo][@"request"];
  [self setCurrentView:errorView];
  [errorLabel setStringValue:err];
  [window orderFront:nil];
  [autoRetry invalidate];

  // From the unofficial Pandora API documentation ( http://6xq.net/playground/pandora-apidoc/json/errorcodes/ ):
  // code 0 == INTERNAL, "It can denote that your account has been temporarily blocked due to having too frequent station.getPlaylist calls."
  // code 1039 == PLAYLIST_EXCEEDED, "Returned on excessive calls to station.getPlaylist. Error self clears (probably 1 hour)."
  if (code != 0 && code != 1039) {
    NSLog(@"[DEBUG] Setting up auto-retry for error code: %d", code);
    autoRetry = [NSTimer scheduledTimerWithTimeInterval:20
                                                 target:self
                                               selector:@selector(retry:)
                                               userInfo:nil
                                                repeats:NO];
  }
}

- (void) handlePandoraLoggedOut: (NSNotification*) notification {
  [stations reset];
  [playback reset];
 // [stations hideDrawer];
 // [history hideDrawer];
  [station editStation:nil];

  /* Remove our credentials */
  [self saveUsername:@"" password:@""];
  [auth show];
}

#pragma mark - User interface validation

/*
- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
  if (![[self pandora] isAuthenticated]) {
    return NO;
  }
  return YES;
}

 */

/*
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
  SEL action = [menuItem action];

  if (action == @selector(showHistoryDrawer:) || action == @selector(showStationsDrawer:) || action == @selector(toggleDrawerVisible:)) {
    if (!self.pandora.isAuthenticated)
      return NO;

    NSInteger openDrawer = [PREF_KEY_VALUE(OPEN_DRAWER) integerValue];
    NSCellStateValue state = NSOffState;
    if (action == @selector(showHistoryDrawer:)) {
      if (openDrawer == DRAWER_NONE_HIST)
        state = NSMixedState;
      else if (openDrawer == DRAWER_HISTORY)
        state = NSOnState;
    } else if (action == @selector(showStationsDrawer:)) {
      if (openDrawer == DRAWER_NONE_STA)
        state = NSMixedState;
      else if (openDrawer == DRAWER_STATIONS)
        state = NSOnState;
    } else {
      if (openDrawer == DRAWER_HISTORY || openDrawer == DRAWER_STATIONS)
        [menuItem setTitle:@"Hide Drawer"];
      else
        [menuItem setTitle:@"Show Drawer"];
    }
    [menuItem setState:state];
  }

  return YES;
}

 */

- (void)updateWindowTitle {
  NSString *debugTitlePrefix = self.debugMode ? DEBUG_MODE_TITLE_PREFIX : @"";
  if (playback.playing != nil) {
    [window setTitle:[NSString stringWithFormat:@"%@%@", debugTitlePrefix, playback.playing.name]];
  } else {
    [window setTitle:[NSString stringWithFormat:@"%@Hermes", debugTitlePrefix]];
  }
}

#pragma mark - Logging facility

- (BOOL)configureLogFile {
  NSString *hermesStandardizedLogPath = [HERMES_LOG_DIRECTORY_PATH stringByStandardizingPath];
  NSError *error = nil;
  BOOL logPathCreated = [[NSFileManager defaultManager] createDirectoryAtPath:hermesStandardizedLogPath
                                                  withIntermediateDirectories:YES
                                                                   attributes:nil
                                                                        error:&error];
  if (!logPathCreated) {
    NSLog(@"Hermes: failed to create logging directory \"%@\". Logging is disabled.", hermesStandardizedLogPath);
    return NO;
  }
  
#define CURRENTTIMEBYTES 50
  // Use unlocalized, fixed-format date functions as prescribed in
  // "Data Formatting Guide" section "Consider Unix Functions for Fixed-Format, Unlocalized Dates"
  // https://developer.apple.com/library/ios/documentation/cocoa/Conceptual/DataFormatting/Articles/dfDateFormatting10_4.html
  time_t now;
  struct tm *localNow;
  char currentDateTime[CURRENTTIMEBYTES];
  
  time(&now);
  localNow = localtime(&now);
  strftime_l(currentDateTime, CURRENTTIMEBYTES, "%Y-%m-%d_%H:%M:%S_%z", localNow, NULL);
  
  _hermesLogFile = [[NSString stringWithFormat:@"%@/HermesLog_%s.log", HERMES_LOG_DIRECTORY_PATH, currentDateTime] stringByStandardizingPath];
  static dispatch_once_t onceTokenForOpeningLogFile = 0;
  dispatch_once(&onceTokenForOpeningLogFile, ^{
    self->_hermesLogFileHandle = fopen([self.hermesLogFile cStringUsingEncoding:NSUTF8StringEncoding], "a");
    setvbuf(self.hermesLogFileHandle, NULL, _IOLBF, 0);
  });
  return YES;
}

- (void)logMessage:(NSString *)message {
#if DEBUG
    // Keep old behavior of DEBUG mode.
    NSLog(@"%@", message);
#endif
    
    if (self.debugMode) {
      if (self.hermesLogFileHandle) {
        fprintf(self.hermesLogFileHandle, "%s\n", [message cStringUsingEncoding:NSUTF8StringEncoding]);
      } else {
#ifndef DEBUG
        // Fall back on NSLog if the log file did not open properly.
        NSLog(@"%@", message);
#endif
      }
    }
}

#pragma mark - QLPreviewPanelController

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel {
  return YES;
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
  panel.dataSource = playback;
  panel.delegate = playback;
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
  panel.dataSource = nil;
  panel.delegate = nil;
}

@end
