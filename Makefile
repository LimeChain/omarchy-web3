.PHONY: test verify sbom

test: verify
	python3 -m unittest discover -s tests -v
	bash tests/test_install.sh

verify:
	bash -n install scripts/*.sh tests/test_install.sh
	python3 scripts/verify-lock.py
	python3 scripts/generate-sbom.py --check
	jq -e . manifest.json toolchains/evm-core.lock.json toolchains/solana-core.lock.json evals/evals.json >/dev/null

sbom:
	python3 scripts/generate-sbom.py
