#!/usr/bin/env python3
"""Real offline fisheye calibration; never synthesizes successful measurements.
Requires numpy + opencv-python. Left/right filenames must match after removing
an optional _left/_right suffix. No image resizing or silent failed-pair skipping.
Square size MUST be supplied in millimetres; T, P translation and Q depth use mm.
At least 15 pairs; 20-30 diverse static pairs recommended. RMS is fit quality,
not held-out epipolar validation or a claim of synchronized exposure.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

try:
    from .generate_remap_lut import validate_config,generate
except ImportError:
    from generate_remap_lut import validate_config,generate

SCRIPT_VERSION="1.0.0"

def pair_files(left_dir,right_dir,min_pairs=15):
    if type(min_pairs) is not int or min_pairs<15: raise ValueError("min_pairs cannot be below 15")
    def scan(directory,eye):
        d=Path(directory)
        if not d.is_dir(): raise ValueError("missing image directory: "+str(d))
        found={}
        for p in sorted(d.iterdir()):
            if not p.is_file() or p.suffix.lower() not in (".png",".jpg",".jpeg",".bmp",".tif",".tiff"): continue
            key=p.stem
            if key.endswith("_"+eye): key=key[:-len(eye)-1]
            if key in found: raise ValueError("duplicate pair key: "+key)
            found[key]=p
        return found
    left,right=scan(left_dir,"left"),scan(right_dir,"right")
    if set(left)!=set(right): raise ValueError("left/right pair names mismatch: left_only=%s right_only=%s"%(sorted(set(left)-set(right)),sorted(set(right)-set(left))))
    if len(left)<min_pairs: raise ValueError("need at least %d complete pairs; found %d"%(min_pairs,len(left)))
    return [(key,left[key],right[key]) for key in sorted(left)]

def detect_pairs(pairs,cols,rows,cv2,np):
    left=[]; right=[]; provenance=[]
    criteria=(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_MAX_ITER,50,1e-4)
    for key,lp,rp in pairs:
        record={"pair_id":key}
        for eye,path,target in (("left",lp,left),("right",rp,right)):
            raw=path.read_bytes(); gray=cv2.imdecode(np.frombuffer(raw,np.uint8),cv2.IMREAD_GRAYSCALE)
            if gray is None: raise ValueError("unreadable image: "+str(path))
            if gray.shape!=(480,800): raise ValueError("all images must be exactly 800x480: "+str(path))
            ok,corners=cv2.findChessboardCorners(gray,(cols,rows),cv2.CALIB_CB_ADAPTIVE_THRESH|cv2.CALIB_CB_NORMALIZE_IMAGE)
            if not ok or corners is None or len(corners)!=cols*rows: raise ValueError("checkerboard detection failed: "+str(path))
            corners=cv2.cornerSubPix(gray,corners,(11,11),(-1,-1),criteria)
            if not np.isfinite(corners).all(): raise ValueError("non-finite detected corners: "+str(path))
            target.append(np.asarray(corners,dtype=np.float64).reshape(1,-1,2))
            record[eye]={"file":str(path.resolve()),"sha256":hashlib.sha256(raw).hexdigest()}
        provenance.append(record)
    return left,right,provenance

def calibrate(left_dir,right_dir,square_mm,cols=9,rows=6,min_pairs=15,balance=0.,fov_scale=1.):
    if not math.isfinite(square_mm) or square_mm<=0: raise ValueError("explicit positive square_mm required")
    if cols<2 or rows<2: raise ValueError("board needs at least 2x2 inner corners")
    if not math.isfinite(balance) or not 0<=balance<=1 or not math.isfinite(fov_scale) or fov_scale<=0: raise ValueError("invalid balance/fov_scale")
    pairs=pair_files(left_dir,right_dir,min_pairs)
    try:
        import cv2
        import numpy as np
    except ImportError as exc: raise RuntimeError("install numpy and opencv-python on the offline host") from exc
    left,right,provenance=detect_pairs(pairs,cols,rows,cv2,np)
    pattern=np.zeros((1,cols*rows,3),dtype=np.float64); pattern[0,:,:2]=np.mgrid[0:cols,0:rows].T.reshape(-1,2)*square_mm
    objects=[pattern.copy() for _ in pairs]; size=(800,480)
    criteria=(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_MAX_ITER,200,1e-8)
    flags=cv2.fisheye.CALIB_RECOMPUTE_EXTRINSIC|cv2.fisheye.CALIB_CHECK_COND|cv2.fisheye.CALIB_FIX_SKEW
    def intrinsics(points):
        rms,K,D,_,_=cv2.fisheye.calibrate(objects,points,size,np.eye(3),np.zeros((4,1)),flags=flags,criteria=criteria)
        return float(rms),K,D
    rms_l,K1,D1=intrinsics(left); rms_r,K2,D2=intrinsics(right)
    result=cv2.fisheye.stereoCalibrate(objects,left,right,K1,D1,K2,D2,size,flags=cv2.fisheye.CALIB_FIX_INTRINSIC,criteria=criteria)
    rms,K1,D1,K2,D2,R,T=result[:7]
    R1,R2,P1,P2,Q=cv2.fisheye.stereoRectify(K1,D1,K2,D2,size,R,T,flags=cv2.CALIB_ZERO_DISPARITY,newImageSize=size,balance=balance,fov_scale=fov_scale)
    baseline=float(np.linalg.norm(T))
    if not math.isfinite(baseline) or baseline<=0: raise ValueError("invalid measured baseline")
    config={"schema":"dual-fisheye-rectify-v1","width":800,"height":480,"grid_step":16,"frac_bits":6,"calibration_valid":True,"calibration_source":"measured_chessboard_pairs","baseline_mm":baseline,"translation_units":"mm","depth_units":"mm","square_mm":square_mm,"board_inner_corners":[cols,rows],"pair_count":len(pairs),"pairs":provenance,"script_version":SCRIPT_VERSION,"script_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),"opencv_version":cv2.__version__,"rms_left":rms_l,"rms_right":rms_r,"rms_stereo":float(rms),"balance":balance,"fov_scale":fov_scale,"held_out_epipolar_validation":"not_performed","quality_acceptance":"requires review; calibration_valid indicates measured provenance, not acceptance"}
    for name,value in (("K_left",K1),("D_left",D1),("K_right",K2),("D_right",D2),("R",R),("T_mm",T),("R1",R1),("R2",R2),("P1",P1),("P2",P2),("Q",Q)):
        if not np.isfinite(value).all(): raise ValueError("non-finite calibration output "+name)
        config[name]=value.tolist()
    maps={}
    for eye,K,D,rotation,P in (("left",K1,D1,R1,P1),("right",K2,D2,R2,P2)):
        config[eye]={"K":K.tolist(),"D":D.reshape(-1).tolist(),"R":rotation.tolist(),"rectified_K":P[:,:3].tolist()}
        mx,my=cv2.fisheye.initUndistortRectifyMap(K,D,rotation,P,size,cv2.CV_32FC1)
        valid=np.isfinite(mx)&np.isfinite(my)&(mx>=0)&(mx<=799)&(my>=0)&(my<=479)
        yy,xx=np.nonzero(valid)
        config[eye]["valid_bbox_xywh"]=[int(xx.min()),int(yy.min()),int(xx.max()-xx.min()+1),int(yy.max()-yy.min()+1)] if xx.size else None
        config[eye]["bbox_is_not_all_valid_roi"]=True
        config[eye]["invalid_pixels"]=int((~valid).sum())
        maps[eye+"_x"]=mx; maps[eye+"_y"]=my; maps[eye+"_valid"]=valid
    validate_config(config); json.dumps(config,allow_nan=False)
    return config,maps

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("--left-dir",required=True); p.add_argument("--right-dir",required=True); p.add_argument("--square-mm",type=float,required=True)
    p.add_argument("--cols",type=int,default=9); p.add_argument("--rows",type=int,default=6); p.add_argument("--min-pairs",type=int,default=15); p.add_argument("--balance",type=float,default=0.); p.add_argument("--fov-scale",type=float,default=1.)
    p.add_argument("--out",required=True); p.add_argument("--maps-out"); p.add_argument("--grid-dir",help="optional: generate step16 and step8 subdirectories"); a=p.parse_args(argv)
    try: c,maps=calibrate(a.left_dir,a.right_dir,a.square_mm,a.cols,a.rows,a.min_pairs,a.balance,a.fov_scale)
    except (ValueError,RuntimeError) as exc: p.error(str(exc))
    out=Path(a.out); out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(c,indent=2,allow_nan=False),encoding="utf-8")
    import numpy as np
    maps_path=Path(a.maps_out) if a.maps_out else out.with_name("maps_full.npz"); maps_path.parent.mkdir(parents=True,exist_ok=True); np.savez_compressed(maps_path,**maps)
    if a.grid_dir:
        for step in (16,8): generate(c,Path(a.grid_dir)/("step%d"%step),step=step)
    print("measured pairs=%d baseline_mm=%.6f rms_stereo=%.6f; held-out validation NOT performed"%(c["pair_count"],c["baseline_mm"],c["rms_stereo"]))
    return 0

if __name__=="__main__": raise SystemExit(main())
