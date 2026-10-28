/* Use OPENSTEP's system bell. AudioToolbox file sounds are unavailable. */
int AudioServicesGetProperty(unsigned property, unsigned specifierSize, const void *specifier,
                             unsigned *size, void *data) {
    if (property == 0x6175726c && !specifierSize) { /* Terminal's system alert URL. */
        static id bell;
        if (!size || !data || *size < sizeof(id))
            return -50;
        if (!bell)
            bell = [[NSURL alloc] initWithString:@"openstep-system-bell:"];
        *(id *)data = [bell retain];
        *size = sizeof(id);
        return 0;
    }
    return 0x7074793f; /* kAudioServicesUnsupportedPropertyError */
}
int AudioServicesCreateSystemSoundID(id url, unsigned *identifier) {
    if (identifier && [[url absoluteString] isEqual:@"openstep-system-bell:"]) {
        *identifier = 1;
        return 0;
    }
    if (identifier)
        *identifier = 0;
    return -1500;
}
int AudioServicesDisposeSystemSoundID(unsigned identifier) {
    return identifier == 1 ? 0 : -1500;
}
int AudioServicesAddSystemSoundCompletion(unsigned identifier, id loop, id mode,
                                          void (*completion)(unsigned, void *), void *context) {
    return -1500;
}
void AudioServicesRemoveSystemSoundCompletion(unsigned identifier) {}
void AudioServicesPlayAlertSound(unsigned identifier) {
    NSBeep();
}
