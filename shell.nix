{
  pkgs ?
    import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-24.05")
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
    export PATH="$PWD:$PWD/scripts:$PATH"
  '';
}
