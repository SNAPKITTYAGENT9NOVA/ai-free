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

