{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  mock,
  nose,
  plotly,
  pytest,
  requests,
  retrying,
  setuptools,
  six,
}:

buildPythonPackage rec {
  pname = "chart-studio";
  version = "5.23.0";
  pyproject = true;

  # chart-studio was split from plotly
  src = fetchFromGitHub {
    owner = "plotly";
    repo = "plotly.py";
    rev = "refs/tags/v${version}";
    hash = "sha256-K1hEs00AGBCe2fgytyPNWqE5M0jU5ESTzynP55kc05Y=";
  };

  sourceRoot = "${src.name}/packages/python/chart-studio";

  nativeBuildInputs = [ setuptools ];

  propagatedBuildInputs = [
    plotly
    requests
    retrying
    six
  ];

  nativeCheckInputs = [
    mock
    nose
    pytest
  ];
  # most tests talk to a service
  checkPhase = ''
    HOME=$TMPDIR pytest chart_studio/tests/test_core chart_studio/tests/test_plot_ly/test_api
  '';

  meta = with lib; {
    description = "Utilities for interfacing with Plotly's Chart Studio service";
    homepage = "https://github.com/plotly/plotly.py/tree/master/packages/python/chart-studio";
    license = with licenses; [ mit ];
    maintainers = [ ];
  };
}
