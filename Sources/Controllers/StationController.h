/**
 * @file StationController.h
 * @brief Headers for editing stations
 */

@class Station;

NS_ASSUME_NONNULL_BEGIN

@protocol StationService <NSObject>
- (void)fetchStationInfo:(Station * _Nonnull)station;
- (void)renameStation:(NSString * _Nonnull)stationToken to:(NSString * _Nonnull)name;
- (void)search:(NSString * _Nonnull)query;
- (void)addSeed:(NSString * _Nonnull)seedIdentifier toStation:(Station * _Nonnull)station;
- (void)removeSeed:(NSString * _Nonnull)seedIdentifier;
- (void)deleteFeedback:(NSString * _Nonnull)feedbackId;
@end

@interface StationController : NSObject <NSTableViewDataSource, NSOutlineViewDataSource> {
  IBOutlet NSWindow *window;

  /* Metadata */
  IBOutlet NSImageView *art;
  IBOutlet NSTextField *stationName;
  IBOutlet NSTextField *stationCreated;
  IBOutlet NSTextField *stationGenres;
  IBOutlet NSProgressIndicator *progress;
  IBOutlet NSButton *gotoStation;

  /* Seeds */
  IBOutlet NSTextField *seedSearch;
  IBOutlet NSOutlineView *seedsResults;
  IBOutlet NSOutlineView *seedsCurrent;
  NSMutableDictionary *seeds;
  NSDictionary *lastResults;
  IBOutlet NSButton *seedAdd;
  IBOutlet NSButton *seedDel;

  /* Likes/Dislikes */
  IBOutlet NSTableView *likes;
  IBOutlet NSTableView *dislikes;
  NSArray *alikes;
  NSArray *adislikes;
  IBOutlet NSButton *deleteFeedback;

  Station *cur_station;
  NSString *station_url;
}

@property (nonatomic, strong, nullable) id<StationService> stationService;
@property (nonatomic, strong, nullable) NSNotificationCenter *notificationCenter;

- (void) editStation: (Station * _Nullable) station;
- (IBAction) renameStation:(id _Nullable)sender;
- (IBAction) gotoPandora:(id _Nullable)sender;

- (IBAction) searchSeeds:(id _Nullable)sender;
- (IBAction) addSeed:(id _Nullable)sender;
- (IBAction) deleteSeed:(id _Nullable)sender;
- (void) seedFailedDeletion:(NSNotification * _Nonnull) not;

- (IBAction) deleteFeedback:(id _Nullable)sender;

@end

NS_ASSUME_NONNULL_END
