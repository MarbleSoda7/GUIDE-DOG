import copy
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys
import tempfile
import unittest
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import generate_remap_lut as g
import remap_reference as r
import stereo_calibrate as s

class RemapLutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config=json.loads((ROOT/"tools/camera_params.json").read_text())
        cls.digest=g.calibration_config_sha256(cls.config)

    def identity(self,step):
        return b"".join(struct.pack("<HH",x*64,y*64) for y in g.grid_axis(480,step) for x in g.grid_axis(800,step))

    def test_header_steps_crc_hash(self):
        for step,cols,rows,size in ((16,51,31,6324),(8,101,61,24644)):
            payload=self.identity(step)
            data=g.blob(800,480,step,6,1,cols,rows,payload,True,self.digest)
            self.assertEqual(len(data),96+size)
            self.assertEqual(struct.unpack_from(g.HEADER_FORMAT,data,4),(1,96,800,480,step,6,1,1,cols,rows,cols*rows,size,zlib.crc32(payload)&0xffffffff))
            self.assertEqual(struct.unpack_from("<H",data,18)[0],1)
            self.assertEqual(struct.unpack_from("<I",data,36)[0],zlib.crc32(data[:36])&0xffffffff)
            self.assertEqual(data[40:72],hashlib.sha256(payload).digest())
            self.assertEqual(data[72:96],self.digest[:24])
            self.assertEqual(r.validate_blob(data,1,expected_config_hash=self.digest)["payload"],payload)
            for offset in (4,18,36,40,96):
                bad=bytearray(data); bad[offset]^=1
                with self.assertRaises(ValueError): r.validate_blob(bad,1,expected_config_hash=self.digest)
            bad=bytearray(data); bad[72]^=1
            with self.assertRaises(ValueError): r.validate_blob(bad,1,expected_config_hash=self.digest)
            with self.assertRaises(ValueError): r.validate_blob(data,2)
            with self.assertRaises(ValueError): r.validate_blob(data+b"x")

    def test_synthetic_guard(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError,"allow-synthetic"): g.generate(self.config,d)
        data=g.blob(800,480,16,6,1,51,31,self.identity(16),False,self.digest)
        with self.assertRaisesRegex(ValueError,"synthetic"): r.validate_blob(data)
        self.assertFalse(r.validate_blob(data,allow_synthetic=True)["calibration_valid"])

    def test_synthetic_focal_and_matrix_precedence(self):
        self.assertAlmostEqual(g.camera_k({})[0][0],800/math.radians(170))
        self.assertAlmostEqual(self.config["left"]["K"][0][0],800/math.radians(170),places=7)
        self.assertAlmostEqual(self.config["left"]["rectified_K"][0][0],400/math.tan(math.radians(50)),places=7)
        c=copy.deepcopy(self.config["left"]); original=g.source_xy(c,200,150); c["hfov_deg"]=120.; c["rectified_hfov_deg"]=80.
        self.assertEqual(g.source_xy(c,200,150),original)

    def test_invalid_nan_bounds(self):
        for value in (None,float("nan"),float("inf"),-1.,799.001): self.assertEqual(g.qcoord(value,800),65535)
        self.assertEqual(g.qcoord(799.,800),799*64); self.assertEqual(g.qcoord(479.,480),479*64)
        c=copy.deepcopy(self.config["left"]); c["K"][0][2]=-1000
        cols,rows,payload,bad=g.make_payload(c,800,480,16,6)
        self.assertEqual(bad,cols*rows); self.assertEqual(set(struct.iter_unpack("<HH",payload)),{(65535,65535)})

    def test_bad_matrices_and_geometry(self):
        for key,value in (("K",[[1,2]]),("D",[0,0,0]),("D",[0,0,float("nan"),0]),("R",[[1,0,0],[0,1,0],[0,0,-1]]),("rectified_K",[[0,0,0],[0,0,0],[0,0,1]])):
            c=copy.deepcopy(self.config); c["left"][key]=value
            with self.assertRaises(ValueError): g.validate_config(c)
        for key,value in (("width",801),("grid_step",4),("grid_step",16.5),("frac_bits",5),("calibration_valid","false")):
            c=copy.deepcopy(self.config); c[key]=value
            with self.assertRaises(ValueError): g.validate_config(c)

    def test_final_cells_and_identity(self):
        for step in (8,16):
            payload=self.identity(step)
            self.assertEqual(g.grid_axis(800,step)[-2:],[800-step,799])
            self.assertEqual(g.grid_axis(480,step)[-2:],[480-step,479])
            for y in (0,1,15,16,464,471,478,479):
                row=r.grid_row_incremental(payload,y,step); self.assertEqual(len(row),800)
                for x in (0,1,15,16,784,791,798,799):
                    self.assertEqual(r.grid_coordinate(payload,x,y,step),(x*64,y*64)); self.assertEqual(row[x],(x*64,y*64))

    def test_kernel_staged_floor_random(self):
        rng=random.Random(31)
        for step in (8,16):
            cols,rows=g.geometry(800,480,step,6)
            payload=b"".join(struct.pack("<HH",rng.randrange(799*64+1),rng.randrange(479*64+1)) for _ in range(cols*rows))
            q,valid=r.reconstruct_grid(payload,step)
            self.assertTrue(valid.all())
            for y in (0,13,16,473,479):
                row=r.grid_row_incremental(payload,y,step)
                for x in range(800):
                    gx=min(x//step,cols-2); gy=min(y//step,rows-2)
                    sx=min(step,799-gx*step); sy=min(step,479-gy*step)
                    dx=x-gx*step; dy=y-gy*step
                    nodes=[struct.unpack_from("<HH",payload,4*i) for i in (gy*cols+gx,gy*cols+gx+1,(gy+1)*cols+gx,(gy+1)*cols+gx+1)]
                    def lerp(a,b,f,span): return (a*(span-f)+b*f)//span
                    expected=tuple(lerp(lerp(nodes[0][c],nodes[1][c],dx,sx),lerp(nodes[2][c],nodes[3][c],dx,sx),dy,sy) for c in (0,1))
                    self.assertEqual(r.grid_coordinate(payload,x,y,step),expected)
                    self.assertEqual(row[x],expected)
                    self.assertEqual(tuple(q[y,x]),expected)

    def test_nonlinear_two_floor_differs_from_single_floor(self):
        for step in (8,16):
            cols,rows=g.geometry(800,480,step,6)
            for gx,gy in ((0,0),(cols-2,rows-2)):
                payload=bytearray(self.identity(step))
                span=step if gx==0 else step-1
                # Nonlinear cross term: bottom slope differs from top. At (1,1)
                # full numerator gives x=1001, but kernel staged floors give 1000.
                nodes=((1000,2000+2*span-1),(1000+span-1,2000),(1000,2000+span-1),(1000+2*span-1,2000))
                indices=(gy*cols+gx,gy*cols+gx+1,(gy+1)*cols+gx,(gy+1)*cols+gx+1)
                for index,node in zip(indices,nodes): struct.pack_into("<HH",payload,4*index,*node)
                x=gx*step+1; y=gy*step+1
                weights=((span-1)**2,span-1,span-1,1)
                old_single_floor=sum(n[0]*w for n,w in zip(nodes,weights))//(span*span)
                expected=(1000,2000+2*span-4)
                self.assertEqual(old_single_floor,1001)
                self.assertNotEqual(old_single_floor,expected[0])
                self.assertEqual(r.grid_coordinate(payload,x,y,step),expected)
                self.assertEqual(r.grid_row_incremental(payload,y,step)[x],expected)
                q,valid=r.reconstruct_grid(payload,step)
                self.assertTrue(valid[y,x]); self.assertEqual(tuple(q[y,x]),expected)

    def test_fractional_rgb_kernel_round_half_up(self):
        source=bytearray(800*480*3)
        for offset,pixel in ((0,(0,10,254)),(3,(1,11,255)),(2400,(2,12,255)),(2403,(4,14,255))):
            source[offset:offset+3]=bytes(pixel)
        # Below half, exactly half, and nonlinear two-dimensional fractional mix.
        for qx,qy,expected in ((31,0,(0,10,254)),(32,0,(1,11,255)),(33,0,(1,11,255)),(32,32,(2,12,255))):
            self.assertEqual(r.sample_rgb888(source,qx,qy),expected)
            if qy: self.assertNotEqual(expected,(1,11,254))  # Old RGB floor result.
            for step in (8,16):
                cols,rows=g.geometry(800,480,step,6)
                payload=struct.pack("<HH",qx,qy)*(cols*rows)
                image,bad=r.remap_rgb888(source,payload,step)
                self.assertEqual(bad,0)
                self.assertEqual(image,bytes(expected)*(800*480))

    def test_invalid_cell_and_source_edges(self):
        payload=bytearray(self.identity(16)); struct.pack_into("<HH",payload,0,65535,65535)
        self.assertIsNone(r.grid_coordinate(payload,15,15)); self.assertEqual(r.grid_coordinate(payload,16,16),(1024,1024))
        source=bytearray(800*480*3); source[-3:]=bytes((11,22,33))
        self.assertEqual(r.sample_rgb888(source,799*64,479*64),(11,22,33))
        self.assertEqual(r.sample_rgb888(source,799*64+1,479*64),(0,0,0))
        self.assertEqual(r.sample_rgb888(source,65535,0),(0,0,0))

    def test_numpy_full_frame_and_reports(self):
        try: import numpy as np
        except ImportError: self.skipTest("numpy unavailable")
        y,x=np.indices((480,800)); full=np.stack((x,y),axis=-1)
        source=np.arange(800*480*3,dtype=np.uint32).astype(np.uint8).tobytes()
        for step in (8,16):
            payload=self.identity(step); q,valid=r.reconstruct_grid(payload,step)
            self.assertTrue(valid.all()); np.testing.assert_array_equal(q,full*64)
            image,bad=r.remap_rgb888(source,payload,step); self.assertEqual(bad,0); self.assertEqual(image,source)
        report=r.analyze_maps(full,self.identity(16)); self.assertEqual(report["grid_error"]["max_px"],0.); self.assertEqual(len(report["source_locality"]["tiles"]),1500)
        mapped=g.full_map(self.config["left"])
        for x,y in ((0,0),(200,150),(799,479)): np.testing.assert_allclose(mapped[y,x],g.source_xy(self.config["left"],x,y),atol=1e-10)

    def test_generate_manifest(self):
        try: import numpy
        except ImportError: self.skipTest("numpy unavailable")
        with tempfile.TemporaryDirectory() as d:
            for step in (16,8):
                m=g.generate(self.config,d,allow_synthetic=True,step=step)
                for eye,name in ((1,"left"),(2,"right")):
                    data=(Path(d)/(name+"_remap.rmp")).read_bytes()
                    r.validate_blob(data,eye,True,m["calibration_config_sha256"])
                    self.assertEqual(m["eyes"][name]["payload_bytes"],6324 if step==16 else 24644)

    def test_opencv_fisheye_map_agreement(self):
        try:
            import cv2
            import numpy as np
        except ImportError: self.skipTest("OpenCV/numpy unavailable")
        c=copy.deepcopy(self.config["left"]); c["D"]=[0.02,-0.003,0.0001,-0.00001]
        c["R"]=cv2.Rodrigues(np.array([0.01,-0.02,0.003]))[0].tolist()
        actual=g.full_map(c)
        mx,my=cv2.fisheye.initUndistortRectifyMap(np.asarray(c["K"]),np.asarray(c["D"]),np.asarray(c["R"]),np.asarray(c["rectified_K"]),(800,480),cv2.CV_32FC1)
        np.testing.assert_allclose(actual[...,0],mx,atol=4e-5,rtol=0)
        np.testing.assert_allclose(actual[...,1],my,atol=4e-5,rtol=0)

    def test_detection_and_resolution_fail_closed(self):
        try:
            import cv2
            import numpy as np
        except ImportError: self.skipTest("OpenCV/numpy unavailable")
        with tempfile.TemporaryDirectory() as d:
            lp=Path(d)/"left.png"; rp=Path(d)/"right.png"
            image=np.zeros((480,800),dtype=np.uint8)
            lp.write_bytes(cv2.imencode(".png",image)[1].tobytes()); rp.write_bytes(lp.read_bytes())
            with self.assertRaisesRegex(ValueError,"detection failed"): s.detect_pairs([("0",lp,rp)],9,6,cv2,np)
            lp.write_bytes(cv2.imencode(".png",image[:400])[1].tobytes())
            with self.assertRaisesRegex(ValueError,"800x480"): s.detect_pairs([("0",lp,rp)],9,6,cv2,np)

    def test_calibration_pair_rejection(self):
        with tempfile.TemporaryDirectory() as d:
            left=Path(d)/"L"; right=Path(d)/"R"; left.mkdir(); right.mkdir()
            with self.assertRaises(ValueError): s.pair_files(left,right,14)
            with self.assertRaises(ValueError): s.pair_files(left,right)
            for i in range(15): (left/("pair_%03d_left.png"%i)).touch(); (right/("pair_%03d_right.png"%i)).touch()
            self.assertEqual(len(s.pair_files(left,right)),15)
            (right/"pair_extra_right.png").touch()
            with self.assertRaisesRegex(ValueError,"mismatch"): s.pair_files(left,right)

if __name__=="__main__": unittest.main()
