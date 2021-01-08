{ lib, stdenv, symlinkJoin, zlib }:

with builtins;

let rpath = "${zlib}/lib:$out/lib";
in mapAttrs (target:
  mapAttrs (profile:
    { date, components }:
    let
      toolchain = mapAttrs (component: source:
        stdenv.mkDerivation {
          pname = "${component}-nightly";
          version = source.date or date;
          src = fetchurl { inherit (source) url sha256; };
          installPhase = ''
            patchShebangs install.sh
            CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

            for file in $(find $out/bin -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter "$(< ${stdenv.cc}/nix-support/dynamic-linker)" \
                  --set-rpath ${rpath} \
                  "$file"
              fi
            done

            for file in $(find $out/lib -type f); do
              if isELF "$file"; then
                patchelf --set-rpath ${rpath} "$file"
              fi
            done

            ${lib.optionalString (component == "rustc")
            "ln -sT {${toolchain.rust-std},$out}/lib/rustlib/${target}/lib"}

            ${lib.optionalString (component == "clippy-preview") ''
              patchelf \
                --set-rpath ${toolchain.rustc}/lib:${rpath} \
                $out/bin/clippy-driver
            ''}
          '';
        }) components;
      combine = import ./combine.nix symlinkJoin;
    in toolchain // {
      toolchain =
        combine "rust-nightly-${profile}-${date}" (attrValues toolchain);
      withComponents = componentNames:
        combine "rust-nightly-${profile}-with-components-${date}"
        (lib.attrVals componentNames toolchain);
    })) (fromJSON (readFile ./toolchains.json))
