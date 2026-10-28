"""Translate Tiger keyed interface archives into native AppKit construction."""
import plistlib
import re


def generate_keyed(path,name):
    from .nibgen import string
    archive=plistlib.loads(path.read_bytes())
    objects=archive['$objects']
    def deref(value):
        return objects[value.data] if isinstance(value,plistlib.UID) else value
    def text(value):
        value=deref(value)
        if isinstance(value,dict):
            return text(value.get('NS.string',value.get('NSString','')))
        return '' if value in (None,'$null') else str(value)
    def array(value):
        value=deref(value)
        return value.get('NS.objects',[]) if isinstance(value,dict) else []
    def cls(value):
        value=deref(value)
        return text(deref(value['$class'])['$classname']) if isinstance(value,dict) and '$class' in value else ''
    def ref(value):
        return 'o[%d]'%value.data if isinstance(value,plistlib.UID) and value.data else 'nil'
    def numbers(value):
        return [float(x) for x in re.findall(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?',text(value))]
    def size(value):
        values=numbers(value)
        return 'NSMakeSize(%g,%g)'%tuple(values[:2]) if len(values)>=2 else 'NSZeroSize'
    def rect(value,frame_size=None):
        values=numbers(value)
        if len(values)!=4:values=[0,0]+numbers(frame_size)
        return 'NSMakeRect(%g,%g,%g,%g)'%tuple(values) if len(values)==4 else 'NSZeroRect'
    root=deref(archive['$top']['IB.objectdata'])
    owner=root['NSRoot'].data
    source=['static BOOL TigerNib_%s(id owner) {'%name,'id o[%d]; unsigned i; memset(o,0,sizeof(o));'%len(objects)]
    attach,settings,connections=[],[],[]
    popup_cells={}
    for i,obj in enumerate(objects):
        if cls(obj)=='NSPopUpButton':popup_cells[obj['NSCell'].data]=i
    popup_menus={objects[cell]['NSMenu'].data:button for cell,button in popup_cells.items()}
    cells={'NSButtonCell','NSTextFieldCell','NSTableHeaderCell','NSPopUpButtonCell','NSSliderCell'}
    views={'NSView','NSCustomView','NSClassSwapper','NSButton','NSTextField','NSPopUpButton','NSMatrix','NSTabView','NSScrollView','NSClipView','NSTableView','NSTableHeaderView','NSScroller','NSColorWell','NSSlider','NSBox','_NSCornerView'}
    for i,obj in enumerate(objects):
        archived_kind=cls(obj)
        kind=text(obj.get('NSOriginalClassName')) if archived_kind=='NSClassSwapper' else archived_kind
        actual=text(obj.get('NSClassName')) if archived_kind in ('NSClassSwapper','NSCustomView') else kind
        dest='o[%d]'%i
        if i==owner:
            source.append('%s=owner;'%dest); continue
        if kind=='NSCustomObject':
            name_=text(obj.get('NSClassName'))
            value='nil' if name_=='FirstResponder' else '[[NSClassFromString(%s) alloc] init]'%string(name_)
            source.append('%s=%s;'%(dest,value))
        elif kind=='NSFont':
            source.append('%s=[[NSFont fontWithName:%s size:%g] retain]; if(!%s)%s=[[NSFont systemFontOfSize:%g] retain];'%(dest,string(text(obj.get('NSName'))),obj.get('NSSize',13),dest,dest,obj.get('NSSize',13)))
        elif kind=='NSColor':
            space=obj.get('NSColorSpace',3)
            if space==6:
                attach.append('%s=[%s retain];'%(dest,ref(obj.get('NSColor')))); continue
            raw=obj.get('NSRGB',obj.get('NSWhite',obj.get('NSCMYK',b'0 1')))
            values=[float(x) for x in raw.rstrip(b'\0').split()]
            components=4 if space in (1,2) else (5 if space==5 else 2)
            if len(values)==components-1:values.append(1.0)
            if space in (1,2):expression='[NSColor colorWithCalibratedRed:%g green:%g blue:%g alpha:%g]'%tuple(values)
            elif space==5:expression='[NSColor colorWithDeviceCyan:%g magenta:%g yellow:%g black:%g alpha:%g]'%tuple(values)
            else:expression='[NSColor colorWithCalibratedWhite:%g alpha:%g]'%tuple(values)
            source.append('%s=[%s retain];'%(dest,expression))
        elif kind=='NSWindowTemplate':
            source.append('%s=[[NSClassFromString(%s) alloc] initWithContentRect:%s styleMask:%d backing:2 defer:YES];'%(dest,string(text(obj['NSWindowClass'])),rect(obj['NSWindowRect']),(obj.get('NSWindowStyleMask',1)|1)&15))
            source.append('[%s setTitle:%s]; [%s setReleasedWhenClosed:NO];'%(dest,string(text(obj.get('NSWindowTitle'))),dest))
            attach.append('[(NSWindow *)%s setContentView:(NSView *)%s];'%(dest,ref(obj['NSWindowView'])))
        elif kind in views:
            if actual=='_NSCornerView':actual='NSView'
            frame=rect(obj.get('NSFrame'),obj.get('NSFrameSize'))
            if kind=='NSMatrix':
                source.append('%s=[[NSMatrix alloc] initWithFrame:%s mode:NSRadioModeMatrix cellClass:[NSButtonCell class] numberOfRows:%d numberOfColumns:%d];'%(dest,frame,obj['NSNumRows'],obj['NSNumCols']))
                settings.append('[%s setCellSize:%s]; [%s setIntercellSpacing:%s];'%(dest,size(obj['NSCellSize']),dest,size(obj['NSIntercellSpacing'])))
                for j,cell in enumerate(array(obj.get('NSCells'))):attach.append('[%s putCell:%s atRow:%d column:%d];'%(dest,ref(cell),j//obj['NSNumCols'],j%obj['NSNumCols']))
                selected=obj.get('NSSelectedCell')
                if selected in array(obj.get('NSCells')):
                    j=array(obj['NSCells']).index(selected)
                    settings.append('[%s selectCellAtRow:%d column:%d];'%(dest,j//obj['NSNumCols'],j%obj['NSNumCols']))
            else:source.append('%s=[[NSClassFromString(%s) alloc] initWithFrame:%s];'%(dest,string(actual),frame))
            source.append('[%s setAutoresizingMask:%d];'%(dest,obj.get('NSvFlags',0)&63))
            if 'NSEnabled' in obj:settings.append('[%s setEnabled:%d];'%(dest,obj['NSEnabled']))
            if 'NSTag' in obj:settings.append('[%s setTag:%d];'%(dest,obj['NSTag']))
            if 'NSCell' in obj and kind!='NSPopUpButton':attach.append('[%s setCell:%s];'%(dest,ref(obj['NSCell'])))
            if kind=='NSBox':
                child=obj.get('NSContentView') or next(iter(array(obj.get('NSSubviews'))),None)
                if child:attach.append('[(NSBox *)%s setContentView:(NSView *)%s];'%(dest,ref(child)))
                cell=deref(obj.get('NSTitleCell',{}))
                settings.append('[%s setTitle:%s]; [%s setTitlePosition:%d]; [%s setBorderType:%d];'%(dest,string(text(cell.get('NSContents'))),dest,obj.get('NSTitlePosition',0),dest,obj.get('NSBorderType',0)))
            elif kind=='NSTabView':
                for item in array(obj.get('NSTabViewItems')):attach.append('[%s addTabViewItem:%s];'%(dest,ref(item)))
                settings.append('[%s setTabViewType:%d]; [%s selectTabViewItem:%s];'%(dest,obj.get('NSTvFlags',0)&7,dest,ref(obj.get('NSSelectedTabViewItem'))))
            elif kind=='NSScrollView':
                attach.append('[(NSScrollView *)%s setContentView:(NSClipView *)%s];'%(dest,ref(obj.get('NSContentView'))))
                settings.append('[%s setHasVerticalScroller:%d]; [%s setHasHorizontalScroller:%d];'%(dest,bool(obj.get('NSsFlags',0)&2),dest,bool(obj.get('NSsFlags',0)&1)))
            elif kind=='NSClipView':
                if obj.get('NSDocView'):attach.append('[%s setDocumentView:%s];'%(dest,ref(obj['NSDocView'])))
            elif kind=='NSTableView' or (kind=='NSClassSwapper' and 'NSTableColumns' in obj):
                for column in array(obj.get('NSTableColumns')):attach.append('[%s addTableColumn:%s];'%(dest,ref(column)))
                settings.append('[%s setHeaderView:%s]; [%s setRowHeight:%g];'%(dest,ref(obj.get('NSHeaderView')),dest,obj.get('NSRowHeight',14)))
            else:
                for child in array(obj.get('NSSubviews')):attach.append('[%s addSubview:%s];'%(dest,ref(child)))
            if kind=='NSColorWell':settings.append('[%s setColor:%s];'%(dest,ref(obj.get('NSColor'))))
        elif kind in cells:
            if i in popup_cells:
                attach.append('%s=[[o[%d] cell] retain];'%(dest,popup_cells[i])); continue
            title=string(text(obj.get('NSContents')))
            source.append('%s=[[NSClassFromString(%s) alloc] initTextCell:%s];'%(dest,string(kind),title))
            flags=obj.get('NSCellFlags',0)&0xffffffff
            if kind=='NSButtonCell':
                images=[deref(obj.get(key,{})) for key in ('NSNormalImage','NSAlternateImage')]
                names=[text(v.get('NSResourceName',v.get('NSImageName'))) for v in images if isinstance(v,dict)]
                button_type=3 if 'NSSwitch' in names else (4 if 'NSRadioButton' in names else 7)
                settings.append('[%s setButtonType:%d]; [%s setBordered:%d]; [%s setKeyEquivalent:%s];'%(dest,button_type,dest,button_type==7,dest,string(text(obj.get('NSKeyEquivalent')))))
                settings.append('[%s setTitle:%s]; [%s setImagePosition:%d];'%(dest,title,dest,2 if button_type in (3,4) else 0))
                if button_type in (3,4):
                    settings.append('[%s setAlignment:NSLeftTextAlignment];'%dest)
            for selector,bit,invert in [('setState',31,False),('setEnabled',29,True),('setEditable',28,False),('setBordered',23,False),('setBezeled',22,False),('setSelectable',21,False),('setScrollable',20,False),('setWraps',6,True)]:
                if kind=='NSButtonCell' and selector not in ('setState','setEnabled'):continue
                settings.append('[%s %s:%d];'%(dest,selector,((flags>>bit)&1)^invert))
            if 'NSTag' in obj:settings.append('[%s setTag:%d];'%(dest,obj['NSTag']))
            if cls(obj.get('NSSupport'))=='NSFont':settings.append('[%s setFont:%s];'%(dest,ref(obj['NSSupport'])))
            if kind in ('NSTextFieldCell','NSTableHeaderCell'):
                settings.append('[%s setDrawsBackground:%d];'%(dest,obj.get('NSDrawsBackground',False)))
                for key,selector in [('NSTextColor','setTextColor'),('NSBackgroundColor','setBackgroundColor'),('NSFormatter','setFormatter')]:
                    if key in obj:settings.append('[%s %s:%s];'%(dest,selector,ref(obj[key])))
            if kind=='NSSliderCell':
                for key,selector in [('NSMinValue','setMinValue'),('NSMaxValue','setMaxValue'),('NSValue','setDoubleValue')]:settings.append('[%s %s:%g];'%(dest,selector,obj.get(key,0)))
        elif kind=='NSTabViewItem':
            source.append('%s=[[NSTabViewItem alloc] initWithIdentifier:%s];'%(dest,string(text(obj.get('NSIdentifier',str(i))))))
            attach.append('[%s setView:%s]; [%s setLabel:%s];'%(dest,ref(obj.get('NSView')),dest,string(text(obj.get('NSLabel')))))
        elif kind=='NSTableColumn':
            source.append('%s=[[NSClassFromString(%s) alloc] initWithIdentifier:%s];'%(dest,string(actual),string(text(obj.get('NSIdentifier',str(i))))))
            attach.append('[%s setHeaderCell:%s]; [%s setDataCell:%s];'%(dest,ref(obj.get('NSHeaderCell')),dest,ref(obj.get('NSDataCell'))))
            for key,selector in [('NSMinWidth','setMinWidth'),('NSMaxWidth','setMaxWidth'),('NSWidth','setWidth')]:
                if key in obj:settings.append('[%s %s:%g];'%(dest,selector,obj[key]))
        elif kind=='NSNumberFormatter':
            source.append('%s=[[NSNumberFormatter alloc] init];'%dest)
            settings.append('[%s setAllowsFloats:%d];'%(dest,obj.get('NS.allowsfloats',False)))
        elif kind=='NSMenu':
            if i in popup_menus:
                button='o[%d]'%popup_menus[i]
                for item in array(obj.get('NSMenuItems')):
                    definition=deref(item)
                    attach.append('[%s addItemWithTitle:%s]; %s=[(id)[%s lastItem] retain]; [%s setTag:%d];'%(button,string(text(definition.get('NSTitle'))),ref(item),button,ref(item),definition.get('NSTag',0)))
                cell=objects[objects[popup_menus[i]]['NSCell'].data]
                if cell.get('NSSelectedIndex',-1)>=0:settings.append('[%s selectItemAtIndex:%d];'%(button,cell['NSSelectedIndex']))
            else:raise ValueError('Unowned keyed menu in '+name)
    for connector in array(root.get('NSConnections'))+array(root.get('NSAccessibilityConnectors')):
        item=deref(connector); kind=cls(item)
        source_ref=ref(item.get('NSSource')); target=ref(item.get('NSDestination')); label=text(item.get('NSLabel'))
        if kind=='NSNibOutletConnector':connections.append('TigerOutlet(%s,%s,%s);'%(source_ref,string(label)[1:],target))
        elif kind=='NSNibControlConnector':connections.append('[%s setTarget:%s]; [%s setAction:sel_getUid(%s)];'%(source_ref,target,source_ref,string(label)[1:]))
        elif kind=='NSNibAXRelationshipConnector':connections.append('[%s accessibilitySetOverrideValue:%s forAttribute:%s];'%(source_ref,target,string(label)))
        elif kind=='NSNibAXAttributeConnector':
            connections.append('[%s accessibilitySetOverrideValue:%s forAttribute:%s];'%(ref(item.get('AXDestinationArchiveKey')),string(text(item.get('AXAttributeValueArchiveKey'))),string(text(item.get('AXAttributeTypeArchiveKey')))))
        else:raise ValueError('Unsupported keyed connector '+kind)
    source.extend(attach); source.extend(settings); source.extend(connections)
    source.append('for(i=1;i<%d;i++) if(o[i] && [o[i] respondsToSelector:@selector(awakeFromNib)]) [o[i] awakeFromNib];'%len(objects))
    source.append('return YES;\n}')
    return '\n'.join(source)
