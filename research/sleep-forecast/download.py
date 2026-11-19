"""Fetch only the pinned files needed for the campus sleep experiment."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from hashlib import file_digest, sha1, sha256
import json
from pathlib import Path
from shutil import copyfileobj
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
ZENODO = "https://zenodo.org/records/21904040/files"
NETHEALTH = {
    "sleep": ("FitbitSleep(1-30-20).csv", "54bd7aaa189ecd129548b3214ef6d398"),
    "activity": ("FitbitActivity(1-30-20).csv", "acf809b53b85b48fcc92da1fcf54fe14"),
}
UVA = "HAI-lab-UVA/Human-Rhythms-Dataset"
UVA_REV = "3fe83300ca9726a1ff6755d235347bc63a976022"
UVA_SLEEP = "Cleaned_Raw_Data/Fitbit/Sleep_Summary"


def checksum(path):
    with path.open("rb") as source:
        return file_digest(source, "md5").hexdigest()


def fetch_nethealth(key, directory):
    file, expected = NETHEALTH[key]
    destination = directory / f"nethealth-{key}.csv"
    if destination.is_file() and checksum(destination) == expected:
        return
    temporary = destination.with_suffix(".part")
    url = f"{ZENODO}/{quote(file, safe='')}?download=1&full=1"
    with urlopen(url, timeout=120) as response, temporary.open("wb") as output:
        copyfileobj(response, output)
    if checksum(temporary) != expected:
        raise ValueError(f"{key}: checksum differs from the Zenodo release")
    temporary.replace(destination)


def git_blob_matches(content, expected):
    return sha1(f"blob {len(content)}\0".encode() + content).hexdigest() == expected


def fetch_uva(directory):
    from urllib.error import URLError

    url = f"https://api.github.com/repos/{UVA}/contents/{UVA_SLEEP}?ref={UVA_REV}"
    with urlopen(Request(url, headers={"Accept": "application/vnd.github+json"}), timeout=25) as response:
        listing = json.load(response)
    files = [item for item in listing if item["type"] == "file" and item["name"].endswith(".csv")]
    if len(files) != 161:
        raise ValueError(f"Expected 161 UVA sleep files at {UVA_REV}, got {len(files)}")
    directory.mkdir(parents=True, exist_ok=True)

    def read(url, limit):
        for attempt in range(3):
            try:
                with urlopen(url, timeout=15) as response:
                    return response.read(limit + 1)
            except (URLError, TimeoutError):
                if attempt == 2:
                    raise

    def fetch(item):
        path = directory / item["name"]
        existing = path.read_bytes() if path.is_file() else b""
        if git_blob_matches(existing, item["sha"]):
            return
        content = read(item["download_url"], item["size"])
        if not git_blob_matches(content, item["sha"]):
            raise ValueError(f"Unexpected UVA sleep blob {item['name']}")
        if content.startswith(b"version https://git-lfs.github.com/spec/v1"):
            _, object_id, size = content.decode().splitlines()
            digest = object_id.removeprefix("oid sha256:")
            if sha256(existing).hexdigest() == digest:
                return
            media = f"https://media.githubusercontent.com/media/{UVA}/{UVA_REV}/{UVA_SLEEP}/{quote(item['name'])}"
            content = read(media, int(size.removeprefix("size ")))
            if sha256(content).hexdigest() != digest:
                raise ValueError(f"Unexpected UVA LFS object {item['name']}")
        temporary = path.with_suffix(".part")
        temporary.write_bytes(content)
        temporary.replace(path)

    with ThreadPoolExecutor(max_workers=12) as executor:
        list(executor.map(fetch, files))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cohort", choices=["nethealth", "uva", "all"])
    parser.add_argument("--data", type=Path, default=ROOT / "data")
    args = parser.parse_args()
    args.data.mkdir(parents=True, exist_ok=True)
    if args.cohort in ("nethealth", "all"):
        with ThreadPoolExecutor(max_workers=2) as executor:
            list(executor.map(lambda key: fetch_nethealth(key, args.data), NETHEALTH))
        print("NetHealth: 2 files verified by publisher MD5")
    if args.cohort in ("uva", "all"):
        fetch_uva(args.data / "uva-sleep")
        print(f"UVA: 161 sleep summaries verified at {UVA_REV}")


if __name__ == "__main__":
    main()
