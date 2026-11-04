from pathlib import Path
import struct,hashlib,gzip,zipfile,json,shutil,zlib,xml.etree.ElementTree as ET
p=Path('/home/caitlyn/workdir/success_five'); project=Path('/mnt/d/distortion_correction/success_five'); out=project/'artifacts';out.mkdir(exist_ok=True)
def fdt(b):
 magic,total,off,strings=struct.unpack_from('>4I',b);assert magic==0xd00dfeed
 st=[]; props={};i=off
 while True:
  t=struct.unpack_from('>I',b,i)[0];i+=4
  if t==1:
   e=b.index(0,i);st.append(b[i:e].decode());i=(e+4)&~3
  elif t==2:st.pop()
  elif t==3:
   n,s=struct.unpack_from('>2I',b,i);i+=8;e=b.index(0,strings+s);key=b[strings+s:e].decode();props[('/'.join(st),key)]=b[i:i+n];i=(i+n+3)&~3
  elif t==4:continue
  elif t==9:break
  else:raise ValueError(t)
 return props
b=(p/'images/linux/image.ub').read_bytes();fit=fdt(b)
for (node,key),v in fit.items():
 if key=='value' and '/hash' in node:
  parent=node.rsplit('/',1)[0];data=fit[(parent,'data')];algo=fit[(node,'algo')].rstrip(b'\0').decode();assert hashlib.new(algo,data).digest()==v;print('FIT hash OK',parent,algo)
dtbs=[v for (n,k),v in fit.items() if k=='data' and v[:4]==bytes.fromhex('d00dfeed')];assert len(dtbs)==1
dt=fdt(dtbs[0]);assert struct.unpack('>2I',dt[('/reserved-memory/dualcam@30000000','reg')])==(0x30000000,0x01000000);print('DDR reserved-memory OK')
rams=[v for (n,k),v in fit.items() if k=='data' and fit.get((n,'type'),b'').startswith(b'ramdisk')];assert len(rams)==1
r=gzip.decompress(rams[0]);files={};i=0
while i<len(r):
 h=r[i:i+110];assert h[:6] in (b'070701',b'070702');size=int(h[54:62],16);ns=int(h[94:102],16);name=r[i+110:i+110+ns-1].decode();i=(i+110+ns+3)&~3;files[name.lstrip('./')]=r[i:i+size];i=(i+size+3)&~3
 if name=='TRAILER!!!':break
z=zipfile.ZipFile(project/'hardware.xsa');hwh=z.read('led_test.hwh');assert files['usr/share/camremap/led_test_wrapper.hwh']==hwh
src=p/'project-spec/meta-user/recipes-apps/camremap/files';pkg='/usr/lib/python3.10/site-packages/camremap/'
for f in (src/'camremap').glob('*.py'):
 vals=[(n,v) for n,v in files.items() if n.endswith('/camremap/'+f.name)]; assert len(vals)==1,(f.name,[n for n,v in vals]); assert vals[0][1]==f.read_bytes(),(f.name,vals[0][0],len(vals[0][1]),len(f.read_bytes()),hashlib.sha256(vals[0][1]).hexdigest(),hashlib.sha256(f.read_bytes()).hexdigest())
main=files['usr/lib/python3.10/site-packages/camremap/main.py'].decode();assert 'Ethernet frame source: camera%d VDMA1 ring' in main and 'self.tx_vdma = self.vdma2' in main and 'TX_CAMERA = 2' in main
assert files.get('etc/hostname',b'').strip()==b'success_five',files.get('etc/hostname');print('Rootfs hostname success_five verified')
assert files['etc/init.d/camremap']==(src/'camremap-init').read_bytes();assert any(n.startswith('etc/rc') and n.endswith('S99camremap') for n in files);print('Exact XSA HWH, camera2 TX software, and startup service verified')
boot=(p/'images/linux/BOOT.BIN').read_bytes();ph=struct.unpack_from('<I',boot,0x9c)[0];parts=[]
for j in range(4):
 h=struct.unpack_from('<16I',boot,ph+64*j);length=h[0]*4;offset=h[5]*4;data=boot[offset:offset+length];assert len(data)==length and length>0;parts.append(data);print('BOOT partition',j,offset,length)
bit=z.read('hardware.bit');sync=bit.index(bytes.fromhex('aa995566'));tail=bit[sync:];swap=b''.join(tail[i:i+4][::-1] for i in range(0,len(tail),4));assert any(tail in d or swap in d for d in parts),'BOOT does not contain XSA bitstream';assert any((p/'images/linux/system.dtb').read_bytes() in d for d in parts);print('BOOT contains current XSA bitstream and device tree')
scr=(p/'images/linux/boot.scr').read_bytes();sh=struct.unpack('>7I4B32s',scr[:64]);assert sh[0]==0x27051956 and zlib.crc32(scr[64:64+sh[3]])==sh[6] and b'image.ub' in scr;print('boot.scr CRC OK')
report={}
for name in ('BOOT.BIN','image.ub','boot.scr'):
 srcfile=p/'images/linux'/name; dest=out/name;shutil.copy2(srcfile,dest);data=dest.read_bytes();report[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
(out/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
