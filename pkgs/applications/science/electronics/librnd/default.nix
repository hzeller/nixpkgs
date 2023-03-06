{ lib, stdenv
, fetchurl
, gd
, glib
, gnome2
, gtk2
, gtk4
, libGLU
, libepoxy
, pkg-config
, wget
}:

stdenv.mkDerivation rec {
  name = "librnd4";
  version = "4.0.0";

  src = fetchurl {
    url = "http://repo.hu/projects/librnd/releases/librnd-${version}.tar.gz";
    hash = "sha256-ZL76ThUD9yRvVJue1e5naQp6qiW/hLblxHTIUH9Abwk=";
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    wget
    gd
    glib
    gnome2.gtkglext
    gtk2
    gtk4
    libepoxy
    libGLU
  ];

  configurePhase = ''
     # Generate default configure options using the packages script.
     export PACKAGING_DIR="doc/developer/packaging"
     ( cd "$PACKAGING_DIR" ; ./packages.sh )

     ./configure $(cat "$PACKAGING_DIR/auto/Configure.args") --prefix=$out
  '';

  doCheck = true;
  checkPhase = "make test";

  meta = with lib; {
    description = "A modular framework library for 2D CAD applications";
    homepage = "http://repo.hu/projects/librnd/";
    license = licenses.gpl2Plus;
    platforms = platforms.all;
    maintainers = with maintainers; [ hzeller ];
  };
}
