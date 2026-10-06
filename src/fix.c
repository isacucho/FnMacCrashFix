/*
 * FnMacCrashFix — Fortnite macOS 26.4 Crash Patch
 *
 * Fortnite v40.00.1 contains a Swift @available(iOS 17.4, *) check that,
 * when running on macOS 26.4 via Catalyst, takes a code path with a NULL
 * async continuation, causing an immediate SIGSEGV on launch.
 *
 * This dylib hooks _availability_version_check (via fishhook/GOT patching)
 * so affected iOS availability checks (17.4 and newer) return false, forcing
 * the safe fallback path.
 * Only __DATA pages are modified — no code signing violations.
 *
 * Crash signature (unpatched):
 *   Thread: com.apple.root.default-qos.cooperative
 *   EXC_BAD_ACCESS (SIGSEGV) at 0x0
 *   completeTaskWithClosure → FortniteClient offset +6041652 / +6043477
 *
 * Inject via sideloadly alongside FnMacTweak.dylib.
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "fishhook.h"

/* ── Types matching dyld_priv.h ───────────────────────────────────── */

typedef struct {
    uint32_t platform;
    uint32_t version;       /* major<<16 | minor<<8 | patch */
} dyld_build_version_t;

/* Platform constants */
#define PLATFORM_IOS  2

/* Pack a version triplet the same way the compiler does. */
#define PACK_VERSION(major, minor, patch) \
    (((uint32_t)(major) << 16) | ((uint32_t)(minor) << 8) | (uint32_t)(patch))

/* The first affected version. Newer iOS availability checks use the same
 * Catalyst path in newer Fortnite builds, so they must be rejected too. */
#define BLOCKED_VERSION  PACK_VERSION(17, 4, 0)

/* ── Hook state ───────────────────────────────────────────────────── */

static bool (*orig_availability_version_check)(uint32_t count,
                                                dyld_build_version_t versions[]);

static bool hooked_availability_version_check(uint32_t count,
                                               dyld_build_version_t versions[]) {
    if (versions == NULL) {
        return orig_availability_version_check
            ? orig_availability_version_check(count, versions)
            : false;
    }

    for (uint32_t i = 0; i < count; i++) {
        if (versions[i].platform == PLATFORM_IOS &&
            versions[i].version >= BLOCKED_VERSION) {
            return false;   /* "not available" → takes the safe fallback path */
        }
    }

    /* All other availability checks pass through unchanged. */
    return orig_availability_version_check
        ? orig_availability_version_check(count, versions)
        : false;
}

/* ── Constructor (runs before other tweak hooks where possible) ──────── */

__attribute__((constructor(101)))
static void fn_crashfix_init(void) {
    struct rebinding rebindings[] = {
        {
            "_availability_version_check",
            (void *)hooked_availability_version_check,
            (void **)&orig_availability_version_check
        },
        /* Some Catalyst-linked images expose one fewer Mach-O underscore. */
        {
            "availability_version_check",
            (void *)hooked_availability_version_check,
            (void **)&orig_availability_version_check
        },
    };

    rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
}
