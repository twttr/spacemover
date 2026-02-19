#define __DARWIN_OPAQUE_ARM_THREAD_STATE64 1
#ifndef __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH
#define __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH 0x1
#endif
#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>
#import <ptrauth.h>

extern kern_return_t mach_vm_allocate(vm_map_t, mach_vm_address_t *, mach_vm_size_t, int);
extern kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t, mach_msg_type_number_t);
extern kern_return_t mach_vm_protect(vm_map_t, mach_vm_address_t, mach_vm_size_t, boolean_t, vm_prot_t);

typedef kern_return_t (*thread_convert_thread_state_t)(
    thread_act_t thread, int direction,
    thread_state_flavor_t flavor,
    thread_state_t in_state, mach_msg_type_number_t in_count,
    thread_state_t out_state, mach_msg_type_number_t *out_count
);

static pid_t findDockPID(void) {
    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *app in apps) {
        if ([app.bundleIdentifier isEqualToString:@"com.apple.dock"]) {
            return app.processIdentifier;
        }
    }
    return 0;
}

#if defined(__arm64__) || defined(__aarch64__)

static uint8_t shell_code[] = {
    0xFF, 0xC3, 0x00, 0xD1,  // sub   sp, sp, #0x30
    0xFD, 0x7B, 0x02, 0xA9,  // stp   x29, x30, [sp, #0x20]
    0xFD, 0x83, 0x00, 0x91,  // add   x29, sp, #0x20
    0xA2, 0x01, 0x00, 0x10,  // adr   x2, #52  -> offset 64 (inner function)
    0x42, 0x12, 0xC1, 0xDA,  // paciza x2
    0xE0, 0x03, 0x1F, 0xAA,  // mov   x0, xzr
    0xE1, 0x03, 0x1F, 0xAA,  // mov   x1, xzr
    0xE3, 0x03, 0x1F, 0xAA,  // mov   x3, xzr
    0xC9, 0x00, 0x00, 0x58,  // ldr   x9, #24  -> offset 56 (pthread_create_from_mach_thread addr)
    0x20, 0x01, 0x3F, 0xD6,  // blr   x9  (pthread_create_from_mach_thread)
    0xA0, 0x4C, 0x8D, 0xD2,  // movz  x0, #0x6265
    0xA0, 0x2C, 0xAF, 0xF2,  // movk  x0, #0x7961, lsl #16
    0x09, 0x00, 0x00, 0x10,  // adr   x9, #0  -> self (infinite loop)
    0x20, 0x01, 0x1F, 0xD6,  // br    x9  (infinite loop)
    0x00, 0x00, 0x00, 0x00,  // [56] pthread_create_from_mach_thread addr (low)
    0x00, 0x00, 0x00, 0x00,  // [60] pthread_create_from_mach_thread addr (high)

    // Inner function (offset 64)
    0x7F, 0x23, 0x03, 0xD5,  // pacibsp
    0xFF, 0xC3, 0x00, 0xD1,  // sub   sp, sp, #0x30
    0xFD, 0x7B, 0x02, 0xA9,  // stp   x29, x30, [sp, #0x20]
    0xFD, 0x83, 0x00, 0x91,  // add   x29, sp, #0x20
    0x21, 0x00, 0x80, 0xD2,  // mov   x1, #1 (RTLD_LAZY)
    0x40, 0x01, 0x00, 0x10,  // adr   x0, #40  -> offset 124 (payload path)
    0xE9, 0x00, 0x00, 0x58,  // ldr   x9, #28  -> offset 116 (dlopen addr)
    0x20, 0x01, 0x3F, 0xD6,  // blr   x9  (dlopen)
    0x09, 0x00, 0x80, 0xD2,  // mov   x9, #0
    0xE0, 0x03, 0x09, 0xAA,  // mov   x0, x9
    0xFD, 0x7B, 0x42, 0xA9,  // ldp   x29, x30, [sp, #0x20]
    0xFF, 0xC3, 0x00, 0x91,  // add   sp, sp, #0x30
    0xFF, 0x0F, 0x5F, 0xD6,  // retab
    0x00, 0x00, 0x00, 0x00,  // [116] dlopen addr (low)
    0x00, 0x00, 0x00, 0x00,  // [120] dlopen addr (high)
    // [124] payload path starts here
};

#define PCFMT_ADDR_OFFSET 56
#define DLOPEN_ADDR_OFFSET 116
#define PAYLOAD_PATH_OFFSET 124
#define INNER_FUNC_OFFSET 64

#endif

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: %s <path-to-dylib>\n", argv[0]);
            return 1;
        }

        const char *dylibPath = argv[1];

        pid_t dockPid = findDockPID();
        if (dockPid == 0) {
            fprintf(stderr, "Could not find Dock.app process\n");
            return 1;
        }

        fprintf(stderr, "Found Dock PID: %d\n", dockPid);

        mach_port_t dockTask;
        kern_return_t kr = task_for_pid(mach_task_self(), dockPid, &dockTask);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "task_for_pid failed: %s (is SIP debug disabled?)\n", mach_error_string(kr));
            return 1;
        }

#if defined(__arm64__) || defined(__aarch64__)
        void *kernel_handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
        if (!kernel_handle) {
            fprintf(stderr, "Failed to load libsystem_kernel\n");
            return 1;
        }

        thread_convert_thread_state_t _thread_convert = dlsym(kernel_handle, "thread_convert_thread_state");
        if (!_thread_convert) {
            fprintf(stderr, "Failed to find thread_convert_thread_state\n");
            return 1;
        }

        uint64_t pcfmt_addr = (uint64_t)ptrauth_strip(
            dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
        uint64_t dlopen_addr = (uint64_t)ptrauth_strip(
            dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);

        if (!pcfmt_addr || !dlopen_addr) {
            fprintf(stderr, "Failed to resolve function addresses\n");
            return 1;
        }

        fprintf(stderr, "pthread_create_from_mach_thread: 0x%llx\n", pcfmt_addr);
        fprintf(stderr, "dlopen: 0x%llx\n", dlopen_addr);

        size_t pathLen = strlen(dylibPath) + 1;
        size_t codeSize = PAYLOAD_PATH_OFFSET + pathLen;
        if (codeSize % 16 != 0) codeSize += 16 - (codeSize % 16);

        memcpy(shell_code + PCFMT_ADDR_OFFSET, &pcfmt_addr, sizeof(uint64_t));
        memcpy(shell_code + DLOPEN_ADDR_OFFSET, &dlopen_addr, sizeof(uint64_t));

        uint8_t *code_buf = calloc(1, codeSize);
        memcpy(code_buf, shell_code, sizeof(shell_code));
        memcpy(code_buf + PAYLOAD_PATH_OFFSET, dylibPath, pathLen);

        size_t stackSize = 0x4000;

        mach_vm_address_t remoteStack = 0;
        kr = mach_vm_allocate(dockTask, &remoteStack, stackSize, VM_FLAGS_ANYWHERE);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "mach_vm_allocate (stack) failed: %s\n", mach_error_string(kr));
            free(code_buf);
            return 1;
        }
        vm_protect(dockTask, (vm_address_t)remoteStack, stackSize, 1, VM_PROT_READ | VM_PROT_WRITE);

        mach_vm_address_t remoteCode = 0;
        kr = mach_vm_allocate(dockTask, &remoteCode, codeSize, VM_FLAGS_ANYWHERE);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "mach_vm_allocate (code) failed: %s\n", mach_error_string(kr));
            free(code_buf);
            return 1;
        }

        kr = mach_vm_write(dockTask, remoteCode, (vm_offset_t)code_buf, (mach_msg_type_number_t)codeSize);
        free(code_buf);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "mach_vm_write failed: %s\n", mach_error_string(kr));
            return 1;
        }

        kr = vm_protect(dockTask, (vm_address_t)remoteCode, codeSize, 0, VM_PROT_READ | VM_PROT_EXECUTE);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "vm_protect (code RX) failed: %s\n", mach_error_string(kr));
            return 1;
        }

        fprintf(stderr, "Remote code: 0x%llx\n", remoteCode);
        fprintf(stderr, "Remote stack: 0x%llx\n", remoteStack);

        thread_act_t thread;
        kr = thread_create(dockTask, &thread);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "thread_create failed: %s\n", mach_error_string(kr));
            return 1;
        }

        arm_thread_state64_t canonical_state = {};
        memset(&canonical_state, 0, sizeof(canonical_state));

        mach_vm_address_t stackTop = remoteStack + stackSize;
        stackTop &= ~0xFULL;

        __darwin_arm_thread_state64_set_pc_fptr(
            canonical_state,
            ptrauth_sign_unauthenticated((void *)remoteCode, ptrauth_key_asia, 0)
        );
        __darwin_arm_thread_state64_set_sp(canonical_state, (void *)stackTop);
        __darwin_arm_thread_state64_set_lr_fptr(canonical_state, (void *)0);

        arm_thread_state64_t machine_state = {};
        mach_msg_type_number_t machine_count = ARM_THREAD_STATE64_COUNT;

        kr = _thread_convert(thread, 2,
                             ARM_THREAD_STATE64,
                             (thread_state_t)&canonical_state, ARM_THREAD_STATE64_COUNT,
                             (thread_state_t)&machine_state, &machine_count);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "thread_convert_thread_state failed: %s\n", mach_error_string(kr));
            thread_terminate(thread);
            return 1;
        }

        fprintf(stderr, "thread_convert succeeded, machine_count=%u\n", machine_count);

        fprintf(stderr, "Trying approach 1: thread_create_running with converted state...\n");
        thread_terminate(thread);

        thread_act_t running_thread;
        kr = thread_create_running(dockTask,
                                   ARM_THREAD_STATE64,
                                   (thread_state_t)&machine_state,
                                   machine_count,
                                   &running_thread);

        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "Approach 1 failed: %s\n", mach_error_string(kr));

            fprintf(stderr, "Trying approach 2: FLAGS_NO_PTRAUTH...\n");
            arm_thread_state64_t raw_state = {};
            memset(&raw_state, 0, sizeof(raw_state));
            raw_state.__opaque_pc = (void *)remoteCode;
            raw_state.__opaque_sp = (void *)stackTop;
            raw_state.__opaque_lr = (void *)0;
            raw_state.__opaque_flags = __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH;

            kr = thread_create_running(dockTask,
                                       ARM_THREAD_STATE64,
                                       (thread_state_t)&raw_state,
                                       ARM_THREAD_STATE64_COUNT,
                                       &running_thread);
        }

        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "Approach 2 failed: %s\n", mach_error_string(kr));

            fprintf(stderr, "Trying approach 3: thread_create + set_state + resume (no convert)...\n");
            thread_act_t fresh_thread;
            kr = thread_create(dockTask, &fresh_thread);
            if (kr == KERN_SUCCESS) {
                arm_thread_state64_t raw_state2 = {};
                memset(&raw_state2, 0, sizeof(raw_state2));
                raw_state2.__opaque_pc = (void *)remoteCode;
                raw_state2.__opaque_sp = (void *)stackTop;
                raw_state2.__opaque_lr = (void *)0;
                raw_state2.__opaque_flags = __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH;

                kr = thread_set_state(fresh_thread, ARM_THREAD_STATE64,
                                      (thread_state_t)&raw_state2, ARM_THREAD_STATE64_COUNT);
                if (kr == KERN_SUCCESS) {
                    kr = thread_resume(fresh_thread);
                }
                if (kr == KERN_SUCCESS) {
                    running_thread = fresh_thread;
                } else {
                    fprintf(stderr, "Approach 3 failed: %s\n", mach_error_string(kr));
                    thread_terminate(fresh_thread);
                    return 1;
                }
            }
        }

        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "All approaches failed\n");
            return 1;
        }

        fprintf(stderr, "Thread running, waiting for sentinel...\n");

        int injected = 0;
        for (int i = 0; i < 10; ++i) {
            arm_thread_state64_t check_state = {};
            mach_msg_type_number_t check_count = ARM_THREAD_STATE64_COUNT;
            thread_get_state(running_thread, ARM_THREAD_STATE64,
                             (thread_state_t)&check_state, &check_count);
            if (check_state.__x[0] == 0x79616265) {
                injected = 1;
                break;
            }
            usleep(20000);
        }

        thread_terminate(running_thread);

        if (injected) {
            fprintf(stderr, "Payload injected successfully into Dock (PID %d)\n", dockPid);
            return 0;
        } else {
            fprintf(stderr, "Injection timed out waiting for sentinel\n");
            return 1;
        }

#else
        uint64_t dlopenAddr = (uint64_t)dlsym(RTLD_DEFAULT, "dlopen");

        size_t pathLen = strlen(dylibPath) + 1;
        size_t stackSize = 0x4000;
        size_t totalSize = pathLen + stackSize + 0x100;

        mach_vm_address_t remoteAddr = 0;
        kr = mach_vm_allocate(dockTask, &remoteAddr, totalSize, VM_FLAGS_ANYWHERE);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "mach_vm_allocate failed: %s\n", mach_error_string(kr));
            return 1;
        }

        kr = mach_vm_write(dockTask, remoteAddr, (vm_offset_t)dylibPath, (mach_msg_type_number_t)pathLen);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "mach_vm_write failed: %s\n", mach_error_string(kr));
            return 1;
        }

        x86_thread_state64_t state = {};
        memset(&state, 0, sizeof(state));

        state.__rip = dlopenAddr;
        state.__rdi = remoteAddr;
        state.__rsi = 0x2;

        mach_vm_address_t stackTop = remoteAddr + pathLen + stackSize;
        stackTop &= ~0xFULL;
        stackTop -= 8;
        state.__rsp = stackTop;

        thread_act_t remoteThread;
        kr = thread_create_running(dockTask,
                                   x86_THREAD_STATE64,
                                   (thread_state_t)&state,
                                   x86_THREAD_STATE64_COUNT,
                                   &remoteThread);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "thread_create_running failed: %s\n", mach_error_string(kr));
            return 1;
        }

        fprintf(stderr, "Payload injected successfully into Dock (PID %d)\n", dockPid);
        return 0;
#endif
    }
}
