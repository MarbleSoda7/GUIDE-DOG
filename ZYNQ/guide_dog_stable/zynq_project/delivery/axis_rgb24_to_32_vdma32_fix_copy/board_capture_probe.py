#!/usr/bin/env python3
"""Read-only VDMA capture probe. Stop camremap auto-recovery before sampling.
This script does not configure/reset capture or load a bitstream.
"""
import argparse, json, os, sys, time
from camremap.hw import Overlay
from camremap.vdma import PARK_PTR, S2MM_CR, S2MM_SR, S2MM_VSIZE, S2MM_HSIZE, S2MM_STRIDE, S2MM_ADDR0, SR_ERROR_MASK
ap=argparse.ArgumentParser()
ap.add_argument('--hwh',default='/usr/share/camremap/led_test_wrapper.hwh')
ap.add_argument('--seconds',type=float,default=10)
a=ap.parse_args()
m=Overlay(a.hwh).axi_vdma_0
initial={name:hex(m.read(off)) for name,off in [('cr',S2MM_CR),('sr',S2MM_SR),('vsize',S2MM_VSIZE),('hsize',S2MM_HSIZE),('stride',S2MM_STRIDE),('addr0',S2MM_ADDR0),('addr1',S2MM_ADDR0+4),('addr2',S2MM_ADDR0+8)]}
print(json.dumps({'hwh':a.hwh,'initial':initial}),flush=True)
raw={name:int(value,16) for name,value in initial.items()}
contract_failures=[]
if not raw['cr'] & 0x9 == 0x9: contract_failures.append('S2MM not running circular')
if raw['vsize'] != 480: contract_failures.append('VSIZE != 480')
if raw['hsize'] != 2400: contract_failures.append('HSIZE != 2400')
if raw['stride'] & 0xffff != 2400: contract_failures.append('stride low16 != 2400')
for i,expected in enumerate((0x30000000,0x30119400,0x30232800)):
    if raw['addr%d' % i] != expected: contract_failures.append('addr%d mismatch' % i)
transitions=0; slots=set(); errors=set(); previous=None; nonsequential=0
end=time.monotonic()+a.seconds
while time.monotonic()<end:
    ptr=m.read(PARK_PTR); sr=m.read(S2MM_SR); writer=(ptr>>24)&31
    slots.add(writer)
    if sr & (SR_ERROR_MASK|1): errors.add(sr)
    if previous!=writer:
        if previous is not None:
            transitions+=1
            if writer!=(previous+1)%3: nonsequential+=1
        print(json.dumps({'t':round(time.monotonic(),6),'park_ptr':hex(ptr),'writer':writer,'sr':hex(sr)}),flush=True)
        previous=writer
    time.sleep(.001)
if not slots.issubset({0,1,2}): contract_failures.append('writer outside three slots')
if nonsequential: contract_failures.append('non-sequential writer transition')
if errors: contract_failures.append('VDMA status error')
if slots != {0,1,2}: contract_failures.append('not all three slots observed')
result={'transitions':transitions,'slots_seen':sorted(slots),'error_statuses':[hex(s) for s in sorted(errors)],'nonsequential_samples':nonsequential,'contract_failures':contract_failures,'note':'Polling can miss transitions; this does not certify electrical timing or frame contents.'}
print(json.dumps(result),flush=True)
if contract_failures: raise SystemExit(2)
