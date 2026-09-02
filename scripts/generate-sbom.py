#!/usr/bin/env python3
"""Generate a deterministic SPDX 2.3 SBOM from the reviewed lockfiles."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "sbom" / "limechain-web3.spdx.json"
PYTHON_REQUIREMENT = re.compile(r"^([A-Za-z0-9_.-]+)==([^\s\\]+)")


def spdx_id(name: str) -> str:
    return "SPDXRef-Package-" + re.sub(r"[^A-Za-z0-9.-]", "-", name)


def package(name: str, version: str, url: str, digest: str | None, purl: str) -> dict[str, object]:
    item: dict[str, object] = {
        "SPDXID": spdx_id(name),
        "name": name,
        "versionInfo": version,
        "downloadLocation": url or "NOASSERTION",
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": "NOASSERTION",
        "copyrightText": "NOASSERTION",
        "externalRefs": [
            {
                "referenceCategory": "PACKAGE-MANAGER",
                "referenceType": "purl",
                "referenceLocator": purl,
            }
        ],
    }
    if digest:
        item["checksums"] = [{"algorithm": "SHA256", "checksumValue": digest}]
    return item


def build() -> dict[str, object]:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    locks = [
        json.loads((ROOT / "toolchains" / profile).read_text(encoding="utf-8"))
        for profile in ("evm-core.lock.json", "solana-core.lock.json", "hedera-core.lock.json")
    ]
    namespace_seed = hashlib.sha256(json.dumps(locks, sort_keys=True).encode()).hexdigest()
    packages: list[dict[str, object]] = [
        {
            "SPDXID": spdx_id("limechain-web3"),
            "name": "limechain-omarchy-web3",
            "versionInfo": version,
            "downloadLocation": "https://github.com/limechain/omarchy-web3",
            "filesAnalyzed": False,
            "licenseConcluded": "MIT",
            "licenseDeclared": "MIT",
            "copyrightText": "Copyright (c) 2026 LimeChain",
            "externalRefs": [
                {
                    "referenceCategory": "PACKAGE-MANAGER",
                    "referenceType": "purl",
                    "referenceLocator": f"pkg:github/limechain/omarchy-web3@{version}",
                }
            ],
        }
    ]
    relationships: list[dict[str, str]] = []
    root_id = spdx_id("limechain-web3")

    for lock in locks:
        for artifact in lock["artifacts"]:
            item = package(
                artifact["id"],
                artifact["version"],
                artifact["url"],
                artifact["sha256"],
                f"pkg:generic/{artifact['id']}@{artifact['version']}?download_url={artifact['url']}",
            )
            packages.append(item)
            relationships.append(
                {
                    "spdxElementId": root_id,
                    "relationshipType": "DEPENDS_ON",
                    "relatedSpdxElement": str(item["SPDXID"]),
                }
            )

    requirement_lines = (ROOT / "toolchains" / "python-requirements.lock").read_text(encoding="utf-8").splitlines()
    seen: set[str] = set()
    for line in requirement_lines:
        match = PYTHON_REQUIREMENT.match(line)
        if not match:
            continue
        name, package_version = match.groups()
        normalized = name.lower().replace("_", "-")
        if normalized in seen:
            continue
        seen.add(normalized)
        item = package(normalized, package_version, "NOASSERTION", None, f"pkg:pypi/{normalized}@{package_version}")
        packages.append(item)
        relationships.append(
            {"spdxElementId": root_id, "relationshipType": "DEPENDS_ON", "relatedSpdxElement": str(item["SPDXID"])}
        )

    relationships.append(
        {"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": root_id}
    )
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"limechain-omarchy-web3-{version}",
        "documentNamespace": f"https://limechain.tech/spdx/{uuid.uuid5(uuid.NAMESPACE_URL, namespace_seed)}",
        "creationInfo": {
            "created": max(str(lock["generated_at"]) for lock in locks),
            "creators": ["Organization: LimeChain", "Tool: scripts/generate-sbom.py"],
        },
        "packages": sorted(packages, key=lambda item: str(item["SPDXID"])),
        "relationships": sorted(
            relationships,
            key=lambda item: (item["spdxElementId"], item["relationshipType"], item["relatedSpdxElement"]),
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = json.dumps(build(), indent=2, sort_keys=True) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != rendered:
            print("SBOM is stale; run scripts/generate-sbom.py", file=sys.stderr)
            return 1
        print("SBOM is current")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8")
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
