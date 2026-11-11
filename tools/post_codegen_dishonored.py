#!/usr/bin/env python3
"""dishonored-nx (2026-11-11): the post-codegen steps of the optimised codegen, pure-nx's tools/post_codegen_pure.py
(renut-nx's tools/post_codegen.py, from sa2-nx, masseffect-nx, sasrt-nx, peggle2-nx, futari-nx) on Dishonored's tree.
Run after EVERY codegen.cmd: the generator writes the plain text back. Every step is idempotent, and so is the
sequence; each tool tells what it does in its own header.

Taken, as pure-nx: pch_no_volatile + loop_barriers (required together), pch_cold_traps, direct_calls --redo,
guest_cas, vec_byteswap, pch_neon_shuffles, ro_constants, float_loads, loop_locals, leaf_locals, vperm_one_source,
leaf_dead_stores, single_floats, inline_memcalls (Dishonored's CRT: memcpy sub_82CD1D20, memset sub_82CD2250),
vec_unaligned_stores, ro_constants_cfg, dead_ctx_defs, store_cards (last; src/dishonored_store_cards.cpp tells Renut).
They need out/default_image.bin, the generator's image dump (codegen.cmd sets REXGLUE_DUMP_IMAGE).

  python tools/post_codegen_dishonored.py [--gen generated/default] [--xex assets/game_root/default.xex]
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGE = os.path.join(ROOT, 'out', 'default_image.bin')
MEMCPY = '82CD1D20'  # overrides.toml: the CRT signature scan (memcpy 0x82CD1D20, memmove 0x82CCD080, memset 0x82CD2250)
MEMSET = '82CD2250'


def run(*args):
    print('post_codegen_dishonored: ' + os.path.basename(args[0]), flush=True)
    result = subprocess.run([sys.executable, *args], cwd=ROOT)
    if result.returncode != 0:
        sys.exit(f'post_codegen_dishonored: {os.path.basename(args[0])} failed ({result.returncode})')


def tool(name):
    return os.path.join(ROOT, 'tools', name)


def manifest_xex():
    try:
        text = open(os.path.join(ROOT, 'dishonored_manifest.toml'), encoding='utf-8').read()
    except OSError:
        return None
    m = re.search(r'^\s*file_path\s*=\s*"([^"]+)"', text, re.M)
    if not m:
        return None
    path = m.group(1)
    return path if os.path.isabs(path) else os.path.join(ROOT, path)


def main():
    gen = sys.argv[sys.argv.index('--gen') + 1] if '--gen' in sys.argv else os.path.join(ROOT, 'generated', 'default')
    xex = sys.argv[sys.argv.index('--xex') + 1] if '--xex' in sys.argv else manifest_xex()
    pchs = [os.path.join(gen, f) for f in os.listdir(gen) if f.endswith('_pch.h')]
    if len(pchs) != 1:
        sys.exit(f'post_codegen_dishonored: no single *_pch.h in {gen}')
    pch = pchs[0]
    if not os.path.isfile(IMAGE):
        sys.exit(f'post_codegen_dishonored: {IMAGE} is missing (the image dump: run codegen.cmd)')
    # --xex: loads of the XEX's import records (kernel variable addresses the loader writes) stay loads.
    xex_args = ['--xex', xex] if xex and os.path.isfile(xex) else []
    if not xex_args:
        print(f'post_codegen_dishonored: WARNING: no default.xex ({xex}); ro_constants without --xex', flush=True)
    run(tool('pch_no_volatile.py'), pch)
    run(tool('loop_barriers.py'), gen)  # REQUIRED with pch_no_volatile.py
    run(tool('pch_cold_traps.py'), pch)
    run(tool('direct_calls.py'), '--redo', '--gen', gen)
    run(tool('guest_cas.py'), '--gen', gen)
    run(tool('vec_byteswap.py'), '--gen', gen)
    run(tool('pch_neon_shuffles.py'), pch)
    run(tool('ro_constants.py'), '--gen', gen, '--image', IMAGE, *xex_args)
    run(tool('float_loads.py'), '--gen', gen)
    run(tool('loop_locals.py'), '--gen', gen)
    run(tool('leaf_locals.py'), '--gen', gen)
    run(tool('vperm_one_source.py'), '--gen', gen)
    run(tool('leaf_dead_stores.py'), '--gen', gen, '--image', IMAGE)
    run(tool('single_floats.py'), '--gen', gen)
    run(tool('inline_memcalls.py'), '--gen', gen, '--memcpy', MEMCPY, '--memset', MEMSET)
    run(tool('vec_unaligned_stores.py'), '--gen', gen)
    run(tool('ro_constants_cfg.py'), '--gen', gen, '--image', IMAGE, *xex_args)
    # Guest register writes no instruction can read, left out (renut-nx's step 22; leaf_dead_stores.py's analysis, so
    # after it). DISHONORED_DEAD_DEFS_OFF=1 takes them back out.
    if os.environ.get('DISHONORED_DEAD_DEFS_OFF'):
        run(tool('dead_ctx_defs.py'), '--gen', gen, '--restore-only')
    else:
        run(tool('dead_ctx_defs.py'), '--gen', gen, '--image', IMAGE, '--abi-indirect')
    # The store cards, for banjo_renut_exact_streams at a fraction of its hashing (no localized copies: --hot -).
    run(tool('store_cards.py'), '--gen', gen, '--hot', '-')
    print('post_codegen_dishonored: done', flush=True)


if __name__ == '__main__':
    main()
