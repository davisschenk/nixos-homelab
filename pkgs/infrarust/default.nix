{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "infrarust";
  version = "2.0.0-beta.1";

  src = fetchurl {
    url = "https://github.com/Shadowner/Infrarust/releases/download/v2.0.0-beta.1/infrarust-linux-x86_64.tar.gz";
    hash = "sha256-tF/Zd5o0OP3PHqsQ7cuXo9tlZRbYIeyke0wVVF4mpSo=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 infrarust $out/bin/infrarust
    runHook postInstall
  '';

  meta = {
    description = "High-performance Minecraft reverse proxy";
    homepage = "https://github.com/Shadowner/Infrarust";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "infrarust";
  };
}
