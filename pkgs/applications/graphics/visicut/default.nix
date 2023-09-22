{ lib
, fetchFromGitHub
, maven
, librsvg
, jdk
}:

maven.buildMavenPackage rec {
  pname = "visicut";

  # The version number the authors use in their release is
  # (tagged-version)-(commits) after last tag.
  # The tags are not annotated, but with
  #   git describe --tags
  # the particular version can be extracted.
  git_hash = "77efb7f4927ffec871254ced58e252479dd32435";
  version = "1.9-203";

  src = fetchFromGitHub {
    owner = "t-oster";
    repo = "VisiCut";
    rev = git_hash;
    sha256 = "sha256-fK/zl7tF3NU2LlLkTxR3pY/5TQBLhO5H3YRghomC+rk=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    maven
    librsvg
  ];

  mvnHash = "";  # TBD - output derivation hash after fetching all packages ?

  postPatch = ''
     patchShebangs \
       ./generateSplash \
       ./tools/inkscape_extension/visicut_export.py
  '';

  preBuild = ''
     export VERSION=${version}
     ./generateSplash
  '';

  installPhase = ''
     runHook preInstall
     # TBD once maven build works; take from Makefile
     runHook postInstall
  '';

  meta = with lib; {
    description = "A userfriendy, platform-independent tool for preparing, saving and sending jobs to Lasercutters";
    homepage = "https://visicut.org/";
    license = licenses.lgpl3;
    maintainers = with maintainers; [ hzeller ];
    platforms = platforms.all;
  };
}
