#!/usr/bin/env python3
"""Refuse to republish an existing ForgeBox version, including partial releases."""
import argparse
import json
import subprocess
import sys


def verify_entry(entry, version):
    if not isinstance(entry, dict):
        raise ValueError("ForgeBox returned an invalid entry")
    versions = entry.get("versions")
    if not isinstance(versions, list):
        raise ValueError("ForgeBox returned no version inventory; publication is stopped")
    wanted = version.split("+", 1)[0]
    for item in versions:
        if not isinstance(item, dict) or not isinstance(item.get("version"), str):
            raise ValueError("ForgeBox returned an invalid version inventory")
        if item["version"].split("+", 1)[0] == wanted:
            raise ValueError("This version already exists on ForgeBox; inspect and recover the existing release instead of republishing")


def verify_result(code, output, version):
    if code:
        # The CLI emits this specific response for an entry that has never been published.
        # Authentication, timeouts and other failures must not be treated as absence.
        if "The entry slug sent is invalid or does not exist" in output:
            return
        raise ValueError("Could not verify ForgeBox publication state; publication is stopped")
    verify_entry(json.loads(output), version)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("slug")
    parser.add_argument("version")
    args = parser.parse_args()
    result = subprocess.run(["box", "forgebox", "show", "slug=" + args.slug, "--json"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
    verify_result(result.returncode, result.stdout, args.version)
    print("ForgeBox version is available for initial publication")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
