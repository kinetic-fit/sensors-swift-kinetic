//
//  KineticSDK
//

#import <Foundation/Foundation.h>

/*! UUID for the Power Service of the Kinetic Smart Control RU */
extern NSString * _Nonnull const KineticControlPowerServiceUUID;

/*! UUID for the Power Characteristic of the Kinetic Smart Control RU. Broadcasts Power Data. */
extern NSString * _Nonnull const KineticControlPowerServicePowerUUID;

/*! UUID for the Configuration Characteristic of the Kinetic Smart Control RU. Broadcasts Config Data. */
extern NSString * _Nonnull const KineticControlPowerServiceConfigUUID;

/*! UUID for the Control Point Characteristic of the Kinetic Smart Control RU */
extern NSString * _Nonnull const KineticControlPowerServiceControlPointUUID;

/*! UUID for the Control Point Characteristic of the Kinetic Smart Control RU. Broadcasts Debug Data. */
extern NSString * _Nonnull const KineticControlPowerServiceDebugUUID;

/*! UUID for the Device Information Service (0x180A) of the Kinetic Smart Control RU */
extern NSString * _Nonnull const KineticControlDeviceInformationUUID;

/*! UUID for the System ID (0x2A23) of the Kinetic Smart Control RU */
extern NSString * _Nonnull const KineticControlDeviceInformationSystemIDUUID;

/*! UUID for the Firmware Version String (0x2A26) of the Kinetic Smart Control RU */
extern NSString * _Nonnull const KineticControlDeviceInformationFirmwareRevisionUUID;


/*! Smart Control Resistance Mode */
typedef NS_ENUM (uint8_t, KineticControlMode)
{
    KineticControlModeERG        = 0x00,
    KineticControlModeFluid      = 0x01,
    KineticControlModeBrake      = 0x02,
    KineticControlModeSimulation = 0x03,
};


/*! Smart Control Calibration State */
typedef NS_ENUM (uint8_t, KineticControlCalibrationState)
{
    KineticControlCalibrationStateNotPerformed      = 0,
    KineticControlCalibrationStateInitializing      = 1,
    KineticControlCalibrationStateSpeedUp           = 2,
    KineticControlCalibrationStateStartCoasting     = 3,
    KineticControlCalibrationStateCoasting          = 4,
    KineticControlCalibrationStateSpeedUpDetected   = 5,
    KineticControlCalibrationStateComplete          = 10,
};


/*! Smart Control Power Data */
@interface KineticControlPowerData: NSObject

/*! Timestamp of when this data was processed */
@property (readonly) double timestamp;

/*! Current Resistance Mode */
@property (readonly) KineticControlMode mode;

/*! Current Power (Watts) */
@property (readonly) uint16_t power;

/*! Current Speed (KPH) */
@property (readonly) double speedKPH;

/*! Current Cadence (Virtual RPM) */
@property (readonly) uint8_t cadenceRPM;

/*! Current wattage the RU is Targetting */
@property (readonly) uint16_t targetResistance;

@end


/*! Smart Control Configuration Data */
@interface KineticControlConfigData: NSObject

/*! Power Data Update Rate (Hz) */
@property (readonly) uint8_t updateRate;

/*! Current Calibration State of the RU */
@property (readonly) KineticControlCalibrationState calibrationState;

/*! Current Spindown Time being applied to the Power Data */
@property (readonly) double spindownTime;

/*! Calibration Speed Threshold (KPH) */
@property (readonly) double calibrationThresholdKPH;

/*! Normalized Brake Strength calculated by a Brake Calibration */
@property (readonly) uint8_t brakeStrength;

/*! Normalized Brake Offset calculated by a Brake Calibration */
@property (readonly) uint8_t brakeOffset;

/*! Brake Calibration Speed Threshold (KPH) */
@property (readonly) double brakeCalibrationThresholdKPH;

@end

/*! Smart Control static Serialization and Deserialization Interface */
@interface KineticControl: NSObject


/*!
 Deserialize the raw power data (bytes) broadcast by Smart Control.
 
 @param data The raw data broadcast from the [Power Service -> Power] Characteristic
 @param systemId The system Id of the RU read from the [Device Information -> System ID] Characteristic
 @param error Throws error if API is not initialized or invalid parameters
 
 @return Smart Control Power Data Object
 */
+ (KineticControlPowerData * _Nullable)processData:(NSData * _Nonnull)data systemId:(NSData * _Nonnull)systemId error:(NSError * _Nullable * _Nullable)error;


/*!
 Deserialize the raw config data (bytes) broadcast by Smart Control.
 
 @param data The raw data broadcast from the [Power Service -> Config] Characteristic
 @param error Throws error if API is not initialized or invalid parameters
 
 @return Smart Control Config Data Object
 */
+ (KineticControlConfigData * _Nullable)processConfig:(NSData * _Nonnull)data error:(NSError * _Nullable * _Nullable)error;


/*!
 Creates the Command to put the Resistance Unit into ERG mode with a target wattage.
 
 @param targetWatts The target wattage the RU should try to maintain by adjusting the brake position
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)setResistanceERG:(uint16_t)targetWatts error:(NSError * _Nullable * _Nullable)error;


/*!
 Creates the Command to put the Resistance Unit into a "Fluid" mode, mimicking a fluid trainer.
 This mode is a simplified interface for the Simulation Mode, where:
    Rider + Bike weight is 85kg
    Rolling Coeff is 0.004
    Wind Resistance is 0.60
    Grade is equal to the "level" parameter
    Wind Speed is 0.0
 
 @param level Difficulty level (0-9) the RU should apply (simulated grade %)
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)setResistanceFluid:(uint8_t)level error:(NSError * _Nullable * _Nullable)error;


/*!
 Creates the Command to put the Resistance Unit Brake at a specific position (as a percent).
 
 @param percent Percent (0-1) of brake resistance to apply.
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)setResistanceBrake:(float)percent error:(NSError * _Nullable * _Nullable)error;



/*!
 Creates the Command to put the Resistance Unit into Simulation mode.
 
 @param weightKG Weight of Rider and Bike in Kilograms (kg)
 @param rollingCoeff Rolling Resistance Coefficient (0.004 for asphault)
 @param windCoeff Wind Resistance Coeffienct (0.6 default)
 @param grade Grade (-45 to 45) of simulated hill
 @param windSpeedMPS Head or Tail wind speed (meters / second)
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)setSimulationWeight:(float)weightKG
                        rollingResistance:(float)rollingCoeff
                           windResistance:(float)windCoeff
                                    grade:(float)grade
                             windSpeedMPS:(float)windSpeedMPS
                                    error:(NSError * _Nullable * _Nullable)error;


/*!
 Creates the Command to start the Calibration Process.
 
 @param brakeCalibration Calibrates the brake (only needs to be done once, result is stored on unit)
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)startCalibration:(bool)brakeCalibration error:(NSError * _Nullable * _Nullable)error;


/*!
 Creates the Command to stop the Calibration Process.
 This is not necessary if the calibration process is allowed to complete.
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)stopCalibration:(NSError * _Nullable * _Nullable)error;


/*!
 Creates the Command to set a custom name in the Advertisement Data.
 
 @param deviceName The new name for the sensor.
 
 @return Write this NSData to the Control Point Characteristic (w/ response)
 */
+ (NSData * _Nullable)setDeviceName:(NSString * _Nonnull)deviceName error:(NSError * _Nullable * _Nullable)error;

/*! Utility function to convert a Control System ID to a NSString */
+ (NSString * _Nonnull)systemIdToString:(NSData * _Nonnull)systemId;

@end




/*! Smart Control USB Vendor Id */
extern uint16_t const KineticControlUSBVendorId;

/*! Smart Control USB Product Id */
extern uint16_t const KineticControlUSBProductId;

/*! Smart Control USB Characterisic Identifier */
typedef NS_ENUM (uint16_t, KineticControlUSBCharacteristic)
{
    KineticControlUSBCharacteristicDeviceName           = 0x2A00,
    KineticControlUSBCharacteristicAppearance           = 0x2A01,
    KineticControlUSBCharacteristicSystemID             = 0x2A23,
    KineticControlUSBCharacteristicModelNumber          = 0x2A24,
    KineticControlUSBCharacteristicFirmwareVer          = 0x2A26,
    KineticControlUSBCharacteristicHardwareRev          = 0x2A27,
    KineticControlUSBCharacteristicManufacturer         = 0x2A29,
    KineticControlUSBCharacteristicFtmsFeature          = 0x2ACC,
    KineticControlUSBCharacteristicFtmsControl          = 0x2AD9,
    KineticControlUSBCharacteristicFtmsStatus           = 0x2ADA,
    KineticControlUSBCharacteristicFtmsTrainingStatus   = 0x2AD3,
    KineticControlUSBCharacteristicFtmsBikeData         = 0x2AD2,
    KineticControlUSBCharacteristicFtmsResistanceRange  = 0x2AD6,
    KineticControlUSBCharacteristicFtmsPowerRange       = 0x2AD8,
    KineticControlUSBCharacteristicPower                = 0x0201,
    KineticControlUSBCharacteristicConfig               = 0x0202,
    KineticControlUSBCharacteristicControlPoint         = 0x0203,
    KineticControlUSBCharacteristicDebug                = 0x0204,
    KineticControlUSBCharacteristicConfig2              = 0x0301,
    KineticControlUSBCharacteristicControl2             = 0x0302,
    KineticControlUSBCharacteristicDebug2               = 0x0303,
    KineticControlUSBCharacteristicWeight2              = 0x0304,
    KineticControlUSBCharacteristicStream               = 0x0342,
};

/*! Smart Control USB Packet */
@interface KineticControlUSBPacket: NSObject

/*! Characteristic Identifier of the data source */
@property (readonly) KineticControlUSBCharacteristic identifier;

/*! Packet Type Bitmask (Request | Data) */
@property (readonly) uint8_t type;

/*! Characteristic Packet Data (up to 20 bytes). Presence indicated in type bitmask. */
@property (readonly) NSData * _Nullable data;

@end


/*! Smart Control static USB Serialization and Deserialization Interface */
@interface KineticControl (USB)

/*!
 Create a USB Packet to write to the system serial USB device.
 
 @param read Request Smart Control to send the data of non-broadcast Characteristic
 @param write Indicate that the packet contains data to write to the specific Characteristic
 @param identifier The Characteristic Identifier to Read / Write to
 @param data The data to write to the Characteristic (if indicated)
 
 @return The data packet to write to the serial USB device
 */
+ (NSData * _Nonnull)usbRequestRead:(BOOL)read write:(BOOL)write characteristic:(KineticControlUSBCharacteristic)identifier data:(NSData * _Nullable)data;

/*!
 Deserialize a chunk of bytes from the serial USB device into an array of USB Packets which can be further processed.
 
 @param data The raw byte bundle recieved from the USB serial device
 
 @return An array of USB Packets.
 */
+ (NSArray<KineticControlUSBPacket *> * _Nonnull)usbProcessData:(NSData * _Nonnull)data;

@end




@interface KineticControlDebugData: NSObject
@property (readonly) float targetPosition;
@property (readonly) float position;
@property (readonly) int16_t tempSensor;
@property (readonly) float tempDie;
@property (readonly) uint32_t temperature;
@property (readonly) int16_t homeAccuracy;
@property (readonly) int16_t encoder;
@property (readonly) uint16_t bleBuild;
@end


/*! Smart Control Firmware Update State */
typedef NS_ENUM (uint8_t, KineticControlFirmwareUpdateState)
{
    KineticControlFirmwareUpdateStateIdle       = 0x00,
    KineticControlFirmwareUpdateStateUpdating   = 0x40,
    KineticControlFirmwareUpdateStateOOO        = 0x80,
    KineticControlFirmwareUpdateStateFailed     = 0xC0,
};
