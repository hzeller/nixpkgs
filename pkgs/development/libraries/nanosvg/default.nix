{ lib
, stdenv
, fetchFromGitHub
, cmake
}:

stdenv.mkDerivation rec {
  pname = "nanosvg";
  version = "2022-12-04";

  src = fetchFromGitHub {
    owner = "memononen";
    repo = "nanosvg";
    rev = "9da543e8329fdd81b64eb48742d8ccb09377aed1";
    sha256 = "sha256-VOiN6583DtzGYPRkl19VG2QvSzl4T9HaynBuNcvZf94=";
  };

  nativeBuildInputs = [ cmake ];

  meta = with lib; {
    homepage = "https://github.com/memononen/nanosvg";
    description = "A simple stupid SVG parser";
    license = licenses.zlib;
    maintainers = with maintainers; [ hzeller ];
    platforms = platforms.all;
  };
}
