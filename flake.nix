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

        packages.pipeline = pkgs.writeShellScriptBin "faa-pipeline" ''
          exec ${self.packages.${system}.default}/bin/quiz --pipeline "$@"
        '';

        # Extract + verify against a single powerful GLM model (default
        # http://localhost:8000). Unlike the l2 pipeline this does one run with
        # no consensus merge, runs the model in reasoning mode, and verifies
        # each generated question with the same GLM. Extra args (e.g.
        # --chapters phak:04) are forwarded to the mine/generate stage.
        packages.extract-glm = pkgs.writeShellScriptBin "faa-extract-glm" ''
          set -euo pipefail
          quiz=${self.packages.${system}.default}/bin/quiz
          url="''${FAA_LLM_URL:-http://localhost:8000}"
          export FAA_LLM_URL="$url"
          export FAA_LLM_MODEL="''${FAA_LLM_MODEL:-/model}"
          export FAA_LLM_THINK="''${FAA_LLM_THINK:-1}"

          if ! ${pkgs.curl}/bin/curl -fsS -m 5 "$url/health" >/dev/null 2>&1 \
             && ! ${pkgs.curl}/bin/curl -fsS -m 5 "$url/v1/models" >/dev/null 2>&1; then
            echo "GLM endpoint $url is not reachable" >&2
            exit 1
          fi
          echo "Using GLM at $url (model $FAA_LLM_MODEL, think=$FAA_LLM_THINK)"

          echo "=== Stage 1: Extract text ==="; "$quiz" --extract-text
          echo "=== Stage 2: Chunk text ==="; "$quiz" --chunk-text
          echo "=== Stage 3+4: Mine + generate (run 1, no cross-check) ==="
          "$quiz" --mine --generate --run-id 1 --small-llm-url "" "$@"
          echo "=== Stage 5: Promote run 1 -> database/questions ==="
          "$quiz" --merge --runs 1
          echo "=== Stage 6: Verify generated questions with GLM ==="
          for f in database/questions/*.json; do
            echo "--- verify $f ---"
            "$quiz" --validate --fix --file "$f"
          done
          echo "=== extract-glm complete ==="
        '';

        # Verify-only pass: run the GLM validate/fix over existing questions.
        packages.verify-glm = pkgs.writeShellScriptBin "faa-verify-glm" ''
          set -euo pipefail
          quiz=${self.packages.${system}.default}/bin/quiz
          url="''${FAA_LLM_URL:-http://localhost:8000}"
          export FAA_LLM_URL="$url"
          export FAA_LLM_MODEL="''${FAA_LLM_MODEL:-/model}"
          export FAA_LLM_THINK="''${FAA_LLM_THINK:-1}"
          for f in database/questions/*.json; do
            echo "--- verify $f ---"
            "$quiz" --validate --fix --file "$f"
          done
        '';

        # Health probe for the GLM endpoint.
        packages.check-glm = pkgs.writeShellScriptBin "faa-check-glm" ''
          url="''${FAA_LLM_URL:-http://localhost:8000}"
          printf 'glm    %s ... ' "$url"
          if ${pkgs.curl}/bin/curl -fsS -m 5 "$url/health" >/dev/null 2>&1 \
             || ${pkgs.curl}/bin/curl -fsS -m 5 "$url/v1/models" >/dev/null 2>&1; then
            echo OK; exit 0
          else
            echo FAIL; exit 1
          fi
        '';

        # Health check for the two LLM endpoints the pipeline targets.
        # llama.cpp itself is managed by the NixOS configs on l/l2 — this
        # only probes /health so a multi-hour run isn't started blind.
        packages.check-llms = pkgs.writeShellScriptBin "faa-check-llms" ''
          large="''${FAA_LLM_URL:-http://l2:8095}"
          small="''${FAA_SMALL_LLM_URL:-http://l2:8096}"
          rc=0
          for pair in "large:$large" "small:$small"; do
            role="''${pair%%:*}"; url="''${pair#*:}"
            printf '%-6s %s ... ' "$role" "$url"
            if ${pkgs.curl}/bin/curl -fsS -m 5 "$url/health" >/dev/null; then echo OK; else echo FAIL; rc=1; fi
          done
          exit $rc
        '';

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/quiz";
        };

        apps.pipeline = {
          type = "app";
          program = "${self.packages.${system}.pipeline}/bin/faa-pipeline";
        };

        apps.check-llms = {
          type = "app";
          program = "${self.packages.${system}.check-llms}/bin/faa-check-llms";
        };

        apps.extract-glm = {
          type = "app";
          program = "${self.packages.${system}.extract-glm}/bin/faa-extract-glm";
        };

        apps.verify-glm = {
          type = "app";
          program = "${self.packages.${system}.verify-glm}/bin/faa-verify-glm";
        };

        apps.check-glm = {
          type = "app";
          program = "${self.packages.${system}.check-glm}/bin/faa-check-glm";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            sqlite
            curl
            gopls
            gotools
            poppler-utils
          ];
        };
      }
    );
}
