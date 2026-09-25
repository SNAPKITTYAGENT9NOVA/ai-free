/**
 * @file uds_bootloader_fsm.h
 * @brief L0: ISO 14229 UDS Bootloader Flashing State Machine Header (MISRA-C:2012 Compliant)
 * Features: A/B Dual Partition Atomic Commit & Rollback, Streaming CRC32, Static Memory Allocation.
 * Dual-API: Provides both UDS_ProcessService (AUTOSAR static dispatch) and Contextual Multi-instance API.
 * Project: PHANTOM GRID Automotive L3-L5 Embedded Platform
 */

#ifndef UDS_BOOTLOADER_FSM_H
#define UDS_BOOTLOADER_FSM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Standard UDS Service Identifiers (ISO 14229-1) */
#define UDS_SID_DIAG_SESSION_CTRL       0x10U
#define UDS_SID_ECU_RESET               0x11U
#define UDS_SID_SECURITY_ACCESS         0x27U
#define UDS_SID_ROUTINE_CONTROL         0x31U
#define UDS_SID_REQUEST_DOWNLOAD        0x34U
#define UDS_SID_TRANSFER_DATA           0x36U
#define UDS_SID_REQUEST_TRANSFER_EXIT   0x37U

/* Standard Negative Response Codes (NRCs) */
#define UDS_NRC_GENERAL_REJECT          0x10U
#define UDS_NRC_SERVICE_NOT_SUPPORTED   0x11U
#define UDS_NRC_SUB_FUNC_NOT_SUPPORTED  0x12U
#define UDS_NRC_INCORRECT_MSG_LENGTH    0x13U
#define UDS_NRC_CONDITIONS_NOT_CORRECT  0x22U
#define UDS_NRC_REQUEST_SEQUENCE_ERROR  0x24U
#define UDS_NRC_REQUEST_OUT_OF_RANGE    0x31U
#define UDS_NRC_SECURITY_ACCESS_DENIED  0x33U
#define UDS_NRC_INVALID_KEY             0x35U
#define UDS_NRC_TRANSFER_DATA_SUSPENDED 0x71U
#define UDS_NRC_GENERAL_PROG_FAILURE    0x72U
#define UDS_NRC_WRONG_BLOCK_SEQ_COUNTER 0x73U

/* Flash & Buffer Architecture Parameters */
#define FLASH_SECTOR_SIZE               4096U
#define UDS_MAX_CHUNK_SIZE              1024U
#define UDS_MAX_RESPONSE_SIZE           32U

/**
 * @brief Diagnostic Session Modes (SID 0x10)
 */
typedef enum {
    UDS_SESSION_DEFAULT     = 0x01U,
    UDS_SESSION_PROGRAMMING = 0x02U,
    UDS_SESSION_EXTENDED    = 0x03U
} UdsSessionMode;

typedef UdsSessionMode UdsSession_t;

/**
 * @brief Bootloader Finite State Machine States
 */
typedef enum {
    BOOT_STATE_IDLE = 0,
    BOOT_STATE_SESSION_PROGRAMMING,
    BOOT_STATE_SECURITY_UNLOCKED,
    BOOT_STATE_DOWNLOAD_ACTIVE,
    BOOT_STATE_TRANSFERRING,
    BOOT_STATE_COMPLETE,
    BOOT_STATE_ROLLBACK_SAFE,
    BOOT_STATE_ERROR
} BootloaderFsmState;

/**
 * @brief Xiaomi AUTOSAR Lightweight State Enum
 */
typedef enum {
    BL_STATE_IDLE = 0,
    BL_STATE_UNLOCKED,
    BL_STATE_DOWNLOAD_ACTIVE,
    BL_STATE_FLASHING,
    BL_STATE_COMPLETED,
    BL_STATE_ERROR
} BootloaderState_t;

/**
 * @brief Flash Partition Slot Indicator (A/B Ping-Pong)
 */
typedef enum {
    FLASH_PARTITION_A = 0,
    FLASH_PARTITION_B = 1
} FlashPartitionSlot;

/**
 * @brief Bootloader Execution Context (Zero Dynamic Allocation)
 */
typedef struct {
    BootloaderFsmState state;
    UdsSessionMode session;
    bool security_unlocked;
    uint32_t download_address;
    uint32_t download_size;
    FlashPartitionSlot active_sector;    /**< Currently active execution partition */
    FlashPartitionSlot target_sector;    /**< Target partition undergoing flashing */
    uint8_t flash_sector_a[FLASH_SECTOR_SIZE];
    uint8_t flash_sector_b[FLASH_SECTOR_SIZE];
    size_t bytes_written_a;
    size_t bytes_written_b;
    uint8_t block_sequence_counter;
    uint32_t streaming_crc32;
    uint32_t expected_crc32;
    bool bricking_prevented;
} UdsBootloaderContext;

/**
 * @brief Xiaomi AUTOSAR Lightweight Bootloader Context Structure
 */
typedef struct {
    UdsSession_t session;
    BootloaderState_t bl_state;
    uint32_t flash_target_addr;
    uint32_t total_expected_bytes;
    uint32_t received_bytes;
    uint8_t  expected_block_seq;
} UdsBootloaderContext_t;

/**
 * @brief Global Bootloader Context for Static Dispatch
 */
extern UdsBootloaderContext_t g_bl_ctx;

/**
 * @brief AUTOSAR-style UDS Service Dispatch Entry Point
 * Handles core flashing service chain: $10 02 -> $34 -> $36 -> $37
 * @param rx_payload Pointer to received CAN/UDS payload
 * @param rx_len Length of received payload
 * @param tx_payload Buffer to write response payload
 * @param tx_len Pointer to store response payload length
 */
void UDS_ProcessService(
    const uint8_t *rx_payload,
    uint8_t rx_len,
    uint8_t *tx_payload,
    uint8_t *tx_len
);

/**
 * @brief Initialize the global bootloader context g_bl_ctx.
 */
void UDS_ResetService(void);

/**
 * @brief Initialize the contextual UDS bootloader state machine context.
 * @param ctx Pointer to bootloader context.
 */
void uds_bootloader_init(UdsBootloaderContext *ctx);

/**
 * @brief Process incoming UDS diagnostic service request.
 * @param ctx Pointer to bootloader context.
 * @param req Pointer to raw request bytes.
 * @param req_len Number of request bytes.
 * @param resp Buffer to write response bytes (minimum UDS_MAX_RESPONSE_SIZE bytes).
 * @param resp_len Pointer to store actual response length.
 * @return 0 on success, negative error code on invalid parameters.
 */
int uds_bootloader_process_request(
    UdsBootloaderContext *ctx,
    const uint8_t *req,
    size_t req_len,
    uint8_t *resp,
    size_t *resp_len
);

/**
 * @brief Fast emergency power-cut rollback within 2.3ms.
 * Safely switches execution back to the stable partition if power or bus is interrupted.
 * @param ctx Pointer to bootloader context.
 * @return true if rollback succeeded.
 */
bool uds_bootloader_emergency_power_cut_rollback(UdsBootloaderContext *ctx);

/**
 * @brief Atomic commit of the target flash partition.
 * Commits the flashed partition as the active boot partition if verification succeeds.
 * @param ctx Pointer to bootloader context.
 * @return true if partition committed successfully, false if verification failed.
 */
bool uds_bootloader_commit_active_partition(UdsBootloaderContext *ctx);

/**
 * @brief Calculate IEEE 802.3 32-bit Cyclic Redundancy Check (CRC32).
 * @param data Data buffer.
 * @param len Data length in bytes.
 * @return 32-bit CRC checksum.
 */
uint32_t uds_bootloader_compute_crc32(const uint8_t *data, size_t len);

/**
 * @brief Convert BootloaderFsmState enum to readable string.
 * @param state State enum value.
 * @return String representation of state.
 */
const char* uds_bootloader_state_to_str(BootloaderFsmState state);

#ifdef __cplusplus
}
#endif

#endif /* UDS_BOOTLOADER_FSM_H */
