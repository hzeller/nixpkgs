{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  git,
}:

buildPythonPackage rec {
  pname = "versiontag";
  version = "1.2.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "thelabnyc";
    repo = "python-versiontag";
    rev = "r${version}";
    sha256 = "1axv2214ykgv5adajv10v2zy5fr9v77db54rkik6ja29p66zl90n";
  };

  postPatch = ''
    substituteInPlace setup.py \
      --replace-fail "get_version(pypi=True)" '"${version}"'
  '';

  build-system = [ setuptools ];

  nativeCheckInputs = [ git ];

  pythonImportsCheck = [ "versiontag" ];

  meta = with lib; {
    description = "Python library designed to make accessing the current version number of your software easy";
    homepage = "https://github.com/thelabnyc/python-versiontag";
    license = licenses.isc;
    maintainers = with maintainers; [ MaskedBelgian ];
  };
}
