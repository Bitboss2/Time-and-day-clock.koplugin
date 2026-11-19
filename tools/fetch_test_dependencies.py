"""Fetch pinned upstream files used only by the development harness."""
from pathlib import Path
from urllib.request import urlopen
import concurrent.futures

ROOT=Path(__file__).resolve().parents[1]
KOREADER='cad5c8d72dd02b39dee388c6e0c43170bcd91dab'
BASE='007ac6a81e2de4822c8df7ce57b8dbb06aa3b8ea'
FILES={
    'time.lua':f'https://raw.githubusercontent.com/koreader/koreader/{KOREADER}/frontend/ui/time.lua',
    'device.lua':f'https://raw.githubusercontent.com/koreader/koreader/{KOREADER}/frontend/device/kobo/device.lua',
    'wakeupmgr.lua':f'https://raw.githubusercontent.com/koreader/koreader/{KOREADER}/frontend/device/wakeupmgr.lua',
    'kindle_mockrtc.lua':f'https://raw.githubusercontent.com/koreader/koreader/{KOREADER}/frontend/device/kindle/mockrtc.lua',
    'kindle_powerd.lua':f'https://raw.githubusercontent.com/koreader/koreader/{KOREADER}/frontend/device/kindle/powerd.lua',
    'screensaver_menu.lua':f'https://raw.githubusercontent.com/koreader/koreader/{KOREADER}/frontend/ui/elements/screensaver_menu.lua',
    'archiver.lua':f'https://raw.githubusercontent.com/koreader/koreader-base/{BASE}/ffi/archiver.lua',
    'libarchive_h.lua':f'https://raw.githubusercontent.com/koreader/koreader-base/{BASE}/ffi/libarchive_h.lua',
    'posix_h.lua':f'https://raw.githubusercontent.com/koreader/koreader-base/{BASE}/ffi/posix_h.lua',
}
def fetch(item):
    name,url=item
    b=urlopen(url,timeout=40).read();path=ROOT/'research-koreader'/name;path.parent.mkdir(exist_ok=True);path.write_bytes(b)
    return name,len(b)
if __name__=='__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        for name,size in pool.map(fetch,FILES.items()):print(name,size)
