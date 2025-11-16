#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HMSStationMode : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly, getter=isCurrent) BOOL current;

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                             current:(BOOL)isCurrent NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface StationModeParser : NSObject
+ (NSArray<HMSStationMode *> *)modesFromResultDictionary:(NSDictionary *)result
                                  currentModeIdentifier:(NSString * _Nullable * _Nullable)currentIdentifier;
@end

NS_ASSUME_NONNULL_END
