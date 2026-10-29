"""Build native controls from the supplied Snow Leopard keyed archives."""
from pathlib import Path
import plistlib
import re
from tools.common.keyednib import generate_keyed, string


def preferences_layout(path):
    """Reserve room for icon-and-label pane buttons above the archived controls."""
    archive = plistlib.loads(path.read_bytes())
    objects = archive['$objects']
    def deref(value):
        return objects[value.data] if isinstance(value, plistlib.UID) else value
    def kind(value):
        cls = deref(value['$class'])['$classname'] if isinstance(value, dict) and '$class' in value else ''
        return deref(value['NSOriginalClassName']) if cls == 'NSClassSwapper' else cls
    def values(value):
        return [float(x) for x in re.findall(r'-?\d+(?:\.\d+)?', deref(value))]
    tabs = {}
    for i, obj in enumerate(objects):
        cls = kind(obj)
        if cls == 'NSTabView' and obj.get('NSTvFlags', 0) & 7 == 6:
            x, y, width, height = values(obj['NSFrame'])
            obj['NSFrame'] = '{{0, 0}, {%g, %g}}' % (width, height + 64)
            tabs[i] = -1
    # The top-level tab archive extends twelve points below its Cocoa window.
    # Icon-and-label buttons require another sixty-four points above its pane views.
    for obj in objects:
        if kind(obj) != 'NSWindowTemplate':
            continue
        root = deref(obj['NSWindowView'])
        children = deref(root.get('NSSubviews', {})).get('NS.objects', [])
        if not any(isinstance(child, plistlib.UID) and child.data in tabs for child in children):
            continue
        x, y, width, height = values(obj['NSWindowRect'])
        obj['NSWindowRect'] = '{{%g, %g}, {%g, %g}}' % (x, y, width, height + 76)
        root['NSFrameSize'] = '{%g, %g}' % (width, height + 76)
    for obj in objects:
        if kind(obj) not in ('NSButton', 'NSPopUpButton') or 'NSFrame' not in obj:
            continue
        x, y, width, height = values(obj['NSFrame'])
        if height == 26 and ((y == 33 and x in (20, 51, 82, 117)) or (x == 82 and y == 9)):
            obj['NSFrame'] = '{{%g, 25}, {%g, 24}}' % (x, width)
            if x == 82:
                cell = deref(obj['NSCell'])
                menu = deref(cell['NSMenu'])
                items = deref(menu['NSMenuItems'])['NS.objects']
                if items:
                    deref(items[0])['NSTitle'] = '...'
    return archive, tabs


def generate(resources, output, names=('MainMenu', 'TTWindow', 'TTAppPreferences', 'TTFindPanel', 'TTRunCommand', 'TTInspector', 'TTGenericPickerPanel', 'TTGenericSavePanel', 'TTProfileSaveAccessory', 'TTWorkspaceSaveAccessory', 'ServiceBrowser')):
    sources = []
    for name in names:
        path = Path(resources)/'English.lproj'/(name+'.nib')/'keyedobjects.nib'
        archive, tabs = preferences_layout(path) if name == 'TTAppPreferences' else (None, None)
        sources.append(generate_keyed(path, name, standalone_menus=True, bindings=True,
                                      archive=archive, tab_types=tabs))
    sources.append('BOOL TigerLoadNib(NSString *name,id owner) {')
    for name in names:
        sources.append('if([name isEqual:%s]) return TigerNib_%s(owner);' % (string(name), name))
    sources.append('return NO;\n}')
    Path(output).write_text('\n'.join(sources)+'\n', encoding='ascii')
