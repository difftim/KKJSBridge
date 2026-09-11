# Local macOS regression tests; no iOS build or CocoaPods installation required.
.DEFAULT_GOAL := test-form-body
# WebKit runners use a desktop session; keep suites and their compiler caches serial.
.NOTPARALLEL:

TEST_DIR := Tests/FormBodyRecovery
SOURCE_DIR := KKJSBridge/KKJSBridge/Modules/Ajax/AjaxProtocolHook
BUILD_DIR := $(CURDIR)/.build/form-body-tests
MODULE_CACHE := $(BUILD_DIR)/modules

.PHONY: test-form-body test-form-body-native test-form-body-webkit test-form-body-wire

test-form-body: test-form-body-native test-form-body-webkit test-form-body-wire test-url-protocol

test-form-body-native:
	@mkdir -p "$(BUILD_DIR)"
	xcrun clang -fobjc-arc -fblocks -framework Foundation -I "$(SOURCE_DIR)" \
		"$(SOURCE_DIR)/KKJSBridgeFormBodyStore.m" "$(TEST_DIR)/FormBodyStoreTests.m" \
		-o "$(BUILD_DIR)/native"
	"$(BUILD_DIR)/native"

test-form-body-webkit:
	@mkdir -p "$(BUILD_DIR)"
	xcrun swiftc "$(TEST_DIR)/FormBodyRecoveryWebKitTests.swift" \
		-module-cache-path "$(MODULE_CACHE)" -o "$(BUILD_DIR)/webkit"
	"$(BUILD_DIR)/webkit" "$(CURDIR)"

test-form-body-wire:
	@mkdir -p "$(BUILD_DIR)"
	xcrun swiftc "$(TEST_DIR)/FormBodyWireTests.swift" \
		-module-cache-path "$(MODULE_CACHE)" -o "$(BUILD_DIR)/wire"
	python3 "$(TEST_DIR)/wire_server.py" "$(CURDIR)" "$(BUILD_DIR)/wire"

# Compile production protocol/cache/serialization; replace network and cookie collaborators only.
.PHONY: test-url-protocol
test-url-protocol:
	@mkdir -p "$(BUILD_DIR)"
	xcrun clang -fobjc-arc -fblocks -framework Foundation -framework WebKit -framework CFNetwork -framework CoreServices \
		$(addprefix -I ,$(sort $(dir $(shell rg --files KKJSBridge/KKJSBridge -g '*.h')))) \
		"$(SOURCE_DIR)/KKJSBridgeAjaxURLProtocol.m" "$(SOURCE_DIR)/KKJSBridgeXMLBodyCacheRequest.m" \
		"$(SOURCE_DIR)/KKJSBridgeFormBodyStore.m" KKJSBridge/KKJSBridge/Modules/Ajax/Util/KKJSBridgeAjaxBodyHelper.m \
		KKJSBridge/KKJSBridge/Modules/Ajax/FormData/*.m KKJSBridge/KKJSBridge/Util/KKJSBridgeSafeDictionary.m \
		KKJSBridge/KKJSBridge/Util/KKJSBridgeWeakProxy.m "$(TEST_DIR)/URLProtocolIsolationTests.m" \
		-o "$(BUILD_DIR)/url-protocol"
	"$(BUILD_DIR)/url-protocol"
