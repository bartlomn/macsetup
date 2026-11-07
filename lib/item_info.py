#!/usr/bin/python3
"""Turns `brew info --json=v2` on stdin into tab-separated rows:
kind, name, aliases and old names (comma), installed (0/1), app paths (colon), description.
"""
import json
import re
import sys


def clean(text):
    return re.sub(r"[\t\r\n]+", " ", text or "").strip()


def app_paths(cask):
    paths = []
    for artifact in cask.get("artifacts") or []:
        for entry in artifact.get("app", []) if isinstance(artifact, dict) else []:
            if isinstance(entry, dict):
                if entry.get("target") and paths:
                    paths[-1] = entry["target"]
            else:
                paths.append(entry)
    return paths


def row(kind, name, others, installed, apps, desc):
    print("\t".join([kind, name, ",".join(others), "1" if installed else "0", ":".join(apps), clean(desc)]))


def main():
    data = json.load(sys.stdin)
    for formula in data.get("formulae") or []:
        others = (formula.get("aliases") or []) + (formula.get("oldnames") or [])
        row("brew", formula["name"], others, formula.get("installed"), [], formula.get("desc"))
    for cask in data.get("casks") or []:
        row("cask", cask["token"], cask.get("old_tokens") or [], cask.get("installed"), app_paths(cask), cask.get("desc"))


main()
