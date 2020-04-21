//
//  KineticSDK
//

#import "KineticSDK.h"
#import "KineticConstants.h"

@implementation KineticSDK

+ (NSString *)version
{
    return SDK_VERSION;
}

+ (NSString *)systemIdToString:(NSData *)systemId
{
    NSMutableString *hexString = [NSMutableString string];
    const unsigned char *bytes = [systemId bytes];
    for (int i = 0; i < systemId.length; i++) {
        [hexString appendFormat:@"%02x", bytes[i]];
    }
    return [NSString stringWithString:hexString];
}

@end
