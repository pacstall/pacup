let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-23.11";
  pkgs = import nixpkgs { config = {}; overlays = []; };
in

pkgs.mkShellNoCC {
  packages = with pkgs; [
    perl
    perlPackages.DataCompare
    perl538Packages.JSON
    perl538Packages.Filechdir
    perl538Packages.IPCSystemSimple
    perl538Packages.TestLWPUserAgent
  ];

  LC_ALL="C";

  shellHook = ''
    export PERL5LIB="$PERL5LIB:$PWD/lib"
  '';
}
