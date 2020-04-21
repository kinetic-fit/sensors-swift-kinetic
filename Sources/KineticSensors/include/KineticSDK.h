//
//  KineticSDK
//

#import <Foundation/Foundation.h>

@interface KineticSDK : NSObject

/*! SDK Version */
+ (NSString *)version;

+ (NSString *)systemIdToString:(NSData *)systemId;

@end
