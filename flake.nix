{
  description = "GPU driver fuzzing research environment (DRM/KMS, syzkaller)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Kernel build toolchain
            gnumake
            gcc
            bc
            flex
            bison
            openssl
            elfutils      # provides libelf
            perl
            python3
            ncurses
            debootstrap

            # Kernel config helper depends on these
            pkg-config

            # VM + rootfs
            qemu
            debootstrap

            # Fuzzing
            go              # syzkaller is written in Go
            git
          ];

          shellHook = ''
            echo "GPU fuzzing dev shell ready."
            echo "Kernel toolchain, QEMU, and Go (for syzkaller) available."
          '';
        };
      });
}
