# Building HelixSR for PS5

Build on Linux or WSL. The [GitHub Actions showcase ZIP](#showcase-with-public-inputs)
can run in bilinear mode. To enable HelixSR, generate the network on your
machine using your own NVIDIA DLSS DLL. Generated network files stay under the
ignored `build/` tree.

## In short

1. Get `nvngx_dlss.dll` **version 310.7.0** (SHA-256 `be6e434a…`). NVIDIA
   publishes it at [github.com/NVIDIA/DLSS](https://github.com/NVIDIA/DLSS)
   (tag `v310.7.0`, `lib/Windows_x86_64/rel/nvngx_dlss.dll`) under
   [its license](https://github.com/NVIDIA/DLSS/blob/v310.7.0/LICENSE.txt);
   many games ship the same file. Another version will not do: the build
   checks the file.
2. Install the packages of [Requirements](#requirements).
3. Run:

   ```sh
   git clone --recurse-submodules --shallow-submodules https://github.com/BlackBearRedux/ps5-helixsr.git
   cd ps5-helixsr
   make inputs                                   # pinned public inputs: app template, payload SDK, DXC, HelixSR release
   eval "$(python3 tools/fetch_build_inputs.py --env)"
   make driver                                   # the Vulkan driver's SDK with the HelixSR profile
   make model DLSS_DLL=/path/to/nvngx_dlss.dll   # HelixSR's own setup: weights and kernel sources
   make shaders                                  # the network's kernels and this project's own shaders
   make network-files                            # build/network-files/model.bin and kernels.bin
   make showcase SHOWCASE_ARGS="--model build/network-files/model.bin --kernels build/network-files/kernels.bin"
   ```

4. Upload `build/showcase/PPSA99013` to `/data/homebrew/` on a PS5 running a
   homebrew loader with ShadowMountPlus, and start **PS5 HelixSR Showcase**
   ([the app](examples/helixsr_showcase/README.md)).

The folder you built holds NVIDIA's network. It is for your own console: do
not upload it, attach it or pass it on.

## Requirements

- Ubuntu 26.04 provides the `glslangValidator` and SPIRV-Tools versions used in CI.
  Install Python 3.11+ with NumPy and Pillow, CMake, a C and C++17 compiler, `make`,
  `glslangValidator` and SPIRV-Tools (`spirv-opt`, `spirv-val`), DejaVu Sans
  (`fonts-dejavu-core`) for the showcase; Mako and PyYAML for the driver's
  shader compiler. The PS5 build uses Clang and LLD 18 and 21. The boilerplate
  uses Ninja and ccache. The workflow's install step lists the Ubuntu packages.
- `make inputs` fetches the pinned public inputs of `tools/build_inputs.json`
  into `build/inputs`: [PS5 Native App Boilerplate 1.000.000](https://github.com/BlackBearRedux/ps5-native-app-boilerplate/releases/tag/1.000.000)
  with its payload SDK, Microsoft's
  DXC and the HelixSR 1.2.0 release. Then
  `eval "$(python3 tools/fetch_build_inputs.py --env)"` points the PS5 builds
  at them (`PS5_PAYLOAD_SDK`, `PS5_NATIVE_APP_TEMPLATE`, `PS5VK_LAB_ROOT`).
- NVIDIA's `nvngx_dlss.dll`, version 310.7.0 (SHA-256 `be6e434a…`): the one
  HelixSR 1.2.0 is made for. NVIDIA publishes it at
  [github.com/NVIDIA/DLSS](https://github.com/NVIDIA/DLSS) under
  [its license](https://github.com/NVIDIA/DLSS/blob/v310.7.0/LICENSE.txt).
- For running the network on the host: a Vulkan driver with 32-lane subgroups
  and FP16 ([below](#running-on-the-host)).

## Build

The targets, in order (the first six are the steps above):

| Target | What it does |
| --- | --- |
| `make inputs` | pinned public inputs into `build/inputs` |
| `make driver` | driver dependencies, the PSBC shader compiler (PS5 and host), the driver SDK with the HelixSR profile |
| `make model DLSS_DLL=...` | HelixSR's setup: the weights and the kernels' PTX |
| `make shaders` | the runtime's SPIR-V, each module compiled with the PS5 compiler as a check |
| `make compact-shaders` | the public-source shaders needed to build the showcase |
| `make network-files` | `model.bin` and `kernels.bin`, the two files the app reads |
| `make showcase` | the app, PPSA99013; it builds without the network and takes the two files as options |
| `make host` | the runtime, the frame runners and the tests for desktop Vulkan |
| `make check` | host tests |

`make model` copies the HelixSR release to `build/helixsr-setup` and runs its
own `setup/helixsr_setup.py` there. That script reads the weights and the CUDA
kernels (PTX) out of the DLL and writes `helixsr_weights.bin`; its working
directory, `build/helixsr-setup-work`, keeps the PTX. Without `DLSS_DLL` the
setup downloads the DLL from NVIDIA's GitHub; that needs
`ACCEPT_NVIDIA_DLSS_LICENSE=1`, which is your acceptance of NVIDIA's license.

`make shaders` produces the two shader sets the runtime embeds:

- `tools/build_generated.py` runs HelixSR's PTX-to-HLSL translator on the
  kernels of the main network, adapts the HLSL to Vulkan (bindings, typed
  images, 16-bit stores), compiles it with DXC and checks every module with
  `spirv-val` and the PS5 shader compiler (`build/compile_probe`);
- `tools/build_compact_resident.py` compiles the four early convolution stages
  that `tools/conv_kernels.py` generates as GLSL, and the E5M3 encoder.

The identities of both sets are pinned in `validation/generated-main.json` and
`validation/compact-resident.json`; the runtime's asset table
(`tools/build_runtime_assets.py`) refuses modules that do not match. After a
deliberate change, copy the new `manifest.json` of each output folder over its
pin.

`make` fetches the driver when `external/ps5-vulkan` is missing: the pinned
submodule in a git checkout, otherwise a clone of `DRIVER_URL` at that
revision. `make driver-sdk` stages the driver SDK with the profile HelixSR
needs, `PS5VK_HELIXSR_DIAGNOSTIC` and `PS5VK_EXTENDED_COMPUTE_DIAGNOSTIC`: 16-bit
integers, the three subgroup operations the generated kernels use, RG16F and
R16F storage images, and sampled inputs that are written again every frame.
The driver's own `make check` restages its SDK without this profile; run
`make driver-sdk` again after it.

`make check-offline` builds and runs only what needs neither Vulkan nor the
model: the planner, the numerics, the contracts and the showcase's tables.
`make check-shaders` compiles the early convolutions and the showcase shaders.
GitHub Actions runs both checks and builds the native showcase on pushes to
`main`, pull requests, manually, and nightly at 05:53 UTC. Builds on `main`
save the pinned Vulkan SDK and compact shaders in a cache keyed by the driver,
toolchain, and shader inputs. The nightly build keeps the shared cache in use.
A cache hit also skips the DXC download.

## Showcase with public inputs

From a fresh clone, run:

```sh
python3 tools/fetch_build_inputs.py --only app_template --only dxc
eval "$(python3 tools/fetch_build_inputs.py --env)"
make driver compact-shaders showcase
python3 "$PS5_NATIVE_APP_TEMPLATE/tools/package-app.py" \
  build/showcase/PPSA99013 build/showcase/PPSA99013.zip
```

CI uses the same commands and checks the packaged file list. The downloadable
ZIP and SHA-256 checksum are Actions artifacts from push, pull request, and
manual runs. Public push and manual builds attest the ZIP. Verify it with
`gh attestation verify PPSA99013.zip -R BlackBearRedux/ps5-helixsr`.
With these inputs the app presents its bilinear comparison. The full build at
the top of this guide also produces the two local files that enable HelixSR.

## Running on the host

The generated kernels are CUDA kernels in HLSL clothing: a block is a number of
32-thread warps, and threads exchange values within their warp. They need a
Vulkan driver whose subgroups are 32 lanes, with FP16 and 16-bit storage. Mesa's
lavapipe runs 8 lanes by default and stops at 16.
`patches/mesa-26.2.1-lavapipe-32-lanes.patch` raises that to 32:

```sh
# in a Mesa 26.2.1 source tree
patch -p1 < /path/to/ps5-helixsr/patches/mesa-26.2.1-lavapipe-32-lanes.patch
meson setup build -Dvulkan-drivers=swrast -Dgallium-drivers=llvmpipe -Dbuildtype=release
ninja -C build
# an ICD file that names build/src/gallium/targets/lavapipe/libvulkan_lvp.so by its full path
export VK_DRIVER_FILES=/path/to/lvp32_icd.json LP_NATIVE_VECTOR_WIDTH=1024
export MESA_SHADER_CACHE_DIR=/path/to/a/cache/of/its/own
```

Give that driver its own shader cache folder: with the default one, shared with
other lane widths, results were wrong. `tools/host_driver_check.cpp` with
`tools/host_driver_check.comp` proves the patched driver against the stock one:
it runs sampling, fetches, FP16 arithmetic and image stores on both and
compares the bytes. Pass `VULKAN_ICD=/path/to/lvp32_icd.json` to `make host` so
that the tests run on it. The first use of each kernel takes minutes while
lavapipe compiles it; later runs take seconds.

## PS5 titles

Both are built against the staged driver SDK and need `PS5_PAYLOAD_SDK` and
`PS5_NATIVE_APP_TEMPLATE`:

- the [showcase app](examples/helixsr_showcase/README.md)
  (`tools/build_showcase.py`, `make showcase`), packaged as PPSA99013;
- the frame runner (`tools/build_runner.py`, `make runner RUNNER_CASES=...`),
  packaged as PPSA89012: it runs frame-input directories through the runtime,
  writes each output frame, times the upscaler and profiles every step, then
  closes itself. It is the PS5 side of the [acceptance](VALIDATION.md).

The frame runner embeds network files. The showcase includes them only when
you pass `--model` and `--kernels`. Keep folders containing these files on your
own machines and console.
