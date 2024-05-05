{
  pkgs ?
    import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-23.11")
    {
      config = {};
      overlays = [];
    },
}:
pkgs.mkShellNoCC {
  packages = with pkgs;
    [
      dpkg
      gitMinimal
      perl
      vim
    ]
    ++ (
      with perl538Packages; [
        DataCompare
        Filechdir
        IPCSystemSimple
        JSON
        ListMoreUtils
        LWPProtocolHttps
        PerlTidy
        TermProgressBar
        TestLWPUserAgent
      ]
    );

  LC_ALL = "C";
  shellHook = ''
    export PATH="$PWD:$PATH"
  '';
}
