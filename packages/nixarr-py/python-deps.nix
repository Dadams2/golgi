{
  fetchFromGitHub,
  fetchPypi,
  python3Packages,
}:

let
  inherit (python3Packages)
    buildPythonPackage
    pydantic
    python-dateutil
    setuptools
    typing-extensions
    urllib3;

  lazy-imports = buildPythonPackage rec {
    pname = "lazy-imports";
    version = "1.1.0";
    pyproject = true;

    src = fetchPypi {
      pname = "lazy_imports";
      inherit version;
      hash = "sha256-5upaHk8JqGE1fmcLeqYe/Lzm/ik2F4XdJT32b43bw2s=";
    };

    build-system = [ setuptools ];
  };

  openapi-deps = [
    pydantic
    python-dateutil
    typing-extensions
    urllib3
    lazy-imports
  ];
in [
  (buildPythonPackage rec {
    pname = "prowlarr";
    version = "1.1.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-PiK4ZrORMV907wX9dPeO2tE97NSu6sCPfH7aUFkyRZk=";
    };

    build-system = [ setuptools ];
    dependencies = openapi-deps;
  })
  (buildPythonPackage rec {
    pname = "radarr";
    version = "1.2.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-suN16BYf/6gm8G/xA5S6wdYerTUq8Dy2yflWYIKLLBQ=";
    };

    build-system = [ setuptools ];
    dependencies = openapi-deps;
  })
  (buildPythonPackage rec {
    pname = "sonarr";
    version = "1.1.1";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "devopsarr";
      repo = "sonarr-py";
      rev = "v${version}";
      hash = "sha256-cqhdsos328jtUYw2HWaoQ95EPTnu3RYPWiyT5FqfTXk=";
    };

    build-system = [ setuptools ];
    dependencies = openapi-deps;
  })
]