APP := Nervegear
WORK := $(CURDIR)/.work
TMP := $(WORK)/tmp

.PHONY: dev dev-fast build release

dev:
	mkdir -p $(TMP) $(WORK)/dev
	TMPDIR=$(TMP) swift -swift-version 6 tools/dev.swift --profile dev

dev-fast:
	mkdir -p $(TMP) $(WORK)/dev
	TMPDIR=$(TMP) swift -swift-version 6 tools/dev.swift --profile dev-fast

build:
	mkdir -p $(TMP)
	TMPDIR=$(TMP) swift build --scratch-path $(WORK)/build/dev --configuration debug -Xswiftc -gnone --product $(APP)

release:
	mkdir -p $(TMP)
	TMPDIR=$(TMP) swift build --scratch-path $(WORK)/build/release --configuration release --product $(APP)
