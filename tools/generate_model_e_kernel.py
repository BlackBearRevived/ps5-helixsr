"""Generate one Model E kernel with the resource layout consumed by the PS5 graph."""
from pathlib import Path
import sys


def main(lib, output, name):
    sys.path.insert(0, str(lib.resolve()))
    import regen_kernels

    # The native graph dispatches one slice per output tile. The desktop split-K
    # recipe adds an extra scratch buffer and a slice count to the launch ABI.
    if name in ("k7", "k11"):
        generator, options, flags, rules = regen_kernels.RECIPES[name]
        rules = dict(rules)
        rules.pop("splitk", None)
        regen_kernels.RECIPES[name] = generator, options, flags, rules
    directory = output / name
    directory.mkdir(parents=True, exist_ok=True)
    regen_kernels.generate(name, directory)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
