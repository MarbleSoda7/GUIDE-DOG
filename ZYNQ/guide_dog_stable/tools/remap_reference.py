#!/usr/bin/env python3
"""Host golden model for RMP2 v1, Q10.6, RGB888.

Cell interpolation matches kernel: floor horizontal lerps, then vertical lerp.
The last cell has width/height step-1, not step. Any invalid corner blacks
the entire cell. Source integer edges 799/479 are legal: clamp the +1 neighbor.
RGB channels match kernel: (weighted_sum + 2048) >> 12 (round half up).
This module does not touch hardware.
"""
import argparse
import hashlib
from pathlib import Path
import struct
import zlib

try:
    from .generate_remap_lut import INVALID,HEADER_FORMAT,geometry,grid_axis
except ImportError:
    from generate_remap_lut import INVALID,HEADER_FORMAT,geometry,grid_axis

def validate_blob(data,expected_eye=None,allow_synthetic=False,expected_config_hash=None):
    if len(data)<96 or data[:4]!=b"RMP2": raise ValueError("bad RMP2 header")
    fields=struct.unpack_from(HEADER_FORMAT,data,4)
    version,header,w,h,step,frac,eye,flags,cols,rows,nodes,size,crc=fields
    if version!=1 or header!=96 or eye not in (1,2) or flags&~1: raise ValueError("unsupported version/header/eye/flags")
    if geometry(w,h,step,frac)!=(cols,rows) or nodes!=cols*rows or size!=nodes*4 or len(data)!=96+size: raise ValueError("LUT geometry/length mismatch")
    if expected_eye is not None and eye!=expected_eye: raise ValueError("eye mismatch")
    if zlib.crc32(data[:36])&0xffffffff!=struct.unpack_from("<I",data,36)[0]: raise ValueError("header CRC mismatch")
    payload=data[96:]
    if zlib.crc32(payload)&0xffffffff!=crc: raise ValueError("payload CRC mismatch")
    if hashlib.sha256(payload).digest()!=data[40:72]: raise ValueError("payload SHA256 mismatch")
    if not any(data[72:96]): raise ValueError("missing calibration/config hash")
    if expected_config_hash is not None:
        expected=bytes.fromhex(expected_config_hash) if isinstance(expected_config_hash,str) else bytes(expected_config_hash)
        if len(expected)!=32 or expected[:24]!=data[72:96]: raise ValueError("calibration/config SHA256 mismatch")
    if not flags&1 and not allow_synthetic: raise ValueError("synthetic LUT requires explicit allow_synthetic")
    for x,y in struct.iter_unpack("<HH",payload):
        if x==INVALID or y==INVALID: continue
        if x>799*64 or y>479*64: raise ValueError("non-sentinel node out of image bounds")
    return {"width":w,"height":h,"step":step,"frac_bits":frac,"eye":eye,"calibration_valid":bool(flags&1),"config_hash_prefix":data[72:96].hex(),"payload":payload}

def grid_coordinate(payload,x,y,step=16):
    cols,rows=geometry(800,480,step,6)
    if len(payload)!=cols*rows*4: raise ValueError("payload length mismatch")
    if not 0<=x<800 or not 0<=y<480: return None
    gx=min(x//step,cols-2); gy=min(y//step,rows-2)
    x0=gx*step; y0=gy*step; cw=min(step,799-x0); ch=min(step,479-y0)
    dx=x-x0; dy=y-y0
    ns=[struct.unpack_from("<HH",payload,4*(gy*cols+gx)),struct.unpack_from("<HH",payload,4*(gy*cols+gx+1)),struct.unpack_from("<HH",payload,4*((gy+1)*cols+gx)),struct.unpack_from("<HH",payload,4*((gy+1)*cols+gx+1))]
    if any(INVALID in n for n in ns): return None
    top=[(ns[0][c]*(cw-dx)+ns[1][c]*dx)//cw for c in (0,1)]
    bottom=[(ns[2][c]*(cw-dx)+ns[3][c]*dx)//cw for c in (0,1)]
    return tuple((top[c]*(ch-dy)+bottom[c]*dy)//ch for c in (0,1))

def grid_row_incremental(payload,y,step=16):
    """Accumulate horizontal numerators; floor horizontally, then vertically."""
    cols,rows=geometry(800,480,step,6)
    if not 0<=y<480 or len(payload)!=cols*rows*4: raise ValueError("invalid row/payload")
    gy=min(y//step,rows-2); ch=min(step,479-gy*step); dy=y-gy*step
    out=[]
    for gx in range(cols-1):
        cw=min(step,799-gx*step); count=cw+int(gx==cols-2)
        n=[struct.unpack_from("<HH",payload,4*(r*cols+c)) for r,c in ((gy,gx),(gy,gx+1),(gy+1,gx),(gy+1,gx+1))]
        if any(INVALID in a for a in n): out.extend([None]*count); continue
        top_acc=[n[0][c]*cw for c in (0,1)]
        bottom_acc=[n[2][c]*cw for c in (0,1)]
        top_delta=[n[1][c]-n[0][c] for c in (0,1)]
        bottom_delta=[n[3][c]-n[2][c] for c in (0,1)]
        for _ in range(count):
            out.append(tuple(((top_acc[c]//cw)*(ch-dy)+(bottom_acc[c]//cw)*dy)//ch for c in (0,1)))
            for c in (0,1):
                top_acc[c]+=top_delta[c]; bottom_acc[c]+=bottom_delta[c]
    return out

def reconstruct_grid(payload,step=16):
    import numpy as np
    cols,rows=geometry(800,480,step,6)
    if len(payload)!=cols*rows*4: raise ValueError("payload length mismatch")
    nodes=np.frombuffer(payload,dtype="<u2").reshape(rows,cols,2).astype(np.int64)
    y,x=np.indices((480,800)); gx=np.minimum(x//step,cols-2); gy=np.minimum(y//step,rows-2)
    cw=np.minimum(step,799-gx*step); ch=np.minimum(step,479-gy*step); dx=x-gx*step; dy=y-gy*step
    ns=(nodes[gy,gx],nodes[gy,gx+1],nodes[gy+1,gx],nodes[gy+1,gx+1])
    top=(ns[0]*(cw-dx)[...,None]+ns[1]*dx[...,None])//cw[...,None]
    bottom=(ns[2]*(cw-dx)[...,None]+ns[3]*dx[...,None])//cw[...,None]
    q=(top*(ch-dy)[...,None]+bottom*dy[...,None])//ch[...,None]
    valid=np.logical_and.reduce([np.all(n!=INVALID,axis=2) for n in ns])
    q[~valid]=INVALID
    return q,valid

def sample_rgb888(source,qx,qy):
    if len(source)!=800*480*3: raise ValueError("RGB888 input must be 1152000 bytes")
    if qx==INVALID or qy==INVALID or not (0<=qx<=799*64 and 0<=qy<=479*64): return (0,0,0)
    x,y=qx>>6,qy>>6; dx,dy=qx&63,qy&63; x1=min(x+1,799); y1=min(y+1,479)
    offsets=((y*800+x)*3,(y*800+x1)*3,(y1*800+x)*3,(y1*800+x1)*3)
    weights=((64-dx)*(64-dy),dx*(64-dy),(64-dx)*dy,dx*dy)
    return tuple((sum(source[p+c]*w for p,w in zip(offsets,weights))+2048)>>12 for c in range(3))

def remap_rgb888(source,payload,step=16):
    import numpy as np
    if len(source)!=800*480*3: raise ValueError("RGB888 input must be 1152000 bytes")
    q,valid=reconstruct_grid(payload,step); q[~valid]=0
    valid &= (q[...,0]<=799*64)&(q[...,1]<=479*64)
    x=np.clip(q[...,0]>>6,0,799); y=np.clip(q[...,1]>>6,0,479); x1=np.minimum(x+1,799); y1=np.minimum(y+1,479)
    dx=q[...,0]&63; dy=q[...,1]&63; src=np.frombuffer(source,dtype=np.uint8).reshape(480,800,3).astype(np.int64)
    weights=((64-dx)*(64-dy),dx*(64-dy),(64-dx)*dy,dx*dy)
    out=(sum(p*w[...,None] for p,w in zip((src[y,x],src[y,x1],src[y1,x],src[y1,x1]),weights))+2048)>>12
    out[~valid]=0
    return out.astype(np.uint8).tobytes(),int((~valid).sum())

def _error_stats(values):
    import numpy as np
    return {"count":int(values.size),"rms_px":float(np.sqrt(np.mean(values**2))) if values.size else None,"p95_px":float(np.percentile(values,95)) if values.size else None,"max_px":float(values.max()) if values.size else None}

def analyze_maps(full,payload,step=16):
    import numpy as np
    full=np.asarray(full,dtype=np.float64)
    if full.shape!=(480,800,2): raise ValueError("full map must be 480x800x2")
    finite=np.isfinite(full).all(axis=2); inside=finite&(full[...,0]>=0)&(full[...,0]<=799)&(full[...,1]>=0)&(full[...,1]<=479)
    q,valid=reconstruct_grid(payload,step); valid &= (q[...,0]<=799*64)&(q[...,1]<=479*64)
    compare=inside&valid; err=np.linalg.norm(q/64.-full,axis=2)
    edge=np.zeros_like(inside); edge[:16]=edge[-16:]=True; edge[:,:16]=edge[:,-16:]=True
    yy,xx=np.nonzero(inside)
    stats={"finite_pixels":int(finite.sum()),"invalid_pixels":int((~inside).sum()),"valid_bbox_xywh":[int(xx.min()),int(yy.min()),int(xx.max()-xx.min()+1),int(yy.max()-yy.min()+1)] if xx.size else None,"bbox_is_not_all_valid_roi":True,"coordinate_min":full[finite].min(axis=0).tolist() if finite.any() else None,"coordinate_max":full[finite].max(axis=0).tolist() if finite.any() else None}
    errors={**_error_stats(err[compare]),"edge":_error_stats(err[compare&edge]),"grid_invalid_pixels":int((~valid).sum()),"full_valid_grid_invalid":int((inside&~valid).sum()),"full_invalid_grid_valid":int((~inside&valid).sum())}
    tiles=[]
    for y in range(0,480,16):
        for x in range(0,800,16):
            mask=inside[y:y+16,x:x+16]; points=full[y:y+16,x:x+16][mask]
            item={"output_xy":[x,y],"invalid_fraction":1-float(mask.mean()),"valid_pixels":int(mask.sum())}
            if points.size:
                lo=np.maximum(0,np.floor(points.min(axis=0)).astype(int)-1); hi=np.minimum([799,479],np.ceil(points.max(axis=0)).astype(int)+1)
                bw,bh=(hi-lo+1).tolist(); area=bw*bh
                item.update({"source_bbox_xyxy_inclusive":lo.tolist()+hi.tolist(),"bbox_area_pixels":area,"source_row_span":bh,"estimated_read_amplification":area/256.,"estimated_64byte_bursts":bh*((bw*3+63)//64),"exceeds_34x34_cache":bw>34 or bh>34})
            else: item.update({"source_bbox_xyxy_inclusive":None,"bbox_area_pixels":0,"source_row_span":0,"estimated_read_amplification":0.,"estimated_64byte_bursts":0,"exceeds_34x34_cache":False})
            tiles.append(item)
    locality={"tile_size":16,"bbox_padding_pixels":1,"burst_estimate_assumption":"contiguous RGB888 rows; 64-byte bursts ignoring alignment and inter-tile reuse","max_bbox_area_pixels":max(t["bbox_area_pixels"] for t in tiles),"mean_read_amplification":sum(t["estimated_read_amplification"] for t in tiles)/len(tiles),"cache_overflow_tiles":sum(t["exceeds_34x34_cache"] for t in tiles),"tiles":tiles}
    return {"full_map":stats,"grid_error":errors,"source_locality":locality}

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("--lut",required=True); p.add_argument("--source",required=True); p.add_argument("--output",required=True); p.add_argument("--allow-synthetic",action="store_true"); p.add_argument("--config-hash")
    a=p.parse_args(argv); lut=validate_blob(Path(a.lut).read_bytes(),allow_synthetic=a.allow_synthetic,expected_config_hash=a.config_hash)
    result,invalid=remap_rgb888(Path(a.source).read_bytes(),lut["payload"],lut["step"]); Path(a.output).write_bytes(result)
    print("invalid_pixels=%d crc32=%08x"%(invalid,zlib.crc32(result)&0xffffffff))
    return 0

if __name__=="__main__": raise SystemExit(main())
