{ pkgs }:
let
  archive = pkgs.fetchurl {
    url = "https://download.db-ip.com/free/dbip-city-lite-2026-08.mmdb.gz";
    hash = "sha256-K1MgPsNql1BRqBidwSB9Yk47wwL77kdkiShHZTO+adE=";
  };
in
pkgs.runCommand "dbip-city-lite-2026-08.mmdb" { nativeBuildInputs = [ pkgs.gzip ]; } ''
  gzip -dc ${archive} > "$out"
''
