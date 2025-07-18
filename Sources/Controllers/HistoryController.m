//
//  HistoryController.m
//  Hermes
//
//  Created by Alex Crichton on 10/9/11.
//

#import "HistoryController.h"
#import "FileReader.h"
#import "FMEngine/NSString+FMEngine.h"
#import "PlaybackController.h"
#import "PreferencesController.h"
#import "URLConnection.h"
#import "Notifications.h"

#define HISTORY_LIMIT 20

@implementation HistoryController

@synthesize songs, controller;

- (void) awakeFromNib {
  [super awakeFromNib];
 // drawersTable.contentView.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
}

- (void) loadSavedSongs {
  NSLogd(@"loading saved songs");
  NSString *historySaveStatePath = [HMSAppDelegate stateDirectory:@"history.savestate"];
  if (historySaveStatePath == nil) return;

  reader = [FileReader readerForFile:historySaveStatePath completionHandler:^(NSData *data, NSError *err) {
    if (err) return;
    assert(data != nil);

    // Fix: Use modern unarchiving method with proper error handling
    NSError *unarchiveError = nil;
    NSArray *s = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSArray class]
                                                   fromData:data
                                                      error:&unarchiveError];
    
    if (unarchiveError) {
      NSLog(@"Error unarchiving saved songs: %@", unarchiveError);
      return;
    }
    
    if (s == nil) {
      NSLog(@"Failed to unarchive saved songs - data may be corrupted");
      return;
    }
    
    for (Song *song in s) {
      if ([self->songs indexOfObject:song] == NSNotFound)
        [self->controller addObject:song];
    }

    self->reader = nil;
  }];
  [reader start];
}

- (void) insertObject:(Song *)s inSongsAtIndex:(NSUInteger)index {
  [songs insertObject:s atIndex:index];
}

- (void) removeObjectFromSongsAtIndex:(NSUInteger)index {
  [songs removeObjectAtIndex:index];
}

- (void) addSong:(Song *)song {
  if (songs == nil) {
    [self loadSavedSongs];
    songs = [NSMutableArray array];
  }
  [self insertObject:song inSongsAtIndex:0];

  [[NSDistributedNotificationCenter defaultCenter]
    postNotificationName:HistoryControllerDidPlaySongDistributedNotification
                  object:@"hermes"
                userInfo:[song toDictionary]
                deliverImmediately: YES];

  while ([songs count] > HISTORY_LIMIT) {
    [self removeObjectFromSongsAtIndex:HISTORY_LIMIT];
  }
}

- (BOOL) saveSongs {
  NSString *path = [HMSAppDelegate stateDirectory:@"history.savestate"];
  if (path == nil) {
    return NO;
  }

  // Fix: Use modern archiving method
  NSError *archiveError = nil;
  NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:songs
                                              requiringSecureCoding:NO
                                                              error:&archiveError];
  
  if (archiveError || archivedData == nil) {
    NSLog(@"Error archiving songs: %@", archiveError);
    return NO;
  }
  
  // Write the archived data to file
  NSError *writeError = nil;
  NSURL *fileURL = [NSURL fileURLWithPath:path];
  BOOL success = [archivedData writeToURL:fileURL
                                  options:NSDataWritingAtomic
                                    error:&writeError];
  
  if (!success) {
    NSLog(@"Error writing archived songs to file: %@", writeError);
    return NO;
  }
  
  return YES;
}

- (Song*) selectedItem {
  NSUInteger selection = [controller selectionIndex];
  if (selection == NSNotFound) {
    return nil;
  }
  return songs[selection];
}

- (Pandora*) pandora {
  return [HMSAppDelegate pandora];
}

- (void) setEnabledState:(BOOL)enabled allowRating:(BOOL)ratingEnabled {
  [pandoraSong setEnabled:enabled];
  [pandoraArtist setEnabled:enabled];
  [pandoraAlbum setEnabled:enabled];
  [lyrics setEnabled:enabled];
  [like setEnabled:ratingEnabled];
  [dislike setEnabled:ratingEnabled];
}

- (void) updateUI {
  Song *song = [self selectedItem];
  int rating = 0;
  if (song && [[song station] shared]) {
    [self setEnabledState:YES allowRating:NO];
  }
  else if (song) {
    [self setEnabledState:YES allowRating:YES];
    rating = [[song nrating] intValue];
  }
  else {
    [self setEnabledState:NO allowRating:NO];
  }

  if (rating == -1) {
    [like setState:NSControlStateValueOff];
    [dislike setState:NSControlStateValueOn];
  }
  else if (rating == 0) {
    [like setState:NSControlStateValueOff];
    [dislike setState:NSControlStateValueOff];
  }
  else if (rating == 1) {
    [like setState:NSControlStateValueOn];
    [dislike setState:NSControlStateValueOff];
  }
}

- (IBAction) dislikeSelected:(id)sender {
  Song* song = [self selectedItem];
  if (!song) return;
  [[HMSAppDelegate playback] rate:song as:NO];
}

- (IBAction) likeSelected:(id)sender {
  Song* song = [self selectedItem];
  if (!song) return;
  [[HMSAppDelegate playback] rate:song as:YES];
}

- (IBAction)gotoSong:(id)sender {
  Song* s = [self selectedItem];
  if (s == nil) return;
  NSURL *url = [NSURL URLWithString:[s titleUrl]];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)gotoArtist:(id)sender {
  Song* s = [self selectedItem];
  if (s == nil) return;
  NSURL *url = [NSURL URLWithString:[s artistUrl]];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)gotoAlbum:(id)sender {
  Song* s = [self selectedItem];
  if (s == nil) return;
  NSURL *url = [NSURL URLWithString:[s albumUrl]];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

/*
- (NSSize) drawerWillResizeContents:(NSDrawer*) drawer toSize:(NSSize) size {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setInteger:size.width forKey:HIST_DRAWER_WIDTH];
  return size;
}

- (void)drawerWillClose:(NSNotification *)notification {
  PREF_KEY_SET_INT(OPEN_DRAWER, DRAWER_NONE_HIST);
}

 */

/*
- (void) showDrawer {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSSize s;
  s.height = 100;
  s.width = [defaults integerForKey:HIST_DRAWER_WIDTH];

  [drawersTable open];
  [drawersTable setContentSize:s];
  [collection setMaxItemSize:NSMakeSize(227, 41)];
  [collection setMinItemSize:NSMakeSize(40, 41)];
  [self focus];
}

- (void) hideDrawer {
  [drawersTable close];
}

- (void) focus {
  [[drawersTable parentWindow] makeFirstResponder:collection];
}
*/

- (IBAction) showLyrics:(id)sender {
  Song* s = [self selectedItem];
  if (s == nil) return;
  NSString *surl =
    [NSString
      stringWithFormat:@"http://lyrics.wikia.com/api.php?action=lyrics&artist=%@&song=%@&fmt=realjson",
      [[s artist] urlEncoded], [[s title] urlEncoded]];
  NSURL *url = [NSURL URLWithString:surl];
  NSURLRequest *req = [NSURLRequest requestWithURL:url];
  NSLogd(@"Fetch: %@", surl);
  URLConnection *conn = [URLConnection connectionForRequest:req
                                          completionHandler:^(NSData *d, NSError *err) {
    if (err == nil) {
      NSDictionary *object = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
      if (err == nil) {
        NSString *url = object[@"url"];
        [self->spinner setHidden:YES];
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
        return;
      }
    }
    NSAlert *alert = [NSAlert alertWithError:err];
    alert.messageText = @"Couldn't open lyrics";
    alert.informativeText = [err localizedDescription];
    [alert beginSheetModalForWindow:[HMSAppDelegate window] completionHandler:nil];
  }];

  [conn setHermesProxy];
  [conn start];
  [spinner setHidden:NO];
}

@end
