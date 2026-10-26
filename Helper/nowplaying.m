// Loaded into /usr/bin/perl so MediaRemote treats us as Apple-signed.
// argv: perl nowplaying.pl <dylib> stream | send <cmd> | seek <seconds>
#import <Foundation/Foundation.h>
#include <crt_externs.h>
#include <dlfcn.h>

static void *mr;
static void *sym(const char *n) { return dlsym(mr, n); }
static id key(const char *n) { CFStringRef *p = sym(n); return p ? (__bridge id)*p : @(n); }

static void emit(void) {
    void (*getInfo)(dispatch_queue_t, void (^)(CFDictionaryRef)) = sym("MRMediaRemoteGetNowPlayingInfo");
    void (*isPlaying)(dispatch_queue_t, void (^)(Boolean)) = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    void (*getClient)(dispatch_queue_t, void (^)(id)) = sym("MRMediaRemoteGetNowPlayingClient");
    CFStringRef (*bundleOf)(id) = sym("MRNowPlayingClientGetBundleIdentifier");
    dispatch_queue_t q = dispatch_get_main_queue();
    getInfo(q, ^(CFDictionaryRef cf) {
        NSDictionary *info = (__bridge NSDictionary *)cf;
        isPlaying(q, ^(Boolean playing) {
            void (^out)(NSString *) = ^(NSString *bundle) {
                NSMutableDictionary *d = [NSMutableDictionary dictionary];
                d[@"title"] = info[key("kMRMediaRemoteNowPlayingInfoTitle")] ?: @"";
                d[@"artist"] = info[key("kMRMediaRemoteNowPlayingInfoArtist")] ?: @"";
                d[@"album"] = info[key("kMRMediaRemoteNowPlayingInfoAlbum")] ?: @"";
                d[@"duration"] = info[key("kMRMediaRemoteNowPlayingInfoDuration")] ?: @0;
                d[@"elapsed"] = info[key("kMRMediaRemoteNowPlayingInfoElapsedTime")] ?: @0;
                NSDate *ts = info[key("kMRMediaRemoteNowPlayingInfoTimestamp")] ?: [NSDate date];
                d[@"timestamp"] = @(ts.timeIntervalSince1970);
                d[@"playing"] = @(playing);
                d[@"bundle"] = bundle ?: @"";
                NSData *art = info[key("kMRMediaRemoteNowPlayingInfoArtworkData")];
                if ([art isKindOfClass:NSData.class]) d[@"artwork"] = [art base64EncodedStringWithOptions:0];
                NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            };
            if (getClient && bundleOf) getClient(q, ^(id c) { out(c ? (__bridge NSString *)bundleOf(c) : nil); });
            else out(nil);
        });
    });
}

__attribute__((visibility("default")))
void nowplaying_main(void *thx, void *cv) {
    @autoreleasepool {
        mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!mr) { fprintf(stderr, "dlopen: %s\n", dlerror()); exit(1); }
        int argc = *_NSGetArgc();
        char **argv = *_NSGetArgv();
        const char *mode = argc > 3 ? argv[3] : "stream";
        if (!strcmp(mode, "send") && argc > 4) {
            Boolean (*send)(int, CFDictionaryRef) = sym("MRMediaRemoteSendCommand");
            send(atoi(argv[4]), NULL);
        } else if (!strcmp(mode, "seek") && argc > 4) {
            void (*seek)(double) = sym("MRMediaRemoteSetElapsedTime");
            seek(atof(argv[4]));
        }
        if (argc > 4) {
            // Both calls are async XPC; give them time to go out.
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
            exit(0);
        }
        void (*reg)(dispatch_queue_t) = sym("MRMediaRemoteRegisterForNowPlayingNotifications");
        reg(dispatch_get_main_queue());
        const char *names[] = {"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                               "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                               "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"};
        for (int i = 0; i < 3; i++)
            [NSNotificationCenter.defaultCenter addObserverForName:key(names[i]) object:nil queue:nil
                                                        usingBlock:^(NSNotification *n) { emit(); }];
        // Die with the app instead of lingering until the next write hits a closed pipe.
        dispatch_source_t parent = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, getppid(), DISPATCH_PROC_EXIT, dispatch_get_main_queue());
        dispatch_source_set_event_handler(parent, ^{ exit(0); });
        dispatch_resume(parent);
        emit();
        CFRunLoopRun();
        exit(0);
    }
}
