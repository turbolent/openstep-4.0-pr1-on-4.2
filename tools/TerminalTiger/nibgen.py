"""Translate supported Tiger typedstream nibs to native AppKit construction.

Requires pytypedstream 0.1.0. Input archives remain the authority for object
identity, geometry, titles, actions, outlets, and view containment.
"""
import json
from pathlib import Path

import typedstream
from typedstream.types import appkit as a, foundation as f
from typedstream.archiving import GenericArchivedObject as Generic


def read_menu_item(self, reader, version):
    if version not in (505, 671):
        raise ValueError('Unsupported NSMenuItem version: ' + str(version))
    self.menu = reader.decode_value_of_type(a.NSMenu)
    fields = reader.decode_values_of_types(
        b'i', f.NSString, f.NSString, b'I', b'I', b'i',
        b'@', b'@', b'@', b'@', b':', b'i', b'@')
    self.flags, title, key, mask = fields[:4]
    self.title, self.key_equivalent = title.value, key.value
    self.modifier_flags = a.NSEventModifierFlags(mask)
    self.state = a.NSControlStateValue(fields[5])
    self.action, self.int_2 = fields[10:12]
    self.on_state_image, self.off_state_image, self.mixed_state_image = fields[7:10]
    self.target = reader.decode_value_of_type(b'@')
    self.submenu = reader.decode_value_of_type(a.NSMenu)


# The upstream reader rejects legitimate mnemonic locations other than INT_MAX.
a.NSMenuItem._init_from_unarchiver_ = read_menu_item


def read_combo_cell(self, reader, version):
    if version != 2:
        raise ValueError('Unsupported NSComboBoxCell version: '+str(version))
    self.number_of_visible_items, self.has_scroller, self.completes, self.uses_data_source = reader.decode_values_of_types(b'i',b'c',b'c',b'c')
    self.values=reader.decode_value_of_type(f.NSArray).elements
    self.combo_box=reader.decode_value_of_type(b'@')
    if self.combo_box is None:
        self.combo_box=reader.decode_value_of_type(a.NSView)
    self.button_cell=reader.decode_value_of_type(a.NSButtonCell)
    self.table_view=reader.decode_value_of_type(a.NSView)


a.NSComboBoxCell._init_from_unarchiver_=read_combo_cell


def string(value):
    if hasattr(value, 'value'):
        value = value.value
    value = value or ''
    if any(ord(c)>=127 or ord(c)<32 for c in value):
        encoded=''.join('\\%03o'%b for b in value.encode('utf-8'))
        return '[[[NSString alloc] initWithCString:"%s" encoding:4] autorelease]' % encoded
    return '@' + json.dumps(value)


def rect(value):
    return 'NSMakeRect(%s,%s,%s,%s)' % (
        value.origin.x, value.origin.y, value.size.width, value.size.height)


def properties(obj):
    if isinstance(obj, a.NSClassSwapper):
        return obj.class_name, obj.template, []
    if isinstance(obj, Generic):
        values = [x for group in obj.contents for x in group.values]
        name = obj.clazz.name.decode('ascii')
        if name == 'NSCustomView':
            name = values[0].value
        return name, obj.super_object, values
    return type(obj).__name__, obj, []


def generate_nib(path, name):
    nib = typedstream.unarchive_from_file(path)
    objects = list(nib.object_ids)
    # Cells and fonts may be reachable without an IB object ID.
    for obj in objects:
        _, base, _ = properties(obj)
        if isinstance(base, a.NSControl) and base.cell is not None and base.cell not in objects:
            objects.append(base.cell)
    index = {id(obj): i + 1 for i, obj in enumerate(objects)}
    popup_cells, popup_menus = {}, {}
    for obj in objects:
        cls,base,raw=properties(obj)
        if cls=='NSPopUpButton':
            cell_cls,cell,values=properties(base.cell)
            popup_cells[id(base.cell)]=obj
            popup_menus[id(values[3])]=(obj,values[0])
    def ref(obj):
        if obj is None:
            return 'nil'
        return 'o[%d]' % index[id(obj)]
    result = ['static BOOL TigerNib_%s(id owner) {' % name,
              'id o[%d]; unsigned i; memset(o,0,sizeof(o));' % (len(objects)+1)]
    later, connections = [], []
    for obj in objects:
        dest = ref(obj)
        cls, base, raw = properties(obj)
        if obj is nib.root:
            result.append('%s = owner;' % dest)
        elif isinstance(obj, a.NSNibConnector) or cls in ('NSNibAXAttributeConnector','NSNibAXRelationshipConnector'):
            continue
        elif isinstance(obj, a.NSMenu):
            result.append('%s = %s;' % (dest,'nil' if id(obj) in popup_menus else '[[NSMenu alloc] initWithTitle:%s]'%string(obj.title)))
        elif isinstance(obj, a.NSMenuItem):
            # Native menu items are cells created by their containing menu.
            continue
        elif isinstance(obj, a.NSCustomObject):
            if obj.class_name == 'FirstResponder':
                result.append('%s = nil;' % dest)
            else:
                result.append('%s = [[NSClassFromString(%s) alloc] init];' % (dest,string(obj.class_name)))
        elif cls == 'NSWindowTemplate':
            result.append('%s = [[NSClassFromString(%s) alloc] initWithContentRect:NSMakeRect(%s,%s,%s,%s) styleMask:%d backing:2 defer:YES];' % (dest,string(raw[8]),*raw[2:6],(raw[0]|1)&15))
            result.append('[%s setTitle:%s]; [%s setReleasedWhenClosed:NO];' % (dest,string(raw[7]),dest))
            later.append('[(NSWindow *)%s setContentView:(NSView *)%s];' % (dest,ref(raw[10])))
        elif isinstance(base,a.NSView):
            if cls == 'NSMatrix':
                result.append('%s = [[NSMatrix alloc] initWithFrame:%s mode:NSRadioModeMatrix cellClass:[NSButtonCell class] numberOfRows:%d numberOfColumns:%d];' % (dest,rect(base.frame),raw[3],raw[4]))
                result.append('[%s setCellSize:NSMakeSize(%s,%s)]; [%s setIntercellSpacing:NSMakeSize(%s,%s)];' % (dest,*raw[8:10],dest,*raw[10:12]))
                for j, cell in enumerate(raw[13].elements):
                    later.append('[%s putCell:%s atRow:%d column:%d];' % (dest,ref(cell),j//raw[4],j%raw[4]))
            else:
                result.append('%s = [[NSClassFromString(%s) alloc] initWithFrame:%s];' % (dest,string('TigerCompletingComboBox' if cls=='NSComboBox' else cls),rect(base.frame)))
            result.append('[%s setAutoresizingMask:%d];' % (dest,(base.flags>>24)&63))
            if cls=='NSBrowser':
                result.append('[%s setMaxVisibleColumns:%d]; [%s setTitled:NO];' % (dest,raw[12],dest))
            if cls=='NSBox' and base.frame.size.height<=4:
                result.append('[%s setTitle:@""]; [%s setTitlePosition:NSNoTitle]; [%s setBorderType:NSGrooveBorder];' % (dest,dest,dest))
            for child in base.subviews:
                later.append('[%s addSubview:%s];' % (dest,ref(child)))
            if isinstance(base,a.NSControl) and base.cell:
                if cls!='NSPopUpButton':
                    later.append('[%s setCell:%s];' % (dest,ref(base.cell)))
        elif isinstance(base,a.NSCell):
            title = base.title_or_image.value if isinstance(base.title_or_image,f.NSString) else ''
            if id(obj) in popup_cells:
                result.append('%s = [[%s cell] retain];' % (dest,ref(popup_cells[id(obj)])))
            else:
                result.append('%s = [[NSClassFromString(%s) alloc] initTextCell:%s];' % (dest,string(cls),string(title)))
            if isinstance(base,a.NSButtonCell):
                image_name=getattr(base.image_1,'resource_name','') or getattr(base.image_2_or_font,'resource_name','')
                button_type=3 if image_name=='NSSwitch' else (4 if image_name=='NSRadioButton' else 7)
                result.append('[%s setButtonType:%d]; [%s setBordered:%d];' % (dest,button_type,dest,button_type==7))
                result.append('[%s setTitle:%s]; [%s setImagePosition:%d];' % (dest,string(title),dest,2 if button_type in (3,4) else 0))
                if button_type in (3,4):
                    result.append('[%s setAlignment:NSLeftTextAlignment];' % dest)
                result.append('[%s setKeyEquivalent:%s];' % (dest,string(base.key_equivalent)))
            flags=base.flags_unknown[0]
            for selector,bit,invert in [('setState',31,False),('setEnabled',29,True),('setEditable',28,False),('setBordered',23,False),('setBezeled',22,False),('setSelectable',21,False),('setScrollable',20,False),('setWraps',6,True)]:
                if isinstance(base,a.NSButtonCell) and selector not in ('setState','setEnabled'):continue
                result.append('[%s %s:%d];' % (dest,selector,((flags>>bit)&1)^invert))
            if isinstance(base,a.NSActionCell):
                result.append('[%s setTag:%d];' % (dest,base.tag))
            if isinstance(base,a.NSTextFieldCell):
                result.append('[%s setDrawsBackground:%d];' % (dest,base.draws_background))
            if isinstance(base,a.NSComboBoxCell):
                result.append('[%s setNumberOfVisibleItems:%d]; [%s setHasVerticalScroller:%d]; [%s setUsesDataSource:%d];' % (dest,base.number_of_visible_items,dest,base.has_scroller,dest,base.uses_data_source))
                for value in base.values:
                    result.append('[%s addItemWithObjectValue:%s];' % (dest,string(value)))
            if base.font:
                result.append('[%s setFont:[NSFont systemFontOfSize:%s]];' % (dest,base.font.size))
        else:
            raise ValueError('Unsupported nib object: %s (%s)' % (cls,name))
    for obj in objects:
        if not isinstance(obj,a.NSMenu):
            continue
        for item in obj.items:
            if id(obj) in popup_menus:
                button,selected=popup_menus[id(obj)]
                result.append('[%s addItemWithTitle:%s]; %s = [[%s lastItem] retain];' % (ref(button),string(item.title),ref(item),ref(button)))
            else:
                result.append('%s = [(id)[%s addItemWithTitle:%s action:NULL keyEquivalent:%s] retain];' % (ref(item),ref(obj),string(item.title),string(item.key_equivalent)))
            result.append('[%s setTag:%d]; [%s setKeyEquivalentModifierMask:%d];' % (ref(item),item.int_2,ref(item),item.modifier_flags.value))
            if item.submenu:
                later.append('[%s setSubmenu:%s forItem:%s];' % (ref(obj),ref(item.submenu),ref(item)))
        if id(obj) in popup_menus:
            button,selected=popup_menus[id(obj)]
            if selected in obj.items:
                later.append('[%s selectItemAtIndex:%d];' % (ref(button),obj.items.index(selected)))
    result.extend(later)
    for connector in nib.connections:
        if isinstance(connector,a.NSNibControlConnector):
            connections.append('[%s setTarget:%s]; [%s setAction:sel_getUid(%s)];' % (ref(connector.source),ref(connector.destination),ref(connector.source),json.dumps(connector.label)))
            if connector.label in ('addServer:','addService:','removeServer:','removeService:'):
                connections.append('[%s setTitle:%s]; [%s setImagePosition:NSNoImage];' % (ref(connector.source),string('+' if connector.label.startswith('add') else '-'),ref(connector.source)))
        elif isinstance(connector,a.NSNibOutletConnector):
            connections.append('TigerOutlet(%s,%s,%s);' % (ref(connector.source),json.dumps(connector.label),ref(connector.destination)))
        elif isinstance(connector,Generic) and connector.clazz.name==b'NSNibAXRelationshipConnector':
            relation=connector.super_object
            connections.append('[%s accessibilitySetOverrideValue:%s forAttribute:%s];' % (ref(relation.source),ref(relation.destination),string(relation.label)))
        elif isinstance(connector,Generic) and connector.clazz.name==b'NSNibAXAttributeConnector':
            values=[value for group in connector.contents for value in group.values]
            connections.append('[%s accessibilitySetOverrideValue:%s forAttribute:%s];' % (ref(values[0]),string(values[2]),string(values[1])))
        else:
            raise ValueError('Unsupported nib connector: '+type(connector).__name__)
    result.extend(connections)
    for obj in objects:
        cls, base, _ = properties(obj)
        if cls == 'TermView':
            outlets = {c.label: c.destination for c in nib.connections
                       if isinstance(c, a.NSNibOutletConnector) and c.source is obj}
            buttons = [child for child in base.subviews
                       if properties(child)[0] == 'NSButton']
            if len(buttons) != 1:
                raise ValueError('Expected one Terminal split-view button')
            result.append('TigerLayoutTerminalPane(%s,%s,%s,YES);' % (
                ref(outlets['mainSubview']), ref(outlets['mainScroller']), ref(buttons[0])))
            result.append('TigerLayoutTerminalPane(%s,%s,nil,NO);' % (
                ref(outlets['scrollSubview']), ref(outlets['scrollScroller'])))
    for obj in objects:
        if isinstance(obj,a.NSMenu):
            role = {'_NSMainMenu':'setMainMenu', '_NSServicesMenu':'setServicesMenu', '_NSWindowsMenu':'setWindowsMenu'}.get(obj.identifier)
            if role:
                result.append('[NSApp %s:%s];' % (role,ref(obj)))
    result.append('for(i=1;i<%d;i++) if(o[i] && [o[i] respondsToSelector:@selector(awakeFromNib)]) [o[i] awakeFromNib];' % (len(objects)+1))
    result.append('return YES;\n}')
    return '\n'.join(result)


def generate(resources, output, names=('Terminal','Term','Find','Preferences','CommandPanel','InspectorX','AccessoryViews','ServiceBrowser')):
    source = ['/* Generated from the supplied Tiger nibs. */']
    for name in names:
        directory=Path(resources)/'English.lproj'/(name+'.nib')
        if (directory/'objects.nib').exists():source.append(generate_nib(directory/'objects.nib', name))
        else:
            from .keyednib import generate_keyed
            source.append(generate_keyed(directory/'keyedobjects.nib',name))
    source.append('BOOL TigerLoadNib(NSString *name,id owner) {')
    for name in names:
        source.append('if([name isEqual:%s]) return TigerNib_%s(owner);' % (string(name),name))
    source.append('return NO;\n}')
    Path(output).write_text('\n'.join(source)+'\n',encoding='ascii')
