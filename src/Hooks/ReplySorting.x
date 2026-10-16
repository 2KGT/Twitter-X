//
//  ReplySorting.x
//  NeoFreeBird
//

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import "HookHelpers.h"

// MARK: - Default reply sort

// Used from the TFSReplySortingState class
enum {
    BHTReplyRankingModeLikes = 0,
    BHTReplyRankingModeRecency = 1,
    BHTReplyRankingModeRelevance = 2,
};

// default_reply_sort: 0 is unchanged, 1 relevance, 2 recency,
// 3 likes.
static BOOL PreferredReplyRankingMode(uint8_t* mode) {
    switch ([BHTSettings integerForKey:@"default_reply_sort"]) {
        case 1:
            *mode = BHTReplyRankingModeRelevance;
            return YES;
        case 2:
            *mode = BHTReplyRankingModeRecency;
            return YES;
        case 3:
            *mode = BHTReplyRankingModeLikes;
            return YES;
        default:
            return NO;
    }
}

static NSInteger userActionDepth;

%hook TFNActionItem

+ (id)actionItemWithTitle:(id)title imageName:(id)imageName action:(void (^)(void))action {
    if (!action) {
        return %orig;
    }

    void (^wrapped)(void) = ^{
        userActionDepth++;
        action();
        userActionDepth--;
    };
    return %orig(title, imageName, wrapped);
}

%end

%hook TFSReplySortingState

- (id)init {
    self = %orig;
    uint8_t mode;
    if (self && PreferredReplyRankingMode(&mode)) {
        switch (mode) {
            case BHTReplyRankingModeRecency:
                [self sortByRecency];
                break;
            case BHTReplyRankingModeLikes:
                [self sortByLikes];
                break;
            default:
                [self sortByRelevance];
                break;
        }
    }
    return self;
}

%end

typedef void* (*ReplySortingStateInitFn)(
    uint8_t mode, void* __attribute__((swift_context)) self) __attribute__((swiftcall));
static ReplySortingStateInitFn orig_ReplySortingStateInit;

__attribute__((swiftcall)) static void* hook_ReplySortingStateInit(
    uint8_t mode, void* __attribute__((swift_context)) self) {
    uint8_t preferred;
    if (userActionDepth == 0 && PreferredReplyRankingMode(&preferred)) {
        mode = preferred;
    }
    return orig_ReplySortingStateInit(mode, self);
}

// Repoints every symbol-pointer slot in an image that holds `target` at
// `replacement`. Matching on the bound address rather than the indirect
// symbol table matters: with chained fixups the table lists these slots as
// LOCAL ABSOLUTE.
static BOOL RebindImagePointer(const struct mach_header_64* header, intptr_t slide,
                               void* target, void* replacement) {
    BOOL rebound = NO;
    const struct load_command* cmd = (const struct load_command*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* segment = (const struct segment_command_64*)cmd;
            const struct section_64* sections = (const struct section_64*)(segment + 1);
            for (uint32_t j = 0; j < segment->nsects; j++) {
                const struct section_64* section = &sections[j];
                uint32_t type = section->flags & SECTION_TYPE;
                if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) {
                    continue;
                }

                void** slots = (void**)((uintptr_t)slide + section->addr);
                for (uint64_t k = 0; k < section->size / sizeof(void*); k++) {
                    if (slots[k] != target) {
                        continue;
                    }

                    // __DATA_CONST is read-only after binding; a data page
                    // can be made writable without touching code signing.
                    vm_address_t page = (vm_address_t)&slots[k] & ~(vm_address_t)vm_page_mask;
                    if (vm_protect(mach_task_self(), page, vm_page_size, false,
                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
                        continue;
                    }
                    slots[k] = replacement;
                    vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ);
                    rebound = YES;
                }
            }
        }
        cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
    }
    return rebound;
}

static void RebindReplySortingStateInit(const struct mach_header* header, intptr_t slide) {
    Dl_info info;
    if (!orig_ReplySortingStateInit || header->magic != MH_MAGIC_64 ||
        !dladdr(header, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, "/T1Twitter.framework/T1Twitter")) {
        return;
    }

    RebindImagePointer((const struct mach_header_64*)header, slide,
                       (void*)orig_ReplySortingStateInit, (void*)hook_ReplySortingStateInit);
}

%ctor {
    %init;

    // TFSTwitterCore.ReplySortingState.init(rankingMode:)
    orig_ReplySortingStateInit = (ReplySortingStateInitFn)dlsym(
        RTLD_DEFAULT,
        "$s14TFSTwitterCore17ReplySortingStateC11rankingModeAC"
        "14GraphQLScalars015TimelineRankingG5InputO_tcfc");

    _dyld_register_func_for_add_image(RebindReplySortingStateInit);
}
