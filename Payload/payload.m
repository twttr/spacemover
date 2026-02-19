#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/ucred.h>
#import <sys/stat.h>
#import <unistd.h>
#import <pthread.h>
#import "common.h"

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

typedef CGSConnectionID (*SLSMainConnectionIDFn)(void);
typedef void (*SLSMoveManagedSpaceToDisplayIndexFn)(CGSConnectionID, CGSSpaceID, CFStringRef, uint32_t);
typedef void (*SLSManagedDisplaySetCurrentSpaceFn)(CGSConnectionID, CFStringRef, CGSSpaceID);

static SLSMainConnectionIDFn              gGetConn = NULL;
static SLSMoveManagedSpaceToDisplayIndexFn gMoveSpace = NULL;
static SLSManagedDisplaySetCurrentSpaceFn  gSetCurrentSpace = NULL;

static void handleCommand(const SMCommand *cmd, int clientFd) {
    SMResponse resp = { .status = SM_STATUS_UNKNOWN_OPCODE };

    if (cmd->version != SM_PROTOCOL_VERSION) {
        resp.status = SM_STATUS_VERSION_MISMATCH;
        write(clientFd, &resp, sizeof(resp));
        return;
    }

    if (cmd->opcode == SM_OP_PING) {
        resp.status = SM_STATUS_OK;
        write(clientFd, &resp, sizeof(resp));
        return;
    }

    if (!gGetConn || !gMoveSpace) {
        resp.status = SM_STATUS_NOT_READY;
        write(clientFd, &resp, sizeof(resp));
        return;
    }

    CGSConnectionID conn = gGetConn();

    char safeBuf[128];
    memcpy(safeBuf, cmd->displayUUID, sizeof(safeBuf));
    safeBuf[127] = '\0';

    CFStringRef displayUUID = CFStringCreateWithCString(NULL, safeBuf, kCFStringEncodingUTF8);
    if (!displayUUID) {
        resp.status = SM_STATUS_INVALID_INPUT;
        write(clientFd, &resp, sizeof(resp));
        return;
    }

    switch (cmd->opcode) {
        case SM_OP_MOVE_SPACE_TO_DISPLAY:
            gMoveSpace(conn, cmd->spaceID, displayUUID, cmd->targetDisplayIndex);
            resp.status = SM_STATUS_OK;
            break;
        case SM_OP_SET_CURRENT_SPACE:
            if (gSetCurrentSpace) {
                gSetCurrentSpace(conn, displayUUID, cmd->spaceID);
                resp.status = SM_STATUS_OK;
            } else {
                resp.status = SM_STATUS_NOT_READY;
            }
            break;
        default:
            resp.status = SM_STATUS_UNKNOWN_OPCODE;
            break;
    }

    CFRelease(displayUUID);
    write(clientFd, &resp, sizeof(resp));
}

static void *socketThread(void *arg) {
    (void)arg;

    void *handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "SpaceMover: dlopen SkyLight failed: %s\n", dlerror());
    } else {
        gGetConn         = (SLSMainConnectionIDFn)dlsym(handle, "SLSMainConnectionID");
        gMoveSpace       = (SLSMoveManagedSpaceToDisplayIndexFn)dlsym(handle, "SLSMoveManagedSpaceToDisplayIndex");
        gSetCurrentSpace = (SLSManagedDisplaySetCurrentSpaceFn)dlsym(handle, "SLSManagedDisplaySetCurrentSpace");

        if (!gGetConn)         fprintf(stderr, "SpaceMover: SLSMainConnectionID not found\n");
        if (!gMoveSpace)       fprintf(stderr, "SpaceMover: SLSMoveManagedSpaceToDisplayIndex not found\n");
        if (!gSetCurrentSpace) fprintf(stderr, "SpaceMover: SLSManagedDisplaySetCurrentSpace not found\n");
    }

    unlink(SPACEMOVER_SOCKET_PATH);

    int serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (serverFd < 0) {
        fprintf(stderr, "SpaceMover: socket() failed: %s\n", strerror(errno));
        return NULL;
    }

    struct sockaddr_un addr = {};
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, SPACEMOVER_SOCKET_PATH, sizeof(addr.sun_path));

    if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "SpaceMover: bind() failed: %s\n", strerror(errno));
        close(serverFd);
        return NULL;
    }

    chmod(SPACEMOVER_SOCKET_PATH, 0600);

    if (listen(serverFd, 8) < 0) {
        fprintf(stderr, "SpaceMover: listen() failed: %s\n", strerror(errno));
        close(serverFd);
        return NULL;
    }

    fprintf(stderr, "SpaceMover: payload listening on %s\n", SPACEMOVER_SOCKET_PATH);

    while (1) {
        int clientFd = accept(serverFd, NULL, NULL);
        if (clientFd < 0) continue;

        struct xucred peercred;
        socklen_t peercredlen = sizeof(peercred);
        if (getsockopt(clientFd, 0, LOCAL_PEERCRED, &peercred, &peercredlen) == 0) {
            if (peercred.cr_uid != getuid()) {
                SMResponse resp = { .status = SM_STATUS_UNAUTHORIZED };
                write(clientFd, &resp, sizeof(resp));
                close(clientFd);
                continue;
            }
        }

        struct timeval tv = { .tv_sec = 5 };
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        SMCommand cmd = {};
        ssize_t bytesRead = read(clientFd, &cmd, sizeof(cmd));
        if (bytesRead == sizeof(cmd)) {
            handleCommand(&cmd, clientFd);
        }
        close(clientFd);
    }

    return NULL;
}

__attribute__((constructor))
static void spaceMoverPayloadInit(void) {
    pthread_t thread;
    pthread_create(&thread, NULL, socketThread, NULL);
    pthread_detach(thread);
}
