#include <assert.h>
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    unsigned size = sizeof(id), sound = 0;
    id url = nil;
    int i;
    for (i = 0; i < 20; i++) {
        assert(!AudioServicesGetProperty(0x6175726c, 0, NULL, &size, &url));
        assert(url && snowLiveTestURLs == 1);
        assert(!AudioServicesCreateSystemSoundID(url, &sound) && sound == 1);
        [url release];
        assert(snowLiveTestURLs == 1);
        assert(!AudioServicesDisposeSystemSoundID(sound));
    }
    size = 0;
    assert(AudioServicesGetProperty(0x6175726c, 0, NULL, &size, &url) != 0);
    assert(AudioServicesCreateSystemSoundID(nil, &sound) != 0 && !sound);
    [pool release];
    puts("PASS native alert sound URL ownership");
    return 0;
}
