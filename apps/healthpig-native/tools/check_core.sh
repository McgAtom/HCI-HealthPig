#!/bin/zsh
set -eu
native_root="${0:A:h:h}"
check_binary="$(mktemp -d /tmp/healthpig-native-check.XXXXXX)/core-checks"
xcrun swiftc -parse-as-library "$native_root/Sources/Shared/MotionEngine.swift" "$native_root/Sources/Shared/PigModels.swift" "$native_root/Sources/Shared/ActivityRings.swift" "$native_root/Sources/Shared/DemoModels.swift" "$native_root/Sources/Shared/FeatureInput.swift" "$native_root/Sources/Shared/PigStore.swift" "$native_root/Tests/CoreChecks.swift" -o "$check_binary"
"$check_binary" "$native_root"
