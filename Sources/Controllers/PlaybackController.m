/**
 * @file PlaybackController.m
 * @brief Implementation of the playback interface for playing/pausing
 *        songs
 *
 * Handles all information regarding playing a station, setting ratings for
 * songs, and listening for notifications. Deals with all user input related
 * to these actions as well
 */

#import <SPMediaKeyTap/SPMediaKeyTap.h>
#import <MediaPlayer/MediaPlayer.h>
#import <ApplicationServices/ApplicationServices.h>
//#import "Integration/Growler.h"
#import "HistoryController.h"
#import "ImageLoader.h"
#import "PlaybackController.h"
#import "StationsController.h"
#import "PreferencesController.h"
#import "Notifications.h"

BOOL playOnStart = YES;

static HMSInputMonitoringAccessFunction HermesPreflightListenEventAccess = NULL;
static HMSInputMonitoringAccessFunction HermesRequestListenEventAccess = NULL;

void HMSSetListenEventAccessFunctionPointers(HMSInputMonitoringAccessFunction preflight,
                                             HMSInputMonitoringAccessFunction request) {
  HermesPreflightListenEventAccess = preflight;
  HermesRequestListenEventAccess = request;
}

@interface NSToolbarItem ()
- (void)_setAllPossibleLabelsToFit:(NSArray *)toolbarItemLabels;
@end

@interface PlaybackController ()
@end

@implementation PlaybackController

@synthesize playing;
@synthesize lastImg;
@synthesize remoteCommandCenter, mediaKeyTap;

+ (void) setPlayOnStart: (BOOL)play {
  playOnStart = play;
}

+ (BOOL) playOnStart {
  return playOnStart;
}

- (BOOL)hasInputMonitoringAccess {
  if (@available(macOS 10.15, *)) {
    if (HermesPreflightListenEventAccess == NULL) {
      HermesPreflightListenEventAccess = CGPreflightListenEventAccess;
    }
    if (HermesPreflightListenEventAccess != NULL) {
      return HermesPreflightListenEventAccess();
    }
  }
  return YES;
}

- (BOOL)requestInputMonitoringAccessIfNeeded {
  if (@available(macOS 10.15, *)) {
    if (HermesPreflightListenEventAccess == NULL) {
      HermesPreflightListenEventAccess = CGPreflightListenEventAccess;
    }
    if (HermesRequestListenEventAccess == NULL) {
      HermesRequestListenEventAccess = CGRequestListenEventAccess;
    }
    if (HermesPreflightListenEventAccess && HermesPreflightListenEventAccess()) {
      [self notifyInputMonitoringReminderUpdate];
      return YES;
    }
    BOOL granted = HermesRequestListenEventAccess ? HermesRequestListenEventAccess() : YES;
    if (!granted) {
      [self presentInputMonitoringInstructions];
    } else {
      presentedInputMonitoringAlert = NO;
    }
    BOOL hasAccess = HermesPreflightListenEventAccess ? HermesPreflightListenEventAccess() : granted;
    [self notifyInputMonitoringReminderUpdate];
    return hasAccess;
  }
  return YES;
}

- (void)presentInputMonitoringInstructions {
  if (!PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED)) {
    presentedInputMonitoringAlert = NO;
    return;
  }
  if (presentedInputMonitoringAlert) {
    return;
  }
  presentedInputMonitoringAlert = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_block_t presentBlock = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf presentInputMonitoringInstructionsAlert];
  };
  if ([NSThread isMainThread]) {
    presentBlock();
  } else {
    dispatch_async(dispatch_get_main_queue(), presentBlock);
  }
}

- (void)presentInputMonitoringInstructionsAllowingRepeat {
  __weak typeof(self) weakSelf = self;
  dispatch_block_t presentBlock = ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf presentInputMonitoringInstructionsAlert];
  };
  if ([NSThread isMainThread]) {
    presentBlock();
  } else {
    dispatch_async(dispatch_get_main_queue(), presentBlock);
  }
}

- (void)openInputMonitoringPreferences {
  NSURL *settingsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"];
  if (settingsURL != nil) {
    [[NSWorkspace sharedWorkspace] openURL:settingsURL];
  } else {
    NSLog(@"Hermes: Unable to construct Input Monitoring settings URL.");
  }
}

- (BOOL)shouldSurfaceInputMonitoringReminder {
  if (@available(macOS 10.15, *)) {
    if (self.mediaKeyTap != nil && PREF_KEY_BOOL(PLEASE_BIND_MEDIA) && PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED)) {
      return ![self hasInputMonitoringAccess];
    }
  }
  return NO;
}

- (void)notifyInputMonitoringReminderUpdate {
  dispatch_async(dispatch_get_main_queue(), ^{
    [HMSAppDelegate refreshInputMonitoringReminder];
  });
}

- (void)requestInputMonitoringReminderIfNeeded {
  if ([self shouldSurfaceInputMonitoringReminder]) {
    [self presentInputMonitoringInstructions];
  }
  [self notifyInputMonitoringReminderUpdate];
}

- (void)presentInputMonitoringInstructionsAlert {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Enable Media Keys";
  alert.informativeText = @"Hermes needs permission in System Settings → Privacy & Security → Input Monitoring to react to media keys. Enable Hermes in Input Monitoring so Play/Pause continues working.";
  [alert addButtonWithTitle:@"Open System Settings"];
  [alert addButtonWithTitle:@"Not Now"];
  [alert addButtonWithTitle:@"Don't Remind Me Again"];
  NSModalResponse response = [alert runModal];
  if (response == NSAlertFirstButtonReturn) {
    [self openInputMonitoringPreferences];
  } else if (response == NSAlertThirdButtonReturn) {
    PREF_KEY_SET_BOOL(INPUT_MONITORING_REMINDER_ENABLED, NO);
    presentedInputMonitoringAlert = NO;
  }
  [self notifyInputMonitoringReminderUpdate];
}

- (void)handleSongExplanation:(NSNotification *)notification {
    NSLog(@"🎵 EXPLANATION RECEIVED: %@", notification.userInfo);
    
    Song *song = (Song *)notification.object;
    NSString *explanation = notification.userInfo[@"explanation"];
    
    if (song && explanation) {
        // Update the existing explanation label
        [explanationLabel setStringValue:explanation];
        [explanationLabel setToolTip:explanation]; // Optional: also set as tooltip
        
        NSLog(@"🎵 Updated explanationLabel with: %@", explanation);
    } else {
        NSLog(@"❌ Missing song or explanation data");
        // Clear the label if no explanation
        [explanationLabel setStringValue:@""];
    }
}

- (void) awakeFromNib {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  NSWindow *window = [HMSAppDelegate window];
  [center addObserver:self
             selector:@selector(stopUpdatingProgress)
                 name:NSWindowWillCloseNotification
               object:window];
  [center addObserver:self
             selector:@selector(stopUpdatingProgress)
                 name:NSApplicationDidHideNotification
               object:NSApp];
  [center addObserver:self
             selector:@selector(startUpdatingProgress)
                 name:NSWindowDidBecomeMainNotification
               object:window];
  [center addObserver:self
             selector:@selector(startUpdatingProgress)
                 name:NSApplicationDidUnhideNotification
               object:NSApp];

  [center
    addObserver:self
    selector:@selector(showToolbar)
    name:PandoraDidAuthenticateNotification
    object:nil];

  [center
    addObserver:self
    selector:@selector(hideSpinner)
    name:PandoraDidRateSongNotification
    object:nil];

  [center
    addObserver:self
    selector:@selector(hideSpinner)
    name:PandoraDidDeleteFeedbackNotification
    object:nil];

  [center
    addObserver:self
    selector:@selector(hideSpinner)
    name:PandoraDidTireSongNotification
    object:nil];

  [center
    addObserver:self
    selector:@selector(handleSongExplanation:)
    name:PandoraDidExplainSongNotification
    object:nil];

 // [center
 //   addObserver:self
 //   selector:@selector(playbackStateChanged:)
 //   name:ASStatusChangedNotification
 //   object:nil];

  [center
     addObserver:self
     selector:@selector(songPlayed:)
     name:StationDidPlaySongNotification
     object:nil];
  [center
     addObserver:self
     selector:@selector(handleStationModesLoaded:)
     name:PandoraDidLoadStationModesNotification
     object:nil];

  // NSDistributedNotificationCenter is for interprocess communication.
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                      selector:@selector(pauseOnScreensaverStart:)
                                                          name:AppleScreensaverDidStartDistributedNotification
                                                        object:nil];
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                      selector:@selector(playOnScreensaverStop:)
                                                          name:AppleScreensaverDidStopDistributedNotification
                                                        object:nil];
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                      selector:@selector(pauseOnScreenLock:)
                                                          name:AppleScreenIsLockedDistributedNotification
                                                        object:nil];
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                      selector:@selector(playOnScreenUnlock:)
                                                          name:AppleScreenIsUnlockedDistributedNotification
                                                        object:nil];

  // This has been SPI forever, but will stop the toolbar icons from sliding around.
  if ([playpause respondsToSelector:@selector(_setAllPossibleLabelsToFit:)])
    [playpause _setAllPossibleLabelsToFit:@[@"Play", @"Pause"]];
  
  // prevent dragging the progress slider
  [playbackProgress setEnabled:NO];
  [self configureStationModesUI];

  // Media keys
  if ([MPRemoteCommandCenter class] != nil) {
    remoteCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    // remoteCommandCenter.previousTrackCommand.enabled = NO;
    [remoteCommandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
      return [self play] ? MPRemoteCommandHandlerStatusSuccess : MPRemoteCommandHandlerStatusCommandFailed;
    }];
    [remoteCommandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
      return [self pause] ? MPRemoteCommandHandlerStatusSuccess : MPRemoteCommandHandlerStatusCommandFailed;
    }];
    // XXX Doesn't show up in the Touch Bar as of 10.12.2 unless there is a previousTrackCommand registered
    [remoteCommandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
      [self next:self];
      return MPRemoteCommandHandlerStatusSuccess;
    }];
#ifndef MPREMOTECOMMANDCENTER_MEDIA_KEYS_BROKEN
    // XXX This gets triggered seemingly at random.
    [remoteCommandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
      [self playpause:self];
      return MPRemoteCommandHandlerStatusSuccess;
    }];
#endif
    [remoteCommandCenter.likeCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
      [self like:self];
      return MPRemoteCommandHandlerStatusSuccess;
    }];
    [remoteCommandCenter.dislikeCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
      [self dislike:self];
      return MPRemoteCommandHandlerStatusSuccess;
    }];
  }
#ifndef DEBUG
#ifndef MPREMOTECOMMANDCENTER_MEDIA_KEYS_BROKEN
  else {
#endif
   mediaKeyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
    if (PREF_KEY_BOOL(PLEASE_BIND_MEDIA)) {
      BOOL canTapMediaKeys = [self requestInputMonitoringAccessIfNeeded];
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 1090
      BOOL hasAccessibilityTrust = YES;
      if (@available(macOS 10.15, *)) {
        hasAccessibilityTrust = YES;
      } else if (@available(macOS 10.9, *)) {
        if (!AXIsProcessTrusted()) {
          NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
          AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
          hasAccessibilityTrust = AXIsProcessTrusted();
        }
      }
      canTapMediaKeys = canTapMediaKeys && hasAccessibilityTrust;
#endif
      if (canTapMediaKeys) {
        [mediaKeyTap startWatchingMediaKeys];
      } else {
        NSLog(@"Hermes: Input Monitoring permission missing; media keys disabled until granted.");
        if ([self hasInputMonitoringAccess] == NO) {
          [self presentInputMonitoringInstructions];
        }
      }
    }
#ifndef MPREMOTECOMMANDCENTER_MEDIA_KEYS_BROKEN
  }
#endif
#endif

  dispatch_async(dispatch_get_main_queue(), ^{
    [self requestInputMonitoringReminderIfNeeded];
  });
}

- (void)showToolbar {
  toolbar.visible = YES;
}

/* Don't run the timer when playback is paused, the window is hidden, etc. */
- (void) stopUpdatingProgress {
  [progressUpdateTimer invalidate];
  progressUpdateTimer = nil;
}

- (void) startUpdatingProgress {
  if (progressUpdateTimer != nil) return;
  __weak typeof(self) weakSelf = self;
  NSTimer *timer = [NSTimer
    timerWithTimeInterval:1
                 repeats:YES
                   block:^(NSTimer * _Nonnull t) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      [strongSelf updateProgress:t];
    }];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
  progressUpdateTimer = timer;
}

/* see https://github.com/nevyn/SPMediaKeyTap */
- (void) mediaKeyTap:(SPMediaKeyTap*)keyTap
      receivedMediaKeyEvent:(NSEvent*)event {
  assert([event type] == NSEventTypeSystemDefined &&
         [event subtype] == SPSystemDefinedEventMediaKeys);

  int keyCode = (([event data1] & 0xFFFF0000) >> 16);
  int keyFlags = ([event data1] & 0x0000FFFF);
  int keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA;
  if (keyState != 1) return;

  switch (keyCode) {

    case NX_KEYTYPE_PLAY:
      [self playpause:nil];
      return;

    case NX_KEYTYPE_FAST:
    case NX_KEYTYPE_NEXT:
      [self next:nil];
      return;

    case NX_KEYTYPE_REWIND:
    case NX_KEYTYPE_PREVIOUS:
      [NSApp activateIgnoringOtherApps:NO];
      return;
  }
}

- (void) prepareFirst {
  NSInteger saved = [[NSUserDefaults standardUserDefaults]
                     integerForKey:@"hermes.volume"];
  if (saved == 0) {
    saved = 100;
  }
  [self setIntegerVolume:saved];
}

- (Pandora*) pandora {
  return [HMSAppDelegate pandora];
}

- (void) reset {
  [self playStation:nil];

  NSString *path = [HMSAppDelegate stateDirectory:@"station.savestate"];
  [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void) show {
  [HMSAppDelegate setCurrentView:playbackView];
}

- (void) showSpinner {
  [songLoadingProgress setHidden:NO];
  [songLoadingProgress startAnimation:nil];
}

- (void)dealloc {
  [progressUpdateTimer invalidate];
  progressUpdateTimer = nil;
}

- (void) hideSpinner {
  [songLoadingProgress setHidden:YES];
  [songLoadingProgress stopAnimation:nil];
}

- (BOOL) saveState {
  NSString *path = [HMSAppDelegate stateDirectory:@"station.savestate"];
  if (path == nil) {
    return NO;
  }

  // Fix: Use modern archiving method
  NSError *archiveError = nil;
  NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:[self playing]
                                              requiringSecureCoding:YES
                                                              error:&archiveError];
  
  if (archiveError || archivedData == nil) {
    NSLog(@"Error archiving playing station: %@", archiveError);
    return NO;
  }
  
  // Write the archived data to file
  NSError *writeError = nil;
  NSURL *fileURL = [NSURL fileURLWithPath:path];
  BOOL success = [archivedData writeToURL:fileURL
                                  options:NSDataWritingAtomic
                                    error:&writeError];
  
  if (!success) {
    NSLog(@"Error writing playing station to file: %@", writeError);
    return NO;
  }
  
  return YES;
}
/* Re-draws the timer counting up the time of the played song */
- (void)updateProgress: (NSTimer *)updatedTimer {
  double prog, dur;

  if (![playing progress:&prog] || ![playing duration:&dur]) {
    [progressLabel setStringValue:@"-:--/-:--"];
    [playbackProgress setDoubleValue:0];
    return;
  }

  [progressLabel setStringValue:
    [NSString stringWithFormat:@"%d:%02d/%d:%02d",
    (int) (prog / 60), ((int) prog) % 60, (int) (dur / 60), ((int) dur) % 60]];
  [playbackProgress setDoubleValue:100 * prog / dur];

  /* See http://www.last.fm/api/scrobbling#when-is-a-scrobble-a-scrobble for
     figuring out when a track should be scrobbled */
  if (!scrobbleSent && dur > 30 && (prog * 2 > dur || prog > 4 * 60)) {
    scrobbleSent = YES;
    [SCROBBLER scrobble:[playing playingSong] state:FinalStatus];
  }
}

// nil = no image available
- (void)setArtImage:(NSImage *)artImage {
  self->_artImage = artImage;
  [art setImage:artImage ? artImage : [NSImage imageNamed:@"missing-album"]];
  if (artImage != nil) {
    artImage.accessibilityDescription = [[playing playingSong] title];
    art.toolTip = [[playing playingSong] title];
    if (@available(macOS 11.0, *)) {
      art.accessibilityLabel = [[playing playingSong] title];
    }
  } else {
    art.toolTip = nil;
    if (@available(macOS 11.0, *)) {
      art.accessibilityLabel = nil;
    }
  }
  [artLoading setHidden:YES];
  [artLoading stopAnimation:nil];
  [self updateQuickLookPreviewWithArt:artImage != nil];
}

- (void)updateQuickLookPreviewWithArt:(BOOL)hasArt {
  [art setEnabled:hasArt];

  if (![QLPreviewPanel sharedPreviewPanelExists])
    return;

  QLPreviewPanel *previewPanel = [QLPreviewPanel sharedPreviewPanel];
  if (previewPanel.currentController != HMSAppDelegate)
    return;

  if (hasArt)
    [previewPanel refreshCurrentPreviewItem];
  else
    [previewPanel reloadData];
}

/*
 * Called whenever a song starts playing, updates all fields to reflect that the
 * song is playing
 */
- (void)songPlayed: (NSNotification *)aNotification {
  Song *song = [playing playingSong];
  assert(song != nil);

  song.playDate = [NSDate date];

  /* Prevent a flicker by not loading the same image twice */
  if ([song art] != lastImgSrc) {
    if ([song art] == nil || [[song art] isEqual: @""]) {
      [self setArtImage:nil];
      if (![self->playing isPaused])
        //[GROWLER growl:song withImage:nil isNew:YES];
        ;
    } else {
      [artLoading startAnimation:nil];
      [artLoading setHidden:NO];
      [art setImage:nil];
      lastImgSrc = [song art];
      lastImg = nil;
      [[ImageLoader loader] loadImageURL:lastImgSrc
                                callback:^(NSData *data) {
        NSImage *image = nil;
        self->lastImg = data;
        if (data != nil) {
          image = [[NSImage alloc] initWithData:data];
        }

        [HMSAppDelegate updateStatusItem:nil];

        if (![self->playing isPaused]) {
          //[GROWLER growl:song withImage:data isNew:YES];
        }
        [self setArtImage:image];
      }];
    }
  } else {
    NSLogd(@"Skipping loading image");
  }

  [HMSAppDelegate setCurrentView:playbackView];

  [songLabel setStringValue: [song title]];
  [songLabel setToolTip:[song title]];
  [artistLabel setStringValue: [song artist]];
  [artistLabel setToolTip:[song artist]];
  [albumLabel setStringValue:[song album]];
  [albumLabel setToolTip:[song album]];
  [playbackProgress setDoubleValue: 0];
  if ([NSFont respondsToSelector:@selector(monospacedDigitSystemFontOfSize:weight:)]) {
    [progressLabel setFont:[NSFont monospacedDigitSystemFontOfSize:[[progressLabel font] pointSize] weight:NSFontWeightRegular]];
  }
  [progressLabel setStringValue: @"0:00/0:00"];
  scrobbleSent = NO;

  if ([[song nrating] intValue] == 1) {
    [toolbar setSelectedItemIdentifier:[like itemIdentifier]];
    if (remoteCommandCenter != nil)
      remoteCommandCenter.likeCommand.active = true;
  } else {
    [toolbar setSelectedItemIdentifier:nil];
    if (remoteCommandCenter != nil)
      remoteCommandCenter.likeCommand.active = false;
  }

  [[HMSAppDelegate history] addSong:song];
  [self hideSpinner];
  // ADD THIS: Automatically request explanation for the new song
  NSLog(@"🎵 Auto-requesting explanation for: %@", [song title]);
  [[self pandora] explainSong:song];

}

/* Plays a new station, or nil to play no station (e.g., if station deleted) */
- (void) playStation: (Station*) station {
  NSLog(@"🎵 playStation called for: %@ (from: %@)", [station name], [NSThread callStackSymbols]);

  if ([playing stationId] == [station stationId]) {
    return;
  }

  if (playing) {
    [playing stop];
    [[ImageLoader loader] cancel:[[playing playingSong] art]];
  }

  playing = station;
  [self refreshStationModesForStation:station];

  if (station == nil) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:LAST_STATION_KEY];
    lastImgSrc = nil;
    return;
  }

  [[NSUserDefaults standardUserDefaults] setObject:[station stationId]
                                            forKey:LAST_STATION_KEY];
  
  [HMSAppDelegate showLoader];

  if (playOnStart) {
    [station play];
  } else {
    playOnStart = YES;
  }
  [playing setVolume:[volume intValue]/100.0];
}

- (BOOL) play {
  if ([playing isPlaying]) {
    return NO;
  } else {
    [playing play];
    //[GROWLER growl:[playing playingSong] withImage:lastImg isNew:NO];
    return YES;
  }
}

- (BOOL) pause {
  if ([playing isPlaying]) {
    [playing pause];
    return YES;
  } else {
    return NO;
  }
}

- (void) stop {
  [playing stop];
}

- (void) rate:(Song *)song as:(BOOL)liked {
  if (!song || [[song station] shared]) return;
  int rating = liked ? 1 : -1;

  // Should we delete the rating?
  if ([[song nrating] intValue] == rating) {
    rating = 0;
  }

  [self showSpinner];
  BOOL songIsPlaying = [playing playingSong] == song;

  if (rating == -1) {
    [[self pandora] rateSong:song as:NO];
    if (songIsPlaying) {
      [self next:nil];
    }
  }
  else if (rating == 0) {
    [[self pandora] deleteRating:song];
    if (songIsPlaying) {
      [toolbar setSelectedItemIdentifier:nil];
    }
  }
  else if (rating == 1) {
    [[self pandora] rateSong:song as:YES];
    if (songIsPlaying) {
      [toolbar setSelectedItemIdentifier:[like itemIdentifier]];
    }
  }

  if ([[HMSAppDelegate history] selectedItem] == song) {
    [[HMSAppDelegate history] updateUI];
  }
}

/* Toggle between playing and pausing */
- (IBAction)playpause: (id) sender {
  if ([playing isPaused]) {
    [self play];
  } else {
    [self pause];
  }
}

/* Stop this song and go to the next */
- (IBAction)next: (id) sender {
  [art setImage:nil];
  [self showSpinner];
  if ([playing playingSong] != nil) {
    [[ImageLoader loader] cancel:[[playing playingSong] art]];
  }

  [playing next];
}

/* Like button was hit */
- (IBAction)like: (id) sender {
  Song *song = [playing playingSong];
  if (!song) return;
  [self rate:song as:YES];
}

/* Dislike button was hit */
- (IBAction)dislike: (id) sender {
  Song *song = [playing playingSong];
  if (!song) return;

  /* Remaining songs in the queue are probably related to this one. If we
     dislike this one, remove all related songs to grab another set */
  [playing clearSongList];
  [self rate:song as:NO];
}

/* We are tired of the currently playing song, play another */
- (IBAction)tired: (id) sender {
  if (playing == nil || [playing playingSong] == nil) {
    return;
  }

  [[self pandora] tiredOfSong:[playing playingSong]];
  [self next:sender];
}

/* Load more songs manually */
- (IBAction)loadMore: (id)sender {
  [self showSpinner];
  [HMSAppDelegate setCurrentView:playbackView];

  if ([playing playingSong] != nil) {
    [playing retry];
  } else {
    [playing play];
  }
}

/* Go to the song URL */
- (IBAction)songURL: (id) sender {
  if ([playing playingSong] == nil) {
    return;
  }

  NSURL *url = [NSURL URLWithString:[[playing playingSong] titleUrl]];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

/* Go to the artist URL */
- (IBAction)artistURL: (id) sender {
  if ([playing playingSong] == nil) {
    return;
  }

  NSURL *url = [NSURL URLWithString:[[playing playingSong] artistUrl]];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

/* Go to the album URL */
- (IBAction)albumURL: (id) sender {
  if ([playing playingSong] == nil) {
    return;
  }

  NSURL *url = [NSURL URLWithString:[[playing playingSong] albumUrl]];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Station Modes

- (void)configureStationModesUI {
  if (!stationModeLabel || !stationModesMenu || !stationModesMenuItem) {
    return;
  }
  stationModeLabel.hidden = YES;
  stationModeLabel.stringValue = @"Station Mode";
  stationModeLabel.textColor = [NSColor secondaryLabelColor];
  [stationModesMenu setAutoenablesItems:NO];
  [self clearStationModeMenu];
}

- (void)refreshStationModesForStation:(Station *)station {
  if (!stationModeLabel) {
    return;
  }
  [self clearStationModeMenu];
  if (station == nil) {
    stationModeLabel.hidden = YES;
    return;
  }
  stationModeLabel.hidden = NO;
  stationModeLabel.textColor = [NSColor secondaryLabelColor];
  stationModeLabel.stringValue = @"Station Mode: Loading…";
  [[self pandora] fetchStationModesForStation:station];
}

- (void)handleStationModesLoaded:(NSNotification *)notification {
  Station *station = notification.object;
  if (station == nil || station != playing) {
    return;
  }
  NSDictionary *payload = notification.userInfo;
  NSArray *modes = payload[@"modes"];
  if (![modes isKindOfClass:[NSArray class]] || [modes count] == 0) {
    [self showStationModesUnavailable];
    return;
  }
  [self populateStationModeMenuWithEntries:modes];
}

- (void)populateStationModeMenuWithEntries:(NSArray<NSDictionary *> *)entries {
  if (!stationModesMenu || !stationModesMenuItem || entries.count == 0) {
    [self showStationModesUnavailable];
    return;
  }
  [stationModesMenu removeAllItems];
  NSString *currentModeName = nil;
  for (NSDictionary *entry in entries) {
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : nil;
    if (name.length == 0) {
      continue;
    }
    BOOL isCurrent = [entry[@"current"] boolValue];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:NULL keyEquivalent:@""];
    item.enabled = NO;
    item.state = isCurrent ? NSControlStateValueOn : NSControlStateValueOff;
    [stationModesMenu addItem:item];
    if (isCurrent) {
      currentModeName = name;
    }
  }
  if (stationModesMenu.numberOfItems == 0) {
    [self showStationModesUnavailable];
    return;
  }
  stationModeLabel.hidden = NO;
  stationModeLabel.textColor = [NSColor secondaryLabelColor];
  NSString *displayName = currentModeName.length > 0 ? currentModeName : @"—";
  stationModeLabel.stringValue = [NSString stringWithFormat:@"Station Mode: %@", displayName];
  [stationModesMenuItem setEnabled:YES];
}

- (void)showStationModesUnavailable {
  if (!stationModeLabel) {
    return;
  }
  stationModeLabel.hidden = NO;
  stationModeLabel.textColor = [NSColor secondaryLabelColor];
  stationModeLabel.stringValue = @"Station Mode: Unavailable";
  [self clearStationModeMenu];
}

- (void)clearStationModeMenu {
  if (!stationModesMenu || !stationModesMenuItem) {
    return;
  }
  [stationModesMenu removeAllItems];
  [stationModesMenuItem setEnabled:NO];
}

- (void) setIntegerVolume: (NSInteger) vol {
  if (vol < 0) { vol = 0; }
  if (vol > 100) { vol = 100; }
  [volume setIntegerValue:vol];
  [playing setVolume:vol/100.0];
  [[NSUserDefaults standardUserDefaults] setInteger:vol
                                             forKey:@"hermes.volume"];
}

- (NSInteger) integerVolume {
  return [volume integerValue];
}

- (void) pauseOnScreensaverStart:(NSNotification *)aNotification {
  if (!PREF_KEY_BOOL(PAUSE_ON_SCREENSAVER_START)) {
    return;
  }
  
  if ([self pause]){
    self.pausedByScreensaver = YES;
  }
}

- (void) playOnScreensaverStop:(NSNotification *)aNotification {
  if (!PREF_KEY_BOOL(PLAY_ON_SCREENSAVER_STOP)) {
    return;
  }

  if (self.pausedByScreensaver) {
    [self play];
  }
  self.pausedByScreensaver = NO;
}

- (void) pauseOnScreenLock:(NSNotification *)aNotification {
  if (!PREF_KEY_BOOL(PAUSE_ON_SCREEN_LOCK)) {
    return;
  }
  
  BOOL didPause = [self pause];
  if (!didPause && playing != nil) {
    [playing pause];
    didPause = YES;
  }
  if (didPause) {
    self.pausedByScreenLock = YES;
  }
}

- (void) playOnScreenUnlock:(NSNotification *)aNotification {
  if (!PREF_KEY_BOOL(PLAY_ON_SCREEN_UNLOCK)) {
    return;
  }

  if (self.pausedByScreenLock) {
    [self play];
  }
  self.pausedByScreenLock = NO;
}

- (IBAction) volumeChanged: (id) sender {
  if (playing) {
    [self setIntegerVolume:[volume intValue]];
  }
}

- (IBAction)increaseVolume:(id)sender {
  [self setIntegerVolume:[self integerVolume] + 5];
}

- (IBAction)decreaseVolume:(id)sender {
  [self setIntegerVolume:[self integerVolume] - 5];
}

- (IBAction)quickLookArt:(id)sender {
  QLPreviewPanel *previewPanel = [QLPreviewPanel sharedPreviewPanel];
  if ([previewPanel isVisible])
    [previewPanel orderOut:nil];
  else
    [previewPanel makeKeyAndOrderFront:nil];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (![[self pandora] isAuthenticated]) {
    return NO;
  }

  SEL action = [item action];

  NSObject *validatedObject = (NSObject *)item;

  if (action == @selector(playpause:)) {
    BOOL hasPlayableStation = (playing != nil);
    NSString *title = [playing isPaused] ? @"Play" : @"Pause";

    if ([validatedObject isKindOfClass:[NSMenuItem class]]) {
      NSMenuItem *menuItem = (NSMenuItem *)validatedObject;
      [menuItem setTitle:title];
    } else if ([validatedObject isKindOfClass:[NSToolbarItem class]]) {
      NSToolbarItem *toolbarItem = (NSToolbarItem *)validatedObject;
      toolbarItem.label = title;
      toolbarItem.paletteLabel = title;
      toolbarItem.toolTip = title;
    }

    return hasPlayableStation;
  }

  if (action == @selector(next:) || action == @selector(tired:)) {
    return playing != nil;
  }

  if (action == @selector(like:) || action == @selector(dislike:)) {
    Song *song = [playing playingSong];
    BOOL canRate = song && ![playing shared];

    if ([validatedObject isKindOfClass:[NSMenuItem class]]) {
      NSMenuItem *menuItem = (NSMenuItem *)validatedObject;
      if (canRate) {
        NSInteger rating = [[song nrating] integerValue];
        if (action == @selector(like:)) {
          menuItem.state = (rating == 1) ? NSControlStateValueOn : NSControlStateValueOff;
        } else {
          menuItem.state = (rating == -1) ? NSControlStateValueOn : NSControlStateValueOff;
        }
      } else {
        menuItem.state = NSControlStateValueOff;
      }
    }

    return canRate;
  }

  return YES;
}

#pragma mark QLPreviewPanelDataSource

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel {
  Song *song = [playing playingSong];
  if (song == nil)
    return 0;

  if ([song art] == nil || [[song art] isEqual: @""])
    return 0;

  return 1;
}

- (id <QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index {
  return self;
}

#pragma mark QLPreviewItem

- (NSURL *)previewItemURL {
  NSURL *artFileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"Hermes Album Art.tiff"]];
  [self.artImage.TIFFRepresentation writeToURL:artFileURL atomically:YES];

  return artFileURL;
}

- (NSString *)previewItemTitle {
  return [[playing playingSong] album];
}

#pragma mark QLPreviewPanelDelegate

- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id <QLPreviewItem>)item {
  NSRect frame = [art frame];
  frame = [[HMSAppDelegate window] convertRectToScreen:frame];

  frame = NSInsetRect(frame, 1, 1); // image doesn't extend into the button border

  NSSize imageSize = self.artImage.size; // correct for aspect ratio
  if (imageSize.width > imageSize.height)
    frame = NSInsetRect(frame, 0, ((imageSize.width - imageSize.height) / imageSize.height) / 2. * frame.size.height);
  else if (imageSize.height > imageSize.width)
    frame = NSInsetRect(frame, ((imageSize.height - imageSize.width) / imageSize.width) / 2. * frame.size.width, 0);

  return frame;
}

- (NSImage *)previewPanel:(QLPreviewPanel *)panel transitionImageForPreviewItem:(id <QLPreviewItem>)item contentRect:(NSRect *)contentRect {

  return self.artImage;
}

@end
