#!/bin/zsh
set -eu
native_root="${0:A:h:h}"
check_dir="$(mktemp -d /tmp/healthpig-native-check.XXXXXX)"
trap 'rm -rf -- "$check_dir"' EXIT
check_binary="$check_dir/core-checks"
xcrun swiftc -parse-as-library "$native_root/Sources/Shared/MotionEngine.swift" "$native_root/Sources/Shared/PigModels.swift" "$native_root/Sources/Shared/ActivityRings.swift" "$native_root/Sources/Shared/SleepSchedule.swift" "$native_root/Sources/Shared/DemoModels.swift" "$native_root/Sources/Shared/FeatureInput.swift" "$native_root/Sources/Shared/PigStore.swift" "$native_root/Sources/Phone/PigDivination.swift" "$native_root/Tests/CoreChecks.swift" -o "$check_binary"
"$check_binary" "$native_root"
