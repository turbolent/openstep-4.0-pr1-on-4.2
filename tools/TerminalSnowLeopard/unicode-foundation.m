/* NSString normalization shares the Unicode implementation used by Terminal. */
static NSString *snowNormalizeString(NSString *text, int mode) {
    unsigned length = [text length];
    unichar *source, *output;
    int needed, status = 0;
    NSString *result;
    if (length > INT_MAX / 2 - 1)
        [NSException raise:NSInvalidArgumentException format:@"String is too long to normalize"];
    source = malloc((length + 1) * sizeof(*source));
    if (!source)
        [NSException raise:NSMallocException format:@"Cannot allocate normalization input"];
    [text getCharacters:source];
    needed = unorm_normalize(source, length, mode, 0, NULL, 0, &status);
    if (status > 0 && status != 15) {
        free(source);
        [NSException raise:NSInvalidArgumentException format:@"Normalization failed (%d)", status];
    }
    output = malloc((needed + 1) * sizeof(*output));
    if (!output) {
        free(source);
        [NSException raise:NSMallocException format:@"Cannot allocate normalization output"];
    }
    status = 0;
    unorm_normalize(source, length, mode, 0, output, needed + 1, &status);
    result = [NSString stringWithCharacters:output length:needed];
    free(source);
    free(output);
    return result;
}
@implementation NSString (SnowNormalization)
- (NSString *)precomposedStringWithCanonicalMapping {
    return snowNormalizeString(self, 4);
}
- (NSString *)decomposedStringWithCanonicalMapping {
    return snowNormalizeString(self, 2);
}
- (NSString *)precomposedStringWithCompatibilityMapping {
    return snowNormalizeString(self, 5);
}
- (NSString *)decomposedStringWithCompatibilityMapping {
    return snowNormalizeString(self, 3);
}
@end
