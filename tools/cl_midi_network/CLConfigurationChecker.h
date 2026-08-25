#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CLCheckLevel) {
    CLCheckLevelInfo,
    CLCheckLevelOK,
    CLCheckLevelWarning,
    CLCheckLevelError,
};

@interface CLConfigurationProfile : NSObject
@property(readonly) NSDictionary *values;
@property(readonly) NSString *name;
@property(readonly) NSString *machineRole;
+ (instancetype)profileWithValues:(NSDictionary *)values error:(NSError **)error;
+ (instancetype)templateForRole:(NSString *)role;
+ (instancetype)loadFromURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url overwrite:(BOOL)overwrite error:(NSError **)error;
+ (NSURL *)profilesDirectory;
@end

@interface CLConfigurationInspector : NSObject
- (NSDictionary *)inspect;
@end

@interface CLConfigurationReport : NSObject
@property(readonly) NSArray<NSDictionary *> *items;
@property(readonly) NSString *globalState;
@property(readonly) NSUInteger warningCount;
@property(readonly) NSUInteger errorCount;
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items;
@end

@interface CLConfigurationValidator : NSObject
- (CLConfigurationReport *)validateProfile:(CLConfigurationProfile *)profile inspection:(NSDictionary *)inspection;
@end
