/* Terminal uses only the standard sRGB and D50 Lab profiles. Convert these
 * analytically; arbitrary ICC profiles are not supported by this adapter.
 * CMLabColor uses L=0..65535 and a,b=(component+128)*256. */
static int snowSRGBProfile = 1, snowLabProfile = 2;
static int snowRGBToLab = 1, snowLabToRGB = 2, snowIdentityColor = 3;
int CMOpenProfile(void **profile, const void *location) {
    const char *path;
    unsigned short kind;
    if (!profile || !location)
        return -50;
    *profile = NULL;
    memcpy(&kind, location, 2);
    path = (const char *)location + 2;
    if (kind != 5)
        return -4;
    if (!strcmp(path, "/System/Library/ColorSync/Profiles/sRGB Profile.icc"))
        *profile = &snowSRGBProfile;
    else if (!strcmp(path, "/System/Library/ColorSync/Profiles/Generic Lab Profile.icc"))
        *profile = &snowLabProfile;
    else
        return -43;
    return 0;
}
int NCWNewColorWorld(void **world, void *source, void *destination) {
    if (!world)
        return -50;
    *world = NULL;
    if ((source != &snowSRGBProfile && source != &snowLabProfile) ||
        (destination != &snowSRGBProfile && destination != &snowLabProfile))
        return -50;
    *world = source == destination ? &snowIdentityColor
                                   : (source == &snowSRGBProfile ? &snowRGBToLab : &snowLabToRGB);
    return 0;
}
static double snowLabCurve(double value) {
    return value > 216.0 / 24389 ? pow(value, 1.0 / 3) : (24389.0 / 27 * value + 16) / 116;
}
static double snowLabInverse(double value) {
    return value > 6.0 / 29 ? value * value * value : (116 * value - 16) * 27 / 24389;
}
static double snowSRGBLinear(double value) {
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
}
static double snowSRGBEncoded(double value) {
    return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1.0 / 2.4) - 0.055;
}
static unsigned short snowColor16(double value) {
    return value <= 0 ? 0 : (value >= 65535 ? 65535 : (unsigned short)(value + 0.5));
}
int CWMatchColors(void *world, unsigned short *colors, unsigned count) {
    unsigned i;
    if (!colors ||
        (world != &snowRGBToLab && world != &snowLabToRGB && world != &snowIdentityColor))
        return -50;
    if (world == &snowIdentityColor)
        return 0;
    for (i = 0; i < count; i++, colors += 4) { /* CMColor's union includes four-channel CMYK. */
        double x, y, z, r, g, b;
        if (world == &snowRGBToLab) {
            r = snowSRGBLinear(colors[0] / 65535.0);
            g = snowSRGBLinear(colors[1] / 65535.0);
            b = snowSRGBLinear(colors[2] / 65535.0);
            /* Bradford-adapted sRGB to D50 XYZ, then CIE Lab. */
            x = snowLabCurve((0.4360747 * r + 0.3850649 * g + 0.1430804 * b) / 0.96422);
            y = snowLabCurve(0.2225045 * r + 0.7168786 * g + 0.0606169 * b);
            z = snowLabCurve((0.0139322 * r + 0.0971045 * g + 0.7141733 * b) / 0.82521);
            colors[0] = snowColor16((116 * y - 16) * 65535 / 100);
            colors[1] = snowColor16((500 * (x - y) + 128) * 256);
            colors[2] = snowColor16((200 * (y - z) + 128) * 256);
        } else {
            y = (colors[0] * 100 / 65535.0 + 16) / 116;
            x = snowLabInverse(y + (colors[1] / 256.0 - 128) / 500) * 0.96422;
            z = snowLabInverse(y - (colors[2] / 256.0 - 128) / 200) * 0.82521;
            y = snowLabInverse(y);
            r = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z;
            g = -0.9787684 * x + 1.9161415 * y + 0.0334540 * z;
            b = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z;
            colors[0] = snowColor16(snowSRGBEncoded(r) * 65535);
            colors[1] = snowColor16(snowSRGBEncoded(g) * 65535);
            colors[2] = snowColor16(snowSRGBEncoded(b) * 65535);
        }
    }
    return 0;
}
