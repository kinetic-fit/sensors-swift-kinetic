//
//  inRide.c
//
//  Copyright © 2017 Kinetic. All rights reserved.
//

#include "inRide.h"

#define SensorHz                32768
#define SpindownMin             1.5
#define SpindownMinPro          4.7
#define SpindownMax             2.0
#define SpindownMaxPro          6.5
#define SpindownDefault         ((SpindownMin + SpindownMax) * 0.5)

bool inride_has_pro_flywheel(double spindown)
{
    return (spindown >= 4.7 && spindown <= 6.5);
}

double inride_speed_for_ticks(uint32_t ticks, uint8_t revs)
{
    if (ticks == 0 || revs <= 0) {
        return 0;
    }
    return (20012.256849 * ((double)revs)) / ((double)ticks);
}

double inride_ticks_to_seconds(uint32_t ticks)
{
    return ((double)ticks) / 32768.0;
}

typedef struct alpha_coast {
    double alpha;
    bool coasting;
} alpha_coast;

alpha_coast alpha(uint32_t interval, uint32_t ticks, uint32_t revs, double speedKPH, uint32_t ticksPrevious, uint32_t revsPrevious, double speedKPHPrevious, bool proFlywheel)
{
    alpha_coast result;
    result.alpha = 0.0;
    result.coasting = false;
    if (ticks > 0 && ticksPrevious > 0) {
        double tpr = ticks / (double)revs;
        double ptpr = ticksPrevious / (double)revsPrevious;
        double dtpr = tpr - ptpr;
        if (dtpr > 0) {
            double deltaSpeed = speedKPHPrevious - speedKPH;
            double alpha = deltaSpeed * dtpr;
            result.alpha = alpha;
            if (alpha > 200 && !proFlywheel) {
                result.coasting = true;
            } else if (alpha > 20 && proFlywheel) {
                result.coasting = true;
            }
        }
    }
    return result;
}

int power_for_speed(double kph, double spindown, double alpha, uint32_t revolutions)
{
    double mph = kph * 0.621371;
    double rawPower = (5.244820 * mph) + (0.019168 * (mph * mph * mph));
    double dragOffset = 0;
    if (spindown > 0 && rawPower > 0) {
        bool proFlywheel = inride_has_pro_flywheel(spindown);
        double spindownTimeMS = spindown * 1000.0;
        double dragOffsetSlope = proFlywheel ? -0.021 : -0.1425;
        double dragOffsetPowerSlope = proFlywheel ? 2.62 : 4.55;
        double yIntercept = proFlywheel ? 104.97 : 236.20;
        dragOffset = (dragOffsetPowerSlope * spindownTimeMS * rawPower * 0.00001) + (dragOffsetSlope * spindownTimeMS) + yIntercept;
    } else {
        dragOffset = 0;
    }
    double power = rawPower + dragOffset;
    if (power < 0) {
        power = 0;
    }
    return (int)power;
}


inride_calibration_result result_for_spindown(double time)
{
    inride_calibration_result result = INRIDE_CAL_RESULT_UNKNOWN;
    if (time >= 1.5 && time <= 2.0) {
        result = INRIDE_CAL_RESULT_SUCCESS;
    } else if (time >= 4.7 && time <= 6.5) {
        result = INRIDE_CAL_RESULT_SUCCESS;
    } else if (time < 1.5) {
        result = INRIDE_CAL_RESULT_TOO_FAST;
    } else if (time > 6.5) {
        result = INRIDE_CAL_RESULT_TOO_SLOW;
    } else {
        result = INRIDE_CAL_RESULT_MIDDLE;
    }
    return result;
}

inride_config_data inride_process_config_data(uint8_t data[20])
{
    inride_config_data configData;
    configData.calibrationReady = (uint16_t)data[0];
    configData.calibrationReady |= ((uint16_t)data[1] << 8);
    configData.calibrationStart = (uint16_t)data[2];
    configData.calibrationStart |= ((uint16_t)data[3] << 8);
    configData.calibrationEnd = (uint16_t)data[4];
    configData.calibrationEnd |= ((uint16_t)data[5] << 8);
    configData.calibrationDebounce = (uint16_t)data[6];
    configData.calibrationDebounce |= ((uint16_t)data[7] << 8);
    uint32_t currentSpindownTicks = (uint32_t)data[8];
    currentSpindownTicks |= ((uint32_t)data[9] << 8);
    currentSpindownTicks |= ((uint32_t)data[10] << 16);
    currentSpindownTicks |= ((uint32_t)data[11] << 24);
    configData.currentSpindownTime = ((double)currentSpindownTicks) / 32768.0;
    configData.updateRateDefault = (uint16_t)data[12];
    configData.updateRateDefault |= ((uint16_t)data[13] << 8);
    configData.updateRateCalibration = (uint16_t)data[14];
    configData.updateRateCalibration |= ((uint16_t)data[15] << 8);
    configData.proFlywheel = inride_has_pro_flywheel(configData.currentSpindownTime);
    return configData;
}

inride_power_data inride_process_power_data(uint8_t data[20])
{
    inride_power_data powerData;
    
    // deobfuscate the power data
    uint8_t i = 0;
    uint8_t deob[20];
    for (i = 0; i < 20; ++i) {
        deob[i] = data[i];
    }
    uint8_t posRotate = (data[0] & 0xC0) >> 6;
    uint8_t xorIdx1 = posRotate + 1;
    xorIdx1 %= 4;
    uint8_t xorIdx2 = xorIdx1 + 1;
    xorIdx2 %= 4;
    static uint8_t indices[4][19] = {
        {14,15,12,16,11,5,17,3,2,1,19,13,6,4,8,9,10,18,7},
        {12,14,8,11,16,4,7,13,18,1,3,19,6,15,9,5,10,17,2},
        {11,5,1,9,4,18,7,15,6,2,10,12,16,3,14,13,19,17,8},
        {13,5,18,1,3,12,15,10,14,19,16,8,6,11,2,9,4,17,7}
    };
    for (i = 1; i < 20; ++i) {
        deob[i] = deob[i] ^ (indices[xorIdx1][i - 1] + indices[xorIdx2][i - 1]);
    }
    uint8_t powerBytes[20];
    powerBytes[0] = deob[0];
    for (i = 0; i < 19; ++i) {
        powerBytes[i + 1] = deob[indices[posRotate][i]];
    }
    
    powerData.state = powerBytes[0] & 0x30;
    powerData.commandResult = powerBytes[0] & 0x0F;
    
    i = 1;
    uint32_t interval = ((uint32_t)powerBytes[i++]);
    interval |= ((uint32_t)powerBytes[i++]) << 8;
    interval |= ((uint32_t)powerBytes[i++]) << 16;
    
    uint32_t ticks = ((uint32_t)powerBytes[i++]);
    ticks |= ((uint32_t)powerBytes[i++]) << 8;
    ticks |= ((uint32_t)powerBytes[i++]) << 16;
    ticks |= ((uint32_t)powerBytes[i++]) << 24;
    
    uint8_t revs = powerBytes[i++];
    
    uint32_t ticksPrevious = ((uint32_t)powerBytes[i++]);
    ticksPrevious |= ((uint32_t)powerBytes[i++]) << 8;
    ticksPrevious |= ((uint32_t)powerBytes[i++]) << 16;
    ticksPrevious |= ((uint32_t)powerBytes[i++]) << 24;
    
    uint8_t revsPrevious = powerBytes[i++];
    
    uint16_t cadenceRaw = ((uint16_t)powerBytes[i++]);
    cadenceRaw |= ((uint16_t)powerBytes[i++]) << 8;
    powerData.cadenceRPM = cadenceRaw == 0 ? 0 : (0.8652 * ((double)cadenceRaw) + 5.2617);
    
    uint32_t spindownTicks = ((uint32_t)powerBytes[i++]);
    spindownTicks |= ((uint32_t)powerBytes[i++]) << 8;
    spindownTicks |= ((uint32_t)powerBytes[i++]) << 16;
    spindownTicks |= ((uint32_t)powerBytes[i++]) << 24;
    
    powerData.lastSpindownResultTime = inride_ticks_to_seconds(spindownTicks);
    powerData.speedKPH = inride_speed_for_ticks(ticks, revs);
    
    powerData.rollerRPM = 0.0;
    if (ticks > 0) {
        double seconds = inride_ticks_to_seconds(ticks);
        double rollerRPS = revs / seconds;
        powerData.rollerRPM = rollerRPS * 60;
    }
    
    double speedKPHPrev = inride_speed_for_ticks(ticksPrevious, revsPrevious);
    powerData.proFlywheel = false;
    
    powerData.spindownTime = SpindownDefault;
    if (powerData.lastSpindownResultTime >= SpindownMin && powerData.lastSpindownResultTime <= SpindownMax) {
        powerData.spindownTime = powerData.lastSpindownResultTime;
    } else if (powerData.lastSpindownResultTime >= SpindownMinPro && powerData.lastSpindownResultTime <= SpindownMaxPro) {
        powerData.spindownTime = powerData.lastSpindownResultTime;
        powerData.proFlywheel = true;
    }
    
    if (!powerData.proFlywheel) {
        powerData.rollerResistance = 1 - ((powerData.spindownTime - SpindownMin) / (SpindownMax - SpindownMin));
    } else {
        powerData.rollerResistance = 1 - ((powerData.spindownTime - SpindownMinPro) / (SpindownMaxPro - SpindownMinPro));
    }
    
    alpha_coast ac = alpha(interval, ticks, revs, powerData.speedKPH, ticksPrevious, revsPrevious, speedKPHPrev, powerData.proFlywheel);
    powerData.coasting = ac.coasting;
    
    if (powerData.coasting) {
        powerData.power = 0;
    } else {
        powerData.power = power_for_speed(powerData.speedKPH, powerData.spindownTime, ac.alpha, revs);
    }
    
    powerData.calibrationResult = result_for_spindown(powerData.lastSpindownResultTime);
    
    return powerData;
}

uint16_t command_key(uint8_t systemId[6])
{
    uint8_t sysidx1 = systemId[3] % 6;
    uint8_t sysidx2 = systemId[5] % 6;
    return ((uint16_t)systemId[sysidx1]) | (((uint16_t)(systemId[sysidx2])) << 8);
}

inride_config_sensor_command inride_create_config_sensor_command_data(inride_update_rate updateRate, uint8_t systemId[6])
{
    inride_config_sensor_command command;
    command.commandKey = command_key(systemId);
    command.command = 0x01;
    command.calReady = 602;
    command.calStart = 655;
    command.calEnd = 950;
    command.calDebounce = 327;
    command.updateRateDefault = updateRate;
    command.updateRateFast = INRIDE_UPDATE_RATE_250;
    return command;
}

inride_start_calibration_command inride_create_start_calibration_command_data(uint8_t systemId[6])
{
    inride_start_calibration_command command;
    command.commandKey = command_key(systemId);
    command.command = 0x03;
    return command;
}

inride_stop_calibration_command inride_create_stop_calibration_command_data(uint8_t systemId[6])
{
    inride_stop_calibration_command command;
    command.commandKey = command_key(systemId);
    command.command = 0x04;
    return command;
}

inride_set_spindown_time_command inride_create_set_spindown_time_command_data(double seconds, uint8_t systemId[6])
{
    inride_set_spindown_time_command command;
    command.commandKey = command_key(systemId);
    command.command = 0x05;
    command.spindown = (uint32_t)(seconds * 32768);
    return command;
}
