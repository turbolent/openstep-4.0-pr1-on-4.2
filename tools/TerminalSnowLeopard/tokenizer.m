/* Word-boundary tokenization for Terminal's double-click selection.
 * Dictionary segmentation for East Asian languages is not available. */
@interface SnowStringTokenizer : NSObject {
  @public
    unichar *characters;
    unsigned length, origin;
    NSRange token;
}
@end
@implementation SnowStringTokenizer
- (void)dealloc {
    free(characters);
    [super dealloc];
}
@end
void CFStringTokenizerSetString(SnowStringTokenizer *tokenizer, NSString *string, NSRange range) {
    unichar *characters = NULL;
    if (!tokenizer)
        return;
    if (range.location > [string length] || range.length > [string length] - range.location)
        [NSException raise:NSRangeException format:@"Invalid tokenizer range"];
    if (range.length) {
        if (range.length > INT_MAX / sizeof(unichar))
            [NSException raise:NSMallocException format:@"Tokenizer text is too large"];
        characters = malloc(range.length * sizeof(unichar));
        if (!characters)
            [NSException raise:NSMallocException format:@"Cannot allocate tokenizer text"];
        [string getCharacters:characters range:range];
    }
    free(tokenizer->characters);
    tokenizer->characters = characters;
    tokenizer->origin = range.location;
    tokenizer->length = range.length;
    tokenizer->token = NSMakeRange(0xffffffff, 0);
}
id CFStringTokenizerCreate(void *allocator, NSString *string, NSRange range, unsigned options,
                           id locale) {
    SnowStringTokenizer *tokenizer;
    if (options != 4)
        return nil;
    tokenizer = [[SnowStringTokenizer alloc] init];
    CFStringTokenizerSetString(tokenizer, string, range);
    return tokenizer;
}
unsigned CFStringTokenizerGoToTokenAtIndex(SnowStringTokenizer *tokenizer, int index) {
    unsigned start, end;
    if (!tokenizer)
        return 0;
    tokenizer->token = NSMakeRange(0xffffffff, 0);
    if (index < 0 || (unsigned)index < tokenizer->origin ||
        (unsigned)index - tokenizer->origin >= tokenizer->length)
        return 0;
    start = index - tokenizer->origin;
    end = start + 1;
    while (start && !SnowWordBoundary(tokenizer->characters, tokenizer->length, start))
        start--;
    while (end < tokenizer->length &&
           !SnowWordBoundary(tokenizer->characters, tokenizer->length, end))
        end++;
    tokenizer->token = NSMakeRange(start + tokenizer->origin, end - start);
    return 1;
}
/* Darwin i386 returns CFRange in EAX:EDX; OPENSTEP returns C structs via EBX. */
unsigned long long CFStringTokenizerGetCurrentTokenRange(SnowStringTokenizer *tokenizer) {
    return tokenizer
               ? ((unsigned long long)tokenizer->token.length << 32) | tokenizer->token.location
               : 0xffffffffU;
}
