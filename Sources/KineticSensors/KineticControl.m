//
//  KineticSDK
//

#import "KineticControl.h"
#import "KineticConstants.h"
//#import "KineticControl_Private.h"
#import "SmartControl.h"
#import "KineticSDK.h"

NSString * const KineticControlPowerServiceUUID = @"E9410200-B434-446B-B5CC-36592FC4C724";
NSString * const KineticControlPowerServicePowerUUID = @"E9410201-B434-446B-B5CC-36592FC4C724";
NSString * const KineticControlPowerServiceConfigUUID = @"E9410202-B434-446B-B5CC-36592FC4C724";
NSString * const KineticControlPowerServiceControlPointUUID = @"E9410203-B434-446B-B5CC-36592FC4C724";
NSString * const KineticControlPowerServiceDebugUUID = @"E9410204-B434-446B-B5CC-36592FC4C724";
NSString * const KineticControlDeviceInformationUUID = @"180A";
NSString * const KineticControlDeviceInformationSystemIDUUID = @"2A23";
NSString * const KineticControlDeviceInformationFirmwareRevisionUUID = @"2A26";

uint16_t const KineticControlUSBVendorId   = 0x085B;

/*! Smart Control USB Product Id */
uint16_t const KineticControlUSBProductId  = 0x0500;

enum {
    CTRL_SET_PERFORMANCE        = 0x00,
    CTRL_FIRMWARE               = 0x01,
    CTRL_MOTOR_SPEED            = 0x02,
    CTRL_SPINDOWN_CALIBRATION   = 0x03,
    CTRL_SET_NOISE_FILTER       = 0x04,
    CTRL_SET_BRAKE_STRENGTH     = 0x05,
    CTRL_SET_BRAKE_OFFSET       = 0x06,
    CTRL_SET_UPDATE_RATE        = 0x07,
    CTRL_GO_HOME                = 0x08,
    CTRL_SET_NAME               = 0x09,
    CTRL_SET_HARDWARE_REV       = 0x0A,
    CTRL_GET_BLE_REV            = 0x0B,
} ControlType;

typedef NS_ENUM (NSInteger, KineticControlErrorCode)
{
    ControlErrorCodeInvalidData = 301,
};

#define SensorHz                10000


@interface KineticControlPowerData ()
@property double timestamp;
@property KineticControlMode mode;
@property uint16_t power;
@property double speedKPH;
@property uint8_t cadenceRPM;
@property uint16_t targetResistance;
@end

@implementation KineticControlPowerData
@end


@interface KineticControlUSBPacket ()
@property KineticControlUSBCharacteristic identifier;
@property uint8_t type;
@property NSData *data;
@end

@implementation KineticControlUSBPacket
@end

@interface KineticControlConfigData ()
@property uint8_t updateRate;
@property KineticControlCalibrationState calibrationState;
@property double calibrationThresholdKPH;
@property double spindownTime;
@property uint8_t brakeStrength;
@property uint8_t brakeOffset;
@property double brakeCalibrationThresholdKPH;

// Private
@property uint32_t tickRate;
@property KineticControlFirmwareUpdateState firmwareUpdateState;
@property uint8_t firmwareUpdateExpectedPacket;
@property uint16_t systemStatus;
@property uint8_t noiseFilter;
@end

@implementation KineticControlConfigData
@end

@interface KineticControlDebugData ()
@property float targetPosition;
@property float position;
@property int16_t tempSensor;
@property float tempDie;
@property uint32_t temperature;
@property int16_t homeAccuracy;
@property int16_t encoder;
@property uint16_t bleBuild;
@end

@implementation KineticControlDebugData
@end


@implementation KineticControl

////////////////////////////////////
// C Library Wrappers
////////////////////////////////////

+ (KineticControlPowerData * _Nullable)processData:(NSData * _Nonnull)data systemId:(NSData * _Nonnull)systemId error:(NSError * _Nullable * _Nullable)error
{
    if (data.length >= 14) {
        KineticControlPowerData *powerData = [[KineticControlPowerData alloc] init];
        powerData.timestamp = [[NSDate date] timeIntervalSince1970];
        
        smart_control_power_data cData = smart_control_process_power_data((uint8_t *)data.bytes, data.length);
        powerData.mode = (KineticControlMode)cData.mode;
        powerData.targetResistance = cData.targetResistance;
        powerData.power = cData.power;
        powerData.cadenceRPM = cData.cadenceRPM;
        powerData.speedKPH = cData.speedKPH;
        
        return powerData;
    }
    
    if (error != nil) {
        NSString *desc = @"Invalid Power Data";
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
        *error = [NSError errorWithDomain:ERROR_DOMAIN code:ControlErrorCodeInvalidData userInfo:userInfo];
    }
    return nil;
}

+ (KineticControlConfigData * _Nullable)processConfig:(NSData *)data error:(NSError * _Nullable * _Nullable)error
{
    if (data.length >= 5) {
        KineticControlConfigData *configData = [[KineticControlConfigData alloc] init];
        
        smart_control_config_data cData = smart_control_process_config_data((uint8_t *)data.bytes, data.length);
        
        configData.updateRate = cData.updateRate;
        configData.tickRate = cData.tickRate;
        configData.firmwareUpdateState = (KineticControlFirmwareUpdateState)(cData.firmwareUpdateState & 0xC0);
        configData.firmwareUpdateExpectedPacket = (cData.firmwareUpdateState & 0x3F);
        configData.systemStatus = cData.systemStatus;
        configData.calibrationState = (KineticControlCalibrationState)cData.calibrationState;
        configData.spindownTime = cData.spindownTime;
        configData.calibrationThresholdKPH = cData.calibrationThresholdKPH;
        configData.brakeCalibrationThresholdKPH = cData.brakeCalibrationThresholdKPH;
        configData.brakeStrength = cData.brakeStrength;
        configData.brakeOffset = cData.brakeOffset;
        configData.noiseFilter = cData.noiseFilter;
        
        return configData;
    }
    if (error != nil) {
        NSString *desc = @"Invalid Config Data";
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
        *error = [NSError errorWithDomain:ERROR_DOMAIN code:ControlErrorCodeInvalidData userInfo:userInfo];
    }
    return nil;
}


+ (NSData *)setResistanceERG:(uint16_t)targetWatts error:(NSError *__autoreleasing  _Nullable *)error
{
    smart_control_set_mode_erg_data command = smart_control_set_mode_erg_command(targetWatts);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}


+ (NSData *)setResistanceFluid:(uint8_t)level error:(NSError *__autoreleasing  _Nullable *)error
{
    smart_control_set_mode_fluid_data command = smart_control_set_mode_fluid_command(level);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (NSData *)setResistanceBrake:(float)percent error:(NSError *__autoreleasing  _Nullable *)error
{
    smart_control_set_mode_brake_data command = smart_control_set_mode_brake_command(percent);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}


+ (NSData *)setSimulationWeight:(float)weightKG
              rollingResistance:(float)rollingCoeff
                 windResistance:(float)windCoeff
                          grade:(float)grade
                   windSpeedMPS:(float)windSpeedMPS
                          error:(NSError *__autoreleasing  _Nullable *)error
{
    smart_control_set_mode_simulation_data command = smart_control_set_mode_simulation_command(weightKG, rollingCoeff, windCoeff, grade, windSpeedMPS);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}


+ (NSData *)startCalibration:(bool)brakeCalibration error:(NSError *__autoreleasing  _Nullable *)error
{
    smart_control_calibration_command_data command = smart_control_start_calibration_command(brakeCalibration);
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (NSData *)stopCalibration:(NSError *__autoreleasing  _Nullable *)error
{
    smart_control_calibration_command_data command = smart_control_stop_calibration_command();
    return [NSData dataWithBytes:&command length:sizeof(command)];
}

+ (NSData * _Nullable)setDeviceName:(NSString * _Nonnull)deviceName error:(NSError * _Nullable * _Nullable)error
{
    NSUInteger nameLength = MIN(deviceName.length, 18);
    
    uint8_t writeData[2 + nameLength];
    writeData[0] = CTRL_SET_NAME;
    NSData * nameData = [deviceName dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    uint8_t * nameBytes = (uint8_t *)nameData.bytes;
    for (NSUInteger i = 0; i < nameLength; i++) {
        writeData[1 + i] = nameBytes[i];
    }
    writeData[1 + nameLength] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 2 + nameLength;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}


////////////////////////////////////
// Objective C Internal Methods
////////////////////////////////////

+ (NSString *)systemIdToString:(NSData *)systemId
{
    return [KineticSDK systemIdToString:systemId];
}

+ (NSData * _Nullable)firmwareUpdateChunk:(NSData *)firmware position:(NSInteger *)position systemId:(NSData * _Nullable)systemId
{
    if (firmware != nil) {
        if (firmware.length >= 0xFC00) {
            return nil;
        }
        uint16_t pos = *position;
        NSInteger payloadSize = MIN(17, firmware.length - pos);
        
        uint8_t writeData[20];
        writeData[0] = CTRL_FIRMWARE;
        
        uint8_t packetNum = (pos == 0) ? 0x80 : ((pos/17) & 0x3F);    // high bit indicates the start of the firmware update, bit 6 is reserved, and the low 6 bits are a packet sequence number
        writeData[1] = packetNum;
        
        for (NSInteger index = 0; index < payloadSize; index++, pos++) {
            writeData[index + 2] = ((const uint8_t*)[firmware bytes])[pos];
        }
        
        writeData[payloadSize + 2] = arc4random_uniform(0x100);                   // nonce
        // Obfustate Packet
        uint8_t hashSeed = 0x42;
        // if the systemId is passed in (only on pre 1024), use the sysId as the hash seed
        if (systemId != nil) {
            hashSeed = [self hash8WithSeed:0 data:systemId.bytes length:systemId.length];
        }
        uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[payloadSize + 2] length:1];
        for (unsigned index = 0; index < payloadSize + 2; index++) {
            uint8_t temp = writeData[index];
            writeData[index] ^= hash;
            hash = [self hash8WithSeed:hash data:&temp length:1];
        }
        *position = pos;
        return [NSData dataWithBytes:writeData length:payloadSize + 3];
    }
    return nil;
}

// CRC-8, using x^8 + x^2 + x + 1 polynomial.
+ (uint8_t)hash8WithSeed:(uint8_t)hash data:(const uint8_t *)buffer length:(uint8_t)length
{
    const uint8_t crc8_table[256] = {
        0x00, 0x91, 0xe3, 0x72, 0x07, 0x96, 0xe4, 0x75,
        0x0e, 0x9f, 0xed, 0x7c, 0x09, 0x98, 0xea, 0x7b,
        0x1c, 0x8d, 0xff, 0x6e, 0x1b, 0x8a, 0xf8, 0x69,
        0x12, 0x83, 0xf1, 0x60, 0x15, 0x84, 0xf6, 0x67,
        0x38, 0xa9, 0xdb, 0x4a, 0x3f, 0xae, 0xdc, 0x4d,
        0x36, 0xa7, 0xd5, 0x44, 0x31, 0xa0, 0xd2, 0x43,
        0x24, 0xb5, 0xc7, 0x56, 0x23, 0xb2, 0xc0, 0x51,
        0x2a, 0xbb, 0xc9, 0x58, 0x2d, 0xbc, 0xce, 0x5f,
        0x70, 0xe1, 0x93, 0x02, 0x77, 0xe6, 0x94, 0x05,
        0x7e, 0xef, 0x9d, 0x0c, 0x79, 0xe8, 0x9a, 0x0b,
        0x6c, 0xfd, 0x8f, 0x1e, 0x6b, 0xfa, 0x88, 0x19,
        0x62, 0xf3, 0x81, 0x10, 0x65, 0xf4, 0x86, 0x17,
        0x48, 0xd9, 0xab, 0x3a, 0x4f, 0xde, 0xac, 0x3d,
        0x46, 0xd7, 0xa5, 0x34, 0x41, 0xd0, 0xa2, 0x33,
        0x54, 0xc5, 0xb7, 0x26, 0x53, 0xc2, 0xb0, 0x21,
        0x5a, 0xcb, 0xb9, 0x28, 0x5d, 0xcc, 0xbe, 0x2f,
        0xe0, 0x71, 0x03, 0x92, 0xe7, 0x76, 0x04, 0x95,
        0xee, 0x7f, 0x0d, 0x9c, 0xe9, 0x78, 0x0a, 0x9b,
        0xfc, 0x6d, 0x1f, 0x8e, 0xfb, 0x6a, 0x18, 0x89,
        0xf2, 0x63, 0x11, 0x80, 0xf5, 0x64, 0x16, 0x87,
        0xd8, 0x49, 0x3b, 0xaa, 0xdf, 0x4e, 0x3c, 0xad,
        0xd6, 0x47, 0x35, 0xa4, 0xd1, 0x40, 0x32, 0xa3,
        0xc4, 0x55, 0x27, 0xb6, 0xc3, 0x52, 0x20, 0xb1,
        0xca, 0x5b, 0x29, 0xb8, 0xcd, 0x5c, 0x2e, 0xbf,
        0x90, 0x01, 0x73, 0xe2, 0x97, 0x06, 0x74, 0xe5,
        0x9e, 0x0f, 0x7d, 0xec, 0x99, 0x08, 0x7a, 0xeb,
        0x8c, 0x1d, 0x6f, 0xfe, 0x8b, 0x1a, 0x68, 0xf9,
        0x82, 0x13, 0x61, 0xf0, 0x85, 0x14, 0x66, 0xf7,
        0xa8, 0x39, 0x4b, 0xda, 0xaf, 0x3e, 0x4c, 0xdd,
        0xa6, 0x37, 0x45, 0xd4, 0xa1, 0x30, 0x42, 0xd3,
        0xb4, 0x25, 0x57, 0xc6, 0xb3, 0x22, 0x50, 0xc1,
        0xba, 0x2b, 0x59, 0xc8, 0xbd, 0x2c, 0x5e, 0xcf
    };
    
    for (uint8_t byte_index = 0; byte_index < length; byte_index++) {
        hash = crc8_table[hash ^ buffer[byte_index]];
    }
    return hash;
}

+ (uint8_t)crc8WithSeed:(uint8_t)crc data:(const uint8_t *)buffer length:(uint8_t)length
{
    return [self hash8WithSeed:crc ^ 0xFF data:buffer length:length] ^ 0xFF;
}



////////////////////////////////////
// Objective C USB Methods
////////////////////////////////////

#define UET_DELIMITER  0xE5
#define UET_ESCAPE     0xE6
#define UET_ESCAPE_XOR 0x80

+ (NSData *)usbRequestRead:(BOOL)read write:(BOOL)write characteristic:(KineticControlUSBCharacteristic)identifier data:(NSData *)data
{
    NSMutableData *crcPacket = [NSMutableData data];
    uint16_t uuidSwapped = CFSwapInt16(identifier);
    [crcPacket appendBytes:&uuidSwapped length:2];
    uint8_t type = 0x00;
    if (read) {
        type |= 0x01;
    }
    if (write) {
        type |= 0x02;
    }
    [crcPacket appendBytes:&type length:1];
    if (data) {
        [crcPacket appendData:data];
    }
    
    uint8_t crc = [self crc8WithSeed:0 data:crcPacket.bytes length:crcPacket.length];
    [crcPacket appendBytes:&crc length:1];
    
    // escape payload
    NSData *usbData = [self usbEscapeData:crcPacket];
    
    uint8_t delimiter = 0xe5;
    NSMutableData *packet = [NSMutableData dataWithBytes:&delimiter length:1];
    [packet appendData:usbData];
    [packet appendBytes:&delimiter length:1];
    
    
    return packet;
}

+ (NSData *)usbEscapeData:(NSData *)data
{
    uint8_t outBuf[50];
    uint8_t outSize = 0;
    uint8_t crc = 0;
    uint8_t *bytes = (uint8_t *)data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        uint8_t tmp_b = bytes[i];
        crc = [self crc8WithSeed:crc data:&tmp_b length:1];
        if ((tmp_b == UET_DELIMITER) || (tmp_b == UET_ESCAPE)) {
            outBuf[outSize++] = UET_ESCAPE;
            outBuf[outSize++] = tmp_b ^ UET_ESCAPE_XOR;
        } else {
            outBuf[outSize++] = tmp_b;
        }
    }
    return [NSData dataWithBytes:&outBuf length:outSize];
}

+ (NSArray<KineticControlUSBPacket *> *)usbProcessData:(NSData *)data
{
    NSMutableArray<KineticControlUSBPacket *> *packets = [NSMutableArray array];
    
    const uint8_t *inBuf = data.bytes;
    NSUInteger inSize = data.length;
    uint8_t rxPacket[24];
    uint8_t rxPacketLen = 0;
    BOOL rxLastByteWasEscape = false;
    
    for (NSUInteger index = 0; index < inSize; index++) {
        if ((rxPacketLen == sizeof(rxPacket)) && ((rxLastByteWasEscape) || (inBuf[index] != UET_DELIMITER))) {
            rxPacketLen = 0;			// The packet in rxPacket is too long.  It must be invalid.
            rxLastByteWasEscape = false;
            do {						// throw away everything up to the next delimiter
                index++;
            } while ((index < inSize) && (inBuf[index] != UET_DELIMITER));
            if (index >= inSize) {
                break;
            }
        }
        if (rxLastByteWasEscape) {
            rxPacket[rxPacketLen++] = inBuf[index] ^ UET_ESCAPE_XOR;
            rxLastByteWasEscape = false;
        }
        else {
            switch (inBuf[index]) {
                case UET_DELIMITER:
                    if (rxPacketLen >= 4) {			// back-to-back delimiters are common (length = 0)
                        if ([self crc8WithSeed:0 data:rxPacket length:rxPacketLen - 1] == rxPacket[rxPacketLen - 1]) {
                            uint16_t characteristic = ((uint16_t)rxPacket[0] << 8) | (uint16_t)rxPacket[1];
                            KineticControlUSBPacket *packet = [[KineticControlUSBPacket alloc] init];
                            packet.identifier = characteristic;
                            packet.type = rxPacket[2];
                            packet.data = [NSData dataWithBytes: &rxPacket[3] length:rxPacketLen - 4];
                            [packets addObject:packet];
                        }
                    }
                    rxPacketLen = 0;
                    break;
                    
                case UET_ESCAPE:
                    rxLastByteWasEscape = true;
                    break;
                    
                default:
                    rxPacket[rxPacketLen++] = inBuf[index];
                    break;
            }
        }
    }
    return packets;
}






////////////////////////////////////
// Objective C Debug Methods
////////////////////////////////////

+ (KineticControlDebugData * _Nullable)processDebug:(NSData *)data error:(NSError * _Nullable * _Nullable)error
{
    if (data.length >= 13) {
        uint8_t hashSeed = 0x42;
        uint8_t inData[data.length];
        memcpy(inData, data.bytes, data.length);
        uint8_t hash = [self hash8WithSeed:hashSeed data:&inData[data.length-1] length:1];
        for (unsigned index = 0; index < (data.length-1); index++) {
            inData[index] ^= hash;
            hash = [self hash8WithSeed:hash data:&inData[index] length:1];
        }
        
        KineticControlDebugData *debugData = [[KineticControlDebugData alloc] init];
        
        uint16_t targetPosition = ((uint16_t)inData[0] << 8) | (uint16_t)inData[1];
        float targetPositionN = (float)targetPosition / 65535.f;
        debugData.targetPosition = targetPositionN;
        uint16_t actualPosition = ((uint16_t)inData[2] << 8) | (uint16_t)inData[3];
        float actualPositionN = (float)actualPosition / 65535.f;
        debugData.position = actualPositionN;
        debugData.tempSensor = ((int16_t)inData[4] << 8) | (int16_t)inData[5];
        debugData.tempDie = ((int16_t)inData[6] << 8) | (int16_t)inData[7];
        debugData.temperature = ((uint16_t)inData[8] << 8) | (uint16_t)inData[9];
        debugData.homeAccuracy = ((int16_t)inData[10] << 8) | (int16_t)inData[11];
        
        if (data.length >= 14) {
            debugData.bleBuild = ((uint16_t)inData[12] << 8) | (uint16_t)inData[13];
        }
        if (data.length >= 16) {
            debugData.encoder = ((int16_t)inData[14] << 8) | (int16_t)inData[15];
        }
        
        return debugData;
    }
    if (error != nil) {
        NSString *desc = @"Invalid Debug Data";
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : desc };
        *error = [NSError errorWithDomain:ERROR_DOMAIN code:ControlErrorCodeInvalidData userInfo:userInfo];
    }
    return nil;
}

+ (NSData *)setNoiseFilter:(uint8_t)strength error:(NSError *__autoreleasing  _Nullable *)error
{
    strength = MIN(strength, 10);
    
    uint8_t writeData[20];
    writeData[0] = CTRL_SET_NOISE_FILTER;
    writeData[1] = strength;
    writeData[2] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 3;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}

+ (NSData *)setBrakeOffset:(uint8_t)offset error:(NSError * __autoreleasing * _Nullable)error
{
    uint8_t writeData[20];
    writeData[0] = CTRL_SET_BRAKE_OFFSET;
    writeData[1] = offset;
    writeData[2] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 3;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}

+ (NSData *)setBrakeStrength:(uint8_t)strength error:(NSError * __autoreleasing * _Nullable)error
{
    uint8_t writeData[20];
    writeData[0] = CTRL_SET_BRAKE_STRENGTH;
    writeData[1] = strength;
    writeData[2] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 3;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}

+ (NSData *)setMotorSpeed:(uint16_t)speed error:(NSError * _Nullable * _Nullable)error
{
    uint8_t writeData[20];
    writeData[0] = CTRL_MOTOR_SPEED;
    writeData[1] = (uint16_t)speed >> 8;
    writeData[2] = (uint16_t)speed;
    writeData[3] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 4;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}
+ (NSData * _Nullable)setHardwareRev:(uint8_t)hardwareRev error:(NSError * _Nullable * _Nullable)error
{
    uint8_t writeData[20];
    writeData[0] = CTRL_SET_HARDWARE_REV;
    writeData[1] = hardwareRev;
    writeData[2] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 3;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}

+ (NSData *)testRange:(NSError * _Nullable * _Nullable)error
{
    uint8_t writeData[20];
    writeData[0] = CTRL_GO_HOME;
    writeData[1] = arc4random_uniform(0x100); // nonce
    uint8_t dataLength = 2;
    
    // Obfustate Packet
    uint8_t hashSeed = 0x42;
    uint8_t hash = [self hash8WithSeed:hashSeed data:&writeData[dataLength - 1] length:1];
    for (unsigned index = 0; index < dataLength - 1; index++) {
        uint8_t temp = writeData[index];
        writeData[index] ^= hash;
        hash = [self hash8WithSeed:hash data:&temp length:1];
    }
    
    return [NSData dataWithBytes:writeData length:dataLength];
}

@end
