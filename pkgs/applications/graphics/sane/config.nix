{ lib, stdenv }:

{
  paths,
  disabledDefaultBackends ? [ ],
}:

let
  installSanePath = path: ''
    if [ -e "${path}/lib/sane" ]; then
      find "${path}/lib/sane" -maxdepth 1 -not -type d | while read backend; do
        symlink "$backend" "$out/lib/sane/$(basename "$backend")"
      done
    fi

    if [ -e "${path}/etc/sane.d" ]; then
      find "${path}/etc/sane.d" -maxdepth 1 -not -type d | while read conf; do
        name="$(basename $conf)"
        if [ "$name" = "dll.conf" ] || [ "$name" = "saned.conf" ] || [ "$name" = "net.conf" ]; then
          cat "$conf" >> "$out/etc/sane.d/$name"
        else
          symlink "$conf" "$out/etc/sane.d/$name"
        fi
      done
    fi

    if [ -e "${path}/etc/sane.d/dll.d" ]; then
      find "${path}/etc/sane.d/dll.d" -maxdepth 1 -not -type d | while read conf; do
        symlink "$conf" "$out/etc/sane.d/dll.d/$(basename $conf)"
      done
    fi
  '';
  disableBackend = backend: ''
    grep -w -q '${backend}' $out/etc/sane.d/dll.conf || { echo '${backend} is not a default plugin in $SANE_CONFIG_DIR/dll.conf'; exit 1; }
    sed -i 's/\b${backend}\b/# ${backend} disabled by nixos config/' $out/etc/sane.d/dll.conf
  '';
in
stdenv.mkDerivation {
  name = "sane-config";
  dontUnpack = true;

  installPhase = ''
    function symlink () {
      local target=$1 linkname=$2
      if [ -e "$linkname" ]; then
        echo "warning: conflict for $linkname. Overriding $(readlink $linkname) with $target."
      fi
      ln -sfn "$target" "$linkname"
    }

    mkdir -p $out/etc/sane.d $out/etc/sane.d/dll.d $out/lib/sane
  ''
  + (lib.concatMapStrings installSanePath paths)
  + (lib.concatMapStrings disableBackend disabledDefaultBackends);
}
