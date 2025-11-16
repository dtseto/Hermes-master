#import "Pandora/StationModeParser.h"

@implementation HMSStationMode

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                             current:(BOOL)isCurrent {
  self = [super init];
  if (self) {
    _identifier = [identifier copy];
    _name = [name copy];
    _current = isCurrent;
  }
  return self;
}

@end

@interface StationModeParser ()
+ (NSString *)sanitizedIdentifierFromValue:(id)value;
@end

@implementation StationModeParser

+ (NSArray<HMSStationMode *> *)modesFromResultDictionary:(NSDictionary *)result
                                  currentModeIdentifier:(NSString * _Nullable * _Nullable)currentIdentifier {
  if (currentIdentifier != NULL) {
    *currentIdentifier = nil;
  }

  if (![result isKindOfClass:[NSDictionary class]]) {
    return @[];
  }

  id currentModeValue = result[@"currentModeId"];
  NSString *resolvedCurrentMode = [self sanitizedIdentifierFromValue:currentModeValue];
  if (currentIdentifier != NULL) {
    *currentIdentifier = resolvedCurrentMode;
  }

  NSArray *rawModes = result[@"availableModes"];
  if (![rawModes isKindOfClass:[NSArray class]]) {
    return @[];
  }

  NSMutableArray<HMSStationMode *> *parsedModes = [NSMutableArray arrayWithCapacity:[rawModes count]];
  for (id entry in rawModes) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *modeDict = (NSDictionary *)entry;
    NSString *identifier = [self sanitizedIdentifierFromValue:modeDict[@"modeId"]];
    NSString *name = [modeDict[@"modeName"] isKindOfClass:[NSString class]] ? modeDict[@"modeName"] : nil;
    if (identifier.length == 0 || name.length == 0) {
      continue;
    }
    BOOL isCurrent = (resolvedCurrentMode.length > 0 && [identifier isEqualToString:resolvedCurrentMode]);
    HMSStationMode *mode = [[HMSStationMode alloc] initWithIdentifier:identifier name:name current:isCurrent];
    [parsedModes addObject:mode];
  }

  return [parsedModes copy];
}

+ (NSString *)sanitizedIdentifierFromValue:(id)value {
  if ([value isKindOfClass:[NSString class]]) {
    return (NSString *)value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [(NSNumber *)value stringValue];
  }
  return nil;
}

@end
