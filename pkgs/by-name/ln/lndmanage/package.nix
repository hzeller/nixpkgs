{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication rec {
  pname = "lndmanage";
  version = "0.16.0";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "bitromortac";
    repo = "lndmanage";
    tag = "v${version}";
    hash = "sha256-VUeGnk/DtNAyEYFESV6kXIRbKqUv4IcMnU3fo0NB4uQ=";
  };

  build-system = with python3Packages; [
    setuptools
  ];

  dependencies = with python3Packages; [
    cycler
    decorator
    googleapis-common-protos
    grpcio
    grpcio-tools
    kiwisolver
    networkx
    numpy
    protobuf
    pyparsing
    python-dateutil
    six
    pygments
  ];

  preBuild = ''
    substituteInPlace setup.py --replace-fail '==' '>='
  '';

  # requires lnregtest
  doCheck = false;

  pythonImportsCheck = [ "lndmanage" ];

  meta = with lib; {
    description = "Channel management tool for lightning network daemon (LND) operators";
    homepage = "https://github.com/bitromortac/lndmanage";
    license = licenses.mit;
    maintainers = with maintainers; [ mmilata ];
    mainProgram = "lndmanage";
  };
}
