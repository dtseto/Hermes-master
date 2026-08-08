/**
 * @file PlaybackController.m
 * @brief Implementation of the playback interface for playing/pausing
 *        songs
 *
 * Handles all information regarding playing a station, setting ratings for
 * songs, and listening for notifications. Deals with all user input related
 * to these actions as well
 */

#import <MediaPlayer/MediaPlayer.h>
//#import "Integration/Growler.h"
#import "HistoryController.h"
#import "ImageLoader.h"
#import "PlaybackController.h"
#import "StationsController.h"
#import "PreferencesController.h"
#import "Notifications.h"
#import "Views/PlaybackSplitView.h"

BOOL playOnStart = YES;

static const CGFloat HermesSongDetailsHorizontalPadding = 10.0;
static const CGFloat HermesSongDetailsBottomPadding = 8.0;
static const CGFloat HermesSongDetailsSpacing = 4.0;

@interface NSToolbarItem ()
- (void)_setAllPossibleLabelsToFit:(NSArray *)toolbarItemLabels;
@end

@interface PlaybackController ()
- (void)configureTitlebarSidebarControlsForWindow:(NSWindow *)window;
- (NSButton *)titlebarButtonWithSystemSymbol:(NSString *)symbolName
                                       label:(NSString *)label
                                     toolTip:(NSString *)toolTip
                                      action:(SEL)action;
- (void)toggleStationsPanelFromTitlebar:(id)sender;
- (void)toggleHistoryPanelFromTitlebar:(id)sender;
- (void)updateTitlebarSidebarToolTips;
- (void)restoreSongInfoVisibility;
- (void)updateSongInfoToolbarItem;
- (void)configureSongDetailsLayout;
- (void)configurePlaybackSplitView;
- (void)restoreSidebarVisibility;
- (void)presentPlaybackView;
- (void)configureRemoteCommands;
- (MPRemoteCommandHandlerStatus)performRemoteCommandAction:(BOOL (^)(void))action;
@end

@implementation PlaybackController

@synthesize playing;
@synthesize lastImg;
@synthesize remoteCommandCenter;
@synthesize stationModeService = _stationModeService;

+ (void) setPlayOnStart: (BOOL)play {
  playOnStart = play;
}

+ (BOOL) playOnStart {
  return playOnStart;
}

- (void)handleSongExplanation:(NSNotification *)notification {
    NSLog(@"🎵 EXPLANATION RECEIVED: %@", notification.userInfo);
    
    Song *song = (Song *)notification.object;
    NSString *explanation = notification.userInfo[@"explanation"];
    
    if (song && explanation) {
        // Update the existing explanation label
        [explanationLabel setStringValue:explanation];
        [explanationLabel setToolTip:explanation]; // Optional: also set as tooltip
        [self updateSongInfoToolbarItem];
        
        NSLog(@"🎵 Updated explanationLabel with: %@", explanation);
    } else {
        NSLog(@"❌ Missing song or explanation data");
        // Clear the label if no explanation
        [explanationLabel setStringValue:@""];
        [self updateSongInfoToolbarItem];
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

  // Let AppKit move controls into the toolbar overflow menu as the window
  // narrows. Toolbar items must not expand the window back to their combined
  // ideal width after a user resize.
  for (NSToolbarItem *item in toolbar.items) {
    item.visibilityPriority = NSToolbarItemVisibilityPriorityLow;
  }
  playpause.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;

  [self updateSongInfoToolbarItem];
  
  // prevent dragging the progress slider
  [playbackProgress setEnabled:NO];
  [self configureStationModesUI];
  [self configureSongDetailsLayout];
  [self configurePlaybackSplitView];

  [playbackView layoutSubtreeIfNeeded];
  stationsPanelVisible = playbackSplitView.leadingPaneVisible;
  historyPanelVisible = playbackSplitView.trailingPaneVisible;
  historyPanel.wantsLayer = YES;
  historyPanel.layer.masksToBounds = YES;
  [self configureTitlebarSidebarControlsForWindow:window];

  // Content constraints may express their natural size, but they must not
  // become an AppKit window-resize guardrail.
  window.contentMinSize = NSZeroSize;

  [self configureRemoteCommands];
}

- (MPRemoteCommandHandlerStatus)performRemoteCommandAction:(BOOL (^)(void))action {
  __block BOOL handled = NO;
  dispatch_block_t actionOnMainThread = ^{
    handled = action();
  };
  if ([NSThread isMainThread]) {
    actionOnMainThread();
  } else {
    dispatch_sync(dispatch_get_main_queue(), actionOnMainThread);
  }
  return handled ? MPRemoteCommandHandlerStatusSuccess : MPRemoteCommandHandlerStatusNoSuchContent;
}

- (void)configureRemoteCommands {
  remoteCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  __weak typeof(self) weakSelf = self;

  remoteCommandCenter.playCommand.enabled = YES;
  [remoteCommandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    return [strongSelf performRemoteCommandAction:^BOOL{
      if (strongSelf->playing == nil) {
        return NO;
      }
      return [strongSelf play] || [strongSelf->playing isPlaying];
    }];
  }];

  remoteCommandCenter.pauseCommand.enabled = YES;
  [remoteCommandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    return [strongSelf performRemoteCommandAction:^BOOL{
      return [strongSelf pause] || [strongSelf->playing isPaused];
    }];
  }];

  remoteCommandCenter.togglePlayPauseCommand.enabled = YES;
  [remoteCommandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    return [strongSelf performRemoteCommandAction:^BOOL{
      if (strongSelf->playing == nil) {
        return NO;
      }
      [strongSelf playpause:nil];
      return YES;
    }];
  }];

  remoteCommandCenter.nextTrackCommand.enabled = YES;
  [remoteCommandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    return [strongSelf performRemoteCommandAction:^BOOL{
      if (strongSelf->playing == nil) {
        return NO;
      }
      [strongSelf next:nil];
      return YES;
    }];
  }];

  [remoteCommandCenter.likeCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    return [strongSelf performRemoteCommandAction:^BOOL{
      if (strongSelf->playing == nil || [strongSelf->playing playingSong] == nil) {
        return NO;
      }
      [strongSelf like:nil];
      return YES;
    }];
  }];
  [remoteCommandCenter.dislikeCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return MPRemoteCommandHandlerStatusCommandFailed;
    }
    return [strongSelf performRemoteCommandAction:^BOOL{
      if (strongSelf->playing == nil || [strongSelf->playing playingSong] == nil) {
        return NO;
      }
      [strongSelf dislike:nil];
      return YES;
    }];
  }];
}

- (void)configureTitlebarSidebarControlsForWindow:(NSWindow *)window {
  if (window == nil || stationsTitlebarButton != nil || historyTitlebarButton != nil) {
    return;
  }

  NSButton *closeButton = [window standardWindowButton:NSWindowCloseButton];
  NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];
  NSView *titlebarView = closeButton.superview;
  if (titlebarView == nil || zoomButton == nil) {
    return;
  }

  stationsTitlebarButton = [self titlebarButtonWithSystemSymbol:@"sidebar.left"
                                                          label:NSLocalizedString(@"Station list", nil)
                                                        toolTip:NSLocalizedString(@"Show or hide station list", nil)
                                                         action:@selector(toggleStationsPanelFromTitlebar:)];
  historyTitlebarButton = [self titlebarButtonWithSystemSymbol:@"sidebar.right"
                                                         label:NSLocalizedString(@"Playback history", nil)
                                                       toolTip:NSLocalizedString(@"Show or hide playback history", nil)
                                                        action:@selector(toggleHistoryPanelFromTitlebar:)];
  titlebarTitleLabel = [NSTextField labelWithString:window.title ?: @""];
  titlebarTitleLabel.alignment = NSTextAlignmentLeft;
  titlebarTitleLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]
                                             weight:NSFontWeightSemibold];
  titlebarTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  titlebarTitleLabel.maximumNumberOfLines = 1;
  titlebarTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [titlebarTitleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];

  window.titleVisibility = NSWindowTitleHidden;
  [titlebarView addSubview:stationsTitlebarButton];
  [titlebarView addSubview:historyTitlebarButton];
  [titlebarView addSubview:titlebarTitleLabel];
  NSLayoutConstraint *titleLeadingConstraint =
    [titlebarTitleLabel.leadingAnchor constraintEqualToAnchor:stationsTitlebarButton.trailingAnchor
                                                constant:10.0];
  NSLayoutConstraint *titleTrailingConstraint =
    [titlebarTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:historyTitlebarButton.leadingAnchor
                                                           constant:-4.0];
  titleLeadingConstraint.priority = NSLayoutPriorityRequired - 1.0;
  [NSLayoutConstraint activateConstraints:@[
    [stationsTitlebarButton.leadingAnchor constraintEqualToAnchor:zoomButton.trailingAnchor constant:12.0],
    [stationsTitlebarButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
    [stationsTitlebarButton.widthAnchor constraintEqualToConstant:28.0],
    [stationsTitlebarButton.heightAnchor constraintEqualToConstant:24.0],
    [historyTitlebarButton.trailingAnchor constraintEqualToAnchor:titlebarView.trailingAnchor constant:-10.0],
    [historyTitlebarButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
    [historyTitlebarButton.widthAnchor constraintEqualToConstant:28.0],
    [historyTitlebarButton.heightAnchor constraintEqualToConstant:24.0],
    titleLeadingConstraint,
    titleTrailingConstraint,
    [titlebarTitleLabel.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor]
  ]];
  [titlebarTitleLabel bind:NSValueBinding
                  toObject:window
               withKeyPath:@"title"
                   options:nil];
  [self updateTitlebarSidebarToolTips];
}

- (void)configureSongDetailsLayout {
  songStack.edgeInsets = NSEdgeInsetsMake(0.0,
                                          HermesSongDetailsHorizontalPadding,
                                          HermesSongDetailsBottomPadding,
                                          HermesSongDetailsHorizontalPadding);
  songStack.alignment = NSLayoutAttributeCenterX;
  songStack.spacing = HermesSongDetailsSpacing;

  NSView *artContainer = art.superview;
  for (NSLayoutConstraint *constraint in songStack.constraints) {
    if (constraint.firstItem == artContainer &&
        constraint.firstAttribute == NSLayoutAttributeWidth &&
        constraint.secondItem == songStack &&
        constraint.secondAttribute == NSLayoutAttributeWidth) {
      constraint.constant = -(HermesSongDetailsHorizontalPadding * 2.0);
      break;
    }
  }

  NSArray<NSTextField *> *detailLabels = @[
    artistLabel,
    albumLabel,
    songLabel,
    stationModeLabel,
    progressLabel,
    explanationLabel
  ];
  NSSet<NSTextField *> *singleLineLabels = [NSSet setWithArray:@[
    artistLabel,
    albumLabel,
    songLabel,
    stationModeLabel,
    progressLabel
  ]];
  NSMutableArray<NSLayoutConstraint *> *detailWidthConstraints = [NSMutableArray array];
  for (NSTextField *detailLabel in detailLabels) {
    detailLabel.alignment = NSTextAlignmentCenter;
    detailLabel.preferredMaxLayoutWidth = 0.0;
    if ([singleLineLabels containsObject:detailLabel]) {
      detailLabel.maximumNumberOfLines = 1;
      detailLabel.cell.wraps = NO;
      detailLabel.cell.scrollable = YES;
      detailLabel.cell.lineBreakMode = NSLineBreakByTruncatingTail;
      [detailLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    for (NSLayoutConstraint *constraint in [detailLabel.constraints copy]) {
      if (constraint.firstItem == detailLabel &&
          constraint.firstAttribute == NSLayoutAttributeWidth &&
          constraint.relation == NSLayoutRelationLessThanOrEqual &&
          constraint.secondItem == nil) {
        constraint.active = NO;
      }
    }
    [detailWidthConstraints addObject:
      [detailLabel.widthAnchor constraintEqualToAnchor:songStack.widthAnchor
                                              constant:-(HermesSongDetailsHorizontalPadding * 2.0)]];
  }
  [NSLayoutConstraint activateConstraints:detailWidthConstraints];
}

- (void)configurePlaybackSplitView {
  NSStackView *legacyPlaybackRow = (NSStackView *)songStack.superview;
  if (![legacyPlaybackRow isKindOfClass:[NSStackView class]]) {
    return;
  }

  [NSLayoutConstraint deactivateConstraints:[playbackView.constraints copy]];
  for (NSLayoutConstraint *constraint in [stationsPanel.constraints copy]) {
    if (constraint.firstItem == stationsPanel &&
        constraint.firstAttribute == NSLayoutAttributeWidth) {
      constraint.active = NO;
    }
  }

  [legacyPlaybackRow removeArrangedSubview:songStack];
  [songStack removeFromSuperview];
  [legacyPlaybackRow removeArrangedSubview:historyPanel];
  [historyPanel removeFromSuperview];
  [stationsPanel removeFromSuperview];
  [legacyPlaybackRow removeFromSuperview];

  playbackSplitView = [[PlaybackSplitView alloc] initWithFrame:playbackView.bounds];
  playbackSplitView.translatesAutoresizingMaskIntoConstraints = NO;
  playbackSplitView.preferredLeadingPaneWidth = 198.0;
  playbackSplitView.preferredTrailingPaneWidth = 198.0;
  [playbackSplitView setLeadingPane:stationsPanel
                        centerPane:songStack
                      trailingPane:historyPanel];
  [playbackView addSubview:playbackSplitView];
  [NSLayoutConstraint activateConstraints:@[
    [playbackSplitView.leadingAnchor constraintEqualToAnchor:playbackView.leadingAnchor],
    [playbackSplitView.trailingAnchor constraintEqualToAnchor:playbackView.trailingAnchor],
    [playbackSplitView.topAnchor constraintEqualToAnchor:playbackView.topAnchor],
    [playbackSplitView.bottomAnchor constraintEqualToAnchor:playbackView.bottomAnchor]
  ]];
}

- (NSButton *)titlebarButtonWithSystemSymbol:(NSString *)symbolName
                                       label:(NSString *)label
                                     toolTip:(NSString *)toolTip
                                      action:(SEL)action {
  NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                             accessibilityDescription:label];
  NSButton *button = [NSButton buttonWithImage:image target:self action:action];
  button.bezelStyle = NSBezelStyleToolbar;
  button.imagePosition = NSImageOnly;
  button.imageScaling = NSImageScaleProportionallyDown;
  button.toolTip = toolTip;
  button.translatesAutoresizingMaskIntoConstraints = NO;
  return button;
}

- (void)toggleStationsPanelFromTitlebar:(id)sender {
  [self toggleStationsPanel];
}

- (void)toggleHistoryPanelFromTitlebar:(id)sender {
  [self toggleHistoryPanel];
}

- (void)updateTitlebarSidebarToolTips {
  stationsTitlebarButton.toolTip = stationsPanelVisible
    ? NSLocalizedString(@"Hide Station List", nil)
    : NSLocalizedString(@"Show Station List", nil);
  historyTitlebarButton.toolTip = historyPanelVisible
    ? NSLocalizedString(@"Hide Playback History", nil)
    : NSLocalizedString(@"Show Playback History", nil);
}

- (void)restoreSidebarVisibility {
  stationsPanelVisible = PREF_KEY_BOOL(STATIONS_PANEL_VISIBLE);
  historyPanelVisible = PREF_KEY_BOOL(HISTORY_PANEL_VISIBLE);
  playbackSplitView.leadingPaneVisible = stationsPanelVisible;
  playbackSplitView.trailingPaneVisible = historyPanelVisible;
  [playbackView layoutSubtreeIfNeeded];
  [self updateTitlebarSidebarToolTips];
}

- (void)setHistoryPanelVisible:(BOOL)visible {
  if (historyPanel == nil || historyPanelVisible == visible) {
    return;
  }

  historyPanelVisible = visible;
  PREF_KEY_SET_BOOL(HISTORY_PANEL_VISIBLE, visible);
  playbackSplitView.trailingPaneVisible = visible;
  [playbackView layoutSubtreeIfNeeded];
  [self updateTitlebarSidebarToolTips];
}

- (void)setStationsPanelVisible:(BOOL)visible {
  if (stationsPanel == nil || stationsPanelVisible == visible) {
    return;
  }

  stationsPanelVisible = visible;
  PREF_KEY_SET_BOOL(STATIONS_PANEL_VISIBLE, visible);
  playbackSplitView.leadingPaneVisible = visible;
  [playbackView layoutSubtreeIfNeeded];
  [self updateTitlebarSidebarToolTips];
}

- (void)toggleStationsPanel {
  [self setStationsPanelVisible:!stationsPanelVisible];
}

- (void)toggleHistoryPanel {
  [self setHistoryPanelVisible:!historyPanelVisible];
}

- (void)showHistoryPanel {
  [self setHistoryPanelVisible:YES];
}

- (void)restoreSongInfoVisibility {
  explanationLabel.hidden = !PREF_KEY_BOOL(SONG_INFO_VISIBLE);
  [self updateSongInfoToolbarItem];
  [playbackView layoutSubtreeIfNeeded];
}

- (void)updateSongInfoToolbarItem {
  BOOL infoVisible = !explanationLabel.hidden;
  NSString *symbolName = infoVisible ? @"info.circle.fill" : @"info.circle";
  songInfoToolbarItem.image = [NSImage imageWithSystemSymbolName:symbolName
                                        accessibilityDescription:@"Song information"];
  songInfoToolbarItem.toolTip = infoVisible
                                  ? @"Hide why this song was chosen"
                                  : @"Show why this song was chosen";
}

- (IBAction)toggleSongInfo:(id)sender {
  explanationLabel.hidden = !explanationLabel.hidden;
  PREF_KEY_SET_BOOL(SONG_INFO_VISIBLE, !explanationLabel.hidden);
  [self updateSongInfoToolbarItem];
  [playbackView layoutSubtreeIfNeeded];
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

- (void) prepareFirst {
  NSInteger saved = [[NSUserDefaults standardUserDefaults]
                     integerForKey:@"hermes.volume"];
  if (saved == 0) {
    saved = 100;
  }
  [self setIntegerVolume:saved];

  [self restoreSongInfoVisibility];
  [self restoreSidebarVisibility];
}

- (Pandora*) pandora {
  return [HMSAppDelegate pandora];
}

- (id<PlaybackStationModeService>)stationModeService {
  if (_stationModeService != nil) {
    return _stationModeService;
  }
  return (id<PlaybackStationModeService>)[self pandora];
}

- (void) reset {
  [self playStation:nil];

  NSString *path = [HMSAppDelegate stateDirectory:@"station.savestate"];
  [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void) show {
  [self presentPlaybackView];
}

- (void)presentPlaybackView {
  [HMSAppDelegate setCurrentView:playbackView];
  [playbackView layoutSubtreeIfNeeded];
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
  Song *song = [playing playingSong];
  self->_artImage = artImage;
  self->_artImageSong = song;
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

  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:artImage ?: [NSNull null]
                                                                      forKey:@"artwork"];
  if (song != nil) {
    userInfo[@"song"] = song;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:PlaybackArtworkDidChangeNotification
                                                      object:self
                                                    userInfo:userInfo];
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
  if (lastImgSrc == nil || ![lastImgSrc isEqualToString:[song art]]) {
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
        // A cancelled request can still finish while the next track is starting.
        // Never let that late callback replace the current track's artwork.
        if ([self->playing playingSong] != song) {
          return;
        }
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
    // The same album image can legitimately be shared by consecutive tracks.
    // Re-associate it so Now Playing can safely publish it for the new song.
    [self setArtImage:self.artImage];
  }

  [self presentPlaybackView];

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
  if ([playing isPlaying]) {
    [self pause];
  } else {
    [self play];
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
  [self presentPlaybackView];

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
  if (![[self stationModeService] fetchStationModesForStation:station]) {
    [self showStationModesUnavailable];
  }
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
    NSString *identifier = [entry[@"identifier"] isKindOfClass:[NSString class]]
                               ? entry[@"identifier"]
                               : nil;
    if (name.length == 0 || identifier.length == 0) {
      continue;
    }
    BOOL isCurrent = [entry[@"current"] boolValue];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name
                                                  action:@selector(selectStationMode:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = identifier;
    item.enabled = YES;
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

- (IBAction)selectStationMode:(id)sender {
  NSString *modeIdentifier = [sender isKindOfClass:[NSMenuItem class]]
                               ? [(NSMenuItem *)sender representedObject]
                               : nil;
  Station *station = playing;
  id<PlaybackStationModeService> service = [self stationModeService];
  if (![modeIdentifier isKindOfClass:[NSString class]] ||
      modeIdentifier.length == 0 ||
      station.stationId.length == 0 ||
      ![service isAuthenticated]) {
    return;
  }

  if (![service setMode:modeIdentifier forStation:station]) {
    return;
  }

  stationModeLabel.hidden = NO;
  stationModeLabel.textColor = [NSColor secondaryLabelColor];
  stationModeLabel.stringValue = @"Station Mode: Loading…";
  [station clearSongList];
  [self next:sender];
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
  if (![[self stationModeService] isAuthenticated]) {
    return NO;
  }

  SEL action = [item action];

  NSObject *validatedObject = (NSObject *)item;

  if (action == @selector(selectStationMode:)) {
    NSString *modeIdentifier = [validatedObject isKindOfClass:[NSMenuItem class]]
                                 ? [(NSMenuItem *)validatedObject representedObject]
                                 : nil;
    return playing.stationId.length > 0 &&
           [modeIdentifier isKindOfClass:[NSString class]] &&
           modeIdentifier.length > 0;
  }

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
