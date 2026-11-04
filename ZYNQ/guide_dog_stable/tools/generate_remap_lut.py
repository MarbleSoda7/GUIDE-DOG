#!/usr/bin/env python3
"""Offline RMP2 v1 generation, never deploys or runs HLS/Vivado.
K and rectified_K override FOV metadata. Synthetic files require opt-in.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib

MAGIC, VERSION, HEADER_BYTES, INVALID = b"RMP2", 1, 96, 0xFFFF
WIDTH, HEIGHT, FRAC_BITS = 800, 480, 6
HEADER_FORMAT = "<HHHHHHHHHHIII"

def finite(x, name):
    if isinstance(x, bool) or not isinstance(x, (int,float)) or not math.isfinite(x):
        raise ValueError(name + " must be finite numeric")
    return float(x)

def matrix(cam,key,default):
    m = cam.get(key,default)
    if not isinstance(m,(list,tuple)) or len(m)!=3 or any(not isinstance(r,(list,tuple)) or len(r)!=3 for r in m):
        raise ValueError(key + " must be 3x3")
    return [[finite(v,key) for v in r] for r in m]

def inv3(m):
    a,b,c=m[0]; d,e,f=m[1]; g,h,i=m[2]
    det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    if not math.isfinite(det) or abs(det)<1e-12: raise ValueError("camera matrix is singular")
    return [[(e*i-f*h)/det,(c*h-b*i)/det,(b*f-c*e)/det],[(f*g-d*i)/det,(a*i-c*g)/det,(c*d-a*f)/det],[(d*h-e*g)/det,(b*g-a*h)/det,(a*e-b*d)/det]]

def mv(m,v): return [sum(m[r][k]*v[k] for k in range(3)) for r in range(3)]
def tr(m): return [list(row) for row in zip(*m)]

def camera_k(cam,w=800,h=480):
    if "K" in cam: return matrix(cam,"K",None)
    fov=finite(cam.get("hfov_deg",170.0),"hfov_deg")
    if not 0<fov<180: raise ValueError("synthetic horizontal FOV must be in (0,180)")
    fx=finite(cam.get("fx",w/math.radians(fov)),"fx")
    fy=finite(cam.get("fy",fx),"fy")
    return [[fx,0.,finite(cam.get("cx",(w-1)/2),"cx")],[0.,fy,finite(cam.get("cy",(h-1)/2),"cy")],[0.,0.,1.]]

def camera_parts(cam,w=800,h=480):
    K=camera_k(cam,w,h)
    if "rectified_K" in cam: Kn=matrix(cam,"rectified_K",None)
    else:
        fov=finite(cam.get("rectified_hfov_deg",100.),"rectified_hfov_deg")
        if not 0<fov<180: raise ValueError("rectified FOV must be in (0,180)")
        f=w/2/math.tan(math.radians(fov)/2)
        Kn=[[f,0.,(w-1)/2],[0.,f,(h-1)/2],[0.,0.,1.]]
    for name,m in (("K",K),("rectified_K",Kn)):
        if m[0][0]<=0 or m[1][1]<=0 or any(abs(m[r][c]-v)>1e-9 for r,c,v in ((1,0,0),(2,0,0),(2,1,0),(2,2,1))):
            raise ValueError(name + " must be upper triangular positive-focal intrinsics")
        inv3(m)
    if abs(K[0][1])>1e-9: raise ValueError("source K skew must be zero (CALIB_FIX_SKEW)")
    D=cam.get("D",[0.,0.,0.,0.])
    if not isinstance(D,(list,tuple)) or len(D)!=4: raise ValueError("D needs four fisheye coefficients")
    D=[finite(v,"D") for v in D]
    R=matrix(cam,"R",[[1.,0.,0.],[0.,1.,0.],[0.,0.,1.]])
    if any(abs(sum(R[k][r]*R[k][c] for k in range(3))-(r==c))>1e-5 for r in range(3) for c in range(3)):
        raise ValueError("R must be orthonormal")
    det=sum(R[0][i]*(R[1][(i+1)%3]*R[2][(i+2)%3]-R[1][(i+2)%3]*R[2][(i+1)%3]) for i in range(3))
    if abs(det-1)>1e-5: raise ValueError("R determinant must be +1")
    return K,D,R,Kn

def source_xy(cam,u,v,w=800,h=480):
    K,D,R,Kn=camera_parts(cam,w,h)
    q=mv(tr(R),mv(inv3(Kn),[u,v,1.]))
    if not all(math.isfinite(t) for t in q) or q[2]<=1e-12: return None
    x,y=q[0]/q[2],q[1]/q[2]; r=math.hypot(x,y); t=math.atan(r); t2=t*t
    s=t*(1+D[0]*t2+D[1]*t2**2+D[2]*t2**3+D[3]*t2**4)/r if r>1e-12 else 1.
    p=(K[0][0]*x*s+K[0][2],K[1][1]*y*s+K[1][2])
    return p if all(math.isfinite(z) for z in p) else None

def full_map(cam,w=800,h=480):
    import numpy as np
    K,D,R,Kn=camera_parts(cam,w,h)
    y,x=np.indices((h,w),dtype=np.float64)
    rays=np.asarray(R).T@np.asarray(inv3(Kn))@np.stack((x.ravel(),y.ravel(),np.ones(w*h)))
    with np.errstate(all="ignore"):
        x,y=rays[0]/rays[2],rays[1]/rays[2]; r=np.hypot(x,y); t=np.arctan(r); t2=t*t
        s=np.divide(t*(1+D[0]*t2+D[1]*t2**2+D[2]*t2**3+D[3]*t2**4),r,out=np.ones_like(r),where=r>1e-12)
        result=np.stack((K[0][0]*x*s+K[0][2],K[1][1]*y*s+K[1][2]),axis=-1)
    result[(rays[2]<=1e-12)|~np.isfinite(result).all(axis=1)]=np.nan
    return result.reshape(h,w,2)

def grid_axis(extent,step):
    if type(extent) is not int or type(step) is not int or extent<2 or step<1: raise ValueError("integer extent>=2 and step>=1 required")
    a=list(range(0,extent,step))
    if a[-1]!=extent-1: a.append(extent-1)
    return a

def geometry(w,h,step,frac):
    if any(type(v) is not int for v in (w,h,step,frac)) or (w,h,frac)!=(800,480,6) or step not in (8,16):
        raise ValueError("RMP2 requires 800x480, step8/16, Q10.6")
    return len(grid_axis(w,step)),len(grid_axis(h,step))

def qcoord(x,limit,frac=6):
    if x is None or not math.isfinite(x) or not 0<=x<=limit-1: return INVALID
    q=int(round(x*(1<<frac)))
    return q if 0<=q<INVALID else INVALID

def make_payload(cam,w,h,step,frac=6):
    cols,rows=geometry(w,h,step,frac); camera_parts(cam,w,h); out=bytearray(); bad=0
    for y in grid_axis(h,step):
        for x in grid_axis(w,step):
            p=source_xy(cam,x,y,w,h)
            sx=qcoord(None if p is None else p[0],w,frac); sy=qcoord(None if p is None else p[1],h,frac)
            if sx==INVALID or sy==INVALID: sx=sy=INVALID; bad+=1
            out+=struct.pack("<HH",sx,sy)
    return cols,rows,bytes(out),bad

def validate_config(c):
    json.dumps(c,allow_nan=False)
    w,h,step,frac=(c.get("width",800),c.get("height",480),c.get("grid_step",16),c.get("frac_bits",6))
    geometry(w,h,step,frac)
    if type(c.get("calibration_valid",False)) is not bool: raise ValueError("calibration_valid must be boolean")
    for eye in ("left","right"):
        camera_parts(c[eye],w,h)
        if c.get("calibration_valid",False) and any(k not in c[eye] for k in ("K","D","R","rectified_K")):
            raise ValueError("measured calibration needs explicit K/D/R/rectified_K")
    if c.get("baseline_mm") is not None and finite(c["baseline_mm"],"baseline_mm")<=0: raise ValueError("baseline_mm must be positive")
    return w,h,step,frac

def calibration_config_sha256(c):
    return hashlib.sha256(json.dumps(c,sort_keys=True,separators=(",",":"),ensure_ascii=False,allow_nan=False).encode("utf-8")).digest()

def blob(w,h,step,frac,eye,cols,rows,payload,calibration_valid=False,config_hash=None):
    if geometry(w,h,step,frac)!=(cols,rows) or eye not in (1,2) or len(payload)!=cols*rows*4: raise ValueError("invalid geometry/eye/payload")
    if config_hash is None: raise ValueError("explicit calibration/config SHA256 required")
    if isinstance(config_hash,str): config_hash=bytes.fromhex(config_hash)
    if len(config_hash)!=32: raise ValueError("config_hash must contain 32 bytes")
    hdr=bytearray(96); hdr[:4]=MAGIC
    struct.pack_into(HEADER_FORMAT,hdr,4,1,96,w,h,step,frac,eye,int(bool(calibration_valid)),cols,rows,cols*rows,len(payload),zlib.crc32(payload)&0xffffffff)
    struct.pack_into("<I",hdr,36,zlib.crc32(hdr[:36])&0xffffffff)
    hdr[40:72]=hashlib.sha256(payload).digest(); hdr[72:96]=config_hash[:24]
    return bytes(hdr)+payload

def generate(config,output_dir,allow_synthetic=False,step=None):
    c=dict(config)
    if step is not None: c["grid_step"]=step
    w,h,step,frac=validate_config(c)
    if not c.get("calibration_valid",False) and not allow_synthetic: raise ValueError("calibration_valid=false: require --allow-synthetic for smoke testing")
    try: from .remap_reference import analyze_maps
    except ImportError: from remap_reference import analyze_maps
    digest=calibration_config_sha256(c)
    manifest={"schema":"pl-remap-manifest-v1","format":"RMP2-v1","width":w,"height":h,"step":step,"frac_bits":frac,"calibration_valid":c.get("calibration_valid",False),"baseline_mm":c.get("baseline_mm"),"calibration_config_sha256":digest.hex(),"hash_definition":"SHA256 sorted compact UTF-8 JSON effective config including step override","eyes":{}}
    products={}
    for eye,name in ((1,"left"),(2,"right")):
        cols,rows,payload,bad=make_payload(c[name],w,h,step,frac)
        products[name]=blob(w,h,step,frac,eye,cols,rows,payload,c.get("calibration_valid",False),digest)
        manifest["eyes"][name]={"file":name+"_remap.rmp","grid_cols":cols,"grid_rows":rows,"node_count":cols*rows,"payload_bytes":len(payload),"invalid_nodes":bad,"sha256":hashlib.sha256(payload).hexdigest(),"file_sha256":hashlib.sha256(products[name]).hexdigest(),**analyze_maps(full_map(c[name]),payload,step)}
    out=Path(output_dir); out.mkdir(parents=True,exist_ok=True)
    for name,data in products.items(): (out/(name+"_remap.rmp")).write_bytes(data)
    (out/"remap_manifest.json").write_text(json.dumps(manifest,indent=2,allow_nan=False),encoding="utf-8")
    return manifest

def main(argv=None):
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument("--config",required=True); ap.add_argument("--output-dir",required=True)
    ap.add_argument("--step","--grid-step",type=int,choices=(8,16)); ap.add_argument("--allow-synthetic",action="store_true"); a=ap.parse_args(argv)
    try: m=generate(json.loads(Path(a.config).read_text(encoding="utf-8-sig")),a.output_dir,a.allow_synthetic,a.step)
    except (ValueError,KeyError,TypeError) as exc: ap.error(str(exc))
    print(json.dumps({k:m[k] for k in ("step","calibration_valid","calibration_config_sha256")})); return 0

if __name__=="__main__": raise SystemExit(main())
