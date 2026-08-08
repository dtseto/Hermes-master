#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

#import "Pandora/Station.h"
#import "Integration/Scrobbler.h"

@class Song;
@class MPRemoteCommandCenter;
@class PlaybackSplitView;

@protocol PlaybackStationModeService <NSObject>
- (BOOL)isAuthenticated;
- (BOOL)fetchStationModesForStation:(Station *)station;
- (BOOL)setMode:(NSString *)modeIdentifier forStation:(Station *)station;
@end

@interface PlaybackController : NSObject <QLPreviewPanelDataSource, QLPreviewPanelDelegate, QLPreviewItem, NSUserInterfaceValidations> {
  IBOutlet NSProgressIndicator *songLoadingProgress;

  IBOutlet NSView *playbackView;

  //new explanation
  IBOutlet NSTextField *explanationLabel;
  
  IBOutlet NSMenu *songContextMenu;  // Add this

  
  // Song view items
  IBOutlet NSTextField *songLabel;
  IBOutlet NSTextField *artistLabel;
  IBOutlet NSTextField *albumLabel;
  IBOutlet NSTextField *progressLabel;
  IBOutlet NSButton *art;
  IBOutlet NSSlider *playbackProgress;
  IBOutlet NSProgressIndicator *artLoading;
  IBOutlet NSTextField *stationModeLabel;
  IBOutlet NSMenu *stationModesMenu;
  IBOutlet NSMenuItem *stationModesMenuItem;
  IBOutlet NSStackView *songStack;
  IBOutlet NSScrollView *stationsPanel;
  IBOutlet NSStackView *historyPanel;
  PlaybackSplitView *playbackSplitView;

  // Playback related items
  IBOutlet NSToolbarItem *like;
  IBOutlet NSToolbarItem *dislike;
  IBOutlet NSToolbarItem *playpause;
  IBOutlet NSToolbarItem *nextSong;
  IBOutlet NSToolbarItem *tiredOfSong;
  IBOutlet NSToolbarItem *songInfoToolbarItem;
  IBOutlet NSSlider *volume;
  IBOutlet NSToolbar *toolbar;

  NSButton *stationsTitlebarButton;
  NSButton *historyTitlebarButton;
  NSTextField *titlebarTitleLabel;

  NSTimer *progressUpdateTimer;
  BOOL scrobbleSent;
  NSString *lastImgSrc;
  NSData *lastImg;
  BOOL stationsPanelVisible;
  BOOL historyPanelVisible;
  id<PlaybackStationModeService> _stationModeService;
}

@property (readonly) Station *playing;
@property (readonly) NSData *lastImg;
@property (nonatomic, retain) NSImage *artImage;
@property (nonatomic, readonly) Song *artImageSong;
@property BOOL pausedByScreensaver;
@property BOOL pausedByScreenLock;

@property (readonly) MPRemoteCommandCenter *remoteCommandCenter;
@property (nonatomic, strong) id<PlaybackStationModeService> stationModeService;

+ (void) setPlayOnStart: (BOOL)play;
+ (BOOL) playOnStart;

//- (void) applicationOpened;

- (void) reset;
- (void) playStation: (Station*) station;
- (BOOL) saveState;
- (void) show;
- (void) prepareFirst;

- (BOOL) play;
- (BOOL) pause;
- (void) stop;
- (void) setIntegerVolume: (NSInteger) volume;
- (NSInteger) integerVolume;
- (void) pauseOnScreensaverStart: (NSNotification *) aNotification;
- (void) playOnScreensaverStop: (NSNotification *) aNotification;
- (void) pauseOnScreenLock: (NSNotification *) aNotification;
- (void) playOnScreenUnlock: (NSNotification *) aNotification;

- (void) rate:(Song *)song as:(BOOL)liked;

- (IBAction)playpause: (id) sender;
- (IBAction)next: (id) sender;
- (IBAction)like: (id) sender;
- (IBAction)dislike: (id) sender;
- (IBAction)tired: (id) sender;
- (IBAction)selectStationMode:(id)sender;
- (IBAction)toggleSongInfo:(id)sender;
- (IBAction)loadMore: (id)sender;
- (IBAction)songURL: (id)sender;
- (IBAction)artistURL: (id)sender;
- (IBAction)albumURL: (id)sender;
- (IBAction)volumeChanged: (id)sender;
- (IBAction)increaseVolume:(id)sender;
- (IBAction)decreaseVolume:(id)sender;
- (IBAction)quickLookArt:(id)sender;
- (void)toggleStationsPanel;
- (void)toggleHistoryPanel;
- (void)showHistoryPanel;

@end
