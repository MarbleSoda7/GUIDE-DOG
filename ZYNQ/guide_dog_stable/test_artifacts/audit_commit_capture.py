"""Streaming frame audit; retain at most one image and its packet indices."""
import hashlib
import json
import sys

sys.path.insert(0, "/home/cat/eth_recv")
from analyze_stage5_pcap import FRAME_BYTES, PACKETS, camera_packet, records
from pathlib import Path

result = dict(packets=0, invalid=0, frames=0, complete=0, duplicates=0,
              fid_gaps=0, complete_hash_unique=0, interior_incomplete=[],
              first_fid=None, last_fid=None)
current = None
previous_fid = None
first_time = last_time = None
hashes = set()


def finish(frame, terminal=False):
    if frame is None:
        return
    result["frames"] += 1
    missing = sorted(set(range(PACKETS)) - frame["packets"].keys())
    if missing:
        info = dict(fid=frame["fid"], count=len(frame["packets"]),
                    missing_count=len(missing), missing=missing[:40])
        if terminal:
            result["terminal_partial"] = info
        else:
            result["interior_incomplete"].append(info)
    else:
        result["complete"] += 1
        digest = hashlib.sha256()
        for i in range(PACKETS):
            digest.update(frame["packets"][i])
        hashes.add(digest.hexdigest())


class StandardInput:
    def open(self, _mode):
        return sys.stdin.buffer


source = StandardInput() if sys.argv[1] == "-" else Path(sys.argv[1])
for timestamp, packet in records(source):
    result["packets"] += 1
    item = camera_packet(packet)
    if item is None:
        result["invalid"] += 1
        continue
    fid, index, data = item
    if current is None or fid != current["fid"]:
        finish(current)
        if previous_fid is not None and fid != ((previous_fid + 1) & 65535):
            result["fid_gaps"] += 1
        previous_fid = fid
        if first_time is None:
            first_time = timestamp
            result["first_fid"] = fid
        last_time = timestamp
        result["last_fid"] = fid
        current = dict(fid=fid, packets={})
    if index in current["packets"]:
        result["duplicates"] += 1
    else:
        current["packets"][index] = data
finish(current, terminal=True)
result["complete_hash_unique"] = len(hashes)
result["start_to_start_fps"] = ((result["frames"] - 1) / (last_time - first_time)
                               if first_time != last_time else 0)
print(json.dumps(result, indent=2))
