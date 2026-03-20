{
  description = "FAA Knowledge Quiz Tool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildGoModule {
          pname = "faa-quiz";
          version = "0.1.0";
          src = ./.;
          vendorHash = null;
          subPackages = [ "cmd/quiz" ];

          meta = {
            description = "FAA Private Pilot knowledge quiz CLI";
            mainProgram = "quiz";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            sqlite
            curl
            gopls
            gotools
          ];
        };
      }
    );
}
