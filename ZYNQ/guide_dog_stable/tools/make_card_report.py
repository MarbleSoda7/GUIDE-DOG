
import hashlib, json, os, pathlib, datetime
card = pathlib.Path("F:/")
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for c in iter(lambda: f.read(1<<20), b''): h.update(c)
    return h.hexdigest()
rep = {
 "written_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
 "source_project": "D:/latest_project_pl_rectify",
 "note": "camremap application code lives inside image.ub initramfs; the card camremap/ dir only supplies args and optional overrides",
 "files": {n: {"size": os.path.getsize(card/n), "sha256": sha(card/n)} for n in ["BOOT.BIN","image.ub","boot.scr"]},
 "camremap_dir": sorted(p.name for p in (card/"camremap").iterdir()),
 "args": (card/"camremap/args").read_text(),
}
out = json.dumps(rep, indent=2)
(card/"BUILD_REPORT.json").write_text(out)
pathlib.Path("D:/latest_project_pl_rectify/sd_card_latest/BUILD_REPORT.json").write_text(out)
print(out)
