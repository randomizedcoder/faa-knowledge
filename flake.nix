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

        # One Android SDK shared by the Flutter dev shell and the emulator
        # package, so both use the *same* adb (mismatched adb client/server
        # versions silently drop the emulator). The SDK is unfree and needs its
        # license accepted, so import a separately-configured nixpkgs for it.
        pkgsAndroid = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
        androidComposition = pkgsAndroid.androidenv.composeAndroidPackages {
          platformVersions = [ "36" "34" ]; # 36 builds the app; 34 is the emulator system image
          buildToolsVersions = [ "35.0.0" ];
          includeEmulator = true; # emulator lives in the SDK now (was a separate emulateApp)
          includeSystemImages = true;
          systemImageTypes = [ "google_apis" ];
          abiVersions = [ "x86_64" ];
          includeNDK = true; # Flutter's Gradle plugin forces NDK resolution
          ndkVersions = [ "28.2.13676358" ]; # matches app/android/app/build.gradle.kts
          cmakeVersions = [ "3.22.1" ]; # NDK presence triggers a CMake config step
        };
        androidSdk = androidComposition.androidsdk;
        sdkRoot = "${androidSdk}/libexec/android-sdk";

        # Runtime inputs + env for launching Flutter with the Android SDK,
        # mirroring devShells.flutter so the `run-*` apps work as one-shots
        # (`nix run` runs outside the dev shell, so they set the env themselves).
        flutterRunInputs = [ pkgs.flutter pkgs.jdk17 pkgs.chromium androidSdk pkgs.coreutils pkgs.gnugrep ];
        flutterEnv = ''
          export ANDROID_SDK_ROOT="${sdkRoot}"
          export ANDROID_HOME="${sdkRoot}"
          export ANDROID_NDK_ROOT="${sdkRoot}/ndk/28.2.13676358"
          export JAVA_HOME="${pkgs.jdk17}"
          export CHROME_EXECUTABLE="${pkgs.chromium}/bin/chromium"
          export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/35.0.0/aapt2"
          export PATH="${sdkRoot}/emulator:${sdkRoot}/platform-tools:${sdkRoot}/cmdline-tools/19.0/bin:$PATH"
        '';

        # Persistent-AVD emulator launcher, shared by packages.emulator and the
        # run-android one-shot. Boots the "faa" AVD (creating it if missing) on
        # the shared SDK, so it uses the same adb as the flutter env.
        faaEmulator = pkgs.writeShellApplication {
          name = "faa-emulator";
          runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];
          text = ''
            export ANDROID_SDK_ROOT="${sdkRoot}"
            export ANDROID_HOME="${sdkRoot}"
            export JAVA_HOME="${pkgs.jdk17}"
            export PATH="${sdkRoot}/emulator:${sdkRoot}/platform-tools:${sdkRoot}/cmdline-tools/19.0/bin:$PATH"

            # The bundled emulator's Qt has no `wayland` plugin, and Wayland
            # sessions preset QT_QPA_PLATFORM=wayland — which is fatal here. Force
            # `xcb` (X11/XWayland) unless the caller asked for something else
            # (e.g. `offscreen` for headless); only override unset/`wayland`.
            case "''${QT_QPA_PLATFORM:-}" in
              "" | wayland) QT_QPA_PLATFORM=xcb ;;
            esac
            export QT_QPA_PLATFORM

            name="''${AVD_NAME:-faa}"
            # Device profile (screen size/density). Default is a phone; override
            # to test other form factors, e.g. a tablet:
            #   AVD_NAME=faa-tablet AVD_DEVICE=pixel_tablet nix run .#emulator
            device="''${AVD_DEVICE:-pixel}"
            # Create the persistent AVD once; it lives in the writable
            # $HOME/.android/avd (the /nix/store SDK stays read-only).
            if ! avdmanager list avd -c | grep -qx "$name"; then
              echo "Creating AVD $name (device: $device) ..."
              echo no | avdmanager create avd -n "$name" \
                -k "system-images;android-34;google_apis;x86_64" -d "$device" --force
            fi

            # Headless: `QT_QPA_PLATFORM=offscreen` only hides the Qt UI — the
            # emulator still tries to create a host window (X_CreateWindow ->
            # BadWindow -> hang) unless we also pass `-no-window`. Add it
            # automatically so headless boots (adb/flutter still connect).
            windowflag=()
            if [ "$QT_QPA_PLATFORM" = "offscreen" ]; then windowflag=(-no-window); fi

            # Software GL (swiftshader) for reliability: flutter doctor reports
            # eglinfo unavailable here, so host-GPU passthrough isn't guaranteed.
            # Override by passing e.g. `-gpu host` as an extra arg.
            exec emulator -avd "$name" -gpu swiftshader_indirect \
              -no-boot-anim -no-snapshot "''${windowflag[@]}" "$@"
          '';
        };
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

        # Android emulator for the app. Heavy (the ~1GB system image is part of
        # the shared SDK closure) and needs KVM (/dev/kvm) to boot. Boots a
        # persistent AVD ("faa") you can `flutter run` against; it uses the same
        # SDK (and thus the same adb) as `nix develop .#flutter`, so the two
        # never fight over the adb server on port 5037. Override the window
        # backend with QT_QPA_PLATFORM (xcb window by default; offscreen for
        # headless). Run: nix run .#emulator
        packages.emulator = faaEmulator;

        # One-shot: launch the app in Chrome (hot reload). Runs the whole thing
        # in one command from the repo root: nix run .#run-web
        packages.run-web = pkgs.writeShellApplication {
          name = "faa-run-web";
          runtimeInputs = flutterRunInputs;
          text = ''
            ${flutterEnv}
            cd app 2>/dev/null || { echo "run from the repo root (needs ./app)" >&2; exit 1; }
            exec flutter run -d chrome "$@"
          '';
        };

        # One-shot: boot the emulator (creating/reusing the "faa" AVD), wait for
        # Android to finish booting, then launch the app on it (hot reload).
        # One command from the repo root: nix run .#run-android
        # (QT_QPA_PLATFORM=offscreen nix run .#run-android boots it headless.)
        packages.run-android = pkgs.writeShellApplication {
          name = "faa-run-android";
          runtimeInputs = flutterRunInputs;
          text = ''
            ${flutterEnv}
            # Force xcb unless the caller wants a specific backend: Wayland
            # sessions preset QT_QPA_PLATFORM=wayland, which the emulator's Qt
            # can't use (see packages.emulator). Only override unset/`wayland`.
            case "''${QT_QPA_PLATFORM:-}" in
              "" | wayland) QT_QPA_PLATFORM=xcb ;;
            esac
            export QT_QPA_PLATFORM

            if adb devices | grep -qE 'emulator-[0-9]+[[:space:]]+device'; then
              echo "Reusing the running emulator."
            else
              echo "Booting emulator (log: /tmp/faa-emulator.log) ..."
              ${faaEmulator}/bin/faa-emulator >/tmp/faa-emulator.log 2>&1 &
              adb wait-for-device
              echo "Waiting for Android to finish booting ..."
              until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
                sleep 2
              done
              echo "Boot complete."
            fi

            # Target whichever emulator is attached — the console port isn't
            # always 5554 (a busy port bumps it to 5556, 5558, ...).
            dev=$(adb devices | awk '$1 ~ /^emulator-[0-9]+$/ && $2 == "device" { print $1; exit }')
            if [ -z "$dev" ]; then echo "no running emulator found" >&2; exit 1; fi
            echo "Running the app on $dev ..."

            # The app follows the device theme; default the emulator to dark so
            # you see the dark high-contrast palette. Override: EMULATOR_THEME=light.
            case "''${EMULATOR_THEME:-dark}" in
              light) adb -s "$dev" shell cmd uimode night no  >/dev/null 2>&1 || true ;;
              *)     adb -s "$dev" shell cmd uimode night yes >/dev/null 2>&1 || true ;;
            esac

            cd app 2>/dev/null || { echo "run from the repo root (needs ./app)" >&2; exit 1; }
            exec flutter run -d "$dev" "$@"
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

        apps.run-web = {
          type = "app";
          program = "${self.packages.${system}.run-web}/bin/faa-run-web";
        };

        apps.run-android = {
          type = "app";
          program = "${self.packages.${system}.run-android}/bin/faa-run-android";
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
          pkgs.mkShell {
            # No pkgs.android-tools here: it ships adb 35, which clashes with the
            # SDK's adb 36 that the emulator uses. Use the SDK's own adb (below).
            buildInputs = [
              pkgs.flutter
              pkgs.jdk17
              pkgs.chromium
              androidSdk
            ];
            ANDROID_SDK_ROOT = sdkRoot;
            ANDROID_HOME = sdkRoot;
            ANDROID_NDK_ROOT = "${sdkRoot}/ndk/28.2.13676358";
            JAVA_HOME = "${pkgs.jdk17}";
            CHROME_EXECUTABLE = "${pkgs.chromium}/bin/chromium";
            GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${sdkRoot}/build-tools/35.0.0/aapt2";
            # Prepend the SDK's own tool dirs so its adb (36), emulator, and
            # avdmanager win over anything else on PATH.
            shellHook = ''
              export PATH="${sdkRoot}/emulator:${sdkRoot}/platform-tools:${sdkRoot}/cmdline-tools/19.0/bin:$PATH"
            '';
          };
      }
    );
}
