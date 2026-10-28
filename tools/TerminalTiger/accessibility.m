/* Accessibility names used by the original Terminal object graph. */
#import <AppKit/AppKit.h>
#include <stdlib.h>

static NSMutableDictionary *tigerAccessibilityOverrides;
@implementation NSObject (TigerAccessibility)
- (void)accessibilitySetOverrideValue:(id)value forAttribute:(NSString *)attribute {
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableDictionary *values;
    if (!tigerAccessibilityOverrides)
        tigerAccessibilityOverrides = [[NSMutableDictionary alloc] init];
    values = [tigerAccessibilityOverrides objectForKey:key];
    if (!values) {
        values = [NSMutableDictionary dictionary];
        [tigerAccessibilityOverrides setObject:values forKey:key];
    }
    if (value && attribute)
        [values setObject:value forKey:attribute];
    else if (attribute)
        [values removeObjectForKey:attribute];
}
- (id)accessibilityAttributeValue:(NSString *)attribute {
    return [[tigerAccessibilityOverrides objectForKey:[NSValue valueWithPointer:self]]
        objectForKey:attribute];
}
- (BOOL)accessibilityIsIgnored {
    return YES;
}
@end
void NSAccessibilityPostNotification(id object, NSString *name) {
    if (object && name)
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:object];
}
void NSAccessibilityRaiseBadArgumentException(id object, SEL selector, id attribute, id value) {
    [NSException raise:NSInvalidArgumentException
                format:@"Invalid accessibility value %@ for %@", value, attribute];
}
id NSAccessibilityRoleDescriptionForUIElement(id object) {
    return @"terminal";
}
id NSAccessibilityUnignoredDescendant(id object) {
    return object;
}
id NSAccessibilityUnignoredChildrenForOnlyChild(id object) {
    return object ? [NSArray arrayWithObject:object] : [NSArray array];
}
NSString *NSAccessibilityBoundsForRangeParameterizedAttribute = @"AXBoundsForRange";
NSString *NSAccessibilityChildrenAttribute = @"AXChildren";
NSString *NSAccessibilityContentsAttribute = @"AXContents";
NSString *NSAccessibilityCreatedNotification = @"AXCreated";
NSString *NSAccessibilityDescriptionAttribute = @"AXDescription";
NSString *NSAccessibilityFocusedAttribute = @"AXFocused";
NSString *NSAccessibilityHorizontalOrientationValue = @"AXHorizontalOrientation";
NSString *NSAccessibilityHorizontalScrollBarAttribute = @"AXHorizontalScrollBar";
NSString *NSAccessibilityInsertionPointLineNumberAttribute = @"AXInsertionPointLineNumber";
NSString *NSAccessibilityLineForIndexParameterizedAttribute = @"AXLineForIndex";
NSString *NSAccessibilityMaxValueAttribute = @"AXMaxValue";
NSString *NSAccessibilityMinValueAttribute = @"AXMinValue";
NSString *NSAccessibilityNextContentsAttribute = @"AXNextContents";
NSString *NSAccessibilityNumberOfCharactersAttribute = @"AXNumberOfCharacters";
NSString *NSAccessibilityOrientationAttribute = @"AXOrientation";
NSString *NSAccessibilityParentAttribute = @"AXParent";
NSString *NSAccessibilityPositionAttribute = @"AXPosition";
NSString *NSAccessibilityPreviousContentsAttribute = @"AXPreviousContents";
NSString *NSAccessibilityRangeForIndexParameterizedAttribute = @"AXRangeForIndex";
NSString *NSAccessibilityRangeForLineParameterizedAttribute = @"AXRangeForLine";
NSString *NSAccessibilityRangeForPositionParameterizedAttribute = @"AXRangeForPosition";
NSString *NSAccessibilityRoleAttribute = @"AXRole";
NSString *NSAccessibilityRoleDescriptionAttribute = @"AXRoleDescription";
NSString *NSAccessibilityScrollAreaRole = @"AXScrollArea";
NSString *NSAccessibilitySelectedTextAttribute = @"AXSelectedText";
NSString *NSAccessibilitySelectedTextChangedNotification = @"AXSelectedTextChanged";
NSString *NSAccessibilitySelectedTextRangeAttribute = @"AXSelectedTextRange";
NSString *NSAccessibilitySizeAttribute = @"AXSize";
NSString *NSAccessibilitySplitGroupRole = @"AXSplitGroup";
NSString *NSAccessibilitySplitterRole = @"AXSplitter";
NSString *NSAccessibilitySplittersAttribute = @"AXSplitters";
NSString *NSAccessibilityStringForRangeParameterizedAttribute = @"AXStringForRange";
NSString *NSAccessibilityTextAreaRole = @"AXTextArea";
NSString *NSAccessibilityTitleAttribute = @"AXTitle";
NSString *NSAccessibilityTopLevelUIElementAttribute = @"AXTopLevelUIElement";
NSString *NSAccessibilityUIElementDestroyedNotification = @"AXUIElementDestroyed";
NSString *NSAccessibilityValueAttribute = @"AXValue";
NSString *NSAccessibilityValueChangedNotification = @"AXValueChanged";
NSString *NSAccessibilityVerticalScrollBarAttribute = @"AXVerticalScrollBar";
NSString *NSAccessibilityVisibleCharacterRangeAttribute = @"AXVisibleCharacterRange";
NSString *NSAccessibilityWindowAttribute = @"AXWindow";
