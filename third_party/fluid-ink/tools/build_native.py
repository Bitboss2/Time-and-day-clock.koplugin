"""Build native transport with KOReader's Kobo or Kindle PW2 toolchain."""
from pathlib import Path
import argparse
import os
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--cc')
    target_options = parser.add_mutually_exclusive_group()
    target_options.add_argument('--host', action='store_true')
    target_options.add_argument('--kindle', action='store_true')
    args = parser.parse_args()
    source = ROOT / 'inkmotion/native/inkmotion.c'
    collector = ROOT / 'inkmotion/native/collector.c'
    phase = ROOT / 'inkmotion/native/phase.c'
    memory = ROOT / 'inkmotion/native/mem_access.c'
    locator = ROOT / 'inkmotion/native/kernel_locator.c'
    exports = ROOT / 'inkmotion/native/exports.map'
    if args.host:
        target = ROOT / 'reference/v03/libinkmotion-host.so'
        cmd = ['gcc', '-shared', '-fPIC', '-O3', '-std=c11', '-Wall', '-Wextra', '-Werror', str(source), str(collector), str(phase), str(memory), str(locator), '-o', str(target), '-lrt']
    else:
        toolchain = 'arm-kindlepw2-linux-gnueabi' if args.kindle else 'arm-kobo-linux-gnueabihf'
        default_cc = ROOT / 'reference/v031/toolchain/x-tools' / toolchain / 'bin' / (toolchain + '-gcc')
        library = 'libinkmotion-kindlepw2.so' if args.kindle else 'libinkmotion-arm.so'
        float_abi = 'softfp' if args.kindle else 'hard'
        target = ROOT / 'inkmotion/inkmotion.koplugin/bin' / library
        cmd = [args.cc or str(default_cc), '-O3', '-std=c11', '-mcpu=cortex-a9', '-mfpu=neon', '-mfloat-abi='+float_abi, '-fno-stack-protector', '-U_FORTIFY_SOURCE',
               '-fPIC', '-shared', '-s', '-Wall', '-Wextra', '-Werror', str(source), str(collector), str(phase), str(memory), str(locator), '-o', str(target), '-lrt',
               '-Wl,--version-script=' + str(exports), '-Wl,-soname,'+library]
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(cmd, env=os.environ.copy(), check=True)
    print(target)


if __name__ == '__main__':
    main()
