import argparse
import json
from importlib import metadata
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    packages = []
    for dist in metadata.distributions():
        meta = dist.metadata
        packages.append(
            {
                "name": meta.get("Name"),
                "version": dist.version,
                "license": meta.get("License"),
                "licenseExpression": meta.get("License-Expression"),
                "licenseClassifiers": [
                    value for value in meta.get_all("Classifier", []) if value.startswith("License ::")
                ],
                "projectUrls": meta.get_all("Project-URL", []),
            }
        )
    packages.sort(key=lambda item: (item["name"] or "").lower())
    Path(args.output).write_text(
        json.dumps(packages, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({"packageCount": len(packages), "output": Path(args.output).name}))


if __name__ == "__main__":
    main()
