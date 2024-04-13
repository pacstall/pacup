{ pkgs
  ? import <nixpkgs> { config = {}; overlays = []; }
}:

pkgs.mkShellNoCC {
  packages = with pkgs; [ perl ]
  ++ (with pkgs.perl538Packages; [
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
