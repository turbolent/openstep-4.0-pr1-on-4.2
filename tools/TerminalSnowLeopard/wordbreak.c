/* Default word boundaries from Unicode 5.1, UAX #29 revision 13.
 * Indexes and results use UTF-16 code units, as Core Foundation requires. */
static unsigned snowWordProperty(unsigned code) {
    unsigned low = 0, high = sizeof(snowWordProperties) / sizeof(snowWordProperties[0]);
    while (low < high) {
        unsigned mid = low + (high - low) / 2;
        if (code < snowWordProperties[mid].first)
            high = mid;
        else if (code > snowWordProperties[mid].last)
            low = mid + 1;
        else
            return snowWordProperties[mid].property;
    }
    return SNWB_Other;
}
static unsigned snowWordNext(const unsigned short *text, unsigned length, unsigned *index) {
    unsigned code = text[(*index)++];
    if (code >= 0xd800 && code <= 0xdbff && *index < length && text[*index] >= 0xdc00 &&
        text[*index] <= 0xdfff)
        code = 0x10000 + ((code - 0xd800) << 10) + (text[(*index)++] - 0xdc00);
    return snowWordProperty(code);
}
static unsigned snowWordPrevious(const unsigned short *text, unsigned *index) {
    unsigned code = text[--*index];
    if (code >= 0xdc00 && code <= 0xdfff && *index && text[*index - 1] >= 0xd800 &&
        text[*index - 1] <= 0xdbff)
        code = 0x10000 + ((text[--*index] - 0xd800) << 10) + (code - 0xdc00);
    return snowWordProperty(code);
}
static int snowWordIgnore(unsigned p) {
    return p == SNWB_Extend || p == SNWB_Format;
}
static int snowWordNewline(unsigned p) {
    return p == SNWB_CR || p == SNWB_LF || p == SNWB_Newline;
}
static int snowWordLetterMiddle(unsigned p) {
    return p == SNWB_MidLetter || p == SNWB_MidNumLet;
}
static int snowWordNumberMiddle(unsigned p) {
    return p == SNWB_MidNum || p == SNWB_MidNumLet;
}
static int snowWordJoined(unsigned p) {
    return p == SNWB_ALetter || p == SNWB_Numeric || p == SNWB_Katakana || p == SNWB_ExtendNumLet;
}
int SnowWordBoundary(const unsigned short *text, unsigned length, unsigned index) {
    unsigned before = index, after = index, left, right, previous = SNWB_Other, next = SNWB_Other;
    if (!index || index >= length)
        return 1;
    if (text[index] >= 0xdc00 && text[index] <= 0xdfff && text[index - 1] >= 0xd800 &&
        text[index - 1] <= 0xdbff)
        return 0;
    left = snowWordPrevious(text, &before);
    right = snowWordNext(text, length, &after);
    if (left == SNWB_CR && right == SNWB_LF)
        return 0;
    if (snowWordNewline(left) || snowWordNewline(right))
        return 1;
    if (snowWordIgnore(right))
        return 0;
    while (snowWordIgnore(left) && before)
        left = snowWordPrevious(text, &before);
    while (before) {
        previous = snowWordPrevious(text, &before);
        if (!snowWordIgnore(previous))
            break;
    }
    while (after < length) {
        next = snowWordNext(text, length, &after);
        if (!snowWordIgnore(next))
            break;
    }
    if ((left == SNWB_ALetter || left == SNWB_Numeric) &&
        (right == SNWB_ALetter || right == SNWB_Numeric))
        return 0;
    if (left == SNWB_ALetter && snowWordLetterMiddle(right) && next == SNWB_ALetter)
        return 0;
    if (previous == SNWB_ALetter && snowWordLetterMiddle(left) && right == SNWB_ALetter)
        return 0;
    if (left == SNWB_Numeric && snowWordNumberMiddle(right) && next == SNWB_Numeric)
        return 0;
    if (previous == SNWB_Numeric && snowWordNumberMiddle(left) && right == SNWB_Numeric)
        return 0;
    if (left == SNWB_Katakana && right == SNWB_Katakana)
        return 0;
    if ((snowWordJoined(left) && right == SNWB_ExtendNumLet) ||
        (left == SNWB_ExtendNumLet && snowWordJoined(right)))
        return 0;
    return 1;
}
