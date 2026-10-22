#!/bin/sh
# Runs inside a Linux container: normalize Unix modes, then pack with the
# official fnOS fnpack. The Windows build of fnpack writes 0666 into the
# archive, so packaging is done here to keep scripts and the binary 0755.
set -eu

: "${PLATFORM:?PLATFORM is required}"
: "${VERSION:?VERSION is required}"

cp /tools/fnpack-linux-amd64 /usr/local/bin/fnpack
chmod +x /usr/local/bin/fnpack

rm -rf /tmp/magpie-fpk
cp -a "/work/build/fpk-stage/${PLATFORM}" /tmp/magpie-fpk
cd /tmp/magpie-fpk

chmod 755 . cmd cmd/* app app/bin app/bin/magpie app/ui app/ui/images app/certs wizard config
chmod 644 manifest config/privilege config/resource wizard/install wizard/uninstall \
  app/ui/config app/ui/images/* app/certs/* ICON.PNG ICON_256.PNG Magpie.sc app/LICENSE

output=$(fnpack build --directory /tmp/magpie-fpk 2>&1) || true
printf '%s\n' "${output}"
case "${output}" in
  *"Packing successfully"*) ;;
  *)
    echo "fnpack failed" >&2
    exit 1
    ;;
esac

test -f /tmp/magpie-fpk/magpie.fpk

# fnpack 1.2.3 drops custom root-level files (the .sc port declaration), so
# repack the archive with Magpie.sc at its root. fnOS reads the port-config
# resource from the package root.
repack_dir=$(mktemp -d)
tar -xzf /tmp/magpie-fpk/magpie.fpk -C "${repack_dir}"
cp /tmp/magpie-fpk/Magpie.sc "${repack_dir}/Magpie.sc"
chmod 644 "${repack_dir}/Magpie.sc"
(
  cd "${repack_dir}"
  tar -czf /tmp/magpie-fpk/magpie.fpk \
    app.tgz cmd config ICON.PNG ICON_256.PNG manifest wizard Magpie.sc
)
rm -rf "${repack_dir}"

tar -tzf /tmp/magpie-fpk/magpie.fpk | grep -qx 'Magpie.sc'
cp /tmp/magpie-fpk/magpie.fpk "/work/dist/magpie_${VERSION}_${PLATFORM}.fpk"
