{
  lib,
  stdenv,
  buildBazelPackage,
  fetchFromGitHub,
  bazel_9,
  jdk,
  elfutils,
  libcap,
}:

let
  registry = fetchFromGitHub {
    owner = "bazelbuild";
    repo = "bazel-central-registry";
    rev = "0aeaaaeee4bb913e21853a0ee0b935b2c114ae3f";
    hash = "sha256-OZjzzwO2+SmlhJvkTaW26gNvmZx0amCLF6e6MGJkRlI=";
  };
in
buildBazelPackage {
  pname = "perf_data_converter";
  version = "0-unstable-2026-03-10";

  src = fetchFromGitHub {
    owner = "google";
    repo = "perf_data_converter";
    rev = "e2c2da7494e1c6cb8bb343c1bb3023ee3f37ab38";
    hash = "sha256-3YaaEQBlNenJihlEkAI3s4WyjOpWpV9rsfLyvubvfMU=";
  };

  bazel = bazel_9;
  bazelFlags = [
    "--registry"
    "file://${registry}"
  ];

  fetchAttrs = {
    hash = "sha256-pel2SqLPTiEDXMOYZIGn7zKkdUl7gaHnWOuef2GrNJQ=";
  };

  nativeBuildInputs = [ jdk ];

  buildInputs = [
    elfutils
    libcap
  ];

  bazelBuildFlags = [ "-c opt" ];
  bazelTargets = [ "src:perf_to_profile" ];

  doCheck = true;
  bazelTestTargets = [ "src:all" ];

  buildAttrs = {
    installPhase = ''
      runHook preInstall
      install -Dm555 -t "$out/bin" bazel-bin/src/perf_to_profile
      runHook postInstall
    '';
  };

  meta = {
    description = "Tool to convert Linux perf files to the profile.proto format used by pprof";
    homepage = "https://github.com/google/perf_data_converter";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [ hzeller ];
    platforms = lib.platforms.linux;
  };
}
