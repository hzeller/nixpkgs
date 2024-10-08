{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pytest-asyncio,
  pytestCheckHook,
  pythonOlder,
  setuptools,
  typing-extensions,
}:

buildPythonPackage rec {
  pname = "aiostream";
  version = "0.6.3";
  pyproject = true;

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "vxgmichel";
    repo = "aiostream";
    rev = "refs/tags/v${version}";
    hash = "sha256-MssA4gDo79mlHjVwQAxhX6DZPHB4Quo6V05Nye91oJg=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail " --cov aiostream" ""
  '';

  build-system = [ setuptools ];

  dependencies = [ typing-extensions ];

  nativeCheckInputs = [
    pytest-asyncio
    pytestCheckHook
  ];

  pythonImportsCheck = [ "aiostream" ];

  meta = with lib; {
    description = "Generator-based operators for asynchronous iteration";
    homepage = "https://aiostream.readthedocs.io";
    changelog = "https://github.com/vxgmichel/aiostream/releases/tag/v${version}";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ rmcgibbo ];
  };
}
