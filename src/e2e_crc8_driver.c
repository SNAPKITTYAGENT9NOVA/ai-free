/**
 * @file e2e_crc8_driver.c
 * @brief L0: Lightweight Embedded C E2E Checksum Driver (SAE J1850 CRC-8 + Alive Counter)
 * Conforms to ISO 26262 ASIL-D, AUTOSAR Profile 1.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define CRC8_SAE_J1850_POLY  0x1D
#define CRC8_INITIAL_VAL     0xFF
#define CRC8_FINAL_XOR       0xFF
#define ALIVE_COUNTER_MASK   0x0F

/**
 * @brief Compute CRC-8 according to SAE J1850 standard.
 * Poly = 0x1D (x^8 + x^4 + x^3 + x^2 + 1), Init = 0xFF, Final XOR = 0xFF.
 */
uint8_t calculate_crc8_sae_j1850(uint8_t data_id, const uint8_t *data, size_t length) {
    uint8_t crc = CRC8_INITIAL_VAL;
    
    /* Mix in Data ID first */
    crc ^= data_id;
    for (int b = 0; b < 8; b++) {
        if (crc & 0x80) {
            crc = (uint8_t)((crc << 1) ^ CRC8_SAE_J1850_POLY);
        } else {
            crc <<= 1;
        }
    }

    /* Mix in data bytes */
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            if (crc & 0x80) {
                crc = (uint8_t)((crc << 1) ^ CRC8_SAE_J1850_POLY);
            } else {
                crc <<= 1;
            }
        }
    }

    return crc ^ CRC8_FINAL_XOR;
}

/**
 * @brief Packs an 8-byte CAN frame with rolling alive counter and SAE J1850 CRC-8.
 * Format: [Byte 0: Alive Counter (0~15)] + [Bytes 1..6: 6-byte Payload] + [Byte 7: CRC-8]
 */
void pack_e2e_frame(uint8_t *frame_8bytes, uint8_t data_id, uint8_t alive_counter, const uint8_t *payload_6bytes) {
    frame_8bytes[0] = (uint8_t)(alive_counter & ALIVE_COUNTER_MASK);
    for (int i = 0; i < 6; i++) {
        frame_8bytes[1 + i] = payload_6bytes[i];
    }
    frame_8bytes[7] = calculate_crc8_sae_j1850(data_id, frame_8bytes, 7);
}

/**
 * @brief Validates an incoming 8-byte E2E protected CAN frame.
 * @return 0 on success, -1 on CRC error, -2 on sequence/alive mismatch.
 */
int validate_e2e_frame(const uint8_t *frame_8bytes, uint8_t data_id, uint8_t expected_alive) {
    uint8_t rx_alive = frame_8bytes[0] & ALIVE_COUNTER_MASK;
    uint8_t rx_crc = frame_8bytes[7];
    uint8_t expected_crc = calculate_crc8_sae_j1850(data_id, frame_8bytes, 7);

    if (rx_crc != expected_crc) {
        return -1; /* CRC Mismatch */
    }

    if (expected_alive <= ALIVE_COUNTER_MASK && rx_alive != expected_alive) {
        return -2; /* Alive Sequence Discontinuity / Out-of-order */
    }

    return 0; /* Verified Valid */
}

/* ========================================================================= */
/* MCU Standard SAE J1850 E2E Implementation & State Machine Receiver        */
/* ========================================================================= */

#define E2E_POLYNOMIAL 0x1D
#define E2E_INITIAL_CRC 0xFF
#define E2E_FINAL_XOR   0xFF

// 計算 CRC-8 (SAE J1850)
uint8_t E2E_CalculateCRC8(const uint8_t *data, uint8_t length) {
    uint8_t crc = E2E_INITIAL_CRC;
    for (uint8_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (uint8_t bit = 0; bit < 8; bit++) {
            if (crc & 0x80) {
                crc = (crc << 1) ^ E2E_POLYNOMIAL;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc ^ E2E_FINAL_XOR;
}

// 接收驗證狀態結構體
typedef struct {
    uint8_t expected_counter;
    uint8_t err_count;
    bool is_degraded;
    uint8_t consecutive_good;
} E2E_RxState_t;

// 封包格式：Byte 0 低 4-bit 為 Counter；Byte 7 為 CRC8
bool E2E_ValidateFrame(const uint8_t *payload, uint8_t dlc, E2E_RxState_t *state) {
    if (dlc != 8 || state == NULL) return false;

    uint8_t received_crc = payload[7];
    uint8_t calculated_crc = E2E_CalculateCRC8(payload, 7);

    if (received_crc != calculated_crc) {
        state->err_count++;
        state->consecutive_good = 0;
        if (state->err_count >= 3) state->is_degraded = true;
        return false;
    }

    uint8_t received_counter = payload[0] & 0x0F;
    if (received_counter != state->expected_counter) {
        state->err_count++;
        state->consecutive_good = 0;
        state->expected_counter = (received_counter + 1) & 0x0F;
        if (state->err_count >= 3) state->is_degraded = true;
        return false;
    }

    // 校驗成功
    state->err_count = 0;
    state->expected_counter = (received_counter + 1) & 0x0F;
    state->consecutive_good++;

    // 連續 10 幀 E2E 正確則自動切回 NORMAL
    if (state->consecutive_good >= 10) {
        state->is_degraded = false;
    }
    return true;
}

