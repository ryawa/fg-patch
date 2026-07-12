#!/usr/bin/env bash
set -e

APP="$HOME/Library/Containers/io.playcover.PlayCover/Applications/uk.co.mediatonic.fallguys.app"
FW="$APP/Frameworks/MarketplaceKit.framework"
UNITY="$APP/Frameworks/UnityFramework.framework/UnityFramework"

cp "$UNITY" "$UNITY.bak" 2>/dev/null || true

# 1. Stub MarketplaceKit
mkdir -p "$FW"

cat > /tmp/marketplace_stub.swift << 'SWIFT'
@_silgen_name("$s14MarketplaceKit14AppDistributorO11marketplaceyACSScACmFWC")
public func _marketplace_witness() {}

@_silgen_name("$s14MarketplaceKit14AppDistributorO7currentACvgZTu")
public func _marketplace_current_tu() {}

public enum AppDistributor: String, RawRepresentable, Hashable, CaseIterable {
    case marketplace = "marketplace"
    public static var current: AppDistributor { .marketplace }
}
SWIFT

swiftc \
  -module-name MarketplaceKit \
  -emit-library \
  -target arm64-apple-macos12.0 \
  -Xlinker -install_name \
  -Xlinker /System/Library/Frameworks/MarketplaceKit.framework/MarketplaceKit \
  -o "$FW/MarketplaceKit" \
  /tmp/marketplace_stub.swift

codesign --force --sign - "$FW/MarketplaceKit"

# 2. @rpath
install_name_tool \
  -change \
  /System/Library/Frameworks/MarketplaceKit.framework/MarketplaceKit \
  @rpath/MarketplaceKit.framework/MarketplaceKit \
  "$UNITY"

# 3. Patches binaires
python3 -c "
patches = {
    0x20ee0: bytes([0x1f, 0x20, 0x03, 0xd5]),  # brk -> nop
    0x20ea4: bytes([0xd6, 0x02, 0x1f, 0x2a]),  # ldrb w22 -> mov w22, #0
    0x20e94: bytes([0x1f, 0x20, 0x03, 0xd5]),  # bl dispatch_semaphore_wait -> nop
}
with open('$UNITY', 'r+b') as f:
    for offset, patch in patches.items():
        f.seek(offset)
        current = f.read(4)
        if current == patch:
            print(f'{hex(offset)} already patched')
        else:
            f.seek(offset)
            f.write(patch)
            print(f'patched {hex(offset)}: {current.hex()} -> {patch.hex()}')
"

codesign --force --sign - "$UNITY"

echo "Done."
