#!/usr/bin/env python3
"""Exact active-source and same-build artifact provenance. No tool invocation."""
import argparse
import hashlib
import json
import pathlib
import xml.etree.ElementTree as ET
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = ROOT / 'zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy'
NAMES = ('led_test_wrapper.bit', 'led_test_wrapper.hwh', 'led_test_wrapper.xsa')

def digest(data):
    return hashlib.sha256(data).hexdigest()

def checked(path):
    path = path.resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError('Source escapes copied tree: ' + str(path))
    if not path.is_file():
        raise ValueError('Missing active dependency: ' + str(path))
    return path

def source_paths():
    xpr = ET.parse(COPY / 'guide_linux_base.xpr').getroot()
    paths = {COPY / 'guide_linux_base.xpr', COPY / 'pl_remap_accel.cpp', COPY / 'rtl/remap_axi_guard.v', ROOT / 'BUILD_PL_RECTIFY.ps1', ROOT / 'tools/build_pl_rectify.py', ROOT / 'tools/build_pl_manifest.py', ROOT / 'tools/launch_pl_rectify_build.tcl'}
    paths.update(COPY / name for name in ('run_pl_remap_hls.tcl', 'integrate_pl_remap.tcl', 'prepare_project.tcl', 'register_hls_ip.tcl'))
    optional_tb = COPY / 'pl_remap_accel_tb.cpp'
    if optional_tb.is_file():
        paths.add(optional_tb)
    substitutions = {'$PPRDIR': str(COPY), '$PSRCDIR': str(COPY / 'guide_linux_base.srcs'), '$PGENDIR': str(COPY / 'guide_linux_base.gen')}
    for fs in xpr.findall('./FileSets/FileSet'):
        if fs.get('Name') not in ('sources_1', 'constrs_1'):
            continue
        for entry in fs.findall('File'):
            attrs = entry.findall('./FileInfo/Attr')
            if any(a.get('Name') == 'AutoDisabled' and a.get('Val') == '1' for a in attrs):
                continue
            value = entry.get('Path', '')
            for key, replacement in substitutions.items():
                value = value.replace(key, replacement)
            if '$' in value:
                raise ValueError('Unresolved active source: ' + value)
            path = pathlib.Path(value)
            paths.add(path if path.is_absolute() else COPY / path)
    bd = json.loads((COPY / 'guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd').read_text())
    used = set()
    def visit(obj):
        if isinstance(obj, dict):
            if isinstance(obj.get('vlnv'), str):
                used.add(obj['vlnv'])
            for value in obj.values():
                visit(value)
        elif isinstance(obj, list):
            for value in obj:
                visit(value)
    visit(bd)
    ns = {'s': 'http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009'}
    for repo in ('ip_repo', 'hls_ip_repo'):
        for component in (COPY / repo).glob('**/component.xml'):
            xml = ET.parse(component).getroot()
            ident = ':'.join(xml.findtext('s:' + key, default='', namespaces=ns) for key in ('vendor', 'library', 'name', 'version'))
            if ident not in used:
                continue
            paths.add(component)
            for name in xml.findall('.//s:file/s:name', ns):
                paths.add(component.parent / name.text)
    return sorted({checked(p) for p in paths})

def snapshot():
    return {p.relative_to(ROOT).as_posix(): {'sha256': digest(p.read_bytes()), 'length': p.stat().st_size} for p in source_paths()}

def seal(output, recorded):
    current = snapshot()
    # Vivado rewrites XPR run status during build; its pre-build hash remains recorded.
    for name, item in recorded.items():
        if name.endswith('.xpr'):
            continue
        if current.get(name) != item:
            raise ValueError('Build source changed after snapshot: ' + name)
    files = {}
    for name in NAMES:
        path = output / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError('Missing canonical artifact: ' + str(path))
        files[name] = {'sha256': digest(path.read_bytes()), 'length': path.stat().st_size}
    with zipfile.ZipFile(output / 'led_test_wrapper.xsa') as archive:
        for extension in ('.bit', '.hwh'):
            candidates = [name for name in archive.namelist() if name.endswith(extension)]
            expected = files['led_test_wrapper' + extension]['sha256']
            matching = [name for name in candidates if digest(archive.read(name)) == expected]
            if len(matching) != 1:
                raise ValueError('XSA must contain exactly one matching ' + extension + ' artifact')
            files['led_test_wrapper' + extension]['xsa_member'] = matching[0]
    hwh = (output / 'led_test_wrapper.hwh').read_text(encoding='utf-8').lower()
    if 'pl_remap_accel_0' not in hwh or 'remap_axi_guard_0' not in hwh:
        raise ValueError('HWH does not describe both new modules')
    return {'schema': 2, 'project': COPY.relative_to(ROOT).as_posix(), 'files': files, 'sources': recorded, 'sources_sha256': digest(json.dumps(recorded, sort_keys=True).encode()), 'final_xpr_sha256': digest((COPY / 'guide_linux_base.xpr').read_bytes()), 'verification': 'same-round canonical outputs; XSA embedded bit/HWH hashes match; immutable inputs unchanged'}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot', type=pathlib.Path)
    parser.add_argument('--seal', type=pathlib.Path)
    parser.add_argument('--inputs', type=pathlib.Path)
    args = parser.parse_args()
    if args.snapshot:
        args.snapshot.write_text(json.dumps(snapshot(), indent=2), encoding='utf-8')
    elif args.seal and args.inputs:
        data = seal(args.seal, json.loads(args.inputs.read_text(encoding='utf-8-sig')))
        (args.seal / 'manifest.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
    else:
        print('PASS: active source inventory: ' + str(len(source_paths())) + ' copy-local files')

if __name__ == '__main__':
    main()
