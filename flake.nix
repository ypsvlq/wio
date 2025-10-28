{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    zig-overlay = {
      url = "github:bandithedoge/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        pkgs,
        system,
        ...
      }: let
        zig' = inputs.zig-overlay.packages.${system}.mach-latest;

        commonLibs = with pkgs; [
          libGL
          libdecor
          libxkbcommon
          pulseaudio
          systemdLibs
          vulkan-loader
          wayland
          xorg.libX11
          xorg.libXcursor
        ];
      in {
        devShells = {
          default = pkgs.mkShell {
            packages = [
              zig'
              zig'.zls
            ];

            env.LD_LIBRARY_PATH = with pkgs.lib.systems;
              pkgs.lib.optionalString
              (inspect.matchAnyAttrs
                (with inspect.patterns; [isLinux isBSD])
                (parse.mkSystemFromString system))
              (pkgs.lib.makeLibraryPath commonLibs);
          };
        };
      };
    };
}
