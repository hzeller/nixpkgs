{
  lib,
  stdenv,
  fetchFromGitHub,

  # Native build inputs
  docbook-xsl-nons,
  gobject-introspection,
  gtk-doc,
  meson,
  ninja,
  pkg-config,
  buildPackages,

  # Build inputs
  expat,
  glib,
  libxml2,
  python3,

  # Optional dependencies
  cfitsio,
  cgif,
  fftw,
  imagemagick,
  lcms2,
  libarchive,
  libexif,
  libheif,
  libhwy,
  libimagequant,
  libjpeg,
  libjxl,
  librsvg,
  libpng,
  libtiff,
  libwebp,
  matio,
  openexr,
  openjpeg,
  openslide,
  pango,
  poppler,
  withIntrospection ?
    lib.meta.availableOn stdenv.hostPlatform gobject-introspection
    && stdenv.hostPlatform.emulatorAvailable buildPackages,

  # passthru
  testers,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "vips";
  version = "8.16.1";

  outputs = [
    "bin"
    "out"
    "man"
    "dev"
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isDarwin && !stdenv.hostPlatform.isFreeBSD) [ "devdoc" ];

  src = fetchFromGitHub {
    owner = "libvips";
    repo = "libvips";
    tag = "v${finalAttrs.version}";
    hash = "sha256-F2ymfvqwuCtNtFIOLgXvqRWATSMaeV7EQKYyQalCNfc=";
    # Remove unicode file names which leads to different checksums on HFS+
    # vs. other filesystems because of unicode normalisation.
    postFetch = ''
      rm -r $out/test/test-suite/images/
    '';
  };

  nativeBuildInputs = [
    docbook-xsl-nons
    gobject-introspection
    meson
    ninja
    pkg-config
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isDarwin && !stdenv.hostPlatform.isFreeBSD) [
    gtk-doc
  ];

  buildInputs = [
    glib
    libxml2
    expat
    (python3.withPackages (p: [ p.pycairo ]))

    # Optional dependencies
    cfitsio
    cgif
    fftw
    imagemagick
    lcms2
    libarchive
    libexif
    libheif
    libhwy
    libimagequant
    libjpeg
    libjxl
    librsvg
    libpng
    libtiff
    libwebp
    matio
    openexr
    openjpeg
    openslide
    pango
    poppler
  ];

  # Required by .pc file
  propagatedBuildInputs = [
    glib
  ];

  mesonFlags = [
    (lib.mesonEnable "pdfium" false)
    (lib.mesonEnable "nifti" false)
    (lib.mesonEnable "spng" false) # we want to use libpng
    (lib.mesonEnable "introspection" withIntrospection)
  ]
  ++ lib.optional (!stdenv.hostPlatform.isDarwin && !stdenv.hostPlatform.isFreeBSD) (
    lib.mesonBool "gtk_doc" true
  )
  ++ lib.optional (imagemagick == null) (lib.mesonEnable "magick" false);

  passthru = {
    tests = {
      pkg-config = testers.hasPkgConfigModules {
        package = finalAttrs.finalPackage;
      };
      version = testers.testVersion {
        package = finalAttrs.finalPackage;
        command = "vips --version";
      };
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--version-regex"
        "v([0-9.]+)"
      ];
    };
  };

  meta = with lib; {
    changelog = "https://github.com/libvips/libvips/blob/${finalAttrs.src.rev}/ChangeLog";
    homepage = "https://www.libvips.org/";
    description = "Image processing system for large images";
    license = licenses.lgpl2Plus;
    maintainers = with maintainers; [
      kovirobi
      anthonyroussel
    ];
    pkgConfigModules = [
      "vips"
      "vips-cpp"
    ];
    platforms = platforms.unix;
    mainProgram = "vips";
  };
})
