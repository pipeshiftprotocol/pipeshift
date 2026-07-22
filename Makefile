.PHONY: help build test fmt fmt-check sdk clean all

help:
	@echo "build      compile contracts and the sdk"
	@echo "test       run both suites"
	@echo "fmt        format contracts"
	@echo "fmt-check  verify formatting without writing"
	@echo "clean      remove build artifacts"

build:
	cd contracts && forge build --sizes
	cd sdk-ts && npm run build

test:
	cd contracts && forge test
	cd sdk-ts && npm test

fmt:
	cd contracts && forge fmt

fmt-check:
	cd contracts && forge fmt --check

sdk:
	cd sdk-ts && npm run build && node dist/cli.js net examples/session.json

clean:
	cd contracts && forge clean
	cd sdk-ts && npm run clean

all: fmt-check build test
