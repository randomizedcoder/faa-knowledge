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
        # The quiz CLI, reused as a runtimeInput so scripts can just call `quiz`.
        quizPkg = self.packages.${system}.default;
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

        packages.pipeline = pkgs.writeShellApplication {
          name = "faa-pipeline";
          runtimeInputs = [ quizPkg ];
          text = ''
            exec quiz --pipeline "$@"
          '';
        };

        # Extract + verify against a single powerful GLM model (default
        # http://localhost:8000). Unlike the l2 pipeline this does one run with
        # no consensus merge, runs the model in reasoning mode, and verifies
        # each generated question with the same GLM. Extra args (e.g.
        # --chapters phak:04) are forwarded to the mine/generate stage.
        packages.extract-glm = pkgs.writeShellApplication {
          name = "faa-extract-glm";
          # pdftotext (poppler-utils) is used by the extract-text stage.
          runtimeInputs = [ quizPkg pkgs.curl pkgs.poppler-utils ];
          text = ''
            url="''${FAA_LLM_URL:-http://localhost:8000}"
            export FAA_LLM_URL="$url"
            export FAA_LLM_MODEL="''${FAA_LLM_MODEL:-/model}"
            export FAA_LLM_THINK="''${FAA_LLM_THINK:-1}"

            if ! curl -fsS -m 5 "$url/health" >/dev/null 2>&1 \
               && ! curl -fsS -m 5 "$url/v1/models" >/dev/null 2>&1; then
              echo "GLM endpoint $url is not reachable" >&2
              exit 1
            fi
            echo "Using GLM at $url (model $FAA_LLM_MODEL, think=$FAA_LLM_THINK)"

            echo "=== Stage 1: Extract text ==="; quiz --extract-text
            echo "=== Stage 2: Chunk text ==="; quiz --chunk-text
            echo "=== Stage 3+4: Mine + generate (run 1, no cross-check) ==="
            quiz --mine --generate --run-id 1 --small-llm-url "" "$@"
            echo "=== Stage 5: Promote run 1 -> database/questions ==="
            quiz --merge --runs 1
            echo "=== Stage 6: Verify generated questions with GLM ==="
            for f in database/questions/*.json; do
              echo "--- verify $f ---"
              quiz --validate --fix --file "$f"
            done
            echo "=== extract-glm complete ==="
          '';
        };

        # Whole-chapter generation (experiment "Method C"): one GLM call per
        # chapter feeds the entire chapter text and returns finished questions.
        # Writes straight to database/questions (no mining/merge). Iterates the
        # real chapters (skips spurious mis-detected ch>18). Extra args (e.g.
        # --gen-cap 25) are forwarded to each per-chapter call.
        packages.gen-chapters-glm = pkgs.writeShellApplication {
          name = "faa-gen-chapters-glm";
          runtimeInputs = [ quizPkg pkgs.curl ];
          text = ''
            url="''${FAA_LLM_URL:-http://localhost:8000}"
            export FAA_LLM_URL="$url"
            export FAA_LLM_MODEL="''${FAA_LLM_MODEL:-/model}"
            export FAA_LLM_THINK="''${FAA_LLM_THINK:-1}"
            textdir="''${FAA_TEXT_DIR:-pdfs_text}"

            if ! curl -fsS -m 5 "$url/health" >/dev/null 2>&1 \
               && ! curl -fsS -m 5 "$url/v1/models" >/dev/null 2>&1; then
              echo "GLM endpoint $url is not reachable" >&2
              exit 1
            fi
            echo "Whole-chapter generation via GLM at $url"

            failed=""
            for src in phak afh; do
              for f in "$textdir/$src"/ch*.txt; do
                [ -e "$f" ] || continue
                ch=$(basename "$f" .txt | sed 's/^ch0*//')
                # Skip spurious mis-detected chapters (PHAK real max 17, AFH 18).
                if [ "$ch" -gt 18 ]; then echo "skip $src ch$ch (spurious)"; continue; fi
                echo "=== $src ch$ch ==="
                if ! quiz --gen-chapter --source "$src" --chapter "$ch" \
                     --method direct --out-dir database/questions "$@"; then
                  echo "FAILED: $src ch$ch (continuing)"
                  failed="$failed $src-ch$ch"
                fi
              done
            done
            if [ -n "''${failed# }" ]; then echo "Chapters that failed:$failed"; fi
            echo "=== gen-chapters-glm complete ==="
          '';
        };

        # Verify-only pass: run the GLM validate/fix over existing questions.
        packages.verify-glm = pkgs.writeShellApplication {
          name = "faa-verify-glm";
          runtimeInputs = [ quizPkg ];
          text = ''
            export FAA_LLM_URL="''${FAA_LLM_URL:-http://localhost:8000}"
            export FAA_LLM_MODEL="''${FAA_LLM_MODEL:-/model}"
            export FAA_LLM_THINK="''${FAA_LLM_THINK:-1}"
            for f in database/questions/*.json; do
              echo "--- verify $f ---"
              quiz --validate --fix --file "$f"
            done
          '';
        };

        # Health probe for the GLM endpoint.
        packages.check-glm = pkgs.writeShellApplication {
          name = "faa-check-glm";
          runtimeInputs = [ pkgs.curl ];
          text = ''
            url="''${FAA_LLM_URL:-http://localhost:8000}"
            printf 'glm    %s ... ' "$url"
            if curl -fsS -m 5 "$url/health" >/dev/null 2>&1 \
               || curl -fsS -m 5 "$url/v1/models" >/dev/null 2>&1; then
              echo OK
            else
              echo FAIL; exit 1
            fi
          '';
        };

        # Health check for the two LLM endpoints the pipeline targets.
        # llama.cpp itself is managed by the NixOS configs on l/l2 — this
        # only probes /health so a multi-hour run isn't started blind.
        packages.check-llms = pkgs.writeShellApplication {
          name = "faa-check-llms";
          runtimeInputs = [ pkgs.curl ];
          text = ''
            large="''${FAA_LLM_URL:-http://l2:8095}"
            small="''${FAA_SMALL_LLM_URL:-http://l2:8096}"
            rc=0
            for pair in "large:$large" "small:$small"; do
              role="''${pair%%:*}"; url="''${pair#*:}"
              printf '%-6s %s ... ' "$role" "$url"
              if curl -fsS -m 5 "$url/health" >/dev/null; then echo OK; else echo FAIL; rc=1; fi
            done
            exit "$rc"
          '';
        };

        # Android emulator for the app. Heavy (pulls a ~1GB+ system image), and
        # needs KVM (/dev/kvm) to boot. Boots a fresh emulator you can
        # `flutter run` against. Run: nix run .#emulator
        packages.emulator =
          let
            pkgsAndroid = import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
                android_sdk.accept_license = true;
              };
            };
            emu = pkgsAndroid.androidenv.emulateApp {
              name = "faa-emulator";
              platformVersion = "34";
              abiVersion = "x86_64";
              systemImageType = "google_apis";
            };
          in
          # The bundled emulator's Qt has no `wayland` platform plugin, so on a
          # Wayland session its window can't open. FORCE `xcb` (X11/XWayland) —
          # we can't use QT_QPA_PLATFORM's own default because Wayland sessions
          # commonly export QT_QPA_PLATFORM=wayland, which would win. Override
          # with FAA_EMULATOR_QT_PLATFORM, e.g. for a headless boot (adb/flutter
          # still connect):  FAA_EMULATOR_QT_PLATFORM=offscreen nix run .#emulator
          pkgs.writeShellApplication {
            name = "faa-emulator";
            text = ''
              export QT_QPA_PLATFORM="''${FAA_EMULATOR_QT_PLATFORM:-xcb}"
              exec ${emu}/bin/run-test-emulator "$@"
            '';
          };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/quiz";
        };

        apps.emulator = {
          type = "app";
          program = "${self.packages.${system}.emulator}/bin/faa-emulator";
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

        apps.gen-chapters-glm = {
          type = "app";
          program = "${self.packages.${system}.gen-chapters-glm}/bin/faa-gen-chapters-glm";
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

        # Flutter + Android toolchain for the quiz app (app/). Web + Android
        # build here; iOS needs macOS + Xcode. Enter with: nix develop .#flutter
        devShells.flutter =
          let
            # Android SDK is unfree and needs its license accepted, so import a
            # separately-configured nixpkgs just for it.
            pkgsAndroid = import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
                android_sdk.accept_license = true;
              };
            };
            androidComposition = pkgsAndroid.androidenv.composeAndroidPackages {
              platformVersions = [ "36" ]; # Flutter 3.41 compileSdk/targetSdk = 36
              buildToolsVersions = [ "35.0.0" ];
              includeEmulator = false;
              includeNDK = true; # Flutter's Gradle plugin forces NDK resolution
              ndkVersions = [ "28.2.13676358" ]; # matches app/android/app/build.gradle.kts
              cmakeVersions = [ "3.22.1" ]; # NDK presence triggers a CMake config step
            };
            androidSdk = androidComposition.androidsdk;
            sdkRoot = "${androidSdk}/libexec/android-sdk";
          in
          pkgs.mkShell {
            buildInputs = [
              pkgs.flutter
              pkgs.jdk17
              pkgs.android-tools
              pkgs.chromium
              androidSdk
            ];
            ANDROID_SDK_ROOT = sdkRoot;
            ANDROID_HOME = sdkRoot;
            ANDROID_NDK_ROOT = "${sdkRoot}/ndk/28.2.13676358";
            JAVA_HOME = "${pkgs.jdk17}";
            CHROME_EXECUTABLE = "${pkgs.chromium}/bin/chromium";
            GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/35.0.0/aapt2";
            shellHook = ''
              export PATH="$PATH:${sdkRoot}/platform-tools"
            '';
          };
      }
    );
}
