//
//  KineticSDK
//

#import "KineticInRide.h"
#import "KineticSDK.h"
#import "KineticConstants.h"
#import "inRide.h"

NSString * const KineticInRidePowerServiceUUID = @"E9410100-B434-446B-B5CC-36592FC4C724";
NSString * const KineticInRidePowerServicePowerUUID = @"E9410101-B434-446B-B5CC-36592FC4C724";
NSString * const KineticInRidePowerServiceConfigUUID = @"E9410104-B434-446B-B5CC-36592FC4C724";
NSString * const KineticInRidePowerServiceControlPointUUID = @"E9410102-B434-446B-B5CC-36592FC4C724";
NSString * const KineticInRideDeviceInformationUUID = @"180A";
NSString * const KineticInRideDeviceInformationSystemIDUUID = @"2A23";

typedef NS_ENUM (uint8_t, KineticInRideSensorCommand)
{
    KineticInRideSensorCommandSetSpindownParams   = 0x01,
    KineticInRideSensorCommandSetName             = 0x02,
    KineticInRideSensorCommandStartCalibration    = 0x03,
    KineticInRideSensorCommandStopCalibration     = 0x04,
    KineticInRideSensorCommandSetSpindownTime     = 0x05
};

// Ticks b/w sensor reading (32 kHz)
typedef NS_ENUM (uint16_t, KineticInRideCalibrationInterval)
{
    KineticInRideCalibrationIntervalReady       = 602,
    KineticInRideCalibrationIntervalStart       = 655,
    KineticInRideCalibrationIntervalEnd         = 950,
    KineticInRideCalibrationIntervalDebounce    = 327
};


typedef NS_ENUM (NSInteger, KineticInRideErrorCode)
{
    InRideErrorCodeInvalidSystemId  = 201,
    InRideErrorCodeInvalidData      = 202,
    InRideErrorCodeInvalidName      = 203,
};

#define SensorHz                32768

@interface KineticInRidePowerData ()
@property double timestamp;
@property KineticInRideSensorState state;
@property NSInteger power;
@property double speedKPH;
@property double rollerRPM;
@property double cadenceRPM;
@property bool coasting;
@property double spindownTime;
@property double rollerResistance;
@property KineticInRideSensorCalibrationResult calibrationResult;
@property double lastSpindownResultTime;
@property bool proFlywheel;
@property KineticInRideSensorCommandResult commandResult;

@property uint16_t cadenceRaw;
@end

@implementation KineticInRidePowerData

- (instancetype)init {
    self = [super init];
    if (self) {
        _timestamp = [[NSDate date] timeIntervalSince1970];
        _state = KineticInRideSensorStateUnknown;
        _power = 0;
        _speedKPH = 0;
        _rollerRPM = 0;
        _cadenceRPM = 0;
        _coasting = NO;
        _spindownTime = 0.0;
        _proFlywheel = NO;
        _lastSpindownResultTime = 0.0;
        _commandResult = KineticInRideSensorCommandResultNone;
    }
    return self;
}
@end

@interface KineticInRideConfigData ()
@property bool proFlywheel;
@property double currentSpindownTime;
@property KineticInRideUpdateRate updateRate;

// Raw data. (Private Header only)
@property uint16_t calibrationReady;
@property uint16_t calibrationStart;
@property uint16_t calibrationEnd;
@property uint16_t calibrationDebounce;
@property uint32_t currentSpindownTicks;
@property uint16_t updateRateCalibration;
@end
@implementation KineticInRideConfigData
@end


typedef struct {
    double timestamp;
    uint16_t cadenceRPM;
} cadence;

typedef struct {
    bool success;
    uint16_t commandKey;
} command_key;

#define CADENCE_BUFFER_SIZE_MAX 10
#define CADENCE_BUFFER_SIZE_DEFAULT 3
#define CADENCE_BUFFER_WEIGHT_DEFAULT 2
static NSUInteger cadenceBufferSize = CADENCE_BUFFER_SIZE_DEFAULT;
static NSUInteger cadenceBufferWeight = CADENCE_BUFFER_WEIGHT_DEFAULT;
static NSUInteger cadenceBufferCount = 0;
static cadence cadenceBuffer[CADENCE_BUFFER_SIZE_MAX];

@implementation KineticInRide

+ (KineticInRideConfigData *)processConfigurationData:(NSData *)data error:(NSError *__autoreleasing *)error
{
    if (data.length != 20) {
        if (error != nil) {
            NSString *desc = @"Invalid inRide Config Data";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
            *error = [NSError errorWithDomain:ERROR_DOMAIN
                                         code:InRideErrorCodeInvalidData
                                     userInfo:userInfo];
        }
        return nil;
    }
    
    KineticInRideConfigData *configData = [[KineticInRideConfigData alloc] init];
    inride_config_data cData = inride_process_config_data((uint8_t *)data.bytes);
    configData.calibrationReady = cData.calibrationReady;
    configData.calibrationStart = cData.calibrationStart;
    configData.calibrationEnd = cData.calibrationEnd;
    configData.calibrationDebounce = cData.calibrationDebounce;
    configData.currentSpindownTime = cData.currentSpindownTime;
    configData.updateRate = cData.updateRateDefault;
    configData.updateRateCalibration = cData.updateRateCalibration;
    configData.proFlywheel = cData.proFlywheel;
    return configData;
}

+ (KineticInRidePowerData *)processPowerData:(NSData *)data systemId:(NSData *)systemId error:(NSError *__autoreleasing *)error
{
    if (data.length != 20) {
        if (error != nil) {
            NSString *desc = @"Invalid inRide Power Data";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
            *error = [NSError errorWithDomain:ERROR_DOMAIN
                                         code:InRideErrorCodeInvalidData
                                     userInfo:userInfo];
        }
        return nil;
    }
    
    if (![self validateSystemId:systemId error:error]) {
        return nil;
    }
    
    KineticInRidePowerData *powerData = [[KineticInRidePowerData alloc] init];
    powerData.timestamp = [[NSDate date] timeIntervalSince1970];
    
    inride_power_data cData = inride_process_power_data((uint8_t *)data.bytes);
    powerData.state = (KineticInRideSensorState)cData.state;
    powerData.power = cData.power;
    powerData.speedKPH = cData.speedKPH;
    powerData.rollerRPM = cData.rollerRPM;
    powerData.cadenceRaw = cData.cadenceRPM;
    powerData.coasting = cData.coasting;
    powerData.spindownTime = cData.spindownTime;
    powerData.rollerResistance = cData.rollerResistance;
    powerData.calibrationResult = (KineticInRideSensorCalibrationResult)cData.calibrationResult;
    powerData.lastSpindownResultTime = cData.lastSpindownResultTime;
    powerData.proFlywheel = cData.proFlywheel;
    powerData.commandResult = (KineticInRideSensorCommandResult)cData.commandResult;
    
    // SDK Adjustment of Cadence
    powerData.cadenceRPM = [self adjustCadence:powerData.cadenceRaw timestamp:powerData.timestamp];
    
    return powerData;
}

+ (void)setCadenceRollingParams:(NSUInteger)bufferSize weight:(NSUInteger)weight
{
    cadenceBufferSize = MIN(CADENCE_BUFFER_SIZE_MAX, bufferSize);
    cadenceBufferWeight = weight;
    cadenceBufferCount = 0;
}

+ (double)adjustCadence:(uint16_t)crankRPM timestamp:(double)timestamp
{
    if (crankRPM == 0) {
        cadenceBufferCount = 0;
        return 0;
    }
    
    if (cadenceBufferCount > 0 && timestamp - cadenceBuffer[0].timestamp > 2) {
        cadenceBufferCount = 0;
    }
    
    // shift cadence values down ...
    for (NSUInteger i = cadenceBufferCount; i > 0; i--) {
        cadenceBuffer[i].timestamp = cadenceBuffer[i - 1].timestamp;
        cadenceBuffer[i].cadenceRPM = cadenceBuffer[i - 1].cadenceRPM;
    }
    cadenceBuffer[0].cadenceRPM = crankRPM;
    cadenceBuffer[0].timestamp = timestamp;
    
    cadenceBufferCount = MIN(cadenceBufferSize, cadenceBufferCount + 1);
    
    double rollingRPM = crankRPM * cadenceBufferWeight;
    for (int i = 1; i < cadenceBufferSize; i++) {
        rollingRPM += cadenceBuffer[i].cadenceRPM;
    }
    rollingRPM /= cadenceBufferSize + cadenceBufferWeight - 1;
    
    return rollingRPM;
}

+ (double)speedForTicks:(uint32_t)ticks revs:(uint8_t)revs
{
    if (ticks == 0 || revs == 0) {
        return 0;
    }
    double distanceKM = (double)revs * RollerCircumferenceKM;
    double hours = (double)ticks / (double)(SensorHz * 3600); // 117,964,800
    return distanceKM / hours;
}

+ (NSData *)startCalibrationCommandData:(NSData *)systemId error:(NSError * __autoreleasing *)error
{
    if (![self validateSystemId:systemId error:error]) {
        return nil;
    }
    inride_start_calibration_command command = inride_create_start_calibration_command_data((uint8_t *)systemId.bytes);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (double)calibrationReadySpeedKPH
{
    return [self speedForTicks:KineticInRideCalibrationIntervalReady revs:1];
}

+ (NSData *)stopCalibrationCommandData:(NSData *)systemId error:(NSError * __autoreleasing *)error
{
    if (![self validateSystemId:systemId error:error]) {
        return nil;
    }
    inride_stop_calibration_command command = inride_create_stop_calibration_command_data((uint8_t *)systemId.bytes);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (NSData *)setSpindownTimeCommandData:(NSData *)systemId seconds:(NSTimeInterval)seconds error:(NSError * __autoreleasing *)error
{
    if (![self validateSystemId:systemId error:error]) {
        return nil;
    }
    inride_set_spindown_time_command command = inride_create_set_spindown_time_command_data(seconds, (uint8_t *)systemId.bytes);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (NSData *)configureSensorCommandData:(NSData *)systemId updateRate:(KineticInRideUpdateRate)rate error:(NSError * __autoreleasing *)error
{
    if (![self validateSystemId:systemId error:error]) {
        return nil;
    }
    inride_config_sensor_command command = inride_create_config_sensor_command_data((inride_update_rate)rate, (uint8_t *)systemId.bytes);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (NSData *)setPeripheralNameCommandData:(NSData *)systemId name:(NSString *)sensorName error:(NSError * __autoreleasing *)error
{
    if (![self validateSystemId:systemId error:error]) {
        return nil;
    }
    if (sensorName.length < 3 || sensorName.length > 8) {
        if (error != nil) {
            NSString *desc = @"Invalid Sensor Name. Must be between 3 and 8 characters.";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
            *error = [NSError errorWithDomain:ERROR_DOMAIN
                                         code:InRideErrorCodeInvalidName
                                     userInfo:userInfo];
        }
        return nil;
    }
    
    const uint8_t *sysIdBytes = systemId.bytes;
    int sysidx1 = (sysIdBytes[3] & 0xFF) % 6;
    int sysidx2 = (sysIdBytes[5] & 0xFF) % 6;
    uint16_t commandKey = sysIdBytes[sysidx1] | (sysIdBytes[sysidx2] << 8);
    
    NSMutableData *command = [NSMutableData dataWithBytes:&commandKey length:2];
    uint8_t code = KineticInRideSensorCommandSetName;
    [command appendBytes:&code length:1];
    NSData *nameData = [sensorName dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    [command appendData:nameData];
    return command;
}

+ (command_key)commandKeyForSystemId:(NSData *)systemId error:(NSError * __autoreleasing *)error
{
    command_key result;
    if (systemId == nil || systemId.length != 6) {
        if (error != nil) {
            NSString *desc = @"Invalid System ID";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
            *error = [NSError errorWithDomain:ERROR_DOMAIN
                                         code:InRideErrorCodeInvalidSystemId
                                     userInfo:userInfo];
        }
        result.success = false;
        result.commandKey = 0;
        return result;
    }
    const uint8_t *sysIdBytes = systemId.bytes;
    int sysidx1 = (sysIdBytes[3] & 0xFF) % 6;
    int sysidx2 = (sysIdBytes[5] & 0xFF) % 6;
    result.success = true;
    result.commandKey = sysIdBytes[sysidx1] | (sysIdBytes[sysidx2] << 8);
    return result;
}

+ (BOOL)validateSystemId:(NSData *)systemId error:(NSError * __autoreleasing *)error
{
    if (systemId == nil || systemId.length != 6) {
        if (error != nil) {
            NSString *desc = @"Invalid System ID";
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
            *error = [NSError errorWithDomain:ERROR_DOMAIN
                                         code:InRideErrorCodeInvalidSystemId
                                     userInfo:userInfo];
        }
        return false;
    }
    return true;
}

+ (NSString *)systemIdToString:(NSData *)systemId
{
    return [KineticSDK systemIdToString:systemId];
}

@end

//+ (void)setCadenceRollingParams:(NSUInteger)bufferSize weight:(NSUInteger)weight;
