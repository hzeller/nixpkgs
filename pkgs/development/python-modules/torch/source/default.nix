{
  stdenv,
  lib,
  fetchFromGitHub,
  fetchFromGitLab,
  git-unroll,
  buildPythonPackage,
  python,
  runCommand,
  writeShellScript,
  config,
  cudaSupport ? config.cudaSupport,
  cudaPackages,
  autoAddDriverRunpath,
  effectiveMagma ?
    if cudaSupport then
      magma-cuda-static
    else if rocmSupport then
      magma-hip
    else
      magma,
  magma,
  magma-hip,
  magma-cuda-static,
  # Use the system NCCL as long as we're targeting CUDA on a supported platform.
  useSystemNccl ? (cudaSupport && !cudaPackages.nccl.meta.unsupported || rocmSupport),
  MPISupport ? false,
  mpi,
  buildDocs ? false,

  # tests.cudaAvailable:
  callPackage,

  # Native build inputs
  cmake,
  symlinkJoin,
  which,
  pybind11,
  pkg-config,
  removeReferencesTo,

  # Build inputs
  apple-sdk_13,
  numactl,
  llvmPackages,

  # dependencies
  astunparse,
  binutils,
  expecttest,
  filelock,
  fsspec,
  hypothesis,
  jinja2,
  networkx,
  packaging,
  psutil,
  pyyaml,
  requests,
  sympy,
  types-dataclasses,
  typing-extensions,
  # ROCm build and `torch.compile` requires `triton`
  tritonSupport ? (!stdenv.hostPlatform.isDarwin),
  triton,

  # TODO: 1. callPackage needs to learn to distinguish between the task
  #          of "asking for an attribute from the parent scope" and
  #          the task of "exposing a formal parameter in .override".
  # TODO: 2. We should probably abandon attributes such as `torchWithCuda` (etc.)
  #          as they routinely end up consuming the wrong arguments\
  #          (dependencies without cuda support).
  #          Instead we should rely on overlays and nixpkgsFun.
  # (@SomeoneSerge)
  _tritonEffective ?
    if cudaSupport then
      triton-cuda
    else if rocmSupport then
      rocmPackages.triton
    else
      triton,
  triton-cuda,

  # Disable MKLDNN on aarch64-darwin, it negatively impacts performance,
  # this is also what official pytorch build does
  mklDnnSupport ? !(stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64),

  # virtual pkg that consistently instantiates blas across nixpkgs
  # See https://github.com/NixOS/nixpkgs/pull/83888
  blas,

  # ninja (https://ninja-build.org) must be available to run C++ extensions tests,
  ninja,

  # dependencies for torch.utils.tensorboard
  pillow,
  six,
  tensorboard,
  protobuf,

  # ROCm dependencies
  rocmSupport ? config.rocmSupport,
  rocmPackages,
  gpuTargets ? [ ],

  vulkanSupport ? false,
  vulkan-headers,
  vulkan-loader,
  shaderc,
}:

let
  inherit (lib)
    attrsets
    lists
    strings
    trivial
    ;
  inherit (cudaPackages) cudnn flags nccl;

  triton = throw "python3Packages.torch: use _tritonEffective instead of triton to avoid divergence";

  setBool = v: if v then "1" else "0";

  # https://github.com/pytorch/pytorch/blob/v2.7.0/torch/utils/cpp_extension.py#L2343-L2345
  supportedTorchCudaCapabilities =
    let
      real = [
        "3.5"
        "3.7"
        "5.0"
        "5.2"
        "5.3"
        "6.0"
        "6.1"
        "6.2"
        "7.0"
        "7.2"
        "7.5"
        "8.0"
        "8.6"
        "8.7"
        "8.9"
        "9.0"
        "9.0a"
        "10.0"
        "10.0"
        "10.0a"
        "10.1"
        "10.1a"
        "12.0"
        "12.0a"
      ];
      ptx = lists.map (x: "${x}+PTX") real;
    in
    real ++ ptx;

  # NOTE: The lists.subtractLists function is perhaps a bit unintuitive. It subtracts the elements
  #   of the first list *from* the second list. That means:
  #   lists.subtractLists a b = b - a

  # For CUDA
  supportedCudaCapabilities = lists.intersectLists flags.cudaCapabilities supportedTorchCudaCapabilities;
  unsupportedCudaCapabilities = lists.subtractLists supportedCudaCapabilities flags.cudaCapabilities;

  isCudaJetson = cudaSupport && cudaPackages.flags.isJetsonBuild;

  # Use trivial.warnIf to print a warning if any unsupported GPU targets are specified.
  gpuArchWarner =
    supported: unsupported:
    trivial.throwIf (supported == [ ]) (
      "No supported GPU targets specified. Requested GPU targets: "
      + strings.concatStringsSep ", " unsupported
    ) supported;

  # Create the gpuTargetString.
  gpuTargetString = strings.concatStringsSep ";" (
    if gpuTargets != [ ] then
      # If gpuTargets is specified, it always takes priority.
      gpuTargets
    else if cudaSupport then
      gpuArchWarner supportedCudaCapabilities unsupportedCudaCapabilities
    else if rocmSupport then
      # Remove RDNA1 gfx101x archs from default ROCm support list to avoid
      # use of undeclared identifier 'CK_BUFFER_RESOURCE_3RD_DWORD'
      # TODO: Retest after ROCm 6.4 or torch 2.8
      lib.lists.subtractLists [
        "gfx1010"
        "gfx1012"
      ] (rocmPackages.clr.localGpuTargets or rocmPackages.clr.gpuTargets)
    else
      throw "No GPU targets specified"
  );

  rocmtoolkit_joined = symlinkJoin {
    name = "rocm-merged";

    paths = with rocmPackages; [
      rocm-core
      clr
      rccl
      miopen
      aotriton
      composable_kernel
      rocrand
      rocblas
      rocsparse
      hipsparse
      rocthrust
      rocprim
      hipcub
      roctracer
      rocfft
      rocsolver
      hipfft
      hiprand
      hipsolver
      hipblas-common
      hipblas
      hipblaslt
      rocminfo
      rocm-comgr
      rocm-device-libs
      rocm-runtime
      clr.icd
      hipify
    ];

    # Fix `setuptools` not being found
    postBuild = ''
      rm -rf $out/nix-support
    '';
  };

  brokenConditions = attrsets.filterAttrs (_: cond: cond) {
    "CUDA and ROCm are mutually exclusive" = cudaSupport && rocmSupport;
    "CUDA is not targeting Linux" = cudaSupport && !stdenv.hostPlatform.isLinux;
    "Unsupported CUDA version" =
      cudaSupport
      && !(builtins.elem cudaPackages.cudaMajorVersion [
        "11"
        "12"
      ]);
    "MPI cudatoolkit does not match cudaPackages.cudatoolkit" =
      MPISupport && cudaSupport && (mpi.cudatoolkit != cudaPackages.cudatoolkit);
    # This used to be a deep package set comparison between cudaPackages and
    # effectiveMagma.cudaPackages, making torch too strict in cudaPackages.
    # In particular, this triggered warnings from cuda's `aliases.nix`
    "Magma cudaPackages does not match cudaPackages" =
      cudaSupport
      && (effectiveMagma.cudaPackages.cudaMajorMinorVersion != cudaPackages.cudaMajorMinorVersion);
  };

  unroll-src = writeShellScript "unroll-src" ''
    echo "{
      version,
      fetchFromGitLab,
      fetchFromGitHub,
      runCommand,
    }:
    assert version == "'"'$1'"'";"
    ${lib.getExe git-unroll} https://github.com/pytorch/pytorch v$1
    echo
    echo "# Update using: unroll-src [version]"
  '';

  stdenv' = if cudaSupport then cudaPackages.backendStdenv else stdenv;
in
buildPythonPackage rec {
  pname = "torch";
  # Don't forget to update torch-bin to the same version.
  version = "2.7.1";
  pyproject = true;

  stdenv = stdenv';

  outputs = [
    "out" # output standard python package
    "dev" # output libtorch headers
    "lib" # output libtorch libraries
    "cxxdev" # propagated deps for the cmake consumers of torch
  ];
  cudaPropagateToOutput = "cxxdev";

  src = callPackage ./src.nix {
    inherit
      version
      fetchFromGitHub
      fetchFromGitLab
      runCommand
      ;
  };

  patches = [
    ./clang19-template-warning.patch
  ]
  ++ lib.optionals cudaSupport [ ./fix-cmake-cuda-toolkit.patch ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    # Propagate CUPTI to Kineto by overriding the search path with environment variables.
    # https://github.com/pytorch/pytorch/pull/108847
    ./pytorch-pr-108847.patch
  ]
  ++ lib.optionals (lib.getName blas.provider == "mkl") [
    # The CMake install tries to add some hardcoded rpaths, incompatible
    # with the Nix store, which fails. Simply remove this step to get
    # rpaths that point to the Nix store.
    ./disable-cmake-mkl-rpath.patch
  ];

  postPatch = ''
    # Prevent NCCL from being cloned during the configure phase
    # TODO: remove when updating to the next release as it will not be needed anymore
    substituteInPlace tools/build_pytorch_libs.py \
      --replace-fail "  checkout_nccl()" "  "

    substituteInPlace cmake/public/cuda.cmake \
      --replace-fail \
        'message(FATAL_ERROR "Found two conflicting CUDA' \
        'message(WARNING "Found two conflicting CUDA' \
      --replace-warn \
        "set(CUDAToolkit_ROOT" \
        "# Upstream: set(CUDAToolkit_ROOT"
    substituteInPlace third_party/gloo/cmake/Cuda.cmake \
      --replace-warn "find_package(CUDAToolkit 7.0" "find_package(CUDAToolkit"

    # annotations (3.7), print_function (3.0), with_statement (2.6) are all supported
    sed -i -e "/from __future__ import/d" **.py
    substituteInPlace third_party/NNPACK/CMakeLists.txt \
      --replace-fail "PYTHONPATH=" 'PYTHONPATH=$ENV{PYTHONPATH}:'
    # flag from cmakeFlags doesn't work, not clear why
    # setting it at the top of NNPACK's own CMakeLists does
    sed -i '2s;^;set(PYTHON_SIX_SOURCE_DIR ${six.src})\n;' third_party/NNPACK/CMakeLists.txt

    # Ensure that torch profiler unwind uses addr2line from nix
    substituteInPlace torch/csrc/profiler/unwind/unwind.cpp \
      --replace-fail 'addr2line_binary_ = "addr2line"' 'addr2line_binary_ = "${lib.getExe' binutils "addr2line"}"'
  ''
  + lib.optionalString rocmSupport ''
    # https://github.com/facebookincubator/gloo/pull/297
    substituteInPlace third_party/gloo/cmake/Hipify.cmake \
      --replace-fail "\''${HIPIFY_COMMAND}" "python \''${HIPIFY_COMMAND}"

    # Replace hard-coded rocm paths
    substituteInPlace caffe2/CMakeLists.txt \
      --replace-fail "hcc/include" "hip/include" \
      --replace-fail "rocblas/include" "include/rocblas" \
      --replace-fail "hipsparse/include" "include/hipsparse"

    # Doesn't pick up the environment variable?
    substituteInPlace third_party/kineto/libkineto/CMakeLists.txt \
      --replace-fail "\''$ENV{ROCM_SOURCE_DIR}" "${rocmtoolkit_joined}"

    # Strangely, this is never set in cmake
    substituteInPlace cmake/public/LoadHIP.cmake \
      --replace "set(ROCM_PATH \$ENV{ROCM_PATH})" \
        "set(ROCM_PATH \$ENV{ROCM_PATH})''\nset(ROCM_VERSION ${lib.concatStrings (lib.intersperse "0" (lib.splitVersion rocmPackages.clr.version))})"

    # Use composable kernel as dependency, rather than built-in third-party
    substituteInPlace aten/src/ATen/CMakeLists.txt \
      --replace-fail "list(APPEND ATen_HIP_INCLUDE \''${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/composable_kernel/include)" "" \
      --replace-fail "list(APPEND ATen_HIP_INCLUDE \''${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/composable_kernel/library/include)" ""
  ''
  # Detection of NCCL version doesn't work particularly well when using the static binary.
  + lib.optionalString cudaSupport ''
    substituteInPlace cmake/Modules/FindNCCL.cmake \
      --replace-fail \
        'message(FATAL_ERROR "Found NCCL header version and library version' \
        'message(WARNING "Found NCCL header version and library version'
  ''
  # Remove PyTorch's FindCUDAToolkit.cmake and use CMake's default.
  # NOTE: Parts of pytorch rely on unmaintained FindCUDA.cmake with custom patches to support e.g.
  # newer architectures (sm_90a). We do want to delete vendored patches, but have to keep them
  # until https://github.com/pytorch/pytorch/issues/76082 is addressed
  + lib.optionalString cudaSupport ''
    rm cmake/Modules/FindCUDAToolkit.cmake
  '';

  # NOTE(@connorbaker): Though we do not disable Gloo or MPI when building with CUDA support, caution should be taken
  # when using the different backends. Gloo's GPU support isn't great, and MPI and CUDA can't be used at the same time
  # without extreme care to ensure they don't lock each other out of shared resources.
  # For more, see https://github.com/open-mpi/ompi/issues/7733#issuecomment-629806195.
  preConfigure =
    lib.optionalString cudaSupport ''
      export TORCH_CUDA_ARCH_LIST="${gpuTargetString}"
      export CUPTI_INCLUDE_DIR=${lib.getDev cudaPackages.cuda_cupti}/include
      export CUPTI_LIBRARY_DIR=${lib.getLib cudaPackages.cuda_cupti}/lib
    ''
    + lib.optionalString (cudaSupport && cudaPackages ? cudnn) ''
      export CUDNN_INCLUDE_DIR=${lib.getLib cudnn}/include
      export CUDNN_LIB_DIR=${lib.getLib cudnn}/lib
    ''
    + lib.optionalString rocmSupport ''
      export ROCM_PATH=${rocmtoolkit_joined}
      export ROCM_SOURCE_DIR=${rocmtoolkit_joined}
      export PYTORCH_ROCM_ARCH="${gpuTargetString}"
      export CMAKE_CXX_FLAGS="-I${rocmtoolkit_joined}/include -I${rocmtoolkit_joined}/include/rocblas"
      python tools/amd_build/build_amd.py
    '';

  # Use pytorch's custom configurations
  dontUseCmakeConfigure = true;

  # causes possible redefinition of _FORTIFY_SOURCE
  hardeningDisable = [ "fortify3" ];

  BUILD_NAMEDTENSOR = setBool true;
  BUILD_DOCS = setBool buildDocs;

  # We only do an imports check, so do not build tests either.
  BUILD_TEST = setBool false;

  # ninja hook doesn't automatically turn on ninja
  # because pytorch setup.py is responsible for this
  CMAKE_GENERATOR = "Ninja";

  # Unlike MKL, oneDNN (née MKLDNN) is FOSS, so we enable support for
  # it by default. PyTorch currently uses its own vendored version
  # of oneDNN through Intel iDeep.
  USE_MKLDNN = setBool mklDnnSupport;
  USE_MKLDNN_CBLAS = setBool mklDnnSupport;

  # Avoid using pybind11 from git submodule
  # Also avoids pytorch exporting the headers of pybind11
  USE_SYSTEM_PYBIND11 = true;

  # Multicore CPU convnet support
  USE_NNPACK = 1;

  # Explicitly enable MPS for Darwin
  USE_MPS = setBool stdenv.hostPlatform.isDarwin;

  # building torch.distributed on Darwin is disabled by default
  # https://pytorch.org/docs/stable/distributed.html#torch.distributed.is_available
  USE_DISTRIBUTED = setBool true;

  cmakeFlags = [
    (lib.cmakeFeature "PYTHON_SIX_SOURCE_DIR" "${six.src}")
    # (lib.cmakeBool "CMAKE_FIND_DEBUG_MODE" true)
    (lib.cmakeFeature "CUDAToolkit_VERSION" cudaPackages.cudaMajorMinorVersion)
  ]
  ++ lib.optionals cudaSupport [
    # Unbreaks version discovery in enable_language(CUDA) when wrapping nvcc with ccache
    # Cf. https://gitlab.kitware.com/cmake/cmake/-/issues/26363
    (lib.cmakeFeature "CMAKE_CUDA_COMPILER_TOOLKIT_VERSION" cudaPackages.cudaMajorMinorVersion)
  ];

  preBuild = ''
    export MAX_JOBS=$NIX_BUILD_CORES
    ${python.pythonOnBuildForHost.interpreter} setup.py build --cmake-only
    ${cmake}/bin/cmake build
  '';

  preFixup = ''
    function join_by { local IFS="$1"; shift; echo "$*"; }
    function strip2 {
      IFS=':'
      read -ra RP <<< $(patchelf --print-rpath $1)
      IFS=' '
      RP_NEW=$(join_by : ''${RP[@]:2})
      patchelf --set-rpath \$ORIGIN:''${RP_NEW} "$1"
    }
    for f in $(find ''${out} -name 'libcaffe2*.so')
    do
      strip2 $f
    done
  '';

  # Override the (weirdly) wrong version set by default. See
  # https://github.com/NixOS/nixpkgs/pull/52437#issuecomment-449718038
  # https://github.com/pytorch/pytorch/blob/v1.0.0/setup.py#L267
  PYTORCH_BUILD_VERSION = version;
  PYTORCH_BUILD_NUMBER = 0;

  # In-tree builds of NCCL are not supported.
  # Use NCCL when cudaSupport is enabled and nccl is available.
  USE_NCCL = setBool useSystemNccl;
  USE_SYSTEM_NCCL = USE_NCCL;
  USE_STATIC_NCCL = USE_NCCL;

  # Set the correct Python library path, broken since
  # https://github.com/pytorch/pytorch/commit/3d617333e
  PYTHON_LIB_REL_PATH = "${placeholder "out"}/${python.sitePackages}";

  env = {
    # disable warnings as errors as they break the build on every compiler
    # bump, among other things.
    # Also of interest: pytorch ignores CXXFLAGS uses CFLAGS for both C and C++:
    # https://github.com/pytorch/pytorch/blob/v1.11.0/setup.py#L17
    NIX_CFLAGS_COMPILE = toString (
      [
        "-Wno-error"
      ]
      # fix build aarch64-linux build failure with GCC14
      ++ lib.optionals (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64) [
        "-Wno-error=incompatible-pointer-types"
      ]
    );
    USE_VULKAN = setBool vulkanSupport;
  }
  // lib.optionalAttrs vulkanSupport {
    VULKAN_SDK = shaderc.bin;
  }
  // lib.optionalAttrs rocmSupport {
    AOTRITON_INSTALLED_PREFIX = "${rocmPackages.aotriton}";
  };

  nativeBuildInputs = [
    cmake
    which
    ninja
    pybind11
    pkg-config
    removeReferencesTo
  ]
  ++ lib.optionals cudaSupport (
    with cudaPackages;
    [
      autoAddDriverRunpath
      cuda_nvcc
    ]
  )
  ++ lib.optionals isCudaJetson [ cudaPackages.autoAddCudaCompatRunpath ]
  ++ lib.optionals rocmSupport [ rocmtoolkit_joined ];

  buildInputs = [
    blas
    blas.provider
  ]
  # Including openmp leads to two copies being used. This segfaults on ARM.
  # https://github.com/pytorch/pytorch/issues/149201#issuecomment-2776842320
  # ++ lib.optionals stdenv.cc.isClang [ llvmPackages.openmp ]
  ++ lib.optionals cudaSupport (
    with cudaPackages;
    [
      cuda_cccl # <thrust/*>
      cuda_cudart # cuda_runtime.h and libraries
      cuda_cupti # For kineto
      cuda_nvcc # crt/host_config.h; even though we include this in nativeBuildInputs, it's needed here too
      cuda_nvml_dev # <nvml.h>
      cuda_nvrtc
      cuda_nvtx # -llibNVToolsExt
      cusparselt
      libcublas
      libcufft
      libcufile
      libcurand
      libcusolver
      libcusparse
    ]
    ++ lists.optionals (cudaPackages ? cudnn) [ cudnn ]
    ++ lists.optionals useSystemNccl [
      # Some platforms do not support NCCL (i.e., Jetson)
      nccl # Provides nccl.h AND a static copy of NCCL!
    ]
    ++ lists.optionals (cudaOlder "11.8") [
      cuda_nvprof # <cuda_profiler_api.h>
    ]
    ++ lists.optionals (cudaAtLeast "11.8") [
      cuda_profiler_api # <cuda_profiler_api.h>
    ]
  )
  ++ lib.optionals rocmSupport [ rocmPackages.llvm.openmp ]
  ++ lib.optionals (cudaSupport || rocmSupport) [ effectiveMagma ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ numactl ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_13
  ]
  ++ lib.optionals tritonSupport [ _tritonEffective ]
  ++ lib.optionals MPISupport [ mpi ]
  ++ lib.optionals rocmSupport [
    rocmtoolkit_joined
    rocmPackages.clr # Added separately so setup hook applies
  ];

  pythonRelaxDeps = [
    "sympy"
  ];
  dependencies = [
    astunparse
    expecttest
    filelock
    fsspec
    hypothesis
    jinja2
    networkx
    ninja
    packaging
    psutil
    pyyaml
    requests
    sympy
    types-dataclasses
    typing-extensions

    # the following are required for tensorboard support
    pillow
    six
    tensorboard
    protobuf

    # torch/csrc requires `pybind11` at runtime
    pybind11
  ]
  ++ lib.optionals tritonSupport [ _tritonEffective ]
  ++ lib.optionals vulkanSupport [
    vulkan-headers
    vulkan-loader
  ];

  propagatedCxxBuildInputs =
    [ ] ++ lib.optionals MPISupport [ mpi ] ++ lib.optionals rocmSupport [ rocmtoolkit_joined ];

  # Tests take a long time and may be flaky, so just sanity-check imports
  doCheck = false;

  pythonImportsCheck = [ "torch" ];

  nativeCheckInputs = [
    hypothesis
    ninja
    psutil
  ];

  checkPhase =
    with lib.versions;
    with lib.strings;
    concatStringsSep " " [
      "runHook preCheck"
      "${python.interpreter} test/run_test.py"
      "--exclude"
      (concatStringsSep " " [
        "utils" # utils requires git, which is not allowed in the check phase

        # "dataloader" # psutils correctly finds and triggers multiprocessing, but is too sandboxed to run -- resulting in numerous errors
        # ^^^^^^^^^^^^ NOTE: while test_dataloader does return errors, these are acceptable errors and do not interfere with the build

        # tensorboard has acceptable failures for pytorch 1.3.x due to dependencies on tensorboard-plugins
        (optionalString (majorMinor version == "1.3") "tensorboard")
      ])
      "runHook postCheck"
    ];

  pythonRemoveDeps = [
    # In our dist-info the name is just "triton"
    "pytorch-triton-rocm"
  ];

  postInstall = ''
    find "$out/${python.sitePackages}/torch/include" "$out/${python.sitePackages}/torch/lib" -type f -exec remove-references-to -t ${stdenv.cc} '{}' +

    mkdir $dev

    # CppExtension requires that include files are packaged with the main
    # python library output; which is why they are copied here.
    cp -r $out/${python.sitePackages}/torch/include $dev/include

    # Cmake files under /share are different and can be safely moved. This
    # avoids unnecessary closure blow-up due to apple sdk references when
    # USE_DISTRIBUTED is enabled.
    mv $out/${python.sitePackages}/torch/share $dev/share

    # Fix up library paths for split outputs
    substituteInPlace \
      $dev/share/cmake/Torch/TorchConfig.cmake \
      --replace-fail \''${TORCH_INSTALL_PREFIX}/lib "$lib/lib"

    substituteInPlace \
      $dev/share/cmake/Caffe2/Caffe2Targets-release.cmake \
      --replace-fail \''${_IMPORT_PREFIX}/lib "$lib/lib"

    mkdir $lib
    mv $out/${python.sitePackages}/torch/lib $lib/lib
    ln -s $lib/lib $out/${python.sitePackages}/torch/lib
  ''
  + lib.optionalString rocmSupport ''
    substituteInPlace $dev/share/cmake/Tensorpipe/TensorpipeTargets-release.cmake \
      --replace-fail "\''${_IMPORT_PREFIX}/lib64" "$lib/lib"

    substituteInPlace $dev/share/cmake/ATen/ATenConfig.cmake \
      --replace-fail "/build/${src.name}/torch/include" "$dev/include"
  '';

  postFixup = ''
    mkdir -p "$cxxdev/nix-support"
    printWords "''${propagatedCxxBuildInputs[@]}" >> "$cxxdev/nix-support/propagated-build-inputs"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    for f in $(ls $lib/lib/*.dylib); do
        install_name_tool -id $lib/lib/$(basename $f) $f || true
    done

    install_name_tool -change @rpath/libshm.dylib $lib/lib/libshm.dylib $lib/lib/libtorch_python.dylib
    install_name_tool -change @rpath/libtorch.dylib $lib/lib/libtorch.dylib $lib/lib/libtorch_python.dylib
    install_name_tool -change @rpath/libc10.dylib $lib/lib/libc10.dylib $lib/lib/libtorch_python.dylib

    install_name_tool -change @rpath/libc10.dylib $lib/lib/libc10.dylib $lib/lib/libtorch.dylib

    install_name_tool -change @rpath/libtorch.dylib $lib/lib/libtorch.dylib $lib/lib/libshm.dylib
    install_name_tool -change @rpath/libc10.dylib $lib/lib/libc10.dylib $lib/lib/libshm.dylib
  '';

  # See https://github.com/NixOS/nixpkgs/issues/296179
  #
  # This is a quick hack to add `libnvrtc` to the runpath so that torch can find
  # it when it is needed at runtime.
  extraRunpaths = lib.optionals cudaSupport [ "${lib.getLib cudaPackages.cuda_nvrtc}/lib" ];
  postPhases = lib.optionals stdenv.hostPlatform.isLinux [ "postPatchelfPhase" ];
  postPatchelfPhase = ''
    while IFS= read -r -d $'\0' elf ; do
      for extra in $extraRunpaths ; do
        echo patchelf "$elf" --add-rpath "$extra" >&2
        patchelf "$elf" --add-rpath "$extra"
      done
    done < <(
      find "''${!outputLib}" "$out" -type f -iname '*.so' -print0
    )
  '';

  # Builds in 2+h with 2 cores, and ~15m with a big-parallel builder.
  requiredSystemFeatures = [ "big-parallel" ];

  passthru = {
    inherit
      cudaSupport
      cudaPackages
      rocmSupport
      rocmPackages
      unroll-src
      ;
    cudaCapabilities = if cudaSupport then supportedCudaCapabilities else [ ];
    # At least for 1.10.2 `torch.fft` is unavailable unless BLAS provider is MKL. This attribute allows for easy detection of its availability.
    blasProvider = blas.provider;
    # To help debug when a package is broken due to CUDA support
    inherit brokenConditions;
    tests = callPackage ../tests { };
  };

  meta = {
    changelog = "https://github.com/pytorch/pytorch/releases/tag/v${version}";
    # keep PyTorch in the description so the package can be found under that name on search.nixos.org
    description = "PyTorch: Tensors and Dynamic neural networks in Python with strong GPU acceleration";
    homepage = "https://pytorch.org/";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [
      GaetanLepage
      teh
      thoughtpolice
      tscholak
    ]; # tscholak esp. for darwin-related builds
    platforms =
      lib.platforms.linux ++ lib.optionals (!cudaSupport && !rocmSupport) lib.platforms.darwin;
    broken = builtins.any trivial.id (builtins.attrValues brokenConditions);
  };
}
