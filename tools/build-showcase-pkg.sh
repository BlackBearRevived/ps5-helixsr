#!/usr/bin/env bash
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
# Build and verify a package from the staged native application.
set -euo pipefail
app=${1:?expected a staged app folder}
output=${2:?expected an output .pkg path}
kit="$(cd -- "$(dirname -- "$0")/.." && pwd)/build/pkgkit-0.1.0"
python3 -m venv "$kit"
"$kit/bin/python" -m pip install --no-index --no-deps --require-hashes \
  'https://github.com/BlackBearRevived/ps5-pkgkit/releases/download/v0.1.0/ps5_pkgkit-0.1.0-py3-none-any.whl#sha256=71cfa598c509322c6752c094486935a8334d7cf0fceb73e838810e46a3823541'
"$kit/bin/ps5-pkgkit" build "$app" -o "$output"
"$kit/bin/ps5-pkgkit" verify "$output"
(cd "$(dirname -- "$output")" && name=$(basename -- "$output") && sha256sum "$name" > "$name.sha256")
