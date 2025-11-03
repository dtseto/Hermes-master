#import "ImageLoader.h"
#import "URLConnection.h"

@implementation ImageLoader

+ (ImageLoader*) loader {
  static ImageLoader *l = nil;
  if (l == nil) {
    l = [[ImageLoader alloc] init];
  }
  return l;
}

- (id) init {
  cur = nil;
  queue = [NSMutableArray array];
  cbqueue = [NSMutableArray array];
  return self;
}

- (void) loadImageURL:(NSString*)url callback:(ImageCallback)cb {
  cb = [cb copy];
  if (url == nil || [url length] == 0) {
    if (cb != nil) {
      cb(nil);
    }
    return;
  }
  if (cur != nil) {
    [queue addObject:url];
    [cbqueue addObject:cb];
    return;
  }

  [self fetch:url cb:cb];
}

- (void) fetch:(NSString*)url cb:(ImageCallback)cb {
  NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
  cur = [URLConnection connectionForRequest:req
                          completionHandler:^(NSData *d, NSError *error) {
    NSLogd(@"fetching: %@", url);
    ImageCallback callback = cb;
    self->cur = nil;
    self->curURL = nil;

    /* If any pending requests are to this url, also satisfy them */
    NSUInteger idx;
    NSMutableArray<ImageCallback> *callbacks = [NSMutableArray array];
    if (callback != nil) {
      [callbacks addObject:callback];
    }
    while ((idx = [self->queue indexOfObject:url]) != NSNotFound) {
      NSLogd(@"cached:   %@", url);
      [self->queue removeObjectAtIndex:idx];
      ImageCallback cb = self->cbqueue[idx];
      if (cb != nil) {
        [callbacks addObject:cb];
      }
      [self->cbqueue removeObjectAtIndex:idx];
    }

    if (callbacks.count > 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        for (ImageCallback callback in callbacks) {
          callback(d);
        }
      });
    }

    [self tryFetch];
  }];
  curURL = url;
  [cur start];
}

- (void) tryFetch {
  if ([queue count] == 0) return;
  NSString *url = queue[0];
  ImageCallback cb = cbqueue[0];
  [queue removeObjectAtIndex:0];
  [cbqueue removeObjectAtIndex:0];
  [self fetch:url cb:cb];
}

- (void) cancel:(NSString*)url {
  NSUInteger idx = [queue indexOfObject:url];
  if (idx == NSNotFound) {
    if ([url isEqualToString:curURL]) {
      [cur cancel];
      cur = nil;
      curURL = nil;
      [self tryFetch];
    }
  } else {
    [queue removeObjectAtIndex:idx];
    [cbqueue removeObjectAtIndex:idx];
  }
}

@end
