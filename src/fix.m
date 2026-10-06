/*
 * FnMacCrashFix — Fortnite macOS 26.4 Crash Patch & Detection Bypass
 */

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/sysctl.h>
#include <mach-o/dyld.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include "fishhook.h"

#define DEVICE_MODEL "iPad17,4"
#define OEM_ID "A3361"

/* ── 1. Availability Version Check Patch ───────────────────────────────── */

typedef struct {
    uint32_t platform;
    uint32_t version;       /* major<<16 | minor<<8 | patch */
} dyld_build_version_t;

#define PLATFORM_IOS  2
#define PACK_VERSION(major, minor, patch) \
    (((uint32_t)(major) << 16) | ((uint32_t)(minor) << 8) | (uint32_t)(patch))

#define BLOCKED_VERSION  PACK_VERSION(17, 4, 0)

static bool (*orig_availability_version_check)(uint32_t count, dyld_build_version_t versions[]);

static bool hooked_availability_version_check(uint32_t count, dyld_build_version_t versions[]) {
    if (versions == NULL) {
        return orig_availability_version_check ? orig_availability_version_check(count, versions) : false;
    }

    for (uint32_t i = 0; i < count; i++) {
        if (versions[i].platform == PLATFORM_IOS && versions[i].version >= BLOCKED_VERSION) {
            return false;
        }
    }

    return orig_availability_version_check ? orig_availability_version_check(count, versions) : false;
}

/* ── 2. Environment Swizzling ─────────────────────────────────────────── */

static bool isSystemCaller(void *retAddr) {
    Dl_info info;
    if (dladdr(retAddr, &info) && info.dli_fname) {
        const char *path = info.dli_fname;
        if (strstr(path, "/System/Library/") != NULL ||
            strstr(path, "/usr/lib/") != NULL ||
            strstr(path, "/System/iOSSupport/") != NULL) {
            return true;
        }
    }
    return false;
}

static void swizzleIsiOSAppOnMac(Class cls) {
    if (!cls) return;
    SEL sel = sel_registerName("isiOSAppOnMac");
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        IMP origImp = method_getImplementation(method);
        class_replaceMethod(cls, sel, imp_implementationWithBlock((id)^BOOL(id self) {
            void *retAddr = __builtin_return_address(0);
            if (isSystemCaller(retAddr)) {
                typedef BOOL (*OrigFunc)(id, SEL);
                return ((OrigFunc)origImp)(self, sel);
            }
            return NO;
        }), method_getTypeEncoding(method));
    } else {
        class_addMethod(cls, sel, imp_implementationWithBlock((id)^BOOL(id self) {
            (void)self;
            void *retAddr = __builtin_return_address(0);
            return isSystemCaller(retAddr) ? YES : NO;
        }), "B@:");
    }
}

static void swizzleIsiOSAppOnMic(Class cls) {
    if (!cls) return;
    SEL sel = sel_registerName("isiOSAppOnMic");
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        class_replaceMethod(cls, sel, imp_implementationWithBlock((id)^BOOL(id self) {
            (void)self;
            return NO;
        }), method_getTypeEncoding(method));
    } else {
        class_addMethod(cls, sel, imp_implementationWithBlock((id)^BOOL(id self) {
            (void)self;
            return NO;
        }), "B@:");
    }
}

static void swizzleIsMacCatalystApp(Class cls) {
    if (!cls) return;
    SEL sel = sel_registerName("isMacCatalystApp");
    Method method = class_getInstanceMethod(cls, sel);
    if (method) {
        IMP origImp = method_getImplementation(method);
        class_replaceMethod(cls, sel, imp_implementationWithBlock((id)^BOOL(id self) {
            void *retAddr = __builtin_return_address(0);
            if (isSystemCaller(retAddr)) {
                typedef BOOL (*OrigFunc)(id, SEL);
                return ((OrigFunc)origImp)(self, sel);
            }
            return NO;
        }), method_getTypeEncoding(method));
    } else {
        class_addMethod(cls, sel, imp_implementationWithBlock((id)^BOOL(id self) {
            (void)self;
            return NO;
        }), "B@:");
    }
}

/* ── 3. Dynamic Linker Stealth & Image Hiding ─────────────────────────── */

static const struct mach_header *g_our_header = NULL;

static uint32_t (*orig_dyld_image_count)(void) = NULL;
static const char *(*orig_dyld_get_image_name)(uint32_t image_index) = NULL;
static const struct mach_header *(*orig_dyld_get_image_header)(uint32_t image_index) = NULL;
static intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t image_index) = NULL;
static void (*orig_dyld_register_func_for_add_image)(void (*func)(const struct mach_header* mh, intptr_t vmaddr_slide)) = NULL;
static void (*orig_dyld_register_func_for_remove_image)(void (*func)(const struct mach_header* mh, intptr_t vmaddr_slide)) = NULL;
static int (*orig_dladdr)(const void *addr, Dl_info *info) = NULL;

static uint32_t hooked_dyld_image_count(void) {
    if (!g_our_header) return orig_dyld_image_count();
    uint32_t count = orig_dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (orig_dyld_get_image_header(i) == g_our_header) {
            return count - 1;
        }
    }
    return count;
}

static uint32_t get_mapped_image_index(uint32_t idx) {
    if (!g_our_header) return idx;
    uint32_t count = orig_dyld_image_count();
    uint32_t current_virtual_idx = 0;
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mh = orig_dyld_get_image_header(i);
        if (mh == g_our_header) continue;
        if (current_virtual_idx == idx) return i;
        current_virtual_idx++;
    }
    return idx;
}

static const char *hooked_dyld_get_image_name(uint32_t image_index) {
    return orig_dyld_get_image_name(get_mapped_image_index(image_index));
}

static const struct mach_header *hooked_dyld_get_image_header(uint32_t image_index) {
    return orig_dyld_get_image_header(get_mapped_image_index(image_index));
}

static intptr_t hooked_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    return orig_dyld_get_image_vmaddr_slide(get_mapped_image_index(image_index));
}

#define MAX_DYLD_CALLBACKS 64
static void (*g_add_image_callbacks[MAX_DYLD_CALLBACKS])(const struct mach_header* mh, intptr_t vmaddr_slide) = {NULL};
static int g_add_image_callbacks_count = 0;
static pthread_mutex_t g_callbacks_mutex = PTHREAD_MUTEX_INITIALIZER;

static void wrapped_add_image_callback(const struct mach_header* mh, intptr_t vmaddr_slide) {
    if (mh == g_our_header) return;
    
    pthread_mutex_lock(&g_callbacks_mutex);
    int count = g_add_image_callbacks_count;
    void (*callbacks[MAX_DYLD_CALLBACKS])(const struct mach_header*, intptr_t);
    for (int i = 0; i < count; i++) callbacks[i] = g_add_image_callbacks[i];
    pthread_mutex_unlock(&g_callbacks_mutex);
    
    for (int i = 0; i < count; i++) {
        if (callbacks[i]) callbacks[i](mh, vmaddr_slide);
    }
}

static void hooked_dyld_register_func_for_add_image(void (*func)(const struct mach_header* mh, intptr_t vmaddr_slide)) {
    if (!func) return;
    
    pthread_mutex_lock(&g_callbacks_mutex);
    bool exists = false;
    for (int i = 0; i < g_add_image_callbacks_count; i++) {
        if (g_add_image_callbacks[i] == func) { exists = true; break; }
    }
    if (!exists && g_add_image_callbacks_count < MAX_DYLD_CALLBACKS) {
        g_add_image_callbacks[g_add_image_callbacks_count++] = func;
    }
    pthread_mutex_unlock(&g_callbacks_mutex);
    
    static bool registered_wrapper = false;
    if (!registered_wrapper) {
        registered_wrapper = true;
        orig_dyld_register_func_for_add_image(wrapped_add_image_callback);
    } else {
        uint32_t count = orig_dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const struct mach_header *mh = orig_dyld_get_image_header(i);
            intptr_t slide = orig_dyld_get_image_vmaddr_slide(i);
            if (mh != g_our_header) func(mh, slide);
        }
    }
}

static void (*g_remove_image_callbacks[MAX_DYLD_CALLBACKS])(const struct mach_header* mh, intptr_t vmaddr_slide) = {NULL};
static int g_remove_image_callbacks_count = 0;
static pthread_mutex_t g_remove_callbacks_mutex = PTHREAD_MUTEX_INITIALIZER;

static void wrapped_remove_image_callback(const struct mach_header* mh, intptr_t vmaddr_slide) {
    if (mh == g_our_header) return;
    
    pthread_mutex_lock(&g_remove_callbacks_mutex);
    int count = g_remove_image_callbacks_count;
    void (*callbacks[MAX_DYLD_CALLBACKS])(const struct mach_header*, intptr_t);
    for (int i = 0; i < count; i++) callbacks[i] = g_remove_image_callbacks[i];
    pthread_mutex_unlock(&g_remove_callbacks_mutex);
    
    for (int i = 0; i < count; i++) {
        if (callbacks[i]) callbacks[i](mh, vmaddr_slide);
    }
}

static void hooked_dyld_register_func_for_remove_image(void (*func)(const struct mach_header* mh, intptr_t vmaddr_slide)) {
    if (!func) return;
    
    pthread_mutex_lock(&g_remove_callbacks_mutex);
    bool exists = false;
    for (int i = 0; i < g_remove_image_callbacks_count; i++) {
        if (g_remove_image_callbacks[i] == func) { exists = true; break; }
    }
    if (!exists && g_remove_image_callbacks_count < MAX_DYLD_CALLBACKS) {
        g_remove_image_callbacks[g_remove_image_callbacks_count++] = func;
    }
    pthread_mutex_unlock(&g_remove_callbacks_mutex);
    
    static bool registered_remove_wrapper = false;
    if (!registered_remove_wrapper) {
        registered_remove_wrapper = true;
        orig_dyld_register_func_for_remove_image(wrapped_remove_image_callback);
    }
}

static int hooked_dladdr(const void *addr, Dl_info *info) {
    int ret = orig_dladdr(addr, info);
    if (ret && info && info->dli_fbase == g_our_header) {
        memset(info, 0, sizeof(Dl_info));
        return 0;
    }
    return ret;
}

/* ── 4. Device Spoofing & sysctl Virtualization ───────────────────────── */

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;
static int (*orig_sysctlnametomib)(const char *, int *, size_t *) = NULL;

typedef void (*MKW_GetEligibilityRegionCallback)(bool eligible, const char *regionCode);
static void (*orig_MKW_GetEligibilityRegion)(MKW_GetEligibilityRegionCallback completion) = NULL;

static void hooked_MKW_GetEligibilityRegion(MKW_GetEligibilityRegionCallback completion) {
    if (completion) completion(true, "EU");
}

typedef void (*MKW_RequestCTTokenCallback)(bool success, const char *token);
static void (*orig_MKW_RequestCTToken)(MKW_RequestCTTokenCallback completion) = NULL;

static void hooked_MKW_RequestCTToken(MKW_RequestCTTokenCallback completion) {
    if (completion) completion(true, "mock_ct_token_mactweak_bypass");
}

#define PSEUDO_MIB_KERN_WILLSHUTDOWN            99901
#define PSEUDO_MIB_SECURITY_LOCKDOWN            99902
#define PSEUDO_MIB_KERN_OSREVISION              99903
#define PSEUDO_MIB_KERN_UUID                    99904
#define PSEUDO_MIB_CPU_BRAND_STRING             99905
#define PSEUDO_MIB_PROC_TRANSLATED              99906

static int handle_string_sysctl(void *oldp, size_t *oldlenp, const char *value) {
    size_t len = strlen(value) + 1;
    if (oldlenp) {
        if (oldp == NULL) { *oldlenp = len; return 0; }
        if (*oldlenp < len) { *oldlenp = len; return ENOMEM; }
        strcpy((char *)oldp, value);
        *oldlenp = len;
    }
    return 0;
}

static int handle_int_sysctl(void *oldp, size_t *oldlenp, int value) {
    if (oldlenp) {
        if (oldp == NULL) { *oldlenp = sizeof(int); return 0; }
        if (*oldlenp < sizeof(int)) { *oldlenp = sizeof(int); return ENOMEM; }
        *(int *)oldp = value;
        *oldlenp = sizeof(int);
    }
    return 0;
}

static int hooked_sysctlnametomib(const char *name, int *mibp, size_t *sizep) {
    if (name) {
        if (strcmp(name, "kern.willshutdown") == 0) {
            if (mibp && sizep && *sizep >= 1) { mibp[0] = PSEUDO_MIB_KERN_WILLSHUTDOWN; *sizep = 1; return 0; }
            return ENOMEM;
        }
        if (strcmp(name, "security.mac.lockdown_mode_state") == 0) {
            if (mibp && sizep && *sizep >= 1) { mibp[0] = PSEUDO_MIB_SECURITY_LOCKDOWN; *sizep = 1; return 0; }
            return ENOMEM;
        }
        if (strcmp(name, "kern.osrevision") == 0) {
            if (mibp && sizep && *sizep >= 1) { mibp[0] = PSEUDO_MIB_KERN_OSREVISION; *sizep = 1; return 0; }
            return ENOMEM;
        }
        if (strcmp(name, "kern.uuid") == 0) {
            if (mibp && sizep && *sizep >= 1) { mibp[0] = PSEUDO_MIB_KERN_UUID; *sizep = 1; return 0; }
            return ENOMEM;
        }
        if (strcmp(name, "machdep.cpu.brand_string") == 0) {
            if (mibp && sizep && *sizep >= 1) { mibp[0] = PSEUDO_MIB_CPU_BRAND_STRING; *sizep = 1; return 0; }
            return ENOMEM;
        }
        if (strcmp(name, "sysctl.proc_translated") == 0) {
            if (mibp && sizep && *sizep >= 1) { mibp[0] = PSEUDO_MIB_PROC_TRANSLATED; *sizep = 1; return 0; }
            return ENOMEM;
        }
    }
    return orig_sysctlnametomib(name, mibp, sizep);
}

static int pt_sysctl(int *name, u_int namelen, void *buf, size_t *size, void *arg0, size_t arg1) {
    if (namelen >= 1) {
        if (name[0] == PSEUDO_MIB_KERN_WILLSHUTDOWN) return handle_int_sysctl(buf, size, 0);
        if (name[0] == PSEUDO_MIB_SECURITY_LOCKDOWN) return handle_int_sysctl(buf, size, 0);
        if (name[0] == PSEUDO_MIB_KERN_OSREVISION) return handle_int_sysctl(buf, size, 199001);
        if (name[0] == PSEUDO_MIB_KERN_UUID) return handle_string_sysctl(buf, size, "00000000-0000-0000-0000-000000000000");
        if (name[0] == PSEUDO_MIB_CPU_BRAND_STRING) return handle_string_sysctl(buf, size, "Apple M1");
        if (name[0] == PSEUDO_MIB_PROC_TRANSLATED) return handle_int_sysctl(buf, size, 0);
        
        if (name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_PRODUCT)) {
            if (buf == NULL) {
                *size = strlen(DEVICE_MODEL) + 1;
            } else {
                if (*size > strlen(DEVICE_MODEL)) {
                    strcpy((char *)buf, DEVICE_MODEL);
                } else {
                    return ENOMEM;
                }
            }
            return 0;
        } else if (name[0] == CTL_HW && name[1] == HW_TARGET) {
            if (buf == NULL) {
                *size = strlen(OEM_ID) + 1;
            } else {
                if (*size > strlen(OEM_ID)) {
                    strcpy((char *)buf, OEM_ID);
                } else {
                    return ENOMEM;
                }
            }
            return 0;
        }
    }
    return orig_sysctl(name, namelen, buf, size, arg0, arg1);
}

static int pt_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name) {
        if (strcmp(name, "kern.willshutdown") == 0) return handle_int_sysctl(oldp, oldlenp, 0);
        if (strcmp(name, "security.mac.lockdown_mode_state") == 0) return handle_int_sysctl(oldp, oldlenp, 0);
        if (strcmp(name, "kern.osrevision") == 0) return handle_int_sysctl(oldp, oldlenp, 199001);
        if (strcmp(name, "kern.uuid") == 0) return handle_string_sysctl(oldp, oldlenp, "00000000-0000-0000-0000-000000000000");
        if (strcmp(name, "machdep.cpu.brand_string") == 0) return handle_string_sysctl(oldp, oldlenp, "Apple M1");
        if (strcmp(name, "sysctl.proc_translated") == 0) return handle_int_sysctl(oldp, oldlenp, 0);
        
        if ((strcmp(name, "hw.machine") == 0) || (strcmp(name, "hw.product") == 0) || (strcmp(name, "hw.model") == 0)) {
            if (oldp == NULL) {
                int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
                if (oldlenp && *oldlenp < strlen(DEVICE_MODEL) + 1) *oldlenp = strlen(DEVICE_MODEL) + 1;
                return ret;
            } else {
                int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
                const char *machine = DEVICE_MODEL;
                strncpy((char *)oldp, machine, strlen(machine));
                ((char *)oldp)[strlen(machine)] = '\0';
                if (oldlenp) *oldlenp = strlen(machine) + 1;
                return ret;
            }
        } else if (strcmp(name, "hw.target") == 0) {
            if (oldp == NULL) {
                int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
                if (oldlenp && *oldlenp < strlen(OEM_ID) + 1) *oldlenp = strlen(OEM_ID) + 1;
                return ret;
            } else {
                int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
                const char *machine = OEM_ID;
                strncpy((char *)oldp, machine, strlen(machine));
                ((char *)oldp)[strlen(machine)] = '\0';
                if (oldlenp) *oldlenp = strlen(machine) + 1;
                return ret;
            }
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

/* ── 5. Constructor Initialization ────────────────────────────────────── */

__attribute__((constructor(101)))
static void fn_crashfix_init(void) {
    /* 1. Swizzle runtime ProcessInfo checks */
    swizzleIsiOSAppOnMac(objc_getClass("NSProcessInfo"));
    swizzleIsiOSAppOnMac(objc_getClass("_NSSwiftProcessInfo"));
    swizzleIsiOSAppOnMic(objc_getClass("NSProcessInfo"));
    swizzleIsiOSAppOnMic(objc_getClass("_NSSwiftProcessInfo"));
    swizzleIsMacCatalystApp(objc_getClass("NSProcessInfo"));
    swizzleIsMacCatalystApp(objc_getClass("_NSSwiftProcessInfo"));

    /* 2. Locate our dylib's mach_header for dyld hiding */
    Dl_info our_info;
    if (dladdr((const void *)swizzleIsiOSAppOnMac, &our_info)) {
        g_our_header = (const struct mach_header *)our_info.dli_fbase;
    }

    /* 3. Rebind C-symbols via fishhook */
    struct rebinding rebindings[] = {
        { "_availability_version_check", (void *)hooked_availability_version_check, (void **)&orig_availability_version_check },
        { "availability_version_check", (void *)hooked_availability_version_check, (void **)&orig_availability_version_check },
        { "sysctl", (void *)pt_sysctl, (void **)&orig_sysctl },
        { "sysctlbyname", (void *)pt_sysctlbyname, (void **)&orig_sysctlbyname },
        { "sysctlnametomib", (void *)hooked_sysctlnametomib, (void **)&orig_sysctlnametomib },
        { "MKW_GetEligibilityRegion", (void *)hooked_MKW_GetEligibilityRegion, (void **)&orig_MKW_GetEligibilityRegion },
        { "MKW_RequestCTToken", (void *)hooked_MKW_RequestCTToken, (void **)&orig_MKW_RequestCTToken },
        { "_dyld_image_count", (void *)hooked_dyld_image_count, (void **)&orig_dyld_image_count },
        { "_dyld_get_image_name", (void *)hooked_dyld_get_image_name, (void **)&orig_dyld_get_image_name },
        { "_dyld_get_image_header", (void *)hooked_dyld_get_image_header, (void **)&orig_dyld_get_image_header },
        { "_dyld_get_image_vmaddr_slide", (void *)hooked_dyld_get_image_vmaddr_slide, (void **)&orig_dyld_get_image_vmaddr_slide },
        { "_dyld_register_func_for_add_image", (void *)hooked_dyld_register_func_for_add_image, (void **)&orig_dyld_register_func_for_add_image },
        { "_dyld_register_func_for_remove_image", (void *)hooked_dyld_register_func_for_remove_image, (void **)&orig_dyld_register_func_for_remove_image },
        { "dladdr", (void *)hooked_dladdr, (void **)&orig_dladdr }
    };

    rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
}