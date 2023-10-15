{ stdenv
, lib
, fetchFromGitHub
, pkg-config
, yosys
, uhdm
, surelog
, capnproto
, antlr4
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "yosys-synlig";
  version = "2023.10.12";  # Currently no tagged versions upstream
  plugin = "synlig";

  src = fetchFromGitHub {
    owner  = "chipsalliance";
    repo   = "synlig";
    rev    = "c5bd73595151212c61709d69a382917e96877a14";
    sha256 = "sha256-WJhf5gdZTCs3EeNocP9aZAh6EZquHgYOG/xiTo8l0ao=";
    fetchSubmodules = false;  # we use all dependencies from nix
  };

  patches = [
    ./synlig-makefile-for-nix.patch  # Remove assumption submodules available.
  ];

  buildInputs = [
    yosys
    uhdm
    surelog
    capnproto
    antlr4.runtime.cpp
  ];

  nativeBuildInputs = [
    pkg-config
  ];

  buildPhase = ''
    runHook preBuild
    make -j $NIX_BUILD_CORES build@systemverilog-plugin
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/yosys/plugins
    cp ./build/release/systemverilog-plugin/systemverilog.so \
           $out/share/yosys/plugins/systemverilog.so
    runHook postInstall
  '';

  meta = with lib; {
    description = "SystemVerilog support plugin for Yosys";
    homepage    = "https://github.com/chipsalliance/synlig";
    license     = licenses.asl20;
    maintainers = with maintainers; [ hzeller ];
    platforms   = platforms.all;
  };
})
