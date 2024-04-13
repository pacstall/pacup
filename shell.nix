{ pkgs
  ? import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-23.11")
  { config = {}; overlays = []; }
}:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    dpkg
    gitMinimal
    perl
  ] ++ (with pkgs.perl538Packages; [
    DataCompare
    Filechdir
    IPCSystemSimple
    JSON
    ListMoreUtils
    TestLWPUserAgent
  ]);

  LC_ALL = "C";
  shellHook = ''
    export PATH="${./bin}:$PATH"
    export PERL5LIB="${./lib}:$PERL5LIB"
  '';
}
