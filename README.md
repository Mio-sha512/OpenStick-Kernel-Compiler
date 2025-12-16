# OpenStick Kernel Compiler

This project is ment to make it easy to build custom kernels for OpenStick and MSM8916 devices in general.

> [!NOTE]
> - The project also includes a CPR patch (optional) that enables CPU frequency scaling from **200 MHz** to **1.2 GHz** instead of the default fixed **998 MHz**. 
Do note that it's is experimental and has only been explicitly tested on the `6.12.1` branch; it may or may not work on other kernel versions.

### Prebuilt releases

If you prefer not to compile yourself check the [releases page](https://github.com/Mio-sha512/OpenStick-Kernel-Compiler/releases) for prebuilt APKs.


## Requirements
- Any distro  with `bash`, `git`, `curl`, and `python3` available.

## Instructions

Simply clone the repo and run the interactive builder:

```bash
git clone https://github.com/Mio-sha512/OpenStick-Kernel-Compiler.git
cd OpenStick-Kernel-Compiler
./build.sh
```

## Options

The script supports interactive and non-interactive modes and a small set of flags. Use these from the command line or via the interactive menu.

- `--auto` - run non-interactively and use values from `.build_config` (see below). When `--auto` is used:
  - If `.build_config` exists, it will be sourced and those settings will be used without prompting.
  - If there is no `.build_config` and you did not pass any explicit flags (for example `--version` or `--cpr`), the script will exit and ask you to either create a saved config (by running once interactively and using `--save`) or supply explicit flags.

- `--version <branch>` - select the kernel branch to build (e.g. `msm8916/6.12.1`). This overrides the saved `KERNEL_VERSION` when used alongside `--auto`.

- `--cpr` / `--no-cpr` - enable or disable the CPR patch (see note below). Passing these on the command line overrides the saved `ENABLE_CPR` value.

- `--clean` - force a clean build (removes output cache).

- `--save` - after you finish the interactive prompts, write the selected settings to `.build_config` so they are reused by `--auto` in future runs.

Example: non-interactive CPR build using a known-good branch

```bash
./build.sh --auto --version msm8916/6.12.1 --cpr
```

> Note on user patches: extra patches placed in `patches/` can be selected from the interactive patch selector. These are not persisted to `.build_config` by the current script.


## .build_config

When you run the builder with `--save`, the script writes a minimal configuration file `.build_config` that contains shell assignments for the most common options. Example contents:

```bash
KERNEL_VERSION="msm8916/6.12.1"
ENABLE_CPR=true
```

- The script sources this file at startup when present. Values in the file are used for `--auto` (non-interactive) runs.
- Command-line flags provided explicitly always take precedence over the saved values.
- Only `KERNEL_VERSION` and `ENABLE_CPR` are saved by `--save`; additional choices (such as user-selected patches) are not persisted.

---

## Using with postmarketOS

To be able to install built kernels in postmarketOS you simply need to pass the `--allow-untrusted` argument and it should installed without issue like seen below

```bash
apk add --allow-untrusted linux-postmarketos-qcom-msm8916-*.apk
```

For device-specific information about see the [postmarketOS wiki](https://wiki.postmarketos.org/)

---

## Using in OpenStick-Builder

easy intergration coming soon, pinky finger promise


