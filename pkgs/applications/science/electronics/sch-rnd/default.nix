{ lib, stdenv
, fetchurl
, librnd4
, pkg-config
}:

stdenv.mkDerivation rec {
  name = "sch-rnd";
  version = "0.9.4";

  src = fetchurl {
    url = "http://repo.hu/projects/sch-rnd/releases/sch-rnd-${version}.tar.gz";
    hash = "sha256-+7XEPG6e/ruYNmD7IfDfLdVITV1AzqwpfZIc6xsfhi4=";
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ librnd4 ];

  configurePhase = ''
     export LIBRND_PREFIX=${librnd4}
     # Two stage configuring: first ./configure to establish librnd location
     # for the packages.sh script to pick up.
     ./configure

     # Generate default configure options using the packages script.
     export PACKAGING_DIR="doc/developer/packaging"
     ( cd "$PACKAGING_DIR" ; ./packages.sh )

     # Now configure for real with the generates configure args and our prefix
     ./configure $(cat "$PACKAGING_DIR/auto/Configure.args") --prefix=$out
  '';

  doCheck = true;
  checkPhase = "make test";

  meta = with lib; {
    description = "A simple, modular, scriptable schematics editor";
    homepage = "http://repo.hu/projects/sch-rnd/";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = with maintainers; [ hzeller ];
  };
}
