//
//  inRide.h
//
//  Copyright © 2017 Kinetic. All rights reserved.
//

#ifndef inRide_h
#define inRide_h

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

static const char INRIDE_SERVICE_UUID[]         = "E9410100-B434-446B-B5CC-36592FC4C724";
static const char INRIDE_SERVICE_POWER_UUID[]   = "E9410101-B434-446B-B5CC-36592FC4C724";
static const char INRIDE_SERVICE_CONFIG_UUID[]  = "E9410104-B434-446B-B5CC-36592FC4C724";
static const char INRIDE_SERVICE_CONTROL_UUID[] = "E9410102-B434-446B-B5CC-36592FC4C724";

// The inRide also exposes Characteristics on the Device Information Service (0x180A)
// - FW Rev, HW Rev, Manufacturer Name, and System Id (!)
// - You will need the System ID value to de-obfuscate the power data and send the sensor commands (see below)


typedef enum inride_state
{
    INRIDE_STATE_NORMAL             = 0x00,
    INRIDE_STATE_SPINDOWN_IDLE      = 0x10,
    INRIDE_STATE_SPINDOWN_READY     = 0x20,
    INRIDE_STATE_SPINDOWN_ACTIVE    = 0x30
} inride_sensor_state;


typedef enum inride_calibration_result
{
    INRIDE_CAL_RESULT_UNKNOWN       = 0x00,
    INRIDE_CAL_RESULT_SUCCESS       = 0x01, // Calibration was successful as the spindown time fell between two ranges (normal and proflywheel)
    INRIDE_CAL_RESULT_TOO_FAST      = 0x02, // Spindown was way too fast. User needs to loosen the roller.
    INRIDE_CAL_RESULT_TOO_SLOW      = 0x03, // Spindown was way too slow. Uwer needs to tighten the roller.
    INRIDE_CAL_RESULT_MIDDLE        = 0x04  // Spindown was ambigious (too slow for normal, too fast for a pro flywheel). Tighten if no pro flywheel and loosen if the pro flywheel is present.
} inride_calibration_result;


// Use Command Results for debug purposes only. If 2 commands are sent in-between the power updates, command results would be lost (not guaranteed).
typedef enum inride_command_result
{
    INRIDE_COM_RESULT_NONE                  = 0x00,
    INRIDE_COM_RESULT_SUCCESS               = 0x01,
    INRIDE_COM_RESULT_NOT_SUPPORTED         = 0x02,
    INRIDE_COM_RESULT_INVALID_REQUEST       = 0x03,
    INRIDE_COM_RESULT_CALIBRATION_RESULT    = 0x0A,
    INRIDE_COM_RESULT_UNKNOWN_ERROR         = 0x0F
} inride_command_result;


// Update interval in 32Hz (the enum describes the update interval in milliseconds, the actual value is in 32hz)
// The fastest update that can be set while maintaing data integrity is 8hz. Do not try to set it faster.
typedef enum inride_update_rate
{
    INRIDE_UPDATE_RATE_1000     = 0x20, // 1 update every 32 cycles (once per second)
    INRIDE_UPDATE_RATE_500      = 0x10, // 1 update every 16 cycles (twice per second)
    INRIDE_UPDATE_RATE_250      = 0x08  // 1 update every 8 cycles (four per second)
} inride_update_rate;


// Most of this data is not relevant to the user.
typedef struct inride_config_data
{
    bool proFlywheel;               // the sensor intelligently detects the proflywheel based on the spindown time.
    double currentSpindownTime;     // 
    uint32_t calibrationReady;      // ignore and be careful when changing this unless you understand what the values are.
    uint32_t calibrationStart;      // ignore and be careful when changing this unless you understand what the values are.
    uint32_t calibrationEnd;        // ignore and be careful when changing this unless you understand what the values are.
    uint32_t calibrationDebounce;   // ignore and be careful when changing this unless you understand what the values are.
    uint32_t updateRateDefault;
    uint32_t updateRateCalibration; // 8hz is a good value here
} inride_config_data;

// The main show.
typedef struct inride_power_data
{
    inride_sensor_state state;
    int power;          // This values gets a little jumpy when done at 8hz update rate. Consider smoothing if doing updates that fast. Based on speed and tire resistance. Still improving.
    double speedKPH;    // This is accurate. Very accurate. FOR THE ROLLER. The Wheel speed may be slightly faster (unnoticeable) due to tire slippage on the roller.
    double rollerRPM;   // Wheel RPM can be derived using the Roller's Circumference of 169.328702435836 millimeters and the wheel circumference (variable).
    double cadenceRPM;  // This value is good, not great. Doing your own "smoothing" (cache / average the last 2 values) will "calm" this value down nicely.
    bool coasting;      // Based on acceleration. Better than good, still improving.
    inride_calibration_result calibrationResult;
    
    /*! Current Spindown Time being applied to the Power Calculation */
    double spindownTime;
    double lastSpindownResultTime;
    /*! Current resistance the roller is using for Power Calculations due to tire tension => Normalized spindownTime (0..1) */
    double rollerResistance;

    bool proFlywheel;
    inride_command_result commandResult;
} inride_power_data;


typedef struct inride_start_calibration_command
{
    uint16_t commandKey;
    uint8_t command;
} __attribute__((packed)) inride_start_calibration_command;

typedef struct inride_stop_calibration_command
{
    uint16_t commandKey;
    uint8_t command;
} __attribute__((packed)) inride_stop_calibration_command;

typedef struct inride_set_spindown_time_command
{
    uint16_t commandKey;
    uint8_t command;
    uint32_t spindown;
} __attribute__((packed)) inride_set_spindown_time_command;

typedef struct inride_config_sensor_command
{
    uint16_t commandKey;
    uint8_t command;
    uint16_t calReady;
    uint16_t calStart;
    uint16_t calEnd;
    uint16_t calDebounce;
    uint16_t updateRateDefault;
    uint16_t updateRateFast;
} __attribute__((packed)) inride_config_sensor_command;


// systemID parameter is the 6-byte value of the Device Info Service (0x180A) System Id Char (0x2A23)
// - it is tied to the MAC address of the BLE Nordic Chip
// - it is used in the de-obfuscation process of the power data as well as a "command key" for control point commands


inride_config_data inride_process_config_data(uint8_t data[20]);
inride_power_data inride_process_power_data(uint8_t data[20]);


// The command structs that are created are packed...
// Send the bytes to the Control Point (INRIDE_SERVICE_CONTROL_UUID) to configure the sensor and start / stop the calibration process

inride_config_sensor_command inride_create_config_sensor_command_data(inride_update_rate updateRate, uint8_t systemId[6]);
inride_start_calibration_command inride_create_start_calibration_command_data(uint8_t systemId[6]);
inride_stop_calibration_command inride_create_stop_calibration_command_data(uint8_t systemId[6]);
inride_set_spindown_time_command inride_create_set_spindown_time_command_data(double seconds, uint8_t systemId[6]);


#endif /* inRide_h */
