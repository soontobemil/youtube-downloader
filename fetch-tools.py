"""Fetch pinned, checksum-verified tools for the Apple Silicon build."""
from pathlib import Path
import hashlib
import urllib.request
import zipfile
import subprocess

ROOT = Path(__file__).resolve().parent / 'deps'
ROOT.mkdir(exist_ok=True)

def fetch(name, url, checksum=None):
    target = ROOT / name
    print('Fetching', name)
    with urllib.request.urlopen(url, timeout=90) as response:
        data = response.read()
    if checksum and hashlib.sha256(data).hexdigest() != checksum:
        raise RuntimeError('Checksum mismatch: ' + name)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return target

engine = fetch('yt-dlp_macos.zip', 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp_macos.zip',
      '20d98fa608998eff87d1d35a6e9fb65e4b874639a6cc89addc19da3becde3ef1')
# ditto preserves the framework symlinks and executable modes in the official archive.
subprocess.run(['/usr/bin/ditto', '-x', '-k', str(engine), str(ROOT / 'yt-dlp-runtime')], check=True)
deno = fetch('deno.zip', 'https://github.com/denoland/deno/releases/download/v2.9.8/deno-aarch64-apple-darwin.zip',
             '9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e')
wheel = fetch('ffmpeg.whl', 'https://files.pythonhosted.org/packages/2b/47/9f9b654f853598bae0850fa22bba168103e45d31b5a2a893ed474f28d54a/imageio_ffmpeg-0.8.1-py3-none-macosx_12_0_arm64.whl',
              '5636d691e36e5274b13fe38182b1f627b2e35dcecc63944012c2470f9484fc45')
with zipfile.ZipFile(deno) as archive:
    (ROOT / 'deno').write_bytes(archive.read('deno'))
with zipfile.ZipFile(wheel) as archive:
    binary = next(n for n in archive.namelist() if '/binaries/ffmpeg-' in n)
    (ROOT / 'ffmpeg').write_bytes(archive.read(binary))
    license_file = next(n for n in archive.namelist() if n.endswith('/licenses/LICENSE'))
    (ROOT / 'Licenses').mkdir(exist_ok=True)
    (ROOT / 'Licenses/IMAGEIO-FFMPEG-LICENSE.txt').write_bytes(archive.read(license_file))
for name in ['deno', 'ffmpeg']:
    (ROOT / name).chmod(0o755)
fetch('Licenses/YT-DLP-THIRD-PARTY.txt', 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.10.26/THIRD_PARTY_LICENSES.txt')
fetch('Licenses/YT-DLP-LICENSE.txt', 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.10.26/LICENSE')
fetch('Licenses/DENO-LICENSE.md', 'https://raw.githubusercontent.com/denoland/deno/v2.9.8/LICENSE.md')
fetch('Licenses/FFMPEG-GPLv3.txt', 'https://raw.githubusercontent.com/FFmpeg/FFmpeg/n9.0/COPYING.GPLv3')
print('Tools ready. Run: bash build.sh')
