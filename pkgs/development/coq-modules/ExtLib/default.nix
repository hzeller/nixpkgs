{
  lib,
  mkCoqDerivation,
  coq,
  stdlib,
  version ? null,
}:

mkCoqDerivation {
  pname = "coq-ext-lib";
  inherit version;
  defaultVersion =
    let
      case = case: out: { inherit case out; };
    in
    with lib.versions;
    lib.switch coq.coq-version [
      (case (range "8.14" "9.1") "0.13.0")
      (case (range "8.11" "8.19") "0.12.0")
      (case (range "8.8" "8.16") "0.11.6")
      (case (range "8.8" "8.14") "0.11.4")
      (case (range "8.8" "8.13") "0.11.3")
      (case ("8.7") "0.9.7")
      (case ("8.6") "0.9.5")
      (case ("8.5") "0.9.4")
    ] null;
  release."0.13.0".sha256 = "sha256-vqVSu+nyGjRVXe2tnE6MPl0kcg4LHfgFwRCpTQAP/is=";
  release."0.12.2".sha256 = "sha256-lSTlbpkSuAY6B9cqofXSlDk2VchtqfZpRQ0+y/BAbEY=";
  release."0.12.1".sha256 = "sha256-YIHyiRUHPy/LGM2DMTRKRwP7j6OSBYKpu6wO2mZOubo=";
  release."0.12.0".sha256 = "sha256-9szpnWoS83bDc+iLqElfgz0LNRo9hSRQwUFIgpTca4c=";
  release."0.11.8".sha256 = "sha256-uUBKJb7XjRnyb7rCisZrDcaDdsp1Bv1lXDIU3Ce8e5k=";
  release."0.11.7".sha256 = "sha256-HkxUny0mxDDT4VouBBh8btwxGZgsb459kBufTLLnuEY=";
  release."0.11.6".sha256 = "0w6iyrdszz7zc8kaybhy3mwjain2d2f83q79xfd5di0hgdayh7q7";
  release."0.11.4".sha256 = "0yp8mhrhkc498nblvhq1x4j6i9aiidkjza4wzvrkp9p8rgx5g5y3";
  release."0.11.3".sha256 = "1w99nzpk72lffxis97k235axss5lmzhy5z3lga2i0si95mbpil42";
  release."0.11.2".sha256 = "0iyka81g26x5n99xic7kqn8vxqjw8rz7vw9rs27iw04lf137vzv6";
  release."0.10.3".sha256 = "0795gs2dlr663z826mp63c8h2zfadn541dr8q0fvnvi2z7kfyslb";
  release."0.11.1".sha256 = "0dmf1p9j8lm0hwaq0af18jxdwg869xi2jm8447zng7krrq3kvkg5";
  release."0.10.2".sha256 = "1b150rc5bmz9l518r4m3vwcrcnnkkn9q5lrwygkh0a7mckgg2k9f";
  release."0.10.1".sha256 = "0r1vspad8fb8bry3zliiz4hfj4w1iib1l2gm115a94m6zbiksd95";
  release."0.10.0".sha256 = "1kxi5bmjwi5zqlqgkyzhhxwgcih7wf60cyw9398k2qjkmi186r4a";
  release."0.9.7".sha256 = "00v4bm4glv1hy08c8xsm467az6d1ashrznn8p2bmbmmp52lfg7ag";
  release."0.9.5".sha256 = "1b4cvz3llxin130g13calw5n1zmvi6wdd5yb8a41q7yyn2hd3msg";
  release."0.9.4".sha256 = "1y66pamgsdxlq2w1338lj626ln70cwj7k53hxcp933g8fdsa4hp0";
  releaseRev = v: "v${v}";

  propagatedBuildInputs = [ stdlib ];

  meta = {
    description = "Collection of theories and plugins that may be useful in other Coq developments";
    maintainers = with lib.maintainers; [
      jwiegley
      ptival
    ];
  };
}
