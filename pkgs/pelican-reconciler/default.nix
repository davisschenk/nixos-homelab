{
  lib,
  python3,
  writeShellApplication,
}:

writeShellApplication {
  name = "pelican-reconcile";
  runtimeInputs = [ python3 ];
  text = ''
    exec python3 ${./reconciler.py} "$@"
  '';
  meta = {
    description = "Reconcile Nix-defined Pelican game servers";
    platforms = lib.platforms.linux;
    mainProgram = "pelican-reconcile";
  };
}
