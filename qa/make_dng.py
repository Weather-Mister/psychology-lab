"""Generate an openly reproducible synthetic Bayer DNG, not a camera photograph."""
import struct
from pathlib import Path
import sys
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
def make(orientation):
    width,height=128,96
    tags=[]
    def tag(n,t,values):
        formats={1:'B',3:'H',4:'I',5:'I',10:'i'}
        if t==2: data=values.encode()+b'\0';count=len(data)
        else:
            data=struct.pack('<'+formats[t]*len(values),*values)
            count=len(values)//2 if t in (5,10) else len(values)
        tags.append((n,t,count,data))
    tag(254,4,[0]);tag(256,4,[width]);tag(257,4,[height]);tag(258,3,[16]);tag(259,3,[1]);tag(262,3,[32803])
    tag(271,2,'Grainlight');tag(272,2,'Synthetic Bayer');tag(273,4,[0]);tag(274,3,[orientation]);tag(277,3,[1]);tag(278,4,[height]);tag(279,4,[width*height*2]);tag(284,3,[1])
    tag(33421,3,[2,2]);tag(33422,1,[0,1,1,2]);tag(50706,1,[1,4,0,0]);tag(50707,1,[1,1,0,0]);tag(50708,2,'Grainlight Synthetic Bayer')
    tag(50710,1,[0,1,2]);tag(50711,3,[1]);tag(50713,3,[1,1]);tag(50714,5,[0,1]);tag(50717,4,[65535])
    tag(50721,10,[1,1,0,1,0,1,0,1,1,1,0,1,0,1,0,1,1,1]);tag(50728,5,[1,1,1,1,1,1]);tag(50778,3,[21])
    tags.sort();start=8+2+12*len(tags)+4
    extra=bytearray();entries=[]
    for n,t,c,data in tags:
        if len(data)<=4: field=data.ljust(4,b'\0')
        else:
            field=struct.pack('<I',start+len(extra));extra.extend(data)
            if len(extra)%2:extra.append(0)
        entries.append([n,t,c,field])
    pixels_offset=start+len(extra)
    for e in entries:
        if e[0]==273:e[3]=struct.pack('<I',pixels_offset)
    header=b'II'+struct.pack('<HIH',42,8,len(tags))+b''.join(struct.pack('<HHI',n,t,c)+v for n,t,c,v in entries)+struct.pack('<I',0)+extra
    pixels=[int(65535*(0.02+0.8*x/(width-1))) for y in range(height) for x in range(width)]
    (out/f'synthetic-bayer-o{orientation}.dng').write_bytes(header+struct.pack('<'+'H'*len(pixels),*pixels))
make(1);make(6)
