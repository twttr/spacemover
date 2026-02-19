#pragma once
#include <stdint.h>

#define SPACEMOVER_SOCKET_PATH "/tmp/com.twttr.spacemover.sock"
#define SM_PROTOCOL_VERSION 1

typedef struct __attribute__((packed)) {
    uint32_t version;
    uint32_t opcode;
    uint64_t spaceID;
    uint32_t targetDisplayIndex;
    uint32_t afterSpaceID;
    char     displayUUID[128];
} SMCommand;

typedef enum {
    SM_OP_MOVE_SPACE_TO_DISPLAY = 1,
    SM_OP_SET_CURRENT_SPACE = 3,
    SM_OP_PING = 0xFF,
} SMOpcode;

typedef enum {
    SM_STATUS_OK = 1,
    SM_STATUS_NOT_READY = 2,
    SM_STATUS_INVALID_INPUT = 3,
    SM_STATUS_UNKNOWN_OPCODE = 4,
    SM_STATUS_UNAUTHORIZED = 5,
    SM_STATUS_VERSION_MISMATCH = 6,
} SMStatus;

typedef struct {
    uint32_t status;
} SMResponse;
