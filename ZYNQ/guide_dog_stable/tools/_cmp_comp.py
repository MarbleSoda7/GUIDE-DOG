
import gzip, sys, pathlib
sys.path.insert(0,'D:/latest_project_pl_rectify/tools')
import fdtlib
for p in ["D:/latest_project_pl_rectify/sd_card_original_backup/image.ub","F:/image.ub","D:/latest_project_pl_rectify/sd_card_latest/image.ub"]:
    fit=fdtlib.parse(pathlib.Path(p).read_bytes())
    ram=fit.root.child("images").child("ramdisk-1")
    d=ram.get("data")
    print("%-62s len=%-10d compression=%r magic=%s" % (pathlib.Path(p).name+" @ "+p.split('/')[-2], len(d), ram.get("compression"), d[:2].hex()))
